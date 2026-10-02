# AIMonitor – Entwurf

Datum: 2. Oktober 2026

## Ziel und bestätigter Umfang

Eine kleine native macOS-App zeigt Codex-Usage-Limits, deren Reset-Zeiten und den aktuellen Status von Codex Desktop sowie Codex CLI. Der Nutzer hat Swift als Sprache, ein normales bewegbares Fenster, unterschiedliche Aktionen für Links-/Rechtsklick, drei Statusfarben und eine native helle/dunkle Oberfläche gewünscht. Desktop und CLI sowie der im Chat vorgeschlagene Entwurf wurden bestätigt.

Arbeitsname: AIMonitor. Oberfläche: Deutsch. Zielsystem: macOS 14 oder neuer. Diese beiden konkreten Standardentscheidungen stammen aus dem Vorschlag des Agents; sie können im Review geändert werden.

## Bedienung und Oberfläche

- Die App läuft als Menüleisten-App mit einem SF-Symbol und einem kleinen farbigen Statuspunkt.
- Linksklick bringt ein einziges normales NSWindow nach vorne. Es hat die üblichen Fensterknöpfe, lässt sich an der Titelleiste bewegen und bleibt nach Fokuswechsel geöffnet. Wiederholte Klicks erzeugen keine weiteren Fenster.
- Rechtsklick beziehungsweise Control-Klick öffnet direkt das eigene Einstellungsfenster.
- Schließen des Monitorfensters lässt die App und die Aktualisierung weiterlaufen. Die Einstellungen enthalten eine Aktion zum Beenden.
- Das Monitorfenster beginnt mit etwa 400 × 480 Punkten. Ein Scrollbereich nimmt zusätzliche Limits und Agents auf; die Darstellung wächst nicht über den Bildschirm hinaus.
- Oben stehen Codex-Verbindung, Gesamtstatus und der Zeitpunkt der letzten erfolgreichen Limit-Aktualisierung. Darunter folgen Limits und eine kompakte Liste zuletzt genutzter Agents mit Titel, Quelle Desktop/CLI und Status in Text und Farbe.
- Limits zeigen verbleibende Prozent als Hauptwert, verbrauchte Prozent ergänzend, einen Fortschrittsbalken, den nächsten Reset als lokale Uhrzeit/Datum und einen Countdown.
- Konto-Limits erscheinen einmal. Desktop und CLI teilen bei demselben Konto die Limits; sie werden nicht addiert oder als Limits pro Agent ausgegeben. Mehrere serverseitige Limit-Buckets behalten eigene Zeilen.
- Einstellungen: Erscheinungsbild System/Hell/Dunkel, Aktualisierungsintervall 15/30/60 Sekunden, Codex-Verzeichnispfad und ausführbare Codex-Datei, Desktop-Verbindungsstatus, CLI-Anbindung aktivieren/deaktivieren, App beenden.
- Die Standarddarstellung folgt macOS. Native semantische Farben, SF Pro, SF Symbols, Standardabstände und dezente Materialien tragen die Gestaltung. Änderungen an Balken und Status erhalten kurze Animationen von etwa 0,2 Sekunden. Bei „Bewegung reduzieren“ entfallen diese Animationen.
- Keine neuen Benachrichtigungen, Tonhinweise, Agent-Steuerung oder weiteren AI-Anbieter im bestätigten Umfang.

## Statusregeln

| Beobachteter Zustand | Darstellung |
| --- | --- |
| Agent ist inaktiv beziehungsweise Turn abgeschlossen/unterbrochen | Grau, „Inaktiv“ |
| Turn läuft ohne offene Eingabeanforderung | Blau, „Arbeitet“ |
| Offene Freigabe oder offene Eingabefrage | Orange, „Eingabe nötig“ |

Eine laufende Anfrage behält Orange, bis sie beantwortet/aufgelöst ist oder der Turn endet. Mehrere offene Anfragen werden gezählt; eine einzelne beantwortete Anfrage darf andere offene Anfragen nicht löschen. Im Menüleisten- und Gesamtstatus hat Orange Vorrang vor Blau, danach Grau.

Verbindungsausfall, unbekanntes Protokoll oder fehlende Daten sind separat als „Nicht verbunden“/„Status unbekannt“ gekennzeichnet. Grau mit dem Text „Inaktiv“ ist nur für einen belegten inaktiven Zustand zulässig. Alte Daten bleiben mit Zeitstempel sichtbar, dürfen aber nicht als aktuelle Live-Daten ausgegeben werden.

## Architektur

SwiftUI rendert Monitor und Einstellungen. AppKit verwaltet NSStatusItem, die Mausaktionen, NSWindow-Lebenszyklus und Aktivierung. Ein Store auf dem MainActor führt die Quellen zusammen; I/O, JSON-Verarbeitung und Prozesskommunikation laufen außerhalb des MainActor.

Ein Swift Package hält Modelle, Normalisierung, Statusreducer und Datenadapter getrennt von der App-Oberfläche und ermöglicht gezielte Tests. Ein projektlokales Build-Skript erstellt eine ausführbare .app und startet sie. Ein Run-Eintrag für Codex nutzt dasselbe Skript. Die erste lokale Version braucht keine Drittanbieterpakete, kein Backend und kein eigenes Modell-Inferenzkonto.

### Limits: dokumentierter Codex-App-Server

Die App verwendet die vorhandene Codex-Installation und deren vorhandene Anmeldung. Ein eigener, von AIMonitor verwalteter `codex app-server --listen stdio://`-Prozess dient nur als RPC-Client für Konto-Limits. Nach `initialize`/`initialized` liest AIMonitor `account/rateLimits/read` und verarbeitet verfügbare `account/rateLimits/updated`-Nachrichten. AIMonitor startet oder resumed damit keine Agent-Turns.

`rateLimitsByLimitId` hat Vorrang vor der älteren einzelnen `rateLimits`-Ansicht. `usedPercent` wird als Verbrauch interpretiert und für die Darstellung auf 0–100 begrenzt. Die verbleibende Quote ist 100 minus Verbrauch. `windowDurationMins` bestimmt den Zeitraum; es werden keine fest angenommenen 5-Stunden-/Wochenfenster angezeigt. `resetsAt` ist ein Unix-Zeitstempel in Sekunden. Fehlende Werte bleiben fehlend und werden nicht als null Verbrauch interpretiert.

Beim Start, beim Öffnen des Monitorfensters, auf manuelle Aktualisierung und standardmäßig alle 30 Sekunden wird neu gelesen. Der Countdown wird lokal jede Sekunde aktualisiert. Beim Ablauf einer Reset-Zeit wird ein neuer Abruf angestoßen; der Verbrauch wird nicht allein aufgrund des Countdowns zurückgesetzt. Keine überlappenden Requests; begrenzte Timeouts und verzögerte Wiederverbindung nach Fehlern. Fehlende Anmeldung wird verständlich angezeigt und nicht durch Auslesen/Anzeigen von Auth-Tokens umgangen.

### Desktop: lesender lokaler IPC-Beobachter

Die Desktop-App stellt unter dem Codex-Verzeichnis `ipc/ipc.sock` einen lokalen Unix-Socket bereit. Das installierte Desktop-Paket und ein lesender Probe-Client belegen die folgenden Verträge:

- Frames bestehen aus einer 4-Byte-Längenangabe Little Endian und UTF-8-JSON.
- Ein eigener Client meldet sich mit `initialize`, `clientType: aimonitor` und Protokollversion 0 an.
- `thread-stream-following-changed`, Version 1, mit `following: true` abonniert die vorhandene Conversation als Beobachter.
- `thread-stream-state-changed`, in der geprüften Installation Version 11, liefert Snapshots und nachfolgende Patches. Ein realer Snapshot enthält `threadRuntimeStatus` sowie `requests`.
- `threadRuntimeStatus.type: active` sowie die Flags `waitingOnApproval` und `waitingOnUserInput` liefern die drei Nutzungszustände. Offene Anfragen ergänzen diese Information.

Ein nur lesender Thread-Katalog aus der lokalen Codex-State-Datenbank beziehungsweise Session-Metadaten findet relevante Thread-IDs und identifiziert Desktop/CLI anhand Quelle/Originator. Es wird keine vollständige Chat-Historie für die Oberfläche geladen. Desktop-Snapshots werden im Arbeitsspeicher gehalten; Patches werden nur bei passender Ausgangsrevision angewendet. Bei einer Lücke wird neu abonniert und ein neuer Snapshot angefordert. Beim Beenden werden Beobachtungs-Abonnements entfernt; AIMonitor übernimmt keine Thread-Ownership.

Die IPC-Schnittstelle ist intern und damit eine konkrete Kompatibilitätsabhängigkeit. Framegröße, Eigentümer des Sockets und Protokollversion werden validiert. Unbekannte Versionen führen zu einem sichtbaren Verbindungsfehler, nicht zu erfundenen Statuswerten. Ein unabhängiger App-Server liefert keine verbindlichen Runtime-Statusdaten der Desktop-Instanz.

### CLI: beobachtende Codex-Hooks

Codex-Hooks liefern die Lifecycle-Ereignisse für genaue CLI-Statusänderungen. Die App enthält einen kleinen nativen Helper-Modus, der Hook-JSON von stdin liest, nur Session-/Turn-/Tool-IDs, Zeitpunkt und Statusereignis in AIMonitors lokale Statusablage schreibt und ohne stdout-Inhalt mit Erfolg endet. Prompttexte, Tool-Argumente und Tokens werden nicht in der Statusablage gespeichert.

`UserPromptSubmit` meldet Arbeit; `Stop`, `Interrupt` und `SessionEnd` melden das Ende des passenden Turns beziehungsweise der Session. `PermissionRequest` meldet eine erforderliche Freigabe. `PreToolUse` für Eingabetools meldet eine Eingabefrage, `PostToolUse` löst die passende Eingabe-/Toolanforderung. Hook-Signale werden mit Session-Metadaten und Session-Ereignissen abgeglichen. Session-/Turn-IDs verhindern, dass verspätete Hook-Ausgaben den Zustand eines späteren Turns überschreiben. Ein beendeter CLI-Prozess darf keinen dauerhaft blauen Zustand hinterlassen.

Die CLI-Anbindung wird in den Einstellungen explizit aktiviert. Ein Installer ergänzt nur AIMonitors eigene Hook-Einträge, erhält vorhandene Hooks, speichert eine Sicherung und entfernt beim Deaktivieren nur die eigenen Einträge. Er beantwortet keine Codex-Freigaben und fügt dem Agent keine Anweisungen hinzu. Bereits laufende CLI-Sessions können einen Neustart benötigen, bevor neue Hooks geladen werden; dies wird beim Aktivieren erklärt. Ohne diese Anbindung zeigt die App vorhandene Sessions und belegte Session-Ereignisse, kennzeichnet aber eine nicht belegbare Eingabeerkennung als unvollständig.

Die Hook-Verträge sind dokumentiert. In der Umsetzung wurden die echte CLI-Hook-Ausführung, offene Eingabefragen, angenommene/abgelehnte Freigaben, Unterbrechung und Prozessende verifiziert; Nachweise stehen in `docs/verification.md`. Prozessanwesenheit allein erfüllt die Statusanforderung nicht.

## Datenfluss und Betrieb

Adapter → normalisierte Ereignisse/Limit-Snapshots → statusreduzierender Store → SwiftUI und Menüleistenpunkt. Dateiereignisse beziehungsweise IPC aktualisieren Status möglichst innerhalb einer Sekunde; ein leichter Abgleich alle zwei Sekunden fängt verpasste Dateiereignisse ab. Limit-Abrufe folgen dem einstellbaren Intervall. Fensteröffnung erzwingt einen aktuellen Abgleich.

Disconnects, Sleep/Wake, fehlende Dateien, teilweise geschriebene JSON-Zeilen und laufende Datenbanktransaktionen werden toleriert. Reconnects und erneute Snapshot-Abfragen laufen ohne zusätzliche Fenster. AIMonitor beendet nur seinen eigenen App-Server-Prozess. Es schreibt nicht in Codex-State-/Log-Datenbanken und verändert keine Agent-Turns.

## Abnahme und Nachweise

1. Eine lokal gebaute .app startet und zeigt ein Menüleisten-Icon.
2. Echte Links-/Rechts-/Control-Klicks öffnen jeweils das normale Monitor- beziehungsweise Einstellungsfenster. Verschieben, Schließen, erneutes Öffnen und Fokuswechsel funktionieren ohne Fensterduplikate.
3. Verifizierte Live-Limits stimmen mit Codex für dasselbe Konto und dieselben Buckets überein. Fehlende Werte, mehrere Buckets und Reset-Ablauf sind zusätzlich durch Fixtures abgedeckt.
4. Desktop-Snapshots und Patches ändern den Status korrekt von Grau zu Blau, zu Orange bei Eingabe/Freigabe und zurück nach Auflösung. Auch mehrere offene Anfragen und Reconnects werden geprüft.
5. CLI-Lifecycle, Eingabefragen und Freigaben einschließlich Ablehnung, Unterbrechung und Prozessende werden durch die tatsächliche CLI-Anbindung überprüft. Simulierte Hook-JSONs ergänzen, ersetzen aber nicht den Integrationstest.
6. Konto-Limits werden für Desktop und CLI nicht doppelt gezählt. Session-IDs werden zwischen Quellen dedupliziert.
7. Hell, Dunkel, Systemwechsel und „Bewegung reduzieren“ werden in der laufenden App geprüft.
8. Swift-Build und die gezielten Modell-/Parser-/Status-/Hook-Installer-Tests bestehen. Build-/Run-Anleitung und bekannte Kompatibilitätsabhängigkeiten sind dokumentiert.
9. Das Ziel ist erst abgeschlossen, wenn beide Codex-Varianten, alle drei Statusfarben und das gewünschte native Fensterverhalten belegt sind.

## Quellen und bisherige Vorprüfung

- [Offizielle Codex-App-Server-Dokumentation](https://learn.chatgpt.com/docs/app-server): Limits-RPC, Statusflags, Thread-Daten.
- [Offizielle Codex-Hooks-Dokumentation](https://learn.chatgpt.com/docs/hooks): Lifecycle-/Tool-/PermissionRequest-Ereignisse und beobachtende Hook-Ausgabe.
- Lokal geprüfte Codex-CLI: 0.154.0; generiertes experimentelles JSON-Schema als temporäres Rechercheartefakt unter `/private/tmp/aimonitor-codex-schema`.
- Lokal geprüftes Desktop-Paket: `/Applications/ChatGPT.app/Contents/Resources/app.asar`; interne IPC-Verträge nur für diese Installation bestätigt.
- Erfolgreiche lesende IPC-Initialisierung und ein Snapshot dieser Conversation; keine Agent-Turns gestartet oder verändert.
- Das Projektverzeichnis war zu Beginn leer. Für die Versionierung dieses Entwurfs wurde ein lokales Git-Repository initialisiert.

## Reviewstand

Der Nutzer hat die Umsetzung am 2. Oktober 2026 mit „Passt genau so umsetzen“ freigegeben. Implementation, unabhängiges Review und Integrationstests sind abgeschlossen. Der Nutzer bestätigte Links-/Rechtsklick und das bewegliche Monitorfenster. Details und tatsächliche Kompatibilitätsgrenzen stehen in `docs/verification.md` und `README.md`.
