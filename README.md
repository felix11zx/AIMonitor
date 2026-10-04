# AIMonitor

**Dein Codex-Status und deine Konto-Limits direkt in der macOS-Menüleiste.** AIMonitor zeigt dir, ob Codex gerade arbeitet oder deine Eingabe braucht, wie viel Nutzung noch verfügbar ist und wann deine Limits zurückgesetzt werden. Eine native, kleine Open-Source-App für Codex Desktop und CLI, geschrieben in Swift, SwiftUI und AppKit.

**[App herunterladen](https://github.com/felix11zx/AIMonitor/releases/latest)** · **[Installationsanleitung](docs/INSTALLATION.md)** · [MIT-Lizenz](LICENSE)

## Installation

Voraussetzungen: **macOS 14+**, Apple Silicon oder Intel, und eine installierte, angemeldete Codex-App bzw. Codex CLI. Für das fertige ZIP brauchst du kein Xcode.

1. Lade `AIMonitor-<Version>-macOS-universal.zip` aus dem [neuesten Release](https://github.com/felix11zx/AIMonitor/releases/latest) herunter.
2. Entpacke das ZIP und ziehe **AIMonitor.app** nach **Programme**.
3. Öffne die App; ihr Symbol erscheint in der Menüleiste.

**Sicherheitswarnung:** Ich habe keinen kostenpflichtigen Apple-Developer-Account. Die App ist deshalb nicht mit einer Apple Developer ID signiert und nicht von Apple notarisiert. macOS kann beim ersten Start eine Warnung anzeigen. Wenn du der App vertraust, versuche sie einmal zu öffnen, schließe die Warnung und gehe zu **Systemeinstellungen → Datenschutz & Sicherheit → Dennoch öffnen**; bestätige anschließend **Öffnen**. [Apple erklärt den Ablauf](https://support.apple.com/de-de/102445).

Du kannst den vollständigen Code durchlesen und die App selbst bauen. Open Source macht den Code überprüfbar, ist aber kein automatischer Sicherheitsnachweis für ein heruntergeladenes Programm. Eine konkrete Schadsoftware- oder Beschädigungswarnung ist von der Entwickler-/Notarisierungswarnung zu unterscheiden. Details und eine optionale Prüfsummenprüfung findest du in der [Installationsanleitung](docs/INSTALLATION.md).

## Kurz erklärt

- **Linksklick:** Monitor öffnen oder nach vorne holen.
- **Rechtsklick / Control-Klick:** Einstellungen öffnen.
- **Blau:** Arbeitet. **Orange:** Eingabe oder Freigabe nötig. **Grau:** Inaktiv oder unbekannt; der genaue Status steht im Fenster.
- Echte Konto-Limits, verbleibende Nutzung, lokale Reset-Zeit und laufender Countdown.
- System-, Hell- und Dunkelmodus; dezente Animationen berücksichtigen „Bewegung reduzieren“.
- **Einstellungen → Updates → Nach Updates suchen:** prüft die neueste stabile GitHub-Version und bietet bei einem Update einen Link zur Download-Seite.

Zum Aktualisieren das neue ZIP herunterladen, AIMonitor beenden und die App in Programme ersetzen. Deine Einstellungen bleiben erhalten. macOS kann die Freigabe erneut verlangen; CLI-Hooks müssen gegebenenfalls erneut unter `/hooks` bestätigt werden.

## Selbst bauen und starten

Das gebaute Bundle liegt unter `dist/AIMonitor.app`. Doppelklick öffnet die App; nach dem Schließen des Fensters läuft sie in der Menüleiste weiter. Über die Einstellungen oder ⌘Q beenden.

Zum Bauen und Starten aus dem Projekt:

```sh
./script/build_and_run.sh
```

Die **Run**-Aktion in Codex führt denselben Befehl aus. Zum Selbstbauen benötigst du eine Swift-6-Toolchain / Xcode Command Line Tools. Getestet auf Apple Silicon mit Codex CLI 0.154.0 und Desktop-Build 154.0.8037.57. Der Download enthält zusätzlich eine Intel-Binary; der Lauf auf Intel wurde nicht auf echter Hardware getestet. Keine externen Swift-Packages.

Ein optimiertes Universal-ZIP inklusive SHA-256-Prüfsumme baust du mit:

```sh
./script/package_release.sh
```

Die Dateien liegen anschließend unter `dist/`. [Neue GitHub-Version veröffentlichen](docs/RELEASING.md).

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

Die Updateprüfung erfolgt ausschließlich auf Knopfdruck über die öffentliche GitHub-API, ohne GitHub-Anmeldung. Dabei erhält GitHub die technisch übliche Verbindungsinformation (etwa deine IP-Adresse) und die installierte App-Version im User-Agent. AIMonitor überträgt dabei keine Codex-Inhalte, Konto-Limits oder Zugangsdaten. Download und Installation erfolgen manuell.

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

## Lizenz und Projekt

AIMonitor ist unter der [MIT-Lizenz](LICENSE) veröffentlicht und ein unabhängiges Community-Projekt, kein offizielles OpenAI-Produkt.

Bei der Entwicklung der App wurde künstliche Intelligenz (KI) verwendet. Auch das Logo wurde mit KI erstellt.

Die Anbindung folgt den [Codex App-Server-Verträgen](https://learn.chatgpt.com/docs/app-server) und der [Codex-Hook-Dokumentation](https://learn.chatgpt.com/docs/hooks).
