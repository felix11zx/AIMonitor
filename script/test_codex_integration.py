#!/usr/bin/env python3
"""Exercise the installed Codex with isolated config, observer hooks and a local model fixture."""
import argparse
import json
import os
import queue
import shlex
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVENTS = ['SessionStart', 'SessionEnd', 'UserPromptSubmit', 'Stop', 'Interrupt',
          'PermissionRequest', 'PreToolUse', 'PostToolUse']


class Fixture(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0)))
        server = self.server
        server.requests += 1
        if server.requests == 1 and server.tool:
            item = dict(type='function_call', id='fc_fixture', call_id='call_fixture',
                        name=server.tool, arguments=json.dumps(server.arguments))
        else:
            server.resumed.set()
            server.finish.wait(10)
            item = dict(type='message', id='msg_fixture', role='assistant',
                        content=[dict(type='output_text', text='Fixture completed.')])
        response = dict(id='resp_fixture', object='response', status='completed',
                        model='gpt-5.4', output=[item],
                        usage=dict(input_tokens=10, output_tokens=10, total_tokens=20))
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()
        for event in [dict(type='response.created', response=dict(response, status='in_progress', output=[])),
                      dict(type='response.output_item.added', output_index=0, item=item),
                      dict(type='response.output_item.done', output_index=0, item=item),
                      dict(type='response.completed', response=response)]:
            try:
                self.wfile.write(('event: ' + event['type'] + '\ndata: ' + json.dumps(event) + '\n\n').encode())
                self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                break


class Client:
    def __init__(self, codex, env):
        # This override applies only to vetted observer hooks in the temporary fixture home.
        self.process = subprocess.Popen([codex, 'app-server'], env=env, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                        text=True, bufsize=1)
        self.messages = queue.Queue()
        self.saved = []
        threading.Thread(target=self.read, daemon=True).start()

    def read(self):
        for line in self.process.stdout:
            try:
                self.messages.put(json.loads(line))
            except ValueError:
                pass

    def send(self, value):
        self.process.stdin.write(json.dumps(value) + '\n')
        self.process.stdin.flush()

    def request(self, number, method, params):
        self.send(dict(id=number, method=method, params=params))
        while True:
            message = self.messages.get(timeout=20)
            if message.get('id') == number and ('result' in message or 'error' in message):
                if 'error' in message:
                    raise RuntimeError(message['error'])
                return message['result']
            self.saved.append(message)

    def receive(self):
        return self.saved.pop(0) if self.saved else self.messages.get(timeout=20)

    def close(self):
        if self.process.poll() is None:
            self.process.stdin.close()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()


def diagnostic(binary, home, directory, thread):
    result = subprocess.check_output([str(binary), '--diagnose-cli', str(home), str(directory)], text=True)
    return json.loads(result).get(thread)


def run_case(codex, binary, mode, decision):
    with tempfile.TemporaryDirectory(prefix='aimonitor-integration-') as temporary:
        root = Path(temporary)
        home, directory = root / 'home', root / 'events'
        home.mkdir()
        server = ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
        server.requests = 0
        server.resumed, server.finish = threading.Event(), threading.Event()
        server.tool = 'request_user_input' if mode == 'input' else 'exec_command'
        server.arguments = ({'questions': [{'id': 'fixture', 'header': 'Test', 'question': 'Choose a test value.',
                                           'options': [{'label': 'One', 'description': 'First value.'},
                                                       {'label': 'Two', 'description': 'Second value.'}]}]}
                            if mode == 'input' else {'cmd': 'printf AIMONITOR_TEST', 'yield_time_ms': 1000})
        if mode == 'permission':
            server.arguments.update(sandbox_permissions='require_escalated',
                                    justification='Test approval for harmless fixture output.')
        threading.Thread(target=server.serve_forever, daemon=True).start()
        (home / 'config.toml').write_text(
            'model="gpt-5.4"\nmodel_provider="fixture"\n'
            '[model_providers.fixture]\nname="Local fixture"\n'
            f'base_url="http://127.0.0.1:{server.server_port}/v1"\n'
            'wire_api="responses"\nrequires_openai_auth=false\nsupports_websockets=false\n')
        command = 'AIMONITOR_EVENT_DIR=' + shlex.quote(str(directory)) + ' ' + shlex.quote(str(binary)) + ' --record-hook'
        (home / 'hooks.json').write_text(json.dumps({'hooks': {event: [{'hooks': [dict(type='command', command=command, timeout=2)]}]
                                                           for event in EVENTS}}))
        env = dict(os.environ, CODEX_HOME=str(home), AIMONITOR_EVENT_DIR=str(directory))
        env.pop('OPENAI_API_KEY', None)
        client = None
        try:
            if mode == 'exec':
                server.finish.set()
                result = subprocess.run([codex, '--dangerously-bypass-hook-trust', 'exec', '--skip-git-repo-check',
                                         '--json', '-C', str(root), 'Run the local integration fixture.'],
                                        env=env, capture_output=True, text=True, timeout=30)
                assert result.returncode == 0, result.stderr[-1000:]
                recorded = [json.loads(path.read_text()) for path in directory.glob('*.json')]
                kinds = {event['kind'] for event in recorded}
                assert {'SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'Stop', 'SessionEnd'} <= kinds, kinds
                assert server.requests == 2
                print('PASS CLI exec lifecycle', flush=True)
                return
            client = Client(codex, env)
            client.request(1, 'initialize', {'clientInfo': {'name': 'aimonitor_fixture', 'version': '0.1.0'},
                                              'capabilities': {'experimentalApi': True}})
            client.send({'method': 'initialized'})
            thread = client.request(2, 'thread/start', dict(model='gpt-5.4', modelProvider='fixture', cwd=str(root),
                                    approvalPolicy='on-request', sandbox='read-only',
                                    config={'bypass_hook_trust': True}))['thread']['id']
            params = dict(threadId=thread, input=[dict(type='text', text='Run the local integration fixture.')])
            if mode == 'input':
                params['collaborationMode'] = dict(mode='plan', settings=dict(model='gpt-5.4'))
            turn = client.request(3, 'turn/start', params)['turn']['id']
            while True:
                message = client.receive()
                if message.get('method') in ['item/tool/requestUserInput', 'item/commandExecution/requestApproval']:
                    break
                assert message.get('method') != 'turn/completed', 'Fixture did not request input/approval'
            assert diagnostic(binary, home, directory, thread) == 'needsInput'
            if decision == 'kill':
                client.process.kill()
                client.process.wait()
                assert diagnostic(binary, home, directory, thread) == 'idle'
                print('PASS killed CLI clears pending input', flush=True)
                return
            if decision == 'interrupt':
                client.request(4, 'turn/interrupt', dict(threadId=thread, turnId=turn))
            else:
                answer = {'answers': {'fixture': {'answers': ['One']}}} if mode == 'input' else {'decision': decision}
                client.send(dict(id=message['id'], result=answer))
                assert server.resumed.wait(5), 'Codex did not resume its model request'
                deadline = time.monotonic() + 4
                while diagnostic(binary, home, directory, thread) != 'working':
                    assert time.monotonic() < deadline, 'Status did not clear before turn completion'
                    time.sleep(.1)
            server.finish.set()
            while client.receive().get('method') != 'turn/completed':
                pass
            client.close()
            assert diagnostic(binary, home, directory, thread) == 'idle'
            kinds = {json.loads(path.read_text())['kind'] for path in directory.glob('*.json')}
            assert ('Interrupt' if decision == 'interrupt' else 'Stop') in kinds, kinds
            print(f'PASS {mode} / {decision}: input -> work -> idle', flush=True)
        finally:
            server.finish.set()
            if client:
                client.close()
            server.shutdown()
            server.server_close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--codex', default='/opt/homebrew/bin/codex')
    args = parser.parse_args()
    binary = ROOT / 'dist/AIMonitor.app/Contents/MacOS/AIMonitor'
    assert binary.is_file(), 'Build the app first: ./script/build_and_run.sh --build'
    for mode, decision in [('exec', 'finish'), ('input', 'answer'), ('permission', 'decline'),
                           ('permission', 'accept'), ('input', 'interrupt'), ('input', 'kill')]:
        run_case(args.codex, binary, mode, decision)


if __name__ == '__main__':
    main()
