class_name AbilityData
extends Resource
## An action a party member can take on their turn (basic attack or skill).

enum Target {
	SINGLE_ENEMY,
	ALL_ENEMIES,
}

## Unique id used in commands and save data. Never change it once content uses it.
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
## AP spent to use it.
@export_range(0, 99) var ap_cost: int = 0
## AP gained after it is used.
@export_range(0, 99) var ap_gain: int = 0
## Damage, in percent of the character's power.
@export_range(0, 2000, 5, "suffix:%") var damage_percent: int = 100
@export var target: Target = Target.SINGLE_ENEMY
## Sound cue played on impact (name from data/audio/sfx_library.tres).
@export var impact_sfx: String = "strike"
