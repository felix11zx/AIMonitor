# AIMonitor installieren

AIMonitor zeigt den Status deiner Codex-Chats und deine Konto-Limits direkt in der macOS-Menüleiste. Voraussetzung: **macOS 14 oder neuer** und eine installierte, angemeldete Codex-App bzw. Codex CLI. Der Download unterstützt **Apple Silicon und Intel**.

1. Öffne die [neueste Version auf GitHub](https://github.com/felix11zx/AIMonitor/releases/latest).
2. Lade `AIMonitor-<Version>-macOS-universal.zip` herunter und entpacke es per Doppelklick. Die automatisch angebotenen „Source code“-Archive enthalten nur den Quellcode.
3. Ziehe **AIMonitor.app** in den Ordner **Programme**.
4. Öffne AIMonitor. Das Symbol erscheint oben in der Menüleiste.

## macOS-Sicherheitswarnung beim ersten Start

Ich habe keinen kostenpflichtigen Apple-Developer-Account. Deshalb ist die App **nicht mit einer Apple Developer ID signiert und nicht von Apple notarisiert**. Das Bundle ist lediglich ad hoc signiert. macOS kann beim ersten Start beispielsweise melden, dass der Entwickler nicht verifiziert werden kann oder Apple die App nicht auf Schadsoftware überprüfen konnte.

Wenn du die App aus diesem Repository heruntergeladen hast und ihr vertraust:

1. Versuche die App zu öffnen und schließe die Warnung mit **Fertig** bzw. **Abbrechen**.
2. Öffne **Systemeinstellungen → Datenschutz & Sicherheit**.
3. Scrolle zum Hinweis über AIMonitor und wähle **Dennoch öffnen**.
4. Bestätige gegebenenfalls mit deinem Mac-Passwort bzw. Touch ID und anschließend **Öffnen**.

Die Ausnahme gilt für diese App. [Apple beschreibt diesen Ablauf hier](https://support.apple.com/de-de/102445).

Der vollständige Quellcode ist öffentlich und unter der MIT-Lizenz verfügbar. Wenn du Bedenken hast, kannst du ihn durchlesen und die App selbst bauen. Offener Quellcode ersetzt keine Sicherheitsprüfung der heruntergeladenen Datei. Die oben beschriebene Entwickler-/Notarisierungswarnung bedeutet für sich genommen keine erkannte Schadsoftware; bei einer konkreten Schadsoftware- oder Beschädigungswarnung solltest du die Datei nicht auf diesem Weg freigeben.

## So benutzt du die App

- **Linksklick** auf das Menüleistensymbol öffnet den Monitor.
- **Rechtsklick / Control-Klick** öffnet die Einstellungen.
- **Blau:** Codex arbeitet. **Orange:** Codex braucht eine Eingabe oder Freigabe. **Grau:** inaktiv bzw. unbekannt; der genaue Status steht im Fenster.
- Konto-Limits und Reset-Countdown werden automatisch aktualisiert.
- Für Desktop-Status muss Codex Desktop geöffnet sein. Für CLI-Status in den Einstellungen die Beobachtungs-Hooks aktivieren, CLI neu starten und in Codex unter `/hooks` bestätigen.

## Updates installieren

Öffne **Einstellungen → Updates → Nach Updates suchen**. Bei einer neuen Version erscheint **Update auf GitHub herunterladen**. Lade das neue ZIP herunter, beende AIMonitor und ersetze die App im Ordner Programme. Starte sie anschließend erneut; die Einstellungen bleiben erhalten. Bei einer neuen Datei kann macOS erneut die oben beschriebene Freigabe verlangen. Bestätige nach einem Update gegebenenfalls die CLI-Hooks erneut unter `/hooks`.

Installiere die App vor dem Aktivieren der CLI-Hooks am endgültigen Ort. Wenn du sie später verschiebst, deaktiviere die Hooks vor dem Verschieben und aktiviere sie danach erneut: Sie enthalten den absoluten App-Pfad.

## Download prüfen (optional)

Im Release liegt `SHA256SUMS.txt`. Lade die Datei neben das ZIP und prüfe im Terminal in diesem Ordner:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

`OK` bestätigt, dass das ZIP mit der veröffentlichten Prüfsumme übereinstimmt. Es ist kein unabhängiger Sicherheitsnachweis.
