import SwiftUI

struct SettingsView:View {
    @ObservedObject var store:MonitorStore
    @State private var home=""
    @State private var executable=""
    var body:some View {
        Form {
            Section("Darstellung") {
                Picker("Erscheinungsbild",selection:$store.appearance) { Text("System").tag("system");Text("Hell").tag("light");Text("Dunkel").tag("dark") }
                Picker("Limits aktualisieren",selection:$store.interval) { Text("Alle 15 Sekunden").tag(15.0);Text("Alle 30 Sekunden").tag(30.0);Text("Alle 60 Sekunden").tag(60.0) }
            }
            Section("Codex Desktop") {
                Label(store.desktopMessage,systemImage:store.desktopConnected ? "checkmark.circle" : "questionmark.circle").font(.callout).foregroundStyle(store.desktopConnected ? Color.green : Color.secondary)
            }
            Section("Codex CLI") {
                HStack {
                    VStack(alignment:.leading,spacing:4) {
                        Text(store.cliEnabled ? "Beobachtungs-Hooks installiert" : "Status-Anbindung einrichten")
                        Text("Erkennt Arbeit, Freigaben und Eingabefragen. Vorhandene Hooks bleiben erhalten.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(store.cliEnabled ? "Deaktivieren" : "Aktivieren") { store.setHooks(!store.cliEnabled) }
                }
                if store.cliEnabled { Text("CLI neu starten, /hooks öffnen und die AIMonitor-Hooks bestätigen. Erst danach werden Live-Statusereignisse geliefert.").font(.caption).foregroundStyle(.secondary) }
                if let message=store.hookMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Verbindung") {
                TextField("Codex-Verzeichnis",text:$home).textFieldStyle(.roundedBorder)
                TextField("Codex-Programm",text:$executable).textFieldStyle(.roundedBorder)
                HStack { Text("Die vorhandene Codex-Anmeldung wird verwendet.").font(.caption).foregroundStyle(.secondary);Spacer();Button("Übernehmen") { store.configure(home:home,executable:executable) }.disabled(home.isEmpty || executable.isEmpty) }
            }
            UpdateSection()
            HStack {
                Text("AIMonitor").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("AIMonitor beenden") { NSApp.terminate(nil) }
            }
        }.formStyle(.grouped).padding(8).frame(width:480,height:650)
        .onAppear { home=store.homePath;executable=store.executablePath }
    }
}
