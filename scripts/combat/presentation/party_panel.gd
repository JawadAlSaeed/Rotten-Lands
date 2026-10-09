class_name PartyPanel
extends PanelContainer
## One party member's panel at the bottom of the screen: name, HP bar and numbers, AP gems (up to
## max_ap), DOWN state, the active-turn highlight (gold) and the "being attacked" highlight (red).
## Values come from the mirror.

const NAME_SIZE: int = 30
const HP_TEXT_SIZE: int = 24
const STATE_SIZE: int = 26
const HP_BAR_HEIGHT: float = 22.0
const LOW_HP_PERCENT: int = 30
const ACTIVE_BORDER_PX: int = 4
const IDLE_BORDER_PX: int = 2
const PANEL_WIDTH: float = 372.0

var fighter_id: int = -1

var _style: StyleBoxFlat
var _accent: Color = Color.WHITE
var _name_label: Label
var _state_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _ap_label: Label
var _pips: Array[TextureRect] = []
var _pip_full: Texture2D
var _pip_empty: Texture2D
var _active: bool = false
var _targeted: bool = false


func setup(id: int, display_name: String, accent: Color, max_ap: int, visuals: CombatVisuals) -> void:
	fighter_id = id
	_accent = accent
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	_style = HudStyle.panel(HudStyle.PANEL_BG, HudStyle.PANEL_BORDER, IDLE_BORDER_PX, 12)
	add_theme_stylebox_override("panel", _style)
	_pip_full = AssetLoader.texture(visuals.ap_pip_path, Vector2i(10, 10))
	_pip_empty = AssetLoader.texture(visuals.ap_pip_empty_path, Vector2i(10, 10))

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	_name_label = HudStyle.make_label(display_name, NAME_SIZE, accent.lightened(0.25))
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_name_label)
	_state_label = HudStyle.make_label("", STATE_SIZE, HudStyle.LATE)
	top.add_child(_state_label)

	_hp_bar = HudStyle.bar(HudStyle.HP_FILL, HP_BAR_HEIGHT)
	column.add_child(_hp_bar)

	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bottom)
	_hp_label = HudStyle.make_label("", HP_TEXT_SIZE)
	_hp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_hp_label)
	_ap_label = HudStyle.make_label("", HP_TEXT_SIZE, HudStyle.JUMP)
	bottom.add_child(_ap_label)

	var pips := HBoxContainer.new()
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.add_theme_constant_override("separation", 4)
	column.add_child(pips)
	for i: int in max_ap:
		var pip := TextureRect.new()
		pip.custom_minimum_size = Vector2(visuals.ap_pip_px, visuals.ap_pip_px)
		pip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.texture = _pip_empty
		pips.add_child(pip)
		_pips.append(pip)


## Updates from a mirror fighter dictionary.
func refresh(f: Dictionary, active: bool) -> void:
	if f.is_empty():
		return
	var hp := int(f.hp)
	var max_hp := maxi(1, int(f.max_hp))
	var ap := int(f.ap)
	var alive := bool(f.alive)
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp
	HudStyle.set_bar_color(_hp_bar, HudStyle.HP_LOW if hp * 100 <= max_hp * LOW_HP_PERCENT else HudStyle.HP_FILL)
	_hp_label.text = "HP %d / %d" % [hp, max_hp]
	_ap_label.text = "AP %d" % ap
	for i: int in _pips.size():
		_pips[i].texture = _pip_full if i < ap else _pip_empty
	_state_label.text = "" if alive else "DOWN"
	modulate = Color.WHITE if alive else Color(0.6, 0.6, 0.65)
	_active = active
	_apply_border()


## Red border while an enemy attack targets this character.
func set_targeted(targeted: bool) -> void:
	_targeted = targeted
	_apply_border()


func _apply_border() -> void:
	var color := HudStyle.PANEL_BORDER
	if _targeted:
		color = HudStyle.LATE
	elif _active:
		color = HudStyle.GOLD
	_style.border_color = color
	_style.set_border_width_all(ACTIVE_BORDER_PX if _targeted or _active else IDLE_BORDER_PX)
