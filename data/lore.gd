class_name Lore
extends RefCounted
## Lager und Tempel-Geschichte (Issue #25): Zwischen den Abenteuern erzählt Professor Knatter im Lager nach und nach
## die Geschichte des Tempels. Neue Einträge werden durch Ereignisse freigeschaltet (erstes Abenteuer, erste
## Niederlage, Ebenen, gemeisterte Wörter …) oder durch 📜 Schriftrollen, die man in Truhen findet.
## Gelesenes steht in profile.loreSeen, gefundene Schriftrollen in profile.records.scrolls.

const NPC_NAME := "Professor Knatter"
## Sprite im Dungeon-Tileset (alter Forscher mit Helm).
const NPC_FRAME := 100
## Wahrscheinlichkeit, dass eine Truhe eine Schriftrolle enthält, solange noch welche fehlen.
const SCROLL_CHANCE := 0.25

## trigger: [Art, Mindestwert]. Arten: runs, defeats, victories, elites, floor, mastered, stars, pact, scrolls
const ENTRIES: Array[Dictionary] = [
	{"id": "l_welcome", "title": "Willkommen im Lager", "trigger": ["runs", 0],
		"text": "Ah, ein neues Gesicht! Ich bin Professor Knatter, Tempelforscher und Teetrinker. Seit vierzig Jahren versuche ich, in den Dschungeltempel zu kommen. Das Problem: Die Türen öffnen sich nur für Leute, die Wörter wirklich kennen. Ich kenne leider nur Wörter über Tee."},
	{"id": "l_first_run", "title": "Der Tempel spricht", "trigger": ["runs", 1],
		"text": "Du bist zurück – und ganz! Hast du die Runen an den Wänden gesehen? Ich glaube, der Tempel wurde von einem Volk gebaut, das Wörter für magisch hielt. Wer ein Wort richtig ausspricht, dem gehorchen die Steine. Wer es falsch sagt … nun ja, dem gehorchen sie nicht."},
	{"id": "l_first_defeat", "title": "Niederlagen sind Notizen", "trigger": ["defeats", 1],
		"text": "Umgehauen worden? Mach dir nichts draus. Ich bin bei meiner ersten Expedition in einen Brunnen gefallen. Zweimal. Weißt du, was ich daraus gelernt habe? Dass man Brunnen besser umgeht. Und dass jedes falsche Wort ein Wort ist, das du beim nächsten Mal weißt."},
	{"id": "l_first_elite", "title": "Die Wächter", "trigger": ["elites", 1],
		"text": "Ein Tempelwächter! Die stehen seit Jahrhunderten dort und fragen jeden nach Wörtern. Mein Großvater meinte, sie wären eigentlich nur sehr strenge Lehrer, die vergessen haben, in Rente zu gehen."},
	{"id": "l_first_victory", "title": "Der Zyklop", "trigger": ["victories", 1],
		"text": "Du hast den Zyklopen besiegt?! Mit nur einem Auge sieht er keine Wörter, nur Fehler. Deshalb kennt er deine Schwachstellen so gut. Aber hinter seinem Thron … ich schwöre, ich habe dort eine Treppe nach unten gesehen."},
	{"id": "l_cave", "title": "Die Kristallhöhle", "trigger": ["floor", 2],
		"text": "Eine Höhle voller Kristalle unter dem Tempel! Die Kristalle leuchten, wenn jemand in der Nähe ein Wort richtig sagt. Ich habe zehn Minuten lang „Tee“ gerufen. Ein Kristall hat kurz geflackert. Ich glaube, er war höflich."},
	{"id": "l_ice", "title": "Der Eistempel", "trigger": ["floor", 3],
		"text": "Ganz unten liegt Schnee – im Dschungel! Der Yeti-König hat dort alle Wörter eingefroren, die je vergessen wurden. Wenn du eines richtig sagst, taut es auf. Deshalb ist es da unten so nass, wenn du durch bist."},
	{"id": "l_words_10", "title": "Zehn sichere Wörter", "trigger": ["mastered", 10],
		"text": "Zehn Wörter, die du wirklich sicher kannst! Weißt du, wie die Tempelbauer zehn sichere Wörter nannten? „Ein Anfang.“ Und hundert? „Ein guter Anfang.“ Sie waren nicht leicht zu beeindrucken."},
	{"id": "l_words_50", "title": "Fünfzig sichere Wörter", "trigger": ["mastered", 50],
		"text": "Fünfzig Wörter! Die Runen im Lager haben angefangen zu summen, als du hereingekommen bist. Entweder ist das ein uraltes Zeichen von Respekt – oder mein Teekessel. Ich tippe auf Respekt."},
	{"id": "l_star", "title": "Set-Meister", "trigger": ["stars", 1],
		"text": "Ein ganzes Set, jedes Wort richtig geschrieben! Im Tempel gibt es eine Wand mit Sternen. Ich dachte immer, das wäre Deko. Jetzt glaube ich, dass jeder Stern ein Abenteurer ist, der ein ganzes Set gemeistert hat. Dein Stern ist gerade aufgetaucht."},
	{"id": "l_pact", "title": "Der Pakt", "trigger": ["pact", 1],
		"text": "Du hast einen Pakt mit dem Tempel geschlossen? Mutig! Der Tempel mag Leute, die es sich schwer machen. Er belohnt sie mit Splittern. Mich belohnt er mit Rückenschmerzen."},
	{"id": "l_scroll_1", "title": "Schriftrolle I: Die Wortbauer", "trigger": ["scrolls", 1],
		"text": "„Wir bauten den Tempel aus Steinen und Wörtern. Die Steine halten die Decke. Die Wörter halten den Tempel zusammen. Wer ein Wort lernt, legt einen Stein dazu.“ – Ich liebe diese Leute."},
	{"id": "l_scroll_2", "title": "Schriftrolle II: Das große Vergessen", "trigger": ["scrolls", 2],
		"text": "„Eines Tages vergaßen die Menschen ihre Wörter. Die Türen schlossen sich, die Wächter erstarrten. Nur wer die Wörter neu lernt, kann sie wieder wecken.“ Das klingt verdächtig nach Hausaufgaben."},
	{"id": "l_scroll_3", "title": "Schriftrolle III: Der Zyklop", "trigger": ["scrolls", 3],
		"text": "„Der Zyklop bewacht die schwersten Wörter jedes Besuchers. Er wird schwächer, je besser der Besucher sie kennt.“ Siehst du? Lernen ist die beste Rüstung – und seine schlechteste."},
	{"id": "l_scroll_4", "title": "Schriftrolle IV: Für die Nachwelt", "trigger": ["scrolls", 4],
		"text": "„Wer diese Rolle liest, hat viele Truhen geöffnet. Du bist neugierig. Bleib es.“ Darunter ist ein Fleck. Ich glaube, es ist Tee. Die Tempelbauer waren mir sehr ähnlich."},
]


## Aktuelle Zählerstände für die Auslöser.
static func counts(profile: Dictionary, progress: Dictionary) -> Dictionary:
	var rec: Dictionary = profile.get("records", {})
	var elites := 0
	for id: String in profile.get("bestiary", {}):
		var def := GameData.get_enemy(id) if GameData.ENEMIES.any(func(e: Dictionary) -> bool: return e.id == id) else {}
		if def.get("tier", "") == "elite":
			elites += int(profile.bestiary[id])
	var mastered := 0
	for k: String in progress:
		var s: Variant = progress[k]
		if s is Dictionary and float(s.get("mastery", 0.0)) >= 0.9:
			mastered += 1
	return {
		"runs": int(rec.get("runs", 0)), "defeats": int(rec.get("defeats", 0)), "victories": int(rec.get("victories", 0)),
		"elites": elites, "floor": int(rec.get("maxFloor", 1 if int(rec.get("runs", 0)) > 0 else 0)), "mastered": mastered,
		"stars": (profile.get("setStars", {}) as Dictionary).size(), "pact": int(rec.get("pactRuns", 0)),
		"scrolls": int(rec.get("scrolls", 0)),
	}


## Alle freigeschalteten Einträge (in Erzählreihenfolge).
static func unlocked(profile: Dictionary, progress: Dictionary) -> Array:
	var c := counts(profile, progress)
	return ENTRIES.filter(func(e: Dictionary) -> bool: return int(c.get(e.trigger[0], 0)) >= int(e.trigger[1]))


static func is_seen(profile: Dictionary, id: String) -> bool:
	return (profile.get("loreSeen", []) as Array).has(id)


static func unread(profile: Dictionary, progress: Dictionary) -> Array:
	return unlocked(profile, progress).filter(func(e: Dictionary) -> bool: return not is_seen(profile, e.id))


static func mark_seen(profile: Dictionary, id: String) -> void:
	if not profile.get("loreSeen") is Array:
		profile.loreSeen = []
	if not (profile.loreSeen as Array).has(id):
		(profile.loreSeen as Array).append(id)


static func scrolls_total() -> int:
	return ENTRIES.filter(func(e: Dictionary) -> bool: return e.trigger[0] == "scrolls").size()


## Truhe: Liegt eine Schriftrolle darin? (nur solange noch welche fehlen)
static func roll_scroll(profile: Dictionary, rng: Callable) -> bool:
	return int(profile.get("records", {}).get("scrolls", 0)) < scrolls_total() and rng.call() < SCROLL_CHANCE
