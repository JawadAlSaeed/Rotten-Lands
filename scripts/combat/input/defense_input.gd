class_name DefenseInput
extends Node
## Stamps defence presses with the real clock the moment Godot delivers them (DESIGN.md 3.1).
## Godot 4.7 input events carry no OS timestamp, so each press is stamped in _input with
## Time.get_ticks_usec() and sent on as an interval: from the previous input pump (recorded every
## frame on SceneTree.process_frame, which runs before any _process) to the moment it arrived.
## Never use Input.is_action_just_pressed() for defence.
##
## Only armed actions are stamped and consumed, so the shared buttons (W is also menu_up, pad A is
## also menu_confirm) still reach the menus whenever no attack or calibration is running.

## A defence press. `action` is a Defense.Outcome (DODGE, PARRY or JUMP). `stamp_us` is when the
## press arrived and `previous_pump_us` the previous input pump (0 if unknown), both
## Time.get_ticks_usec(). `device` is the Godot device id (-1 for injected presses).
signal pressed(action: int, stamp_us: int, previous_pump_us: int, device: int)

const ACTIONS: Dictionary = {
	&"defend_parry": Defense.Outcome.PARRY,
	&"defend_dodge": Defense.Outcome.DODGE,
	&"defend_jump": Defense.Outcome.JUMP,
}

var _armed: Dictionary = {}
var _last_pump_us: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().process_frame.connect(_on_process_frame)
	_last_pump_us = Time.get_ticks_usec()


func _input(event: InputEvent) -> void:
	if _armed.is_empty() or event.is_echo() or not event.is_pressed():
		return
	for action_name: StringName in ACTIONS:
		var outcome: int = ACTIONS[action_name]
		# Not exact_match: Left Shift (dodge) arrives with shift_pressed set, and a press while
		# another defence key is held must still count.
		if _armed.has(outcome) and event.is_action_pressed(action_name, false, false):
			var stamp := Time.get_ticks_usec()
			get_viewport().set_input_as_handled()
			pressed.emit(outcome, stamp, _last_pump_us, event.device)
			return


## Starts stamping and consuming these actions (Defense.Outcome values).
func arm(actions: Array[int]) -> void:
	_armed.clear()
	for a: int in actions:
		_armed[a] = true


## Stamps and consumes all three defence actions.
func arm_all() -> void:
	arm([Defense.Outcome.PARRY, Defense.Outcome.DODGE, Defense.Outcome.JUMP])


## Stops stamping; the buttons go back to the menus.
func disarm() -> void:
	_armed.clear()


func is_armed() -> bool:
	return not _armed.is_empty()


## The previous input pump time (Time.get_ticks_usec()).
func previous_pump_us() -> int:
	return _last_pump_us


## A press from code (autoplay bot) through the same path as a real one, stamped now.
func inject_press(action: int) -> void:
	if not _armed.has(action):
		return
	pressed.emit(action, Time.get_ticks_usec(), _last_pump_us, -1)


func _on_process_frame() -> void:
	_last_pump_us = Time.get_ticks_usec()
