class_name TrainingSession
extends RefCounted
## Trainingsmodus ohne Spiel: Jede Vokabel eines Sets kommt einmal als Karte dran. Falsch beantwortete
## Karten kommen am Ende der Runde noch einmal – so lange, bis alle einmal richtig waren.

var items: Array
var round := 1
## Noch offene Karten dieser Runde; die erste ist die aktuelle.
var queue: Array = []
## Falsch beantwortete Karten für die nächste Runde.
var retry: Array = []
var answered := 0
var first_try := 0
var wrong := 0
## Schlüssel der Karten, die schon einmal falsch waren.
var _missed := {}
var _rng: Callable


func _init(learning_items: Array, rng: Callable) -> void:
	items = learning_items
	_rng = rng
	queue = Rng.shuffle(rng, items)


func current() -> Dictionary:
	return queue[0] if not queue.is_empty() else {}


func is_finished() -> bool:
	return queue.is_empty() and retry.is_empty()


## Karten, die noch mindestens einmal richtig beantwortet werden müssen.
func remaining() -> int:
	return queue.size() + retry.size()


## War die Karte in diesem Training schon einmal falsch?
func was_missed(key: String) -> bool:
	return _missed.has(key)


## Ergebnis für die aktuelle Karte melden (AnswerResult, outcome „correct“ oder „wrongCorrected“).
func submit(res: Dictionary) -> void:
	if queue.is_empty():
		return
	var item: Dictionary = queue.pop_front()
	answered += 1
	if res.outcome == "correct":
		if not _missed.has(item.key):
			first_try += 1
	else:
		wrong += 1
		_missed[item.key] = true
		retry.append(item)
	if queue.is_empty() and not retry.is_empty():
		round += 1
		queue = Rng.shuffle(_rng, retry)
		retry = []


## Tempelsplitter für ein vollständig geschafftes Training (je `wordsPerShard` Wörter einer, mindestens einer).
static func reward_for(word_count: int) -> int:
	if word_count <= 0:
		return 0
	var per := maxi(1, int(GameConfig.section("training").wordsPerShard))
	return maxi(1, word_count / per)
