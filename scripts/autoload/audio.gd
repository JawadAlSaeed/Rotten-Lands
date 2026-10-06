extends Node
## Global sound player (autoload "Audio"). Plays named cues from data/audio/sfx_library.tres.
## A missing or broken file prints one warning and stays silent; it never crashes the game.
## Usage: Audio.play("parry")

const LIBRARY_PATH := "res://data/audio/sfx_library.tres"
const POOL_SIZE := 24

var _library: SfxLibrary
## cue name -> AudioStream (null if it failed to load)
var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next_player := 0
var _warned: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists(LIBRARY_PATH):
		_library = load(LIBRARY_PATH) as SfxLibrary
	if _library == null:
		push_warning("Audio: no sound library at %s" % LIBRARY_PATH)
		_library = SfxLibrary.new()
	for i: int in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "Sfx%d" % i
		add_child(player)
		_pool.append(player)


## Plays a cue. `volume_offset_db` is added to the cue's own volume.
func play(cue_name: String, volume_offset_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	var cue := _library.find(cue_name)
	if cue == null:
		_warn_once(cue_name, "Audio: unknown cue '%s' (add it to %s)" % [cue_name, LIBRARY_PATH])
		return
	var stream := _stream_for(cue)
	if stream == null:
		return
	var player := _pool[_next_player]
	_next_player = (_next_player + 1) % _pool.size()
	player.stream = stream
	player.volume_db = cue.volume_db + volume_offset_db
	var jitter := 1.0
	if cue.pitch_jitter > 0.0:
		jitter = randf_range(1.0 - cue.pitch_jitter, 1.0 + cue.pitch_jitter)
	player.pitch_scale = maxf(0.01, pitch_scale * jitter)
	player.play()


## Loads every cue now so the first parry sound has no loading hitch.
func preload_all() -> void:
	for cue: SfxCue in _library.cues:
		if cue != null:
			_stream_for(cue)


func has_cue(cue_name: String) -> bool:
	return _library.find(cue_name) != null


func _stream_for(cue: SfxCue) -> AudioStream:
	if _streams.has(cue.name):
		return _streams[cue.name]
	var stream: AudioStream = null
	if not cue.path.is_empty() and ResourceLoader.exists(cue.path):
		stream = load(cue.path) as AudioStream
	if stream == null:
		_warn_once(cue.name, "Audio: cue '%s' has no playable file at '%s'" % [cue.name, cue.path])
	_streams[cue.name] = stream
	return stream


func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(message)
