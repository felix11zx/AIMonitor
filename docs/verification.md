# AIMonitor — Prüfnachweise

## Release 0.2.0 — 4. Oktober 2026

- `swift test`: **23 Tests, 0 Fehler**, einschließlich fünf neuer Update-Tests (numerischer Versionsvergleich, neue/gleiche/ältere Version, Entwürfe/Vorabversionen, ungültige Antworten, HTTP-Fehler, fehlende Releases, Offline-Fall sowie Anfrage ohne Authentifizierung oder Nutzdaten).
- `python3 script/test_codex_integration.py`: **6 Integrationstests erfolgreich** gegen die Universal-Release-Binary; isolierte Test-Konfigurationen und lokaler Modell-Testserver.
- `./script/package_release.sh`: optimierte Universal-App und `AIMonitor-0.2.0-macOS-universal.zip` erzeugt. Beide Mach-O-Architekturen (`arm64`, `x86_64`) setzen **macOS 14.0** als Mindestversion. Intel wurde kompiliert, aber nicht auf echter Intel-Hardware ausgeführt.
- Ad-hoc-Signatur mit `codesign --verify --deep --strict` geprüft; keine Developer-ID-Signatur und keine Notarisierung.
- ZIP erneut in ein temporäres Verzeichnis entpackt: gültige Signatur, ausführbare Binary und identischer Binary-Inhalt. `shasum -a 256 -c SHA256SUMS.txt`: **OK**.
- Universal-App auf Apple Silicon als `.app` gestartet; Prozess und native Oberfläche geprüft. In Einstellungen sichtbar: **Installiert: 0.2.0** und **Nach Updates suchen**. Klick vor der ersten GitHub-Veröffentlichung liefert korrekt **Noch keine veröffentlichte Version verfügbar**.
- Neue Versionen öffnen eine Download-Seite im festen Repository `felix11zx/AIMonitor`; Installation bleibt manuell. Die Prüfung erfolgt nur auf Knopfdruck und überträgt keine Codex-Daten oder Zugangsdaten.
- Deutsche README, Installationsanleitung, Release-Anleitung und MIT-Lizenz hinzugefügt; bestehendes App-Icon in Bundle und Repository aufgenommen.

Die folgenden Nachweise dokumentieren die ursprüngliche Version 0.1.0.

Stand: 2. Oktober 2026, Europe/Vienna. Swift 6.4 / macOS-SDK 27; Deployment Target macOS 14. Codex CLI 0.154.0, Desktop-Build 154.0.8037.57.

## Automatische Prüfung

- `swift test --cache-path .build/cache --disable-sandbox` mit lokalen Modul-Caches: **18 Tests, 0 Fehler**, letzter Lauf 22:47:54.
- `./script/build_and_run.sh --verify`: erfolgreich gebaut, ad hoc signiert, als `.app` geöffnet und laufender Prozess nachgewiesen.
- `python3 script/test_codex_integration.py`: **6 erfolgreiche Integrationstests** mit der tatsächlich installierten Codex-Binary, temporärem CODEX_HOME und lokalem Responses-Testserver.

Die Integration prüft CLI-exec-Lifecycle einschließlich Start, Prompt, Tool, Stop und Session-Ende; eine tatsächlich offene Eingabefrage; angenommene und abgelehnte Freigaben; Unterbrechung sowie hartes Prozessende. Der gebaute Diagnosemodus prüft dieselben Core-Reducer und Sessiondateien wie der Monitor. Vor der Antwort ist der Status `needsInput`; nach der Antwort/Freigabe/Ablehnung ist er `working`, während die nächste Modellantwort noch zurückgehalten wird; nach dem Ende ist er `idle`.

Wichtiger beobachteter Sonderfall: Codex 0.154.0 emittiert nach abgelehnter Freigabe **kein PostToolUse**. Das Tool-Ergebnis in der Sessiondatei enthält die zugehörige Call-ID. AIMonitor löst genau diese Anforderung auf und schreibt den korrigierten Zustand unter derselben Dateisperre zurück. Alte Ergebnisse werden bei Bedarf auch außerhalb des 256-KB-Tails gesucht. Die echte Codex-Konfiguration wurde durch diese Integrationstests nicht verändert.

Regressionstests decken ab: mehrere Limit-Buckets und fehlende Werte, Reset-Sekunden, Status-Vorrang, Desktop-Requests und Array-Patches, Revisionlücken, fragmentierte Frames, verspätete Hooks und Turn-Ende, identische parallele Anforderungen, abgelehnte Freigaben, persistente Statuskorrektur, große Sessiondateien, ungültige Hook-Konfiguration, Erhalt fremder Hooks/Backup/Deaktivierung sowie Limits-Notifications auf einer sonst ruhenden RPC-Verbindung.

## Echte Daten

- Limits aus AIMonitors `--diagnose` wurden mit dem Codex-Usage-Tool verglichen: verbleibende Prozentwerte, Zeitfenster und Unix-Reset-Zeitstempel stimmen überein.
- Desktop-IPC: Initialisierung und Live-Snapshot dieser Conversation empfangen; Snapshot-Protokollversion 11. Die laufende Conversation wurde blau angezeigt, eine bekannte inaktive Conversation grau. Updates kamen ohne erneutes Laden des Fensters an.
- Konto-Limits erscheinen einmal; Desktop und CLI erhalten keine addierten oder getrennten fiktiven Kontingente.

## Native Oberfläche

- Fenster, Live-Limits und Einstellungen über den Computer-Use-Zugriff gelesen und visuell betrachtet.
- Hell-, Dunkel- und Systemmodus ausprobiert; Systemmodus wiederhergestellt.
- Einstellungen und Monitor geschlossen; App-Fenster erneut geöffnet.
- **Nutzerbestätigung:** Linksklick öffnet den Monitor, Rechtsklick öffnet die Einstellungen, Monitor lässt sich an der Titelleiste verschieben — „Ja, alle drei funktionieren“.
- Fenster sind normale NSWindows; es gibt kein Popover und keine MenuBarExtra-Fensterszene. Je Rolle wird ein Fenster gehalten, Schließen gibt es nicht frei. Wiederöffnen und Minimierung führen zum bestehenden Fenster.
- Animationen sind auf 0,2 Sekunden begrenzt und deaktivieren sich bei „Bewegung reduzieren“; dies wurde im Code geprüft. Eine systemweite Änderung dieser Bedienungshilfe war für den Test nicht nötig.

Das endgültige Bundle wurde nach den letzten Reducer-Korrekturen erneut gebaut und gestartet. Der Mac war beim anschließenden zusätzlichen GUI-Zugriff wieder gesperrt; die zuvor bestätigten Maus-/Fenster-/Appearance-Tests bleiben die GUI-Nachweise. Die letzten Änderungen betrafen Statuskorrekturen, native Tastaturmenüs und Fehlerbehandlung.

## Review und verbleibende technische Grenzen

Unabhängiges Review über mehrere Korrekturrunden durchgeführt. Behoben: hängenbleibende abgelehnte Freigaben, fälschlich aktive historische CLI-Sessions, Überschreiben ungültiger fremder Hook-Konfiguration, kollabierende Request-Zählung, unsichere numerische Patch-Indizes, unbegrenzte Ereignishistorie, wieder auftauchende abgelehnte Requests und verspätete Tool-Ergebnisse nach Turn-Ende.

CLI-Freigabe-Hooks enthalten bei identischen parallelen Aufrufen keine eindeutige Call-ID. AIMonitor rät in einer mehrdeutigen teilweise aufgelösten Gruppe nicht, sondern zeigt vorübergehend „Status unbekannt“. Der Desktop-IPC ist versionsabhängig. Diese Grenzen und die notwendige einmalige Hook-Bestätigung sind in README und Einstellungen erklärt. Das lokale Bundle ist ad hoc signiert; notarisierten Versand enthält dieser Build nicht.
