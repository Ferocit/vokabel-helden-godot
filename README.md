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
| I | Charakter & Inventar (Ausrüstung an-/ablegen, verkaufen, Werte) |
| Esc | Menü (Lernstand, Speichern, Beenden) |
| 1–4, ↑↓ / W S + Enter | Kampfbefehl wählen |
| Alt+1 / Alt+2 | Hilfe: Wortlänge / erster Buchstabe |
| F8 oder 🐞 unten rechts | etwas melden |
| Controller | Stick/Steuerkreuz bewegen, A interagieren, Y Inventar, Start Menü |

Einstellungen (Ton, Lautstärke, Vollbild) und eine Spielanleitung gibt es im Titel über ⚙ und ❔.

## Spielablauf

1. **Titel:** Vokabel-Sets auswählen (Filter, Sortierung, Mastery), importieren, bearbeiten oder trainieren.
   „🚪 Spiel verlassen“ beendet das Spiel.
2. **Klasse wählen** (Tasten 1–3): Krieger, Schurke oder Magier (Schurke und Magier müssen erst freigeschaltet werden).
3. **Erkunden:** Runen ◆ sammeln (Gegner, Türen), um das Siegeltor zum Boss zu öffnen. **Wissensschreine**
   (blaue Steintafeln) fragen drei Vokabeln ab – je mehr richtig, desto besser die Belohnung, alle drei heilen.
   **Runenplatten** in den Gängen fragen beim Drüberlaufen ein Wort ab (richtig: Gold, falsch: ein paar HP).
   Der Kristallaltar heilt und ist der Rückkehrpunkt nach einer Niederlage.
4. **Kämpfen:** Jede Aktion verlangt eine richtig erinnerte Vokabel. Falsch → die Aktion verpufft, die
   Lösung wird gezeigt und einmal abgetippt; das Wort kommt bald wieder. **Fast richtig** (ein Tippfehler oder
   nur die Großschreibung falsch): Die Aktion wirkt halb so stark, die richtige Schreibweise wird gezeigt.
   Kleingeschriebene Lösungen dürfen auch großgeschrieben werden („House“ für „house“).
   **Kombo ⚡:** Richtige Antworten in Folge ohne Hilfe machen Angriffe stärker (bis ×1,5); ein Fehler setzt sie zurück. Gegner kündigen ihre nächste
   Aktion an (z. B. „Schwerer Schlag“ → jetzt verteidigen).
5. **Auswertung:** Was sofort saß, was mit Hilfe, was weiter geübt wird – und die verdienten 🔷 Tempelsplitter.
   Freiwillig gibt es die **📝 Letzte Prüfung**: Die Fehlerwörter des Abenteuers noch einmal ohne Hilfe, je zwei
   richtige bringen einen Bonus-Splitter (`meta.shards.finalExamPer`).

**Rogue-lite:** Jedes Abenteuer beginnt auf Level 1 mit Holzschwert; Ausrüstung, Gold und Level verfallen am
Ende. Mit Tempelsplittern werden dauerhaft Klassen freigeschaltet (anfangs nur der Krieger) und Skillbäume
ausgebaut (Titel → „🌳 Fertigkeiten“). Pro Abenteuer gibt es 3 Leben, bei jedem Level-up ein Talent zur Wahl,
Segnungen nach Elite-Siegen und einen Händler am Kristallaltar; nach Siegen werden schwerere Tempelstufen frei. Details: `ROGUELITE.md`.

Es gibt kein Zeitlimit und keinen Strafsound – Fehler sind Teil des Lernens.

**Welche Vokabel drankommt:** Für jedes Wort wird über alle Abenteuer und Trainings hinweg gezählt, wie oft
es dran war, wie oft es auf Anhieb (ohne Hilfe und ohne vorherigen Fehler) richtig war und ob es zuletzt
falsch war (Titel → „Sets & Statistik“ → Statistik). Noch nie oder selten abgefragte und zuletzt falsche
Wörter haben Vorrang; wer ein Wort mehrmals in Folge auf Anhieb weiß, bekommt es deutlich seltener
(Gewichte unter `learning` in `config/game.json`).

**⏱ Zeit-Challenge (optional):** Im Titel unter „Neues Abenteuer“ einschaltbar. Dann muss das ganze Abenteuer
in einer festen Zeit geschafft werden: 6 Minuten + 15 Sekunden pro Vokabel der gewählten Sets, mindestens
10 und höchstens 40 Minuten (`timeChallenge` in `config/game.json`). Die Uhr läuft auch in Kämpfen und
Abfragen und steht nur im Menü (Esc) und im Inventar (I) still. Läuft sie ab, wird die laufende Aktion noch beendet, dann endet
das Abenteuer. Ein Sieg in der Zeit bringt +30 % Tempelsplitter.

**🎯 Training:** Mit 🎯 neben einem Set (oder „🎯 Training“ unter „Sets & Statistik“) übt man ohne Spiel:
Karte mit dem deutschen Wort, englisch eintippen, keine Hilfen. Falsche Wörter kommen am Ende der Runde
noch einmal, bis alle sitzen. Jede Antwort zählt für Statistik und Mastery; wer alle schafft, bekommt
einen 🔷 Tempelsplitter je 5 Wörter (mindestens einen, `training.wordsPerShard`).

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

**Balancing-Simulator:** `start.bat sim` (bzw. `./start.sh sim`) spielt viele Abenteuer mit einem Bot und gibt
Tabellen aus (Siegquote, Splitter, Abfragen pro Minute, Lernzuwachs …). Optionen als `schlüssel=wert`, Listen mit
Komma, z. B. `start.bat sim runs=40 class=warrior,mage learner=beginner,average heat=0,3 skills=none,full` oder
`start.bat sim campaign=8` (mehrere Läufe mit Meta-Fortschritt). Alle Optionen: `tools/sim.gd`, Modell und Bot:
`logic/sim/balance_sim.gd`, Annahmen: `simulation` in `config/game.json`. Änderungen an Kampf, Lernen oder
Belohnungen ziehen den Simulator und `tests/test_balance.gd` mit.

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
| `logic/sim/` | Balancing-Simulator (Bot, Lerner-Modell, Zeitmodell) |
| `tools/` | Screenshot-Werkzeug, Simulator-Kommandozeile (`sim.gd`) |

Spielstände liegen unter `user://save/` (Windows: `%APPDATA%\Godot\app_userdata\Vokabel-Helden\save`).

## Lizenzen

Grafik und Sounds: [Kenney.nl](https://kenney.nl) (CC0). Schriften: Cinzel und Nunito (SIL Open Font
License, siehe `assets/fonts`).
Die Helm-Symbole in `assets/tiles/items.png` sind eigene Pixel-Art im Kenney-Stil, erzeugt mit
`python tools/item_icons.py` (dort als Pixelraster beschrieben und leicht anpassbar).
