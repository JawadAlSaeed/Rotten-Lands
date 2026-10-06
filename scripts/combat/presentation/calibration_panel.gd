class_name CalibrationPanel
extends Control
## Lag calibration (F2, DESIGN.md 3.2): a big circle flashes with the "metronome" sound on a fixed
## beat; the player presses Parry on each beat. Presses are stamped by the same DefenseInput as in
## combat (the midpoint of the press interval). The median offset of the last presses becomes the
## player's lag compensation when they confirm (saved by UserSettings); cancel discards it.

signal closed

const TITLE_SIZE: int = 44
const TEXT_SIZE: int = 30
const CIRCLE_RADIUS: float = 150.0
const CIRCLE_RING_WIDTH: float = 8.0
const SEGMENTS: int = 96
const DIM := Color(0.0, 0.0, 0.0, 0.8)
const CIRCLE_IDLE := Color(0.3, 0.32, 0.38)
const CIRCLE_LIT := Color(1.0, 0.95, 0.7)

var _visuals: CombatVisuals
var _input: DefenseInput
var _running: bool = false
var _first_beat_us: int = 0
var _next_beat: int = 0
var _lit_until_us: int = 0
var _offsets_us: Array[int] = []
var _title: Label
var _text: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_preset(Control.PRESET_TOP_WIDE)
	column.offset_top = 120.0
	add_child(column)
	_title = HudStyle.make_label("LAG CALIBRATION", TITLE_SIZE, HudStyle.GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	_text = HudStyle.make_label("", TEXT_SIZE)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_text)
	visible = false


func setup(visuals: CombatVisuals, input: DefenseInput) -> void:
	_visuals = visuals
	_input = input
	_input.pressed.connect(_on_pressed)


func is_running() -> bool:
	return _running


func open() -> void:
	_running = true
	visible = true
	_offsets_us.clear()
	_next_beat = 0
	_lit_until_us = 0
	_first_beat_us = Time.get_ticks_usec() + _visuals.calibration_lead_ms * 1000
	var parry: Array[int] = [Defense.Outcome.PARRY]
	_input.arm(parry)
	_update_text()


## Confirm saves (once enough presses were made), cancel discards. Returns true if used.
func handle_input(event: InputEvent) -> bool:
	if not _running:
		return false
	if event.is_action_pressed("menu_confirm", false, true):
		if _offsets_us.size() >= _visuals.calibration_min_presses:
			PlayerSettings.set_latency_compensation_ms(roundi(_median_us() / 1000.0))
			Sfx.play("menu_confirm")
			_close()
		else:
			Sfx.play("locked")
		return true
	if event.is_action_pressed("menu_cancel", false, true):
		Sfx.play("menu_cancel")
		_close()
		return true
	return true


func _process(_delta: float) -> void:
	if not _running:
		return
	var now := Time.get_ticks_usec()
	while _next_beat < _visuals.calibration_beats and now >= _beat_time_us(_next_beat):
		Sfx.play("metronome")
		_lit_until_us = now + _visuals.calibration_flash_ms * 1000
		_next_beat += 1
		_update_text()
	queue_redraw()


func _draw() -> void:
	if not _running:
		return
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	var centre := size * 0.5 + Vector2(0.0, 60.0)
	var lit := Time.get_ticks_usec() < _lit_until_us
	if lit:
		draw_circle(centre, CIRCLE_RADIUS, CIRCLE_LIT)
	draw_arc(centre, CIRCLE_RADIUS, 0.0, TAU, SEGMENTS, CIRCLE_LIT if lit else CIRCLE_IDLE, CIRCLE_RING_WIDTH, true)


func _on_pressed(action: int, stamp_us: int, previous_pump_us: int, _device: int) -> void:
	if not _running or action != Defense.Outcome.PARRY:
		return
	var mid := stamp_us
	if previous_pump_us > 0 and previous_pump_us < stamp_us:
		@warning_ignore("integer_division")
		mid = previous_pump_us + (stamp_us - previous_pump_us) / 2
	var interval_us := _visuals.calibration_interval_ms * 1000
	var beat := clampi(roundi(float(mid - _first_beat_us) / float(interval_us)), 0, _visuals.calibration_beats - 1)
	var offset := mid - _beat_time_us(beat)
	@warning_ignore("integer_division")
	var half_us := interval_us / 2
	if absi(offset) <= half_us:
		_offsets_us.append(offset)
		Sfx.play("menu_move")
	_update_text()


func _beat_time_us(beat: int) -> int:
	return _first_beat_us + beat * _visuals.calibration_interval_ms * 1000


func _median_us() -> float:
	var count := mini(_visuals.calibration_sample_count, _offsets_us.size())
	var recent: Array[int] = []
	recent.assign(_offsets_us.slice(_offsets_us.size() - count))
	return DefenseStats.median_us(recent)


func _update_text() -> void:
	var lines := PackedStringArray()
	lines.append("Press PARRY (Space / RB) exactly when the circle flashes.")
	lines.append("Beat %d / %d   presses counted: %d" % [_next_beat, _visuals.calibration_beats, _offsets_us.size()])
	if _offsets_us.is_empty():
		lines.append("Median offset: -")
	else:
		lines.append("Median offset (last %d): %+d ms" % [mini(_visuals.calibration_sample_count, _offsets_us.size()), roundi(_median_us() / 1000.0)])
	if _offsets_us.size() >= _visuals.calibration_min_presses:
		lines.append("Enter / A: save as lag compensation      Esc / B: cancel")
	else:
		lines.append("Esc / B: cancel")
	_text.text = "\n".join(lines)


func _close() -> void:
	_running = false
	visible = false
	_input.disarm()
	closed.emit()
