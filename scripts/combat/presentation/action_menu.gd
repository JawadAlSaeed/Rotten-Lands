class_name ActionMenu
extends PanelContainer
## The party member's action menu, driven only by the menu_* input actions (no focus-driven
## buttons, so the parry key can never click it). Up/down picks an ability, confirm uses it;
## unaffordable skills are greyed out. If more than one enemy is alive a target step follows
## (left/right or up/down cycles, cancel goes back).

signal chosen(ability_id: String, target_id: int)
## The target being pointed at during the target step, or -1 when the step ends.
signal target_changed(target_id: int)

const TITLE_SIZE: int = 30
const ITEM_SIZE: int = 32
const HINT_SIZE: int = 20
const MENU_WIDTH: float = 400.0
const CURSOR := "> "

var _title: Label
var _items_box: VBoxContainer
var _hint: Label
var _labels: Array[Label] = []
var _abilities: Array[AbilityData] = []
var _ap: int = 0
var _index: int = 0
var _targets: Array[int] = []
var _target_names: Dictionary = {}
var _target_index: int = 0
var _choosing_target: bool = false
## Process frame of the last stick move (a held stick sends many motion events).
var _stick_frame: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(MENU_WIDTH, 0.0)
	add_theme_stylebox_override("panel", HudStyle.panel(HudStyle.PANEL_BG, HudStyle.GOLD, 2, 16))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	_title = HudStyle.make_label("", TITLE_SIZE)
	column.add_child(_title)
	_items_box = VBoxContainer.new()
	_items_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_items_box)
	_hint = HudStyle.make_label("", HINT_SIZE, HudStyle.TEXT_DIM)
	column.add_child(_hint)
	visible = false


## Opens the menu for one actor. `enemies` are the living enemy ids; `names` maps id -> name.
func open(actor_name: String, accent: Color, abilities: Array[AbilityData], ap: int,
		enemies: Array[int], names: Dictionary) -> void:
	_title.text = "%s's turn" % actor_name
	_title.label_settings.font_color = accent.lightened(0.25)
	_abilities = abilities
	_ap = ap
	_targets = enemies
	_target_names = names
	_choosing_target = false
	_index = 0
	for label: Label in _labels:
		label.queue_free()
	_labels.clear()
	for ability: AbilityData in _abilities:
		var label := HudStyle.make_label("", ITEM_SIZE)
		_items_box.add_child(label)
		_labels.append(label)
	_redraw()
	visible = true


func close() -> void:
	visible = false
	if _choosing_target:
		_choosing_target = false
		target_changed.emit(-1)


func is_open() -> bool:
	return visible


## The abilities currently offered (empty when closed).
func abilities() -> Array[AbilityData]:
	var list: Array[AbilityData] = []
	if visible:
		list.assign(_abilities)
	return list


## Handles one input event. Returns true if it was used.
func handle_input(event: InputEvent) -> bool:
	if not visible or _abilities.is_empty():
		return false
	if _choosing_target:
		return _handle_target_input(event)
	if _pressed(event, &"menu_up"):
		_move(-1)
	elif _pressed(event, &"menu_down"):
		_move(1)
	elif _pressed(event, &"menu_confirm"):
		_confirm_ability()
	else:
		return false
	return true


## Picks an ability (and the first target) directly, for the autoplay bot. Same affordability
## check as a confirm press.
func choose(ability_id: String) -> bool:
	if not visible:
		return false
	for i: int in _abilities.size():
		if _abilities[i].id == ability_id and _can_afford(_abilities[i]):
			_index = i
			_redraw()
			Sfx.play("menu_confirm")
			close()
			chosen.emit(ability_id, _targets[0] if not _targets.is_empty() else -1)
			return true
	return false


## True for a fresh press of `action`. Sticks only count when they cross the deadzone.
func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, false, true):
		return false
	if event is InputEventJoypadMotion:
		var frame := Engine.get_process_frames()
		if not Input.is_action_just_pressed(action) or frame == _stick_frame:
			return false
		_stick_frame = frame
	return true


func _handle_target_input(event: InputEvent) -> bool:
	if _pressed(event, &"menu_left") or _pressed(event, &"menu_up"):
		_cycle_target(-1)
	elif _pressed(event, &"menu_right") or _pressed(event, &"menu_down"):
		_cycle_target(1)
	elif _pressed(event, &"menu_confirm"):
		Sfx.play("menu_confirm")
		var target := _targets[_target_index]
		_choosing_target = false
		target_changed.emit(-1)
		visible = false
		chosen.emit(_abilities[_index].id, target)
	elif _pressed(event, &"menu_cancel"):
		Sfx.play("menu_cancel")
		_choosing_target = false
		target_changed.emit(-1)
		_redraw()
	else:
		return false
	return true


func _move(step: int) -> void:
	_index = wrapi(_index + step, 0, _abilities.size())
	Sfx.play("menu_move")
	_redraw()


func _confirm_ability() -> void:
	var ability := _abilities[_index]
	if not _can_afford(ability):
		Sfx.play("locked")
		return
	if _targets.size() > 1:
		Sfx.play("menu_move")
		_choosing_target = true
		_target_index = 0
		_redraw()
		target_changed.emit(_targets[_target_index])
		return
	Sfx.play("menu_confirm")
	visible = false
	chosen.emit(ability.id, _targets[0] if not _targets.is_empty() else -1)


func _cycle_target(step: int) -> void:
	_target_index = wrapi(_target_index + step, 0, _targets.size())
	Sfx.play("menu_move")
	_redraw()
	target_changed.emit(_targets[_target_index])


func _can_afford(ability: AbilityData) -> bool:
	return _ap >= ability.ap_cost


func _redraw() -> void:
	for i: int in _labels.size():
		var ability := _abilities[i]
		var text := ability.display_name
		if ability.ap_cost > 0:
			text += "   %d AP" % ability.ap_cost
		var selected := i == _index
		_labels[i].text = (CURSOR if selected else "  ") + text
		var color := HudStyle.TEXT
		if not _can_afford(ability):
			color = HudStyle.TEXT_DIM
		elif selected:
			color = HudStyle.GOLD
		_labels[i].label_settings.font_color = color
	if _choosing_target:
		var target := _targets[_target_index]
		_hint.text = "Target: %s   (left/right, Esc/B back)" % String(_target_names.get(target, "?"))
	else:
		_hint.text = "Up/Down choose   Enter/A confirm"
