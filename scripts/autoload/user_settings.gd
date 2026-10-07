class_name PlayerSettings
extends Node
## Per-machine player settings, saved in user://settings.cfg. Registered as the autoload
## "UserSettings"; the functions are static (class PlayerSettings) so code can call them as
## PlayerSettings.x() without the autoload's global name (which `--check-only` does not know)
## and they also work when no autoload exists (unit tests). UserSettings.x() works too.
## Holds what belongs to this machine and player rather than to the game's balance: the measured
## lag compensation (F2 calibration) and the training ring toggle (F1 then R). Anything not saved
## here falls back to the value in data/tuning/tuning.tres.

const PATH := "user://settings.cfg"
const SECTION_TIMING := "timing"
const SECTION_CUES := "cues"
const KEY_LATENCY := "latency_compensation_ms"
const KEY_RING := "show_timing_ring"

static var _config: ConfigFile


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_settings()


## Lag compensation in ms: the calibrated value if there is one (kept within tuning's
## calibration_min_ms .. calibration_max_ms, even if the file was edited), else the tuning default.
static func latency_compensation_ms(tuning: Tuning) -> int:
	if is_calibrated():
		return clamp_latency(int(_settings().get_value(SECTION_TIMING, KEY_LATENCY, 0)), tuning)
	return tuning.input_latency_compensation_ms if tuning != null else 0


## Saves a calibrated lag compensation (overrides the tuning default from now on), clamped.
static func set_latency_compensation_ms(value: int, tuning: Tuning) -> void:
	_settings().set_value(SECTION_TIMING, KEY_LATENCY, clamp_latency(value, tuning))
	_save()


## `value` limited to the calibration bounds in tuning.
static func clamp_latency(value: int, tuning: Tuning) -> int:
	if tuning == null:
		return value
	return clampi(value, tuning.calibration_min_ms, tuning.calibration_max_ms)


## True once the player has saved a calibration on this machine.
static func is_calibrated() -> bool:
	return _settings().has_section_key(SECTION_TIMING, KEY_LATENCY)


## Whether the training ring is shown: the saved choice, else the tuning default.
static func show_timing_ring(tuning: Tuning) -> bool:
	if _settings().has_section_key(SECTION_CUES, KEY_RING):
		return bool(_settings().get_value(SECTION_CUES, KEY_RING, false))
	return tuning.show_timing_ring if tuning != null else false


static func set_show_timing_ring(value: bool) -> void:
	_settings().set_value(SECTION_CUES, KEY_RING, value)
	_save()


static func _settings() -> ConfigFile:
	if _config == null:
		_config = ConfigFile.new()
		var err := _config.load(PATH)
		if err != OK and err != ERR_FILE_NOT_FOUND:
			push_warning("UserSettings: could not read %s (error %d); using defaults" % [PATH, err])
	return _config


static func _save() -> void:
	var err := _settings().save(PATH)
	if err != OK:
		push_warning("UserSettings: could not save %s (error %d)" % [PATH, err])
