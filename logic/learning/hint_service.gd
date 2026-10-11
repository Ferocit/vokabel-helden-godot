class_name HintService
extends RefCounted
## Hilfen beziehen sich immer auf die Hauptlösung `en`.
## HintState  { lengthShown: bool, revealed: Dictionary (Index → true), used: Array[String] }
## HintWallet { freeCharges: {length, firstLetter}, focus: int, costs: {length, firstLetter} }

const LABELS := {"length": "Wortlänge", "firstLetter": "Erster Buchstabe"}

static var _letter_re: RegEx


static func is_letter(ch: String) -> bool:
	if _letter_re == null:
		_letter_re = RegEx.create_from_string("^[\\p{L}\\p{N}]$")
	return _letter_re.search(ch) != null


static func create_state() -> Dictionary:
	return {"lengthShown": false, "revealed": {}, "used": []}


static func letter_count(text: String) -> int:
	var n := 0
	for ch in text:
		if is_letter(ch):
			n += 1
	return n


static func _first_letter_index(text: String) -> int:
	for i in text.length():
		if is_letter(text[i]):
			return i
	return -1


static func is_useful(e: Dictionary, state: Dictionary, type: String) -> bool:
	if type == "length":
		return not state.lengthShown
	var first := _first_letter_index(e.en)
	return first >= 0 and not state.revealed.has(first)


static func apply(e: Dictionary, state: Dictionary, type: String) -> Dictionary:
	var used: Array = state.used.duplicate()
	used.append(type)
	var next := {"lengthShown": state.lengthShown, "revealed": state.revealed.duplicate(), "used": used}
	if type == "length":
		next.lengthShown = true
	elif type == "firstLetter":
		var first := _first_letter_index(e.en)
		if first >= 0:
			next.revealed[first] = true
		next.lengthShown = true
	return next


## Maske wie "d _ _ _ _"; Leerzeichen und Satzzeichen bleiben sichtbar. Leer, wenn nichts aufgedeckt ist.
static func render_mask(e: Dictionary, state: Dictionary) -> String:
	if not state.lengthShown and state.revealed.is_empty():
		return ""
	var en: String = e.en
	var parts: PackedStringArray = []
	for i in en.length():
		var ch := en[i]
		if ch == " ":
			parts.append(" ")
		elif not is_letter(ch):
			parts.append(ch)
		else:
			parts.append(ch if state.revealed.has(i) else "_")
	return " ".join(parts)


static func describe_length(e: Dictionary) -> String:
	var words: PackedStringArray = []
	for w in (e.en as String).split(" ", false):
		words.append(w)
	if words.size() <= 1:
		return "%d Buchstaben" % letter_count(e.en)
	var counts: PackedStringArray = []
	for w in words:
		counts.append(str(letter_count(w)))
	return "%d Wörter: %s Buchstaben" % [words.size(), " + ".join(counts)]


## Zahlungsart: {"source": "free"} | {"source": "focus", "cost": n} | {} (nicht bezahlbar)
static func payment(wallet: Dictionary, type: String) -> Dictionary:
	if int(wallet.freeCharges.get(type, 0)) > 0:
		return {"source": "free"}
	var cost: int = wallet.costs[type]
	return {"source": "focus", "cost": cost} if int(wallet.focus) >= cost else {}


## Liefert die neue Wallet oder ein leeres Dictionary, wenn nicht bezahlbar.
static func pay(wallet: Dictionary, type: String) -> Dictionary:
	var p := payment(wallet, type)
	if p.is_empty():
		return {}
	var next := wallet.duplicate(true)
	if p.source == "free":
		next.freeCharges[type] = int(wallet.freeCharges.get(type, 0)) - 1
	else:
		next.focus = int(wallet.focus) - int(p.cost)
	return next
