# Godot-Port: Arbeitsstand (Übergabe-Notiz)

- **Gesamtplan:** `C:\Users\Feroc\.claude\plans\schau-dir-mal-die-bubbly-stonebraker.md`
- **Phaser-Original als Referenz:** `G:\VibeCoding\VokabelHeroes`. Dort nichts ändern.
- **Godot:** `E:\Spiele\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe` (4.7.2)
- **Tests:** `godot --headless --path . -s res://tests/run_tests.gd [-- filter]`. Erwartet: 50 grün, etwa 40 s.
- **Repo:** github.com/Ferocit/vokabel-helden-godot (privat), Branch `main`.

## Erledigt
- **Phase 1:** Die gesamte Logik ist portiert, mit 50 grünen Tests:
  - `logic/learning`, `logic/io`, `logic/game`
  - `data/game_data.gd`
  - Der Generator ist mit einem inline gerechneten A* optimiert.
- **Phase 2 (begonnen):**
  - Schriften Cinzel und Nunito unter `assets/fonts` (OFL)
  - `ui/assets.gd` für Sheet-Frames
  - `ui/sound.gd`, gedacht als Autoload „Sound“, noch nicht in `project.godot` eingetragen

## Nächste Schritte (siehe Plan, Abschnitt „Reihenfolge“)
1. **Phase 2:**
   - `ui/ui_theme.gd`: Theme im Code bauen. Stil: dunkle Fenster, Goldrand #c9a96a, Cinzel-Überschriften, Nunito-Text. Vorlage ist `src/style.css` im Phaser-Projekt.
   - `ui/ui.gd`: Helfer für Label, Button, Fenster, Modal, Bestätigung, Mastery-Balken und Toast.
   - Autoloads Sound und Theme eintragen.
   - `scenes/title.tscn` und `title.gd`:
     - Set-Liste mit Filter, Sortierung, Datum, Mastery, ✎ und Alle/Keine
     - Import-Knopf und Drag&Drop
     - Klassenwahl mit den Tasten 1–3
     - Sets & Statistik, Ausrüstung
     - Fortsetzen
   - `ui/import_dialog.gd` (Tabellen-Editor).
   - `run/main_scene` zeigt bereits auf `res://scenes/title.tscn`.
2. **Phase 3:** HD-2D-Erkundung in 3D (`world/level_builder.gd`):
   - Sprite3D-Billboards, OmniLight-Fackeln
   - WorldEnvironment mit Glow, SSAO und Nebel; **keine Tiefenunschärfe**
3. **Phase 4:** Kampf
4. **Phase 5:** Auswertung, Sound
5. **Phase 6:** Melden via gh, start.bat, README

**Arbeitsweise:**
- Selbstständig ohne Rückfragen arbeiten.
- Nach jeder Phase Tests ausführen, committen und pushen.
- Screenshots über ein Hilfsskript in `tools/` prüfen.
- Diese Datei aktuell halten.
