class_name CombatOptions
extends RefCounted
## How the combat scene was launched (command line) plus the session state that survives a
## restart (R): the F1 overlay toggles and the defence statistics.
##
## User args (after "--" on the Godot command line):
##   --autoplay[=perfect|miss|mash]  bot plays the fight (perfect is the default)
##   --quit-on-end                   quit one second after the fight ends
##   --seed=N                        fixed fight seed (else tuning fixed_seed, else random)

const AUTOPLAY_PERFECT := "perfect"
const AUTOPLAY_MISS := "miss"
const AUTOPLAY_MASH := "mash"

## "" when a human plays, else AUTOPLAY_PERFECT, AUTOPLAY_MISS or AUTOPLAY_MASH.
var autoplay_mode: String = ""
var quit_on_end: bool = false
## -1 when no --seed was given.
var seed_override: int = -1
## Session toggles (F1 overlay; not saved): telegraph flash (F), timing readout (T) and the
## enemy's motion sounds (L: lunge whoosh and slam).
var telegraph_flash: bool = true
var timing_readout: bool = true
var motion_sounds: bool = true
## Defence statistics for the F1 overlay, kept across restarts.
var stats := DefenseStats.new()


static func from_args(args: PackedStringArray, tuning: Tuning) -> CombatOptions:
	var options := CombatOptions.new()
	if tuning != null:
		options.telegraph_flash = tuning.show_telegraph_flash
		options.timing_readout = tuning.show_timing_feedback
		options.motion_sounds = tuning.play_motion_sounds
	for arg: String in args:
		if arg == "--autoplay":
			options.autoplay_mode = AUTOPLAY_PERFECT
		elif arg.begins_with("--autoplay="):
			var mode := arg.substr("--autoplay=".length()).to_lower()
			if mode in [AUTOPLAY_PERFECT, AUTOPLAY_MISS, AUTOPLAY_MASH]:
				options.autoplay_mode = mode
			else:
				push_warning("CombatOptions: unknown autoplay mode '%s', using perfect" % mode)
				options.autoplay_mode = AUTOPLAY_PERFECT
		elif arg == "--quit-on-end":
			options.quit_on_end = true
		elif arg.begins_with("--seed="):
			var text := arg.substr("--seed=".length())
			if text.is_valid_int():
				options.seed_override = absi(text.to_int())
			else:
				push_warning("CombatOptions: --seed needs a whole number, got '%s'" % text)
	return options


func is_autoplay() -> bool:
	return not autoplay_mode.is_empty()
