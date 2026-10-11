class_name TestCase
extends RefCounted
## Minimaler Testrahmen: Jede Methode `test_*` ist ein Test, Prüfungen sammeln Fehler statt abzubrechen.

var failures: Array[String] = []
var current := ""


func fail(message: String) -> void:
	failures.append("%s: %s" % [current, message])


func expect_true(cond: bool, message: String = "erwartet true") -> void:
	if not cond:
		fail(message)


func expect_false(cond: bool, message: String = "erwartet false") -> void:
	if cond:
		fail(message)


func expect_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if not _equal(actual, expected):
		fail("%s erwartet %s, erhalten %s" % [message, var_to_str(expected), var_to_str(actual)])


func expect_ne(actual: Variant, other: Variant, message: String = "") -> void:
	if _equal(actual, other):
		fail("%s erwartet ungleich %s" % [message, var_to_str(other)])


func expect_near(actual: float, expected: float, eps: float = 0.005, message: String = "") -> void:
	if absf(actual - expected) > eps:
		fail("%s erwartet ≈%s, erhalten %s" % [message, expected, actual])


func expect_ge(actual: float, bound: float, message: String = "") -> void:
	if actual < bound:
		fail("%s erwartet ≥ %s, erhalten %s" % [message, bound, actual])


func expect_le(actual: float, bound: float, message: String = "") -> void:
	if actual > bound:
		fail("%s erwartet ≤ %s, erhalten %s" % [message, bound, actual])


func expect_lt(actual: float, bound: float, message: String = "") -> void:
	if actual >= bound:
		fail("%s erwartet < %s, erhalten %s" % [message, bound, actual])


func expect_gt(actual: float, bound: float, message: String = "") -> void:
	if actual <= bound:
		fail("%s erwartet > %s, erhalten %s" % [message, bound, actual])


## Prüft, dass alle Schlüssel von `subset` in `actual` mit gleichem Wert vorkommen (wie toMatchObject).
func expect_match(actual: Dictionary, subset: Dictionary, message: String = "") -> void:
	for k: Variant in subset:
		if not actual.has(k) or not _equal(actual[k], subset[k]):
			fail("%s Feld %s: erwartet %s, erhalten %s" % [message, k, var_to_str(subset[k]), var_to_str(actual.get(k))])


## Zahlen werden typunabhängig verglichen (JSON liefert float statt int).
static func _equal(a: Variant, b: Variant) -> bool:
	var num := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in num and typeof(b) in num:
		return is_equal_approx(float(a), float(b))
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not _equal(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for k: Variant in a:
			if not (b as Dictionary).has(k) or not _equal(a[k], b[k]):
				return false
		return true
	if typeof(a) != typeof(b):
		return false
	return a == b
