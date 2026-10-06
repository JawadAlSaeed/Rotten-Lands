class_name SfxCue
extends Resource
## One named sound effect.

## Name used in code and data (for example "parry").
@export var name: String = ""
## Sound file. Replace the file at this path to change the sound.
@export_file_path("*.wav", "*.ogg", "*.mp3") var path: String = ""
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var volume_db: float = 0.0
## Random pitch change per play, so repeats sound less robotic (0.05 = up to 5%).
@export_range(0.0, 0.5, 0.01) var pitch_jitter: float = 0.0
