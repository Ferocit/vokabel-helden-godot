# Godot-Port: Arbeitsstand (Übergabe-Notiz)

- **Gesamtplan:** `C:\Users\Feroc\.claude\plans\schau-dir-mal-die-bubbly-stonebraker.md`
- **Phaser-Original als Referenz:** `G:\VibeCoding\VokabelHeroes`. Dort nichts ändern.
- **Godot:** `E:\Spiele\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe` (4.7.2)
- **Godot in der Cloud (Linux):** 4.7.2 stable von github.com/godotengine/godot-builds, nach `/usr/local/bin/godot` verlinken.
- **Tests:** `godot --headless --path . -s res://tests/run_tests.gd [-- filter]`. Erwartet: 86 grün, etwa 25–40 s.
- **Screenshots:** Linux: `tools/shot.sh <name> scene=res://scenes/title.tscn [call=open_unit_manager]` (xvfb + opengl3).
  Ohne GPU: `apt-get install mesa-vulkan-drivers` (lavapipe) für Forward+, sonst `DRIVER=opengl3`.
  Mit `run=1 [class=rogue] [seed=…] [at=x,y]` startet ein Abenteuer im Arbeitsspeicher.
  Windows: `godot --path . res://tools/screenshot.tscn -- out=screenshots/x.png scene=…`. Argumente mit `|` trennen, `@pfad` übergibt Dateiinhalt.
- **Repo:** github.com/Ferocit/vokabel-helden-godot (privat), Branch `main`.

## Erledigt
- **Phase 1:** Die gesamte Logik ist portiert, mit 50 grünen Tests:
  - `logic/learning`, `logic/io`, `logic/game`
  - `data/game_data.gd`
  - Der Generator ist mit einem inline gerechneten A* optimiert.
- **Phase 2:** Titelbildschirm komplett, 8 UI-Tests.
  - Autoloads `UiTheme` (`ui/ui_theme.gd`, Theme im Code, variable Fonts mit wght) und `Sound`
  - `ui/ui.gd` (class `UI`): Farben, Label/Button/Fenster/Modal/Bestätigung/Mastery-Balken/Toast, `focus_later`
  - `scenes/title.tscn`: Set-Liste (Filter, Sortierung, Datum, Mastery, ✎, Alle/Keine), Import + Drag & Drop
    (`files_dropped`), Klassenwahl (1–3), Sets & Statistik, Ausrüstung mit Händler, Fortsetzen
  - `ui/import_dialog.gd` (Tabellen-Editor mit Anhängen), `ui/stats_view.gd`, `ui/equipment_view.gd`
  - Testläufer startet jetzt im ersten Frame (damit `_ready` beim Einhängen läuft)
- **Phase 3:** HD-2D-Erkundung in 3D, 12 Welt-Tests.
  - `world/level_builder.gd`: Boden, Mauerblöcke (2 hoch, Rückwände), Urwald und Deko als zur Kamera geneigte
    Sprite-Quads, pro 8×8-Chunk zu Meshes zusammengefasst. Vor Wegen nur niedrige Büsche (Sichtlinie).
    Objekte (Gegner, Truhen, Türen, Altar) als Sprite3D mit Licht, Markierungspfeil (immer sichtbar), Funken.
  - `world/world_fx.gd`: Kamera (52°, FOV 34), Glow, SSAO, Nebel, Filmic, Vignette, Glühwürmchen, Blätter. Keine DOF.
  - `world/fx.gd`: Pixel-Fackel (3 Frames), Pfeil, Schatten, Lichtstrahl; Flicker/FrameAnim/Bob-Helfer.
  - `scenes/exploration.tscn`: Bewegung mit Wandgleiten, Interaktion (E/Enter/Leertaste), Truhen/Türen per
    Vokabeln (`run_challenge`), Altar, Siegeltor, HUD (`ui/hud.gd`), Minikarte (`ui/minimap.gd`), Toasts, Menü (Esc).
  - `ui/vocab_prompt.gd`: Abfrage mit Hilfen (Alt+1/2), Fehlerkorrektur durch Abtippen, Esc bricht ab.
  - `ui/controls.gd`: Input-Actions zur Laufzeit. Titel-Kulisse ist jetzt ein schwenkendes 3D-Level.
  - Kampfstart ruft `res://scenes/combat.tscn` auf (Knoten mit `object_id` und Signal `finished(data)`),
    Rückgabe über `on_combat_return({objectId, outcome, messages, victory?})`.
- **Phase 4:** Kampf, 7 Kampf-Tests.
  - `scenes/combat.tscn`: Tempelhalle als 3D-Arena (LevelBuilder mit kleiner Karte, flache Kamera 24°),
    Gegner links (Größe nach Stufe), Held rechts, Absichtsblase über dem Gegner (unproject), Panels unten,
    Befehle 1–4 / ↑↓ / W/S + Enter, Vokabel je Aktion, Ereignisse mit Effekten (Schadenszahlen als Label3D,
    Funken, Ringe, Schild, Blitz, Wackeln), Klassenangriffe (Krieger-Sturm + Schockwelle, Schurken-Nachbilder +
    Kreuzhiebe + Giftwolke, Magier-Zauberkreis + Feuerball mit Licht und Funkenspur), Sieg/Niederlage-Fenster.
  - `static var fast` in Kampf und Erkundung (sowie `VocabPrompt.instant`) macht Abläufe für Tests synchron.
  - Theme wird in das Standard-Theme gemischt (gilt so auch unter CanvasLayer/3D). `UI.pin()` verankert Overlays.
- **Phase 5:** Auswertung und Sound, 4 Tests.
  - `scenes/summary.tscn`: Sternenhimmel, Kennzahlen, Wort-Chips (sofort gewusst, mit Hilfe, üben), schwierigste
    Wörter mit Mastery, Zeit/XP/Gold/Beute, „Zurück zum Titel“ (setzt `Ctx.run = {}`).
  - Test prüft, dass jede im Code verwendete Sound-ID als Datei unter `assets/audio` existiert.
- **Phase 6:** Melden, Start, README, 4 Tests.
  - Autoload `Reporter` (`ui/reporter.gd`): 🐞-Knopf bzw. F8 in jeder Szene, Screenshot (abwählbar), Kategorien,
    Kontext (Szene, offene Dialoge, aktuelle Vokabel mit Treffern in allen Sets, Abenteuer, Log-Auszug),
    pausiert das Spiel. Ablage unter `reports/` (exportiert: `user://reports`), GitHub-Issue per `gh` im
    Hintergrund-Thread inkl. Screenshot-Upload auf Branch `report-screenshots`. `VQ_REPORT_GITHUB=0` = nur lokal.
  - `start.bat` (GODOT-Variable, Steam-Pfad, PATH; `start.bat test`), `start.sh`, `README.md`.
  - Testläufer zählt Script-Fehler über einen `Logger` und wertet sie als Fehlschlag.

- **Nach Phase 6:** Bäume zwischen Kamera und Held werden per `world/foliage.gdshader` durchsichtig gedithert
  (globaler Shader-Parameter `player_world`, gesetzt in `exploration._place_hero`, sonst weit weg = aus).
- Export-Vorlagen Windows/Linux (`export_presets.cfg`), `start.bat export` / `./start.sh export`. In der Cloud
  geprüft: beide Exporte erzeugt, Linux-Build startet fehlerfrei bis zum Titel; JSON-Daten sind im Paket.

## Stand
Alle sechs Phasen sind portiert. Mögliche nächste Schritte:
- Auf echter Hardware (Windows, Forward+) spielen und Licht/Kamera feinjustieren; in der Cloud wurde mit
  lavapipe (Software-Vulkan) geprüft.

**Arbeitsweise:**
- Selbstständig ohne Rückfragen arbeiten.
- Nach jeder Änderung Tests ausführen, committen und pushen.
- Screenshots über `tools/shot.sh` bzw. `tools/screenshot.tscn` prüfen.
- Diese Datei aktuell halten.
