# Rogue-lite-System (Stand 2)

## Grundidee
Jedes Abenteuer beginnt bei null: **Level 1, Holzschwert, kein Gold, keine Tasche**. Was im Lauf gefunden
wird (Ausrüstung, Gold, Level), verfällt am Ende. Dauerhaft bleiben nur:

| Dauerhaft | Wo |
| --- | --- |
| 🔷 Tempelsplitter (Meta-Währung) | `profile.shards` |
| Freigeschaltete Klassen | `profile.unlockedClasses` (Start: nur Krieger) |
| Skillbaum-Ränge je Klasse | `profile.skills[klasse][knoten] = rang` |
| Statistik (Abenteuer, Siege, Splitter gesamt, freie Tempelstufe) | `profile.records` |
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

## Im Abenteuer (Stand 2)
- **3 Leben** (`meta.lives`): Jede Niederlage kostet eins; man erwacht am Kristallaltar. Ohne Leben endet das
  Abenteuer – Splitter gibt es trotzdem für alles Erreichte (ohne Siegbonus). HUD: ❤.
- **Segnungen** (`data/blessings.gd`): Nach jedem Elite-Sieg eine von 3 zufälligen Segnungen wählen (Tasten 1–3).
  Gelten bis zum Ende des Abenteuers (`profile.blessings`), nutzen die Skill-Effektschlüssel.
- **Händler am Kristallaltar:** pro Abenteuer und Altar 3 feste Angebote (Seed), Preise nach Seltenheit
  (`meta.shopPrice` 20/45/90), dazu Heiltränke. Gekauftes landet in der Tasche.
- **Gegenstände** nutzen ebenfalls die Skill-Effektschlüssel (z. B. Wandererring = Tempo, Runenklinge =
  Fähigkeitsschaden). Keine Gratis-Vokabelhilfen mehr; einzige Lern-Ausnahme bleibt der Bibliotheksring
  (falsch beantwortete Wörter kommen früher wieder – hilft beim Lernen, nicht beim Antworten).

## Tempelstufen (Schwierigkeit)
Ein Sieg auf der höchsten freien Stufe schaltet die nächste frei (bis 5). Vor dem Abenteuer im Titel wählbar.
Pro Stufe: Gegner +25 % HP, +20 % Angriff, +25 % Splitter (`meta.heat`). Gegenstück zur wachsenden Stärke durch
Skillbäume.

## Gemessene Balance (Bot-Simulation, `tests/test_balance.gd`)
Der Bot weiß 80 % der Wörter und heilt sich vor Elite und Boss – echte Spieler sind eher schwächer.

| Fall | Läufe verloren | Ø Splitter |
| --- | --- | --- |
| Stufe 0, keine Skills, 80 % | 0/40 | ≈ 42 |
| Stufe 0, keine Skills, 60 % | 0/40 | ≈ 42 |
| Stufe 3, keine Skills | 19/30 | – |
| Stufe 3, voller Krieger-Baum | 0/30 | ≈ 76 |
| Stufe 5, voller Krieger-Baum | 2/30 | ≈ 108 |

Folgerung: Schurke nach dem ersten Sieg, Magier nach dem zweiten freischaltbar; ein Baum braucht ≈ 5 Siege.
Die Tests sichern diese Eckwerte ab (Splitter 30–60 pro Sieg, Stufe 3 braucht Skills, Stufe 5 bleibt schaffbar).

## Offene Ideen zum Weiterentwickeln
- Balance mit echten Spielern prüfen (der Bot spielt nahezu optimal).
- Weitere Welten mit eigenen Gegnern und Bossen (Freischaltung über Splitter oder Tempelstufen).
- Weitere Freischaltungen: Welten, kosmetische Helden, neue Startwaffen.
