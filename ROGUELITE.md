# Rogue-lite-System (Stand 1)

## Grundidee
Jedes Abenteuer beginnt bei null: **Level 1, Holzschwert, kein Gold, keine Tasche**. Was im Lauf gefunden
wird (Ausrüstung, Gold, Level), verfällt am Ende. Dauerhaft bleiben nur:

| Dauerhaft | Wo |
| --- | --- |
| 🔷 Tempelsplitter (Meta-Währung) | `profile.shards` |
| Freigeschaltete Klassen | `profile.unlockedClasses` (Start: nur Krieger) |
| Skillbaum-Ränge je Klasse | `profile.skills[klasse][knoten] = rang` |
| Statistik (Abenteuer, Siege, Splitter gesamt) | `profile.records` |
| Lernfortschritt der Vokabeln | unverändert (`progress`) |

## Splitter verdienen
Am Ende jedes Abenteuers (Sieg **oder** vorzeitiges Beenden über das Menü), Werte in `config/game.json → meta.shards`:

| Quelle | Splitter |
| --- | --- |
| normaler Gegner | 1 |
| Elite-Gegner | 3 |
| Boss | 10 |
| Truhe | 1 |
| Tür | 2 |
| je 5 richtig erinnerte Vokabeln | 1 |
| Tempel bezwungen (Sieg) | 10 |

Ein vollständiger Sieg bringt grob 30–50 Splitter (geschätzt, nicht ausbalanciert getestet). Ein abgebrochenes Abenteuer zahlt für das bis dahin Erreichte –
es gibt keine Strafe fürs Aufhören (Lernspiel).

## Ausgeben
- **Klassen freischalten:** Schurke 25 🔷, Magier 40 🔷 (`meta.classUnlockCost`).
- **Skillbaum je Klasse:** 3 Zweige × 3 Stufen, Ränge 3/2/2. Preis = Stufenpreis × Rang
  (`meta.tierCost` = 3 / 6 / 10). Stufe 2/3 eines Zweigs braucht mind. Rang 1 der Stufe davor.
  Einen Baum komplett auszubauen kostet 198 🔷.

| Klasse | Zweige |
| --- | --- |
| Krieger | Bollwerk (HP, Verteidigen, Rüstung) · Klinge (Angriff, Fähigkeit, Krit) · Wanderer (Tempo, Startträge, HP nach Sieg) |
| Schurke | Schatten (Krit, Krit-Schaden, Angriff) · Gift (Fähigkeit, Giftdauer, Tränke) · Streuner (Tempo, Gold, Splitter) |
| Magier | Glut (Fähigkeit, Krit, Angriff) · Arkanschild (HP, Verteidigen, HP nach Sieg) · Gelehrter (Tempo, Tränke, Splitter) |

**Designregel:** Fertigkeiten helfen nie beim Vokabellernen – keine Gratis-Hilfen, keine billigeren Hilfen,
kein zusätzlicher Fokus. Die Klassen-Passiven (Schurke: 1× erster Buchstabe, Magier: 1× Wortlänge) bleiben wie bisher.

## Code
| Datei | Inhalt |
| --- | --- |
| `data/skill_trees.gd` | Bäume, Effekttexte (Daten – hier neue Knoten ergänzen) |
| `logic/game/meta.gd` | Freischalten, Lernen, Effekte summieren, Reset pro Lauf, Belohnung |
| `logic/game/player.gd` | `compute_stats` addiert `maxHp`/`attack`, liefert `mods` |
| `logic/game/combat_service.gd` | `combat_player_from(base, cls, mods)`: Verteidigen, Krit, Fähigkeit, Gift, Rüstung, Trankheilung |
| `logic/game/game_context.gd` | `start_run` setzt zurück, `end_run(victory)` zahlt einmalig aus, Goldbonus in `apply_loot`, `move_speed_factor()` |
| `ui/skill_tree_view.gd` | Fertigkeiten-Bildschirm (Titel → „🌳 Fertigkeiten“) |

Neue Effekte: Schlüssel in `SkillTrees.EFFECT_TEXT` eintragen und an der passenden Stelle mit
`Meta.mod(stats.mods, "schluessel")` auswerten. `tests/test_meta.gd` prüft u. a., dass jeder Effekt bekannt ist.

## Offene Ideen zum Weiterentwickeln
- **Niederlage beendet den Lauf?** Aktuell erwacht man weiter am Kristallaltar (lernfreundlich). Echte
  Rogue-lite-Spannung: Niederlage = Ende, aber Splitter für das Erreichte.
- **Händler im Lauf:** Gold hat nur noch innerhalb des Laufs Wert (Heiltränke). Ein Händler-Raum mit Ausrüstung
  oder Segnungen pro Lauf würde Gold wichtiger machen.
- **Lauf-Segnungen:** zufällige Boni zur Auswahl nach Elite-Kämpfen (klassisches Rogue-lite-Element).
- **Schwierigkeitsstufen** („Tempelfluch“) für mehr Splitter.
- Weitere Freischaltungen: Welten, kosmetische Helden, neue Startwaffen.
