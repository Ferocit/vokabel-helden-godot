# Vokabel-Helden (Godot)

Ein rundenbasiertes Lern-Abenteuer im geheimen Dschungeltempel: Vokabeln Deutsch → Englisch sind die
Kampfmechanik. Erkunden, Truhen und Türen mit Vokabeln öffnen, Gegner im JRPG-Kampf besiegen, Beute
sammeln, aufsteigen. HD-2D-Optik: scharfe 16-px-Pixel-Art in einer beleuchteten 3D-Welt.

Port der Phaser-Version auf **Godot 4.7** (GDScript, Forward+).

## Starten

- **Windows:** `start.bat` doppelklicken. Godot wird über die Umgebungsvariable `GODOT`, den bekannten
  Steam-Pfad oder den `PATH` gefunden. Beim ersten Start werden die Ressourcen importiert.
- **Linux/macOS:** `./start.sh`
- **Direkt:** `godot --path .`

### Eigenständige Version (ohne Godot)

`start.bat export` erzeugt `build/windows/Vokabel-Helden.exe` (eine Datei, Daten eingebettet);
`./start.sh export` entsprechend `build/linux/Vokabel-Helden.x86_64`. Voraussetzung sind die
Godot-Export-Templates 4.7.2 (im Editor: *Editor → Export-Vorlagen verwalten → Herunterladen*).
Die Vorlagen stehen in `export_presets.cfg`. In der exportierten Version landen Meldungen unter
`%APPDATA%\Godot\app_userdata\Vokabel-Helden\reports` und werden nur lokal gespeichert.

## Steuerung

| Taste | Aktion |
| --- | --- |
| WASD / Pfeiltasten | bewegen |
| E / Enter / Leertaste | interagieren (Truhe, Tür, Altar, Siegeltor) |
| Esc | Menü (Ausrüstung, Lernstand, Speichern, Beenden) |
| 1–4, ↑↓ / W S + Enter | Kampfbefehl wählen |
| Alt+1 / Alt+2 | Hilfe: Wortlänge / erster Buchstabe |
| F8 oder 🐞 unten rechts | etwas melden |

## Spielablauf

1. **Titel:** Vokabel-Sets auswählen (Filter, Sortierung, Mastery), importieren oder bearbeiten.
2. **Klasse wählen** (Tasten 1–3): Krieger, Schurke oder Magier. Level, Gold und Ausrüstung bleiben.
3. **Erkunden:** Runen ◆ sammeln (Gegner, Türen), um das Siegeltor zum Boss zu öffnen.
   Der Kristallaltar heilt und ist der Rückkehrpunkt nach einer Niederlage.
4. **Kämpfen:** Jede Aktion verlangt eine richtig erinnerte Vokabel. Falsch → die Aktion verpufft, die
   Lösung wird gezeigt und einmal abgetippt; das Wort kommt bald wieder. Gegner kündigen ihre nächste
   Aktion an (z. B. „Schwerer Schlag“ → jetzt verteidigen).
5. **Auswertung:** Was sofort saß, was mit Hilfe, was weiter geübt wird.

Es gibt kein Zeitlimit und keinen Strafsound – Fehler sind Teil des Lernens.

## Vokabeln importieren

Vokabelseite fotografieren, das Foto mit der KI-Anweisung (Knopf „KI-Anweisung kopieren“ im Import)
an eine KI geben und das erzeugte JSON einfügen, als Datei laden oder ins Fenster ziehen:

```json
{
  "version": 1,
  "title": "Unit 3",
  "sourceLanguage": "de",
  "targetLanguage": "en",
  "vocabulary": [
    { "id": "u3_001", "de": "Haus", "en": "house", "alternatives": ["home"], "caseSensitive": true }
  ]
}
```

Vor dem Speichern zeigt eine Tabelle alle Einträge zur Kontrolle; Fehler (leere Felder, doppelte
Einträge) werden markiert. Weitere Seiten lassen sich später an ein Set anhängen. Beispiele liegen in
`vokabeln/`.

## Melden

Der 🐞-Knopf nimmt einen Screenshot auf, sammelt Spielstand und aktuelle Vokabel und legt die Meldung unter
`reports/<Zeitstempel>_<kategorie>/` ab. Ist die [GitHub-CLI](https://cli.github.com) angemeldet
(`gh auth login`), entsteht zusätzlich ein Issue im Repository (`origin`), der Screenshot liegt dann auf dem
Branch `report-screenshots`. Mit `VQ_REPORT_GITHUB=0` wird nur lokal gespeichert.

## Entwicklung

```sh
godot --headless --path . --import                       # einmalig
godot --headless --path . -s res://tests/run_tests.gd    # alle Tests (oder: start.bat test)
godot --headless --path . -s res://tests/run_tests.gd -- test_combat   # gefiltert
```

Der Testläufer wertet auch Script-Fehler während eines Tests als Fehlschlag.

Screenshots ohne Fenster (Linux, z. B. in der Cloud): `tools/shot.sh <name> scene=res://scenes/title.tscn`
(siehe Kommentar in `tools/screenshot.gd`; `run=1` startet ein Abenteuer im Arbeitsspeicher).

### Aufbau

| Ordner | Inhalt |
| --- | --- |
| `logic/` | Spiellogik ohne Darstellung: Lernen (Scheduler, Mastery, Hilfen), Kampf, Levelgenerator, Spielstand |
| `data/` | Klassen, Gegner, Items, Welt-Themen, Beispiel-Set |
| `world/` | 3D-Welt: `level_builder.gd` (Kacheln, Mauern, Urwald, Objekte), `world_fx.gd` (Kamera, Licht, Glow, SSAO, Nebel), `fx.gd` |
| `scenes/` | Titel, Erkundung, Kampf, Auswertung |
| `ui/` | Theme, UI-Helfer, Vokabel-Abfrage, Import-Editor, HUD, Minikarte, Ausrüstung, Statistik, Melden, Sound |
| `tests/` | Testrahmen und Tests |
| `tools/` | Screenshot-Werkzeug |

Spielstände liegen unter `user://save/` (Windows: `%APPDATA%\Godot\app_userdata\Vokabel-Helden\save`).

## Lizenzen

Grafik und Sounds: [Kenney.nl](https://kenney.nl) (CC0). Schriften: Cinzel und Nunito (SIL Open Font
License, siehe `assets/fonts`).
