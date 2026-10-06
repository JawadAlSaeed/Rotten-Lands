extends Node
## Entry point (run/main_scene). Reads the user arguments, loads the phase 1 encounter and
## the tuning and starts the combat scene. R / "fight again" frees the fight and starts a new
## one; the options (and the F1 statistics they hold) survive restarts.
##
## User arguments (after "--"): --autoplay[=perfect|miss|mash], --quit-on-end, --seed=N.

const ENCOUNTER_PATH := "res://data/encounters/phase1_test.tres"
const TUNING_PATH := "res://data/tuning/tuning.tres"
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"
const COMBAT_SCENE := preload("res://scenes/combat.tscn")

var _encounter: EncounterData
var _tuning: Tuning
var _visuals: CombatVisuals
var _options: CombatOptions
var _combat: CombatController


func _ready() -> void:
	_encounter = load(ENCOUNTER_PATH) as EncounterData
	_tuning = load(TUNING_PATH) as Tuning
	_visuals = load(VISUALS_PATH) as CombatVisuals
	if _encounter == null or _tuning == null:
		push_error("Main: could not load %s or %s" % [ENCOUNTER_PATH, TUNING_PATH])
		return
	if _visuals == null:
		push_warning("Main: could not load %s, using built-in presentation defaults" % VISUALS_PATH)
		_visuals = CombatVisuals.new()
	_options = CombatOptions.from_args(OS.get_cmdline_user_args(), _tuning)
	if _options.is_autoplay():
		print("Autoplay: %s%s" % [_options.autoplay_mode, " (quit on end)" if _options.quit_on_end else ""])
	_start_combat()


func _start_combat() -> void:
	if _combat != null:
		remove_child(_combat)
		_combat.queue_free()
	_combat = COMBAT_SCENE.instantiate() as CombatController
	_combat.configure(_encounter, _tuning, _visuals, _options)
	_combat.restart_requested.connect(_on_restart_requested)
	add_child(_combat)


func _on_restart_requested() -> void:
	_start_combat.call_deferred()
