class_name Sfx
extends RefCounted
## Plays sound cues through the Audio autoload (scripts/autoload/audio.gd). Presentation scripts
## call this instead of the global `Audio` name so they still pass `--check-only`, which does not
## register autoload names. Silent if the autoload is missing (for example in unit tests).

const AUTOLOAD_PATH := ^"/root/Audio"


static func play(cue: String, volume_offset_db: float = 0.0) -> void:
	var audio := _audio()
	if audio != null:
		audio.call(&"play", cue, volume_offset_db)


## Stops every sound (before quitting, so no playback is left running at exit).
static func stop_all() -> void:
	var audio := _audio()
	if audio != null:
		audio.call(&"stop_all")


## Loads every cue now so the first parry sound has no loading hitch.
static func preload_all() -> void:
	var audio := _audio()
	if audio != null:
		audio.call(&"preload_all")


static func _audio() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(AUTOLOAD_PATH)
