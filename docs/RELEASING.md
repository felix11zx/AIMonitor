# Neue Version veröffentlichen

Die Updateprüfung liest den neuesten stabilen Release von `felix11zx/AIMonitor` über die öffentliche GitHub-API. Sie installiert nichts automatisch. Verwende für stabile Releases Tags im Format **vMAJOR.MINOR.PATCH**, etwa `v0.3.0`. Entwürfe und Vorabversionen werden nicht angeboten.

1. Erhöhe `CFBundleShortVersionString` und `CFBundleVersion` in `Resources/Info.plist`.
2. Führe die Tests aus:

   ```sh
   CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
   SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
   swift test --cache-path .build/cache --disable-sandbox
   ```

3. Baue das Release-Paket mit `./script/package_release.sh`. Das Script erstellt eine optimierte Universal-App für arm64 und x86_64, prüft die ad-hoc-Signatur und erzeugt ein ZIP sowie `SHA256SUMS.txt` und eine separate `INSTALLATION.md` in `dist/`.
4. Committe den vollständigen Stand und pushe ihn auf GitHub. Der Tag muss auf genau den Quellcode zeigen, aus dem das ZIP gebaut wurde.
5. Erstelle in GitHub einen Release für den neuen Tag und lade das ZIP, `SHA256SUMS.txt` und `INSTALLATION.md` hoch. Markiere ihn als **Latest**, ohne **Pre-release** auszuwählen. Erwähne die Änderungen und die fehlende Developer-ID-Signatur/Notarisierung.
6. Prüfe, dass die Release-Dateien öffentlich herunterladbar sind und dass „Nach Updates suchen“ in der vorherigen App-Version das Update anbietet.

Für die GitHub CLI kannst du die Release-Beschreibung in eine Markdown-Datei schreiben und mit `gh release create <tag> <dateien> --repo felix11zx/AIMonitor --target <commit> --title <titel> --notes-file <markdown-datei> --latest` veröffentlichen.

Ein kostenloses GitHub-Konto reicht für die Veröffentlichung. Eine Developer-ID-Signatur und Apple-Notarisierung sind in diesem Build nicht enthalten.
