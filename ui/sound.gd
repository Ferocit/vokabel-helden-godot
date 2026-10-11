extends Node
## Autoload „Sound“: dezentes Feedback – positiv bei richtig, neutral bei falsch, nie ein aggressiver Fail-Sound.

const VOLUME := {"select": 0.5, "wrong": 0.45, "hint": 0.6}
const POOL_SIZE := 10

var enabled := true
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(id: String, volume: float = -1.0, rate: float = 1.0) -> void:
	if not enabled:
		return
	if not _streams.has(id):
		var path := "res://assets/audio/%s.ogg" % id
		_streams[id] = load(path) if ResourceLoader.exists(path) else null
	var stream: AudioStream = _streams[id]
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	var vol := volume if volume >= 0.0 else float(VOLUME.get(id, 0.7))
	p.volume_db = linear_to_db(maxf(vol, 0.0001))
	# Leichte Tonhöhen-Variation, damit sich Wiederholungen nicht mechanisch anhören.
	p.pitch_scale = rate * pow(2.0, randf_range(-0.06, 0.06) / 1.2)
	p.play()
