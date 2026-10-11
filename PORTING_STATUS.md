# Godot-Port: Arbeitsstand (Übergabe-Notiz)

- **Gesamtplan:** `C:\Users\Feroc\.claude\plans\schau-dir-mal-die-bubbly-stonebraker.md`
- **Phaser-Original als Referenz:** `G:\VibeCoding\VokabelHeroes`. Dort nichts ändern.
- **Godot:** `E:\Spiele\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe` (4.7.2)
- **Godot in der Cloud (Linux):** 4.7.2 stable von github.com/godotengine/godot-builds, nach `/usr/local/bin/godot` verlinken.
- **Tests:** `godot --headless --path . -s res://tests/run_tests.gd [-- filter]`. Erwartet: 58 grün, etwa 25–40 s.
- **Screenshots:** Linux: `tools/shot.sh <name> scene=res://scenes/title.tscn [call=open_unit_manager]` (xvfb + opengl3).
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

## Nächste Schritte (siehe Plan, Abschnitt „Reihenfolge“)
1. **Phase 3:** HD-2D-Erkundung in 3D (`world/level_builder.gd`):
   - Sprite3D-Billboards, OmniLight-Fackeln
   - WorldEnvironment mit Glow, SSAO und Nebel; **keine Tiefenunschärfe**
   - Titel-Kulisse (`title.gd/_build_backdrop`) danach durch schwenkendes 3D-Level ersetzen
2. **Phase 4:** Kampf
3. **Phase 5:** Auswertung, Sound
4. **Phase 6:** Melden via gh, start.bat, README

**Arbeitsweise:**
- Selbstständig ohne Rückfragen arbeiten.
- Nach jeder Phase Tests ausführen, committen und pushen.
- Screenshots über ein Hilfsskript in `tools/` prüfen.
- Diese Datei aktuell halten.
