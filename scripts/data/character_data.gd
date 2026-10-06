class_name CharacterData
extends Resource
## A playable character (placeholder until classes arrive in phase 2).

## Unique id used in commands and save data.
@export var id: String = ""
@export var display_name: String = ""
## Accent colour for UI and placeholder tint.
@export var color: Color = Color.WHITE
## Battle sprite sheet: one row of equal frames in this order:
## idle, ready, parry, dodge, jump, hurt, strike, down. Replace the file to change the art.
@export_file_path("*.png") var sprite_path: String = ""
## Number of frames in the sprite sheet row.
@export_range(1, 64) var sprite_hframes: int = 8
## Small picture for the timeline and party panel.
@export_file_path("*.png") var portrait_path: String = ""
## World units per sprite pixel (bigger = larger on screen).
@export_range(0.001, 0.2, 0.001) var sprite_pixel_size: float = 0.045
## HP, in percent of tuning base_character_hp.
@export_range(10, 1000, 5, "suffix:%") var hp_percent: int = 100
## Power (base damage), in percent of tuning base_party_damage.
@export_range(10, 1000, 5, "suffix:%") var power_percent: int = 100
## Turn speed. 100 is average; 200 acts twice as often as 100.
@export_range(1, 1000) var speed: int = 100
@export var basic_attack: AbilityData
@export var skills: Array[AbilityData] = []


func all_abilities() -> Array[AbilityData]:
	var list: Array[AbilityData] = []
	if basic_attack != null:
		list.append(basic_attack)
	for skill: AbilityData in skills:
		if skill != null:
			list.append(skill)
	return list
