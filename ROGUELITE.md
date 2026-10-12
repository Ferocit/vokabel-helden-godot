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
- **Regel-Segnungen und Duos** (Issue #20): Neben Werte-Segnungen (gewöhnlich) gibt es seltene und legendäre
  Segnungen, die richtiges Erinnern belohnen: ⚡ Kettenblitz (Kombo 3, 6 … trifft doppelt), 📜 Rache des Gelehrten
  (früher falsches Wort jetzt richtig: doppelter Schaden), 🎯 Jagdinstinkt (erster Treffer kritisch), 🩸 Lebensdurst
  (Krit heilt), 🐍 Schlangenbiss (Schurke: Gift stapelt sich), ✨ Funkenflug (Magier: Krit gibt Fokus).
  Gezogen wird gewichtet nach Seltenheit (6 : 3 : 1,2), klassengebundene nur für ihre Klasse. Zwei passende
  Segnungen ergeben eine **Duo-Segnung** (z. B. Steinhaut + Schildgebet = 🏰 Festung), die von selbst wirkt; die
  Auswahl zeigt an, welche Karte ein Duo vervollständigt. Regel-Talente: Überraschungsangriff, Kampfeslust, Geistesblitz.
- **Talente** (`data/talents.gd`): Jedes Level-up im Abenteuer bringt eine Wahl aus 3 zufälligen Talenten
  (Tasten 1–3), z. B. +8 HP, +1 Angriff, +5 % Krit. Stapelbar bis zur jeweiligen Höchststufe, kleiner als
  Segnungen, gelten bis zum Ende des Abenteuers (`profile.talents`, offene Wahlen `profile.pendingTalents`).
  Die Wahl erscheint in der Erkundung, sobald man frei ist (auch nach einem Kampf).
- **Kombo** (`logic/game/combo.gd`, `combat.combo`): Jede auf Anhieb richtige Antwort (ohne Hilfe) erhöht die Kombo,
  Angriffe und Fähigkeiten machen dann +10 % Schaden je Stufe (bis ×1,5). Mit Hilfe oder „fast richtig“ bleibt sie
  stehen, ein Fehler setzt sie zurück. Sie gilt für das ganze Abenteuer (auch Truhen und Türen). Ausgleich: Gegner
  haben ×1,3 HP (`combat.enemyHpFactor`).
- **Händler am Kristallaltar:** pro Abenteuer und Altar 3 feste Angebote (Seed), Preise nach Seltenheit
  (`meta.shopPrice` 20/45/90), dazu Heiltränke. Gekauftes landet in der Tasche.
- **Gegenstände** nutzen ebenfalls die Skill-Effektschlüssel (z. B. Wandererring = Tempo, Runenklinge =
  Fähigkeitsschaden). Keine Gratis-Vokabelhilfen mehr; einzige Lern-Ausnahme bleibt der Bibliotheksring
  (falsch beantwortete Wörter kommen früher wieder – hilft beim Lernen, nicht beim Antworten).

## Biome (Issue #28, `GameData.THEMES`)
Jede Ebene hat ein eigenes Biom (`GameData.theme_for_floor`): 1 Dschungeltempel, 2 Kristallhöhle, 3 Eistempel. Ein
Thema bestimmt Gegner und Boss sowie `look`: Boden-, Weg- und Pflanzen-Kacheln samt Sheet, Farbtöne von Raumboden,
Mauern und Pflanzen, Hintergrund, Nebel, Umgebungslicht, Fackellicht und Partikel. Die Kristallhöhle nutzt
umgefärbte Dungeon-Kacheln und -Gegner (`tint`), der Eistempel Kenney „Tiny Ski“ (Schnee, verschneite Bäume, Yetis,
Schneemann; `sheet: "ski"`). Neue Biome: Eintrag in `THEMES` mit `look` und Gegnern anlegen.

## Nemesis-Boss (Issue #24, `logic/learning/nemesis.gd`, `nemesis`)
Der Boss eröffnet mit „Ich kenne deine Schwachstellen …“ und trägt bis zu 3 Rüstungsteile – die schwierigsten
Wörter des Spielers über alle Abenteuer (hohe Fehlerquote, wenig Mastery, zuletzt falsch). Solange Rüstung hält,
kommt nur 50 % des Schadens durch. Angriffe fragen die Rüstungswörter ab; richtig beantwortet zerbricht das Teil,
falsch rückt es nach hinten. Wörter mit Mastery ≥ 0,9 verschwinden aus der Rüstung – der Boss wird mit dem
Lernfortschritt sichtbar schwächer. Simulator: Spalte „Nemesis gebrochen“.

## Tempelarchiv (Issue #23, `data/unlocks.gd`, Titel → „🏛 Archiv“)
Splitter schalten neue **Inhalte** frei statt nur Werte: seltene Gegenstände (Runenklinge, Präzisionsklinge,
Ritterhelm, Bibliotheksring, Heilerreif) kommen erst danach in Beute und Händler, die Regel-Segnungen
(Kettenblitz 40 🔷 u. a.) und Regel-Talente erst danach in die Auswahl. Dazu Startwaffen (Jägerdolch, Fokusstab,
Eisenschwert) und Aussehen je Klasse (reine Optik). Die **Sammlung** zeigt das Bestiarium (`profile.bestiary`),
gefundene Gegenstände (`profile.found`), sehr sichere Wörter und Set-Sterne.
Gesamtkosten: 3 Skillbäume ≈ 594 🔷 + Archiv ≈ 430 🔷. Simulator-Kampagne (eine Klasse, Bot nutzt alle Pakt-Punkte):
Baum nach 3 Läufen, Archiv (ohne Aussehen) nach ≈ 5 Läufen.

## Ebenen (Issue #27, `config/game.json → floors`)
Nach dem Bosssieg führt eine Treppe tiefer: „⬇ Tiefer hinab“ oder „🏆 Abenteuer beenden“ (bis Ebene 3). Unten gibt
es eine neue Karte (Seed `Meta.floor_seed`), Gegner haben pro Ebene +110 % HP und +80 % Angriff. Held, Ausrüstung,
Talente, Segnungen, Leben, Kombo und Lernstand bleiben; HP und Fokus werden aufgefüllt. Alles Erreichte früherer
Ebenen zählt weiter (`run.pastCounts`), jede bezwungene Ebene zahlt den Siegbonus – auch wenn man tiefer unten
scheitert. Simulator: `start.bat sim floors=3` (der Bot steigt nur mit mindestens 2 Leben ab).
Gemessen (Durchschnitt, Stufe 0, 30 Läufe): Ø 2,8 von 3 Ebenen, ≈ 150 Splitter, ≈ 185 Abfragen pro Lauf.

## Gegnerbewegung (`logic/game/enemy_agent.gd`, Werte in `config/game.json → enemyAI`)
- **Normale Gegner** patrouillieren langsam in ihrem Raum, verfolgen den Helden ab 3 Kacheln und geben auf,
  wenn er länger als 3 s weiter als 5 Kacheln entfernt ist oder sie sich 7 Kacheln von ihrem Platz entfernt haben.
- **Elite-Gegner** bewachen ihren Platz, reagieren ab 2,2 Kacheln und folgen höchstens 3 Kacheln weit.
- **Boss** steht.
- **Lernspiel-Regel:** Gegner sind nie schneller als 90 % des Heldentempos – man kann Kämpfen immer ausweichen.
- Nach einer Niederlage und beim Fortsetzen eines gespeicherten Abenteuers stehen alle Gegner wieder auf ihrem Platz.

## Pakt (Schwierigkeit, Issue #22, `data/pact.gd`, `meta.pact`)
Statt fester Tempelstufen wählt man im Titel („🔥 Pakt“) einzelne Erschwernisse mit Rängen. Jeder Punkt bringt
+12,5 % Splitter. Freie Punkte: 3 × Pakt-Stufe (`records.heatUnlocked`); der erste Sieg schaltet Stufe 1 frei, jeder
Sieg mit voll ausgeschöpftem Pakt die nächste (bis 5 = 15 Punkte).

| Erschwernis | Ränge | Punkte/Rang | Wirkung |
| --- | --- | --- | --- |
| 🛡 Zähe Gegner | 5 | 1 | Gegner +35 % HP |
| ⚔ Wilde Gegner | 5 | 1 | Gegner +35 % Angriff |
| 👹 Elite-Horden | 2 | 1 | +1 Elite-Gegner pro Ebene |
| 🧪 Karge Vorräte | 2 | 1 | −1 Heiltrank zu Beginn |
| 💔 Zerbrechlich | 2 | 2 | −1 Leben (mind. 1) |
| 💰 Gierige Händler | 2 | 1 | Händler +50 % teurer |
| 🚫 Ohne Hilfen | 1 | 2 | keine Hilfen |
| 🔁 Umgekehrte Richtung | 2 | 1 | jede 3. bzw. jede Abfrage Englisch → Deutsch |
| 🆕 Neue Wörter | 1 | 1 | noch nie Geübtes kommt 3× öfter |

Die alten Tempelstufen entsprechen `{p_hp: n, p_atk: n}` (`Pact.from_heat`), ältere Spielstände laufen so weiter.
Ein **Hörmodus** ist bewusst nicht dabei: Ein vorgelesenes deutsches Wort ist für deutschsprachige Kinder keine echte
Erschwernis, und Sprachausgabe hängt unter Windows von installierten Stimmen ab. Sinnvoller wäre ein eigenes
„Aussprache anhören“ für englische Wörter.

## Gemessene Balance (Simulator `logic/sim/balance_sim.gd`)
Der Simulator spielt komplette Abenteuer mit der echten Spiellogik. Der Bot geht immer zum nächsten Ziel, heilt sich
am Altar vor Elite/Boss und bei weniger als 50 % HP, kauft beim Händler, wählt Talente und Segnungen, nutzt Hilfen
bei unsicheren Wörtern und verliert nach 3 Niederlagen. Lerner-Modelle (`config/game.json → simulation.learners`):
jedes Wort hat eine eigene Trefferwahrscheinlichkeit, die mit jedem Abruf wächst (Anfänger ≈ 25 %, Durchschnitt ≈ 55 %,
stark ≈ 80 % zu Beginn); zwischen zwei Läufen wird etwas vergessen. Zeiten (Laufen, Antworten, Kampfrunden) sind grobe
Schätzwerte unter `simulation.time`.

Neu erzeugen: `start.bat sim runs=40 learner=beginner,average,strong` bzw.
`start.bat sim runs=40 heat=3,5 skills=none,full` und `start.bat sim campaign=8` (Linux/macOS: `./start.sh sim …`).

| Fall (Krieger, 40 Läufe) | Sieg | Ø Splitter | Ø Abfragen | Ø Minuten |
| --- | --- | --- | --- | --- |
| Stufe 0, Anfänger | 100 % | ≈ 42 | ≈ 68 | ≈ 17 |
| Stufe 0, Durchschnitt | 100 % | ≈ 41 | ≈ 43 | ≈ 10 |
| Stufe 0, stark | 100 % | ≈ 41 | ≈ 31 | ≈ 7 |
| Stufe 3, Durchschnitt, keine Skills | ≈ 50 % | ≈ 59 | ≈ 76 | ≈ 17 |
| Stufe 3, Durchschnitt, voller Baum | 100 % | ≈ 75 | ≈ 54 | ≈ 12 |
| Stufe 5, Durchschnitt, voller Baum | ≈ 80 % | ≈ 95 | ≈ 81 | ≈ 18 |

Kampagne (Durchschnitt, immer höchste freie Stufe, Splitter sofort in den Baum): Splitter pro Lauf 37 → 53 → 60 → 80 …,
der Krieger-Baum ist nach 4 Läufen voll.

Folgerung: Schurke nach dem ersten Sieg freischaltbar; Stufe 3 braucht den Skillbaum, Stufe 5 bleibt mit vollem Baum
schaffbar. Talente, Segnungen und Händler machten die alten Tempelstufen zu leicht – deshalb wachsen Gegner-HP und
-Angriff jetzt um je 35 % pro Stufe (vorher 25 % / 20 %; nach „fast richtig“ und ohne
leichte Wörter beim Verteidigen nachjustiert). Die Tests in `tests/test_balance.gd` sichern diese
Eckwerte ab.

**Regel:** Wer Kampf, Lernen, Belohnungen, Talente/Segnungen oder Meta-Fortschritt ändert, passt den Simulator und
die Balance-Tests im selben Zug an.

## Offene Ideen zum Weiterentwickeln
- Balance mit echten Spielern prüfen (der Bot spielt nahezu optimal).
- Weitere Welten mit eigenen Gegnern und Bossen (Freischaltung über Splitter oder Tempelstufen).
- Weitere Freischaltungen: Welten, kosmetische Helden, neue Startwaffen.
