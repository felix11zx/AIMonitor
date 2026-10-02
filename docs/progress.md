# SDD ledger — plan: docs/superpowers/plans/2026-10-02-aimonitor.md

Ruling: Direkte Ausführung der bestätigten Spezifikation — der Nutzer fordert ausdrücklich „Passt genau so umsetzen“ — keine erneute Freigabe für dieselbe lokale Umsetzung.
Pre-flight: Task 1 stellt Modelle bereit; Task 2 konsumiert sie; Task 3 konsumiert Modelle und Adapter; Task 4 prüft die ganze App. Keine Namenskonflikte.
Ruling: Im neuen, nur lokal genutzten Projekt arbeiten; keine fremden Änderungen vorhanden. Keine Veröffentlichung.

Task 1 — Modelle/Parser/Reducer: abgeschlossen; Red-Tests beobachtet, implementiert, grüner Testlauf; Core-Commit a2c2404.
Task 2 — Live-Adapter/Hooks: abgeschlossen; echte Limits und IPC-Snapshot gelesen; bestehende Hooks bleiben erhalten, invalides Format wird vor Mutation zurückgewiesen.
Task 3 — Native App: abgeschlossen; signiertes Bundle, Run-Aktion, native Fenster, Appearance und Live-Daten. Nutzer hat beide Mauswege und Verschieben bestätigt.
Task 4 — Integration/Review: abgeschlossen; 18 Core-/RPC-Tests, 6 tatsächliche Codex-Fixture-Szenarien. Unabhängiger Reviewer, gezielte Korrekturen, Regressionstests. Tasks 3/4 werden gemeinsam als fertig geprüfte App lokal committed.
Ruling: Mehrdeutige ID-lose parallele CLI-Freigaben bleiben ausdrücklich unbekannt, bis eine sichere Zuordnung vorliegt; keine erfundene Statusentscheidung. Diese reale Schnittstellengrenze ist dokumentiert.
Ruling: Die echte CLI-Anbindung bleibt bis zur Aktivierung in den Einstellungen und Codex-/hooks-Bestätigung durch den Nutzer aus; dies ist der im Entwurf vorgesehene Einrichtungsfluss. Keine Vertrauensprüfung der echten Codex-Installation umgehen.
Ruling: Letzter zusätzlicher GUI-Zugriff war wegen erneut gesperrtem Mac nicht möglich. Frühere visuelle Tests und direkte Nutzerbestätigung dokumentiert; endgültiges Bundle nach letzten Korrekturen erfolgreich gestartet.
