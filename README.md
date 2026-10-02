# AIMonitor

Native macOS-App in Swift, SwiftUI und AppKit für Codex Desktop und CLI. Ein Menüleistensymbol öffnet ein normales, frei bewegbares Fenster.

- **Linksklick:** Monitor öffnen oder nach vorne holen.
- **Rechtsklick / Control-Klick:** Einstellungen öffnen.
- **Grau:** Inaktiv. **Blau:** Arbeitet. **Orange:** Eingabe oder Freigabe nötig.
- Echte Konto-Limits, verbleibende Nutzung, lokale Reset-Zeit und laufender Countdown.
- System-, Hell- und Dunkelmodus; dezente Animationen berücksichtigen „Bewegung reduzieren“.

## Starten

Das gebaute Bundle liegt unter `dist/AIMonitor.app`. Doppelklick öffnet die App; nach dem Schließen des Fensters läuft sie in der Menüleiste weiter. Über die Einstellungen oder ⌘Q beenden.

Zum Bauen und Starten aus dem Projekt:

```sh
./script/build_and_run.sh
```

Die **Run**-Aktion in Codex führt denselben Befehl aus. Voraussetzungen: macOS 14+, Swift-6-Toolchain / Xcode Command Line Tools und eine angemeldete Codex-Installation. Getestet auf Apple Silicon mit Codex CLI 0.154.0 und Desktop-Build 154.0.8037.57. Keine externen Swift-Packages.

## Codex verbinden

Desktop-Status wird automatisch über den lokalen Socket im Codex-Verzeichnis beobachtet. Codex Desktop muss geöffnet sein. Limits liest die App über einen eigenen, ausschließlich für Konto-Abfragen verwendeten `codex app-server`-Prozess. Desktop und CLI teilen Konto-Limits; AIMonitor zählt sie einmal.

Limits werden standardmäßig alle 30 Sekunden aktualisiert, wählbar alle 15/30/60 Sekunden. Desktop-Status wird als Ereignis empfangen; CLI-Status wird alle zwei Sekunden abgeglichen. Der Countdown läuft jede Sekunde. Ein erreichter Reset wird erneut geprüft; die App setzt den Verbrauch nicht selbst auf null.

Für den vollständigen **CLI-Status**:

1. Einstellungen öffnen und bei Codex CLI **Aktivieren** wählen.
2. Bereits laufende CLI-Sessions neu starten.
3. In Codex `/hooks` öffnen und die Einträge **AIMonitor status observer** überprüfen und bestätigen. Codex verlangt diese Bestätigung für neue oder veränderte Hooks.

AIMonitor ergänzt `hooks.json`, erhält fremde Hooks und erstellt eine Sicherung `hooks.json.aimonitor-backup`. **Deaktivieren** entfernt ausschließlich die eigenen Einträge. Die Beobachtungs-Hooks geben keinen Text und keine Freigabeentscheidung an Codex zurück.

Wenn du das App-Bundle verschiebst, deaktiviere die Anbindung am bisherigen Ort und aktiviere sie am neuen Ort erneut; der Hook-Befehl enthält den absoluten Programmpfad.

## Daten und Grenzen

Die App liest Codex-Sessionmetadaten und Desktop-Laufzeitdaten. Eigene Statusdateien liegen unter `~/Library/Application Support/AIMonitor/events`. Gespeichert werden Session-/Turn-/Tool-IDs, Argument-Hashes, Status und Zeit-/Prozessmetadaten. Prompttexte, Tool-Argumente und Zugangsdaten werden dort nicht gespeichert. Diagnostische Ereignisdateien sind auf 512 begrenzt; inaktive Statusdateien werden nach sieben Tagen entfernt.

Eine fehlende oder nicht eindeutig belegbare Information erscheint als **Status unbekannt**. Ohne bestätigte CLI-Hooks kann ein offener historischer Turn keinen aktuellen Arbeitsstatus beweisen. Bei identischen parallelen Toolaufrufen liefert Codex für Freigaben keine eindeutige Tool-ID: Nach einer teilweise aufgelösten, mehrdeutigen Gruppe zeigt AIMonitor vorübergehend „Status unbekannt“, bis sie eindeutig aufgelöst ist.

Desktop-IPC ist eine interne Codex-Schnittstelle. AIMonitor prüft die beobachtete Protokollversion und zeigt bei einer inkompatiblen Änderung einen Verbindungsfehler. Die App verändert keine Codex-Datenbanken, startet keine Agent-Turns und beantwortet keine Agent-Fragen.

## Prüfen

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift test --cache-path .build/cache --disable-sandbox

./script/build_and_run.sh --build
python3 script/test_codex_integration.py
```

Der Integrationstest verwendet temporäre Codex-Verzeichnisse und einen lokalen Responses-Testserver. Er prüft die echten Hooks der installierten Codex-Version für Arbeit, Eingabe, Freigabe, Ablehnung, Unterbrechung und Prozessabbruch. Nur die eigenen geprüften Test-Hooks erhalten im isolierten Test eine Vertrauensausnahme; die echte Codex-Konfiguration bleibt unverändert.

Weitere Startmodi: `--verify`, `--debug`, `--logs`, `--telemetry`. Das Bundle ist lokal ad hoc signiert; eine notarisierte Distribution ist kein Bestandteil dieses lokalen Builds. Prüfnachweise stehen in `docs/verification.md`.

Die Anbindung folgt den [Codex App-Server-Verträgen](https://learn.chatgpt.com/docs/app-server) und der [Codex-Hook-Dokumentation](https://learn.chatgpt.com/docs/hooks).
