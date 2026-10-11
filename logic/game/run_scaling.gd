class_name RunScaling
extends RefCounted
## Größere Vokabel-Sets brauchen längere Abenteuer, damit möglichst viele Wörter drankommen (Issue #16).
## Bis 30 Wörter bleibt alles beim Standard; darüber wächst das Level bis zum Faktor 2,5 (ab 75 Wörtern).

const MAX_LEVEL_SCALE := 2.5


static func level_scale_for(word_count: int) -> float:
	return roundf(clampf(word_count / 30.0, 1.0, MAX_LEVEL_SCALE) * 100.0) / 100.0


static func _scale_range(r: Dictionary, factor: float) -> Dictionary:
	var min_v := maxi(int(r.min), CombatService.js_round(int(r.min) * factor))
	return {"min": min_v, "max": maxi(min_v, CombatService.js_round(int(r.max) * factor))}


static func scale_level_config(cfg: Dictionary, scale: float) -> Dictionary:
	if scale <= 1.0:
		return cfg
	var c := cfg.duplicate(true)
	# Mehr Inhalt braucht mehr Räume und mehr Platz.
	c.rooms = _scale_range(cfg.rooms, pow(scale, 0.8))
	c.gridSize = CombatService.js_round(int(cfg.gridSize) * sqrt(scale)) + 2
	c.extraLoops = CombatService.js_round(int(cfg.extraLoops) * scale)
	c.normalEnemies = _scale_range(cfg.normalEnemies, scale)
	c.eliteEnemies = _scale_range(cfg.eliteEnemies, sqrt(scale))
	c.chests = _scale_range(cfg.chests, scale)
	c.doors = _scale_range(cfg.doors, pow(scale, 0.7))
	if cfg.has("shrines"):
		c.shrines = _scale_range(cfg.shrines, sqrt(scale))
		c.plates = _scale_range(cfg.plates, scale)
	return c


## Zeit-Challenge: Zeit für das ganze Abenteuer in Sekunden, wächst mit der Anzahl der Vokabeln.
static func time_limit_for(word_count: int) -> int:
	var c := GameConfig.section("timeChallenge")
	return clampi(int(c.baseSeconds) + int(c.secondsPerWord) * word_count, int(c.minSeconds), int(c.maxSeconds))


## Bei größeren Abenteuern braucht das Siegeltor etwas mehr Runen.
static func scaled_boss_runes(base: int, scale: float) -> int:
	return CombatService.js_round(base * sqrt(scale))
