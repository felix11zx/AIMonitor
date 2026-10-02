# AIMonitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Native Menüleisten-App mit normalen Fenstern und echten Codex-Limits sowie Desktop-/CLI-Status bauen.

**Architecture:** Swift Package mit AIMonitorCore und AIMonitor-App. AppKit steuert Fenster und Mausaktionen, SwiftUI rendert die Oberfläche. Ein MainActor-Store kombiniert lesende Desktop-IPC-Snapshots, Codex-Limits-RPC und lokale CLI-Hook-Ereignisse.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Foundation, Darwin, SQLite3; keine externen Packages.

**Spec:** `docs/superpowers/specs/2026-10-02-aimonitor-design.md`

## Global Constraints

- macOS 14 oder neuer; Oberfläche Deutsch; Arbeitsname AIMonitor.
- Normales bewegbares NSWindow, kein Popover; links Monitor, rechts/Control-Klick Einstellungen.
- Grau Inaktiv, Blau Arbeitet, Orange Eingabe nötig. Unbekannte Daten klar kennzeichnen.
- System/Hell/Dunkel, 0,2-Sekunden-Animationen, Bewegung reduzieren respektieren.
- Keine Agent-Steuerung, keine Auth-Tokens in Ausgaben, keine Änderungen an Codex-Datenbanken.
- Limits alle 30 Sekunden, wählbar 15/30/60; Statusabgleich alle zwei Sekunden, Countdown jede Sekunde.

## Review Focus

- Revisionlücke oder Array-Patches im Desktop-IPC: neu abonnieren statt einen falschen Status anzeigen.
- Verspätete CLI-Hooks und mehrere offene Requests: passenden Turn/Request auflösen.
- Abgelehnte Freigabe oder getötete CLI: Orange/Blau darf nicht hängen bleiben.
- Vorhandene Codex-Hooks: Installer erhält fremde Einträge und sichert Originale.
- Fehlende Limits und abgelaufene Resets: keine erfundene Quote oder automatische Nullsetzung.

---

### Task 1: Modelle und Parser

**Files:** `Package.swift`, `Sources/AIMonitorCore/Models.swift`, `JSON.swift`, `StatusReducer.swift`, `Tests/AIMonitorCoreTests/CoreTests.swift`.

**Interfaces:** Produces `UsageSnapshot.decode(_:)`, `AgentStatus`, `AgentRecord`, `DesktopState.apply(_:)`, `HookEvent`, `CLIState.apply(_:)`.

- [x] Tests für mehrere Buckets, fehlende Prozent, Reset-Sekunden, Orange-Vorrang, Revisionlücken, Array-Patches und verspätete Hooks schreiben.
- [x] `swift test` ausführen, fehlende Implementierung nachweisen.
- [x] Normalisierung und Reducer implementieren; unbekannte Werte bleiben unbekannt.
- [x] `swift test` besteht; Modelle/Tests lokal committen.

### Task 2: Live-Adapter und CLI-Anbindung

**Files:** `Sources/AIMonitorCore/Catalog.swift`, `CodexRPC.swift`, `DesktopIPC.swift`, `HookIntegration.swift`, `Tests/AIMonitorCoreTests/HookTests.swift`.

**Interfaces:** Consumes Task 1; produces `Catalog.read(home:)`, `CodexRPC.readLimits(executable:home:)`, `DesktopIPC.observe(ids:onEvent:)`, `HookInstaller.setEnabled(_:home:executable:)`, `HookRecorder.record(_:)`.

- [x] Hook-Merge/Uninstall/Backup, fragmentierte Frames und Prozessende als Tests mit temporären Verzeichnissen schreiben und fehlschlagen sehen.
- [x] SQLite-Katalog nur lesend, zeitlich begrenztes RPC und abgesicherten Socket mit Hintergrund-I/O implementieren.
- [x] Hook-Helper speichert nur Statusmetadaten; Installer erhält fremde Einträge und arbeitet atomar.
- [x] Tests bestehen; echte Limits und Desktop-Snapshot mit installiertem Codex lesen. Lokaler Commit.

### Task 3: Native App, Fenster und UI

**Files:** `Sources/AIMonitor/App.swift`, `MonitorStore.swift`, `MonitorView.swift`, `SettingsView.swift`, `script/build_and_run.sh`, `Resources/Info.plist`, `.codex/environments/environment.toml`.

**Interfaces:** Consumes Task 1/2; produces `dist/AIMonitor.app` and `./script/build_and_run.sh`.

- [x] MainActor-Store, Lifecycle/Refresh, AppKit-StatusItem und genau ein Fenster pro Rolle implementieren.
- [x] Native Limit-/Agent-Zeilen, lokale Countdowns, klare Fehler-/Verbindungsanzeige, Erscheinungsbild und CLI-Setup umsetzen.
- [x] Bundle erstellen; Run-Aktion erst danach konfigurieren.
- [x] `swift test` und Build bestehen. App starten und reale Daten sowie beide Klickwege, Verschieben/Fokus/Schließen/Wiederöffnen und Appearance prüfen. Lokaler Commit.

### Task 4: Integration, Review und Auslieferung

**Files:** `README.md`, `docs/verification.md`, gezielte Korrekturen an bestehenden Dateien.

**Interfaces:** Consumes fertige App, Tests und Live-Adapter; produces dokumentierte startbare App und Anbindung.

- [x] Tatsächliche CLI-Hook-Ausführung für Arbeit, Eingabe, Freigabe/Ablehnung und Ende überprüfen; vollständige Anbindung muss bestehen.
- [x] Einen frischen Reviewer auf gesamte Änderung und Review Focus ansetzen, notwendige Fehler beheben und gezielt nachtesten.
- [x] Build/Tests abschließend ausführen, Nachweise und eventuelle echte Einschränkungen dokumentieren. Lokaler Commit.
- [x] App geöffnet bereitstellen; Ziel nur bei vollständig belegter Abnahme als erreicht markieren.

## Ausführung

Der Nutzer hat am 2. Oktober 2026 die schriftliche Spezifikation mit „Passt genau so umsetzen“ zur Umsetzung freigegeben. Umsetzung durch den Hauptagenten in dieser Sitzung; ein unabhängiges finales Review nach Executing-Plans. Die ausdrückliche Implementierungsanweisung hat Vorrang vor weiteren routinemäßigen Bestätigungsrunden.
