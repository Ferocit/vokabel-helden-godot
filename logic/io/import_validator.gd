class_name ImportValidator
extends RefCounted
## DraftEntry  { id, de, en, alternatives: Array[String], caseSensitive }
## ImportIssue { row: int (-1 = ganze Datei), severity: "error" | "warning", message }

const ALTERNATIVE_SEPARATOR := ";"


static func _issue(row: int, severity: String, message: String) -> Dictionary:
	return {"row": row, "severity": severity, "message": message}


static func _as_text(value: Variant) -> String:
	if value is String:
		return value
	if value is float or value is int:
		var f := float(value)
		return str(int(f)) if f == floorf(f) else str(f)
	return ""


## Liest JSON aus dem KI-Export. Ergebnis: {ok: true, title, entries, issues} oder {ok: false, message}.
static func parse_import(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "message": "Die Datei ist kein gültiges JSON. Bitte prüfe Klammern, Kommas und Anführungszeichen.\n(Zeile %d: %s)" % [json.get_error_line(), json.get_error_message()]}
	var data: Variant = json.data

	var title := "Neue Einheit"
	var list: Variant = null
	var issues: Array = []
	if data is Array:
		list = data
	elif data is Dictionary:
		var root: Dictionary = data
		if root.get("title") is String and (root.title as String).strip_edges() != "":
			title = (root.title as String).strip_edges()
		if root.has("version") and not (root.version is float and float(root.version) == 1.0):
			issues.append(_issue(-1, "warning", "Unbekannte Formatversion \"%s\" – Import wird trotzdem versucht." % str(root.version)))
		if root.has("sourceLanguage") and root.sourceLanguage != "de":
			issues.append(_issue(-1, "warning", "Ausgangssprache ist nicht \"de\"."))
		if root.has("targetLanguage") and root.targetLanguage != "en":
			issues.append(_issue(-1, "warning", "Zielsprache ist nicht \"en\"."))
		list = root.get("vocabulary")
	if not list is Array:
		return {"ok": false, "message": "Es wurde keine Vokabelliste gefunden. Erwartet wird ein Feld \"vocabulary\" mit einer Liste von Einträgen."}
	if (list as Array).is_empty():
		return {"ok": false, "message": "Die Vokabelliste ist leer."}

	var entries: Array = []
	var row := 0
	for raw: Variant in list:
		if not raw is Dictionary:
			issues.append(_issue(row, "warning", "Eintrag ist kein Objekt und wurde leer übernommen."))
			entries.append({"id": "", "de": "", "en": "", "alternatives": [], "caseSensitive": true})
			row += 1
			continue
		var e: Dictionary = raw
		var alternatives: Array = []
		var alt: Variant = e.get("alternatives")
		if alt is Array:
			for a: Variant in alt:
				if a is String:
					alternatives.append(a)
			if alternatives.size() != (alt as Array).size():
				issues.append(_issue(row, "warning", "Alternativen enthielten Nicht-Text-Werte; diese wurden entfernt."))
		elif alt is String:
			alternatives = Array((alt as String).split(ALTERNATIVE_SEPARATOR))
			issues.append(_issue(row, "warning", "Alternativen waren Text statt Liste und wurden umgewandelt."))
		elif alt != null:
			issues.append(_issue(row, "warning", "Alternativen haben einen ungültigen Typ und wurden ignoriert."))
		if e.has("de") and not e.de is String:
			issues.append(_issue(row, "warning", "\"de\" ist kein Text."))
		if e.has("en") and not e.en is String:
			issues.append(_issue(row, "warning", "\"en\" ist kein Text."))
		var cleaned: Array = []
		for a: String in alternatives:
			if a.strip_edges() != "":
				cleaned.append(a.strip_edges())
		entries.append({
			"id": _as_text(e.get("id")).strip_edges(),
			"de": _as_text(e.get("de")).strip_edges(),
			"en": _as_text(e.get("en")).strip_edges(),
			"alternatives": cleaned,
			"caseSensitive": e.caseSensitive if e.get("caseSensitive") is bool else true,
		})
		row += 1

	var seen := {}
	var duplicates: Array = []
	for en: Dictionary in entries:
		var id: String = en.id
		if id == "":
			continue
		if seen.has(id) and not duplicates.has(id):
			duplicates.append(id)
		seen[id] = true
	if not duplicates.is_empty():
		issues.append(_issue(-1, "warning", "Doppelte IDs (%s) – sie werden beim Speichern automatisch neu vergeben." % ", ".join(PackedStringArray(duplicates))))
	return {"ok": true, "title": title, "entries": entries, "issues": issues}


## Prüft den aktuellen Stand der (ggf. bearbeiteten) Tabelle. Fehler verhindern das Speichern.
static func validate_entries(entries: Array) -> Array:
	var issues: Array = []
	if entries.is_empty():
		issues.append(_issue(-1, "error", "Das Set enthält keine Vokabeln."))
	var seen_pairs := {}
	var seen_de := {}
	for row in entries.size():
		var e: Dictionary = entries[row]
		var de := (e.de as String).strip_edges()
		var en := (e.en as String).strip_edges()
		if de == "":
			issues.append(_issue(row, "error", "Deutsch fehlt."))
		if en == "":
			issues.append(_issue(row, "error", "Englisch fehlt."))
		if de == "" or en == "":
			continue
		var pair := "%s→%s" % [de.to_lower(), en.to_lower()]
		if seen_pairs.has(pair):
			issues.append(_issue(row, "error", "Doppelter Eintrag (gleich wie Zeile %d)." % (int(seen_pairs[pair]) + 1)))
		else:
			seen_pairs[pair] = row
			if seen_de.has(de.to_lower()):
				issues.append(_issue(row, "warning", "\"%s\" kommt schon in Zeile %d vor. Eventuell als Alternative eintragen?" % [de, int(seen_de[de.to_lower()]) + 1]))
			else:
				seen_de[de.to_lower()] = row
		for a: String in e.alternatives:
			if a.strip_edges() == en:
				issues.append(_issue(row, "warning", "Eine Alternative ist identisch mit der Hauptlösung."))
				break
	return issues


static func has_errors(issues: Array) -> bool:
	return issues.any(func(i: Dictionary) -> bool: return i.severity == "error")


## Wandelt die Tabelle in gespeicherte Vokabeln um; fehlende oder doppelte IDs werden neu vergeben.
static func finalize_entries(entries: Array, id_prefix: String) -> Array:
	var used := {}
	for e: Dictionary in entries:
		if e.id != "":
			used[e.id] = true
	var counter := [1]
	var fresh_id := func() -> String:
		var id := ""
		while true:
			id = "%s_%03d" % [id_prefix, counter[0]]
			counter[0] += 1
			if not used.has(id):
				break
		return id
	var taken := {}
	var result: Array = []
	for e: Dictionary in entries:
		var id := (e.id as String).strip_edges()
		if id == "" or taken.has(id):
			id = fresh_id.call()
		taken[id] = true
		used[id] = true
		var en := (e.en as String).strip_edges()
		var alts: Array = []
		for a: String in e.alternatives:
			var t := a.strip_edges()
			if t != "" and t != en and not alts.has(t):
				alts.append(t)
		result.append({"id": id, "de": (e.de as String).strip_edges(), "en": en, "alternatives": alts, "caseSensitive": e.caseSensitive})
	return result


static func parse_alternatives(text: String) -> Array:
	var list: Array = []
	for a in text.split(ALTERNATIVE_SEPARATOR):
		if a.strip_edges() != "":
			list.append(a.strip_edges())
	return list


static func format_alternatives(alternatives: Array) -> String:
	return (ALTERNATIVE_SEPARATOR + " ").join(PackedStringArray(alternatives))
