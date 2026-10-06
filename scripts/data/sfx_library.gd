class_name SfxLibrary
extends Resource
## Maps sound cue names to files. Edit data/audio/sfx_library.tres.

@export var cues: Array[SfxCue] = []


func find(cue_name: String) -> SfxCue:
	for cue: SfxCue in cues:
		if cue != null and cue.name == cue_name:
			return cue
	return null
