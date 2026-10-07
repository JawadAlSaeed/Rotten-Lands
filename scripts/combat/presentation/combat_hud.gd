class_name CombatHud
extends CanvasLayer
## The combat HUD on the 1920x1080 canvas (DESIGN.md 7.1): turn timeline (top left), attack
## banner (top centre), enemy HP (top right), party panels (bottom), action menu, popups and
## damage numbers, training rings, lock icon, controls hint, practice status, F1 overlay,
## calibration and the end screen. It shows what the CombatMirror says; world positions are
## projected through the CombatView camera.

const MARGIN: float = 24.0
const BANNER_TOP: float = 150.0
const BANNER_SIZE: int = 40
const CENTER_BANNER_SIZE: int = 96
## The attack banner's slot: it is hidden before a counter plays, and this keeps the big text
## above the defence readouts near the heads.
const CENTER_BANNER_TOP: float = 150.0
## Share of a centre banner's time it stays fully visible before fading.
const CENTER_BANNER_HOLD_SHARE: float = 0.7
const POPUP_SIZE: int = 40
const DAMAGE_SIZE: int = 52
const POPUP_WIDTH: float = 480.0
const HINT_SIZE: int = 24
const PRACTICE_SIZE: int = 20
const ENEMY_NAME_SIZE: int = 30
const ENEMY_HP_SIZE: int = 22
const ENEMY_BAR_WIDTH: float = 520.0
const ENEMY_BAR_HEIGHT: float = 26.0
const MENU_BOTTOM: float = 236.0
const PANEL_GAP: int = 20
const END_TITLE_SIZE: int = 150
const END_HINT_SIZE: int = 40
const END_DIM := Color(0.0, 0.0, 0.0, 0.62)
const VICTORY_COLOR := Color(1.0, 0.85, 0.35)
const DEFEAT_COLOR := Color(0.9, 0.3, 0.28)
const TARGET_MARKER_SIZE: int = 48
const END_SUMMARY_SIZE: int = 30
## Gap kept between stacked popups (pixels).
const POPUP_GAP_PX: float = 4.0
## Popups whose spots are closer than this share of POPUP_WIDTH horizontally share a column.
const POPUP_COLUMN_SHARE: float = 0.3
## A popup pushed against the ceiling fades out over this share of its life (not a hard cut).
const POPUP_LEAVE_SHARE: float = 0.12
## Popup animation shape: punch settle, then fade over the end of the life.
const POPUP_PUNCH_SHARE: float = 0.15
const POPUP_FADE_FROM_SHARE: float = 0.6

var action_menu: ActionMenu
var overlay: DebugOverlay
var calibration: CalibrationPanel

var _view: CombatView
var _visuals: CombatVisuals
var _tuning: Tuning
var _root: Control
var _timeline: TimelineRow
var _banner: PanelContainer
var _banner_label: Label
var _center_banner: Label
var _enemy_box: VBoxContainer
var _enemy_rows: Dictionary = {}
var _party_box: HBoxContainer
var _party_panels: Dictionary = {}
var _practice_label: Label
var _popup_layer: Control
var _ring_layer: RingLayer
var _lock_icon: TextureRect
var _target_marker: Label
## One arrow per targeted character while an attack winds up.
var _target_arrows: Array[Label] = []
var _end_screen: Control
var _end_title: Label
var _end_summary: Label
var _end_hint: Label
var _portraits: Dictionary = {}
var _colors: Dictionary = {}
## Popups on screen, oldest first: [{label: Label, base: Vector2 (spawn centre), born_us: int}].
var _popups: Array[Dictionary] = []
var _center_tween: Tween
var _targeted: Array[int] = []


## Builds the parts that do not depend on the fighters.
func setup(view: CombatView, visuals: CombatVisuals, tuning: Tuning) -> void:
	_view = view
	_visuals = visuals
	_tuning = tuning
	layer = 10

	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_ring_layer = RingLayer.new()
	_ring_layer.name = "Rings"
	_root.add_child(_ring_layer)

	_popup_layer = Control.new()
	_popup_layer.name = "Popups"
	_popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_popup_layer)

	_lock_icon = TextureRect.new()
	_lock_icon.name = "Lock"
	_lock_icon.texture = AssetLoader.texture(visuals.lock_icon_path, Vector2i(12, 12))
	_lock_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lock_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lock_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_lock_icon.size = Vector2(visuals.lock_icon_px, visuals.lock_icon_px)
	_lock_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_icon.visible = false
	_root.add_child(_lock_icon)

	_target_marker = HudStyle.make_label("v", TARGET_MARKER_SIZE, HudStyle.GOLD)
	_target_marker.visible = false
	_root.add_child(_target_marker)

	_timeline = TimelineRow.new()
	_timeline.name = "Timeline"
	_timeline.position = Vector2(MARGIN, MARGIN)
	_timeline.setup(tuning.turn_order_preview, visuals.portrait_px)
	_root.add_child(_timeline)

	_banner = PanelContainer.new()
	_banner.name = "Banner"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_stylebox_override("panel", HudStyle.panel(Color(0.08, 0.02, 0.02, 0.85), HudStyle.LATE, 3, 14))
	_banner_label = HudStyle.make_label("", BANNER_SIZE)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_label)
	_banner.visible = false
	# Anchored at the top centre and growing both ways, so it stays centred for any text length.
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = BANNER_TOP
	_root.add_child(_banner)

	_center_banner = HudStyle.make_label("", CENTER_BANNER_SIZE, HudStyle.GOLD)
	_center_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_center_banner.offset_top = CENTER_BANNER_TOP
	_center_banner.visible = false
	_root.add_child(_center_banner)

	# Top right: enemy HP bars, then the practice status under them.
	var right_column := VBoxContainer.new()
	right_column.name = "RightColumn"
	right_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_column.add_theme_constant_override("separation", 18)
	right_column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_column.offset_right = -MARGIN
	right_column.offset_top = MARGIN
	_root.add_child(right_column)
	# Popups and the lock icon draw above the banners and timeline (never hidden under them);
	# everything added after this (panels, menu, overlay, end screen) draws above them.
	_root.move_child(_popup_layer, -1)
	_root.move_child(_lock_icon, -1)
	_enemy_box = VBoxContainer.new()
	_enemy_box.name = "Enemies"
	_enemy_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_box.add_theme_constant_override("separation", 10)
	right_column.add_child(_enemy_box)
	_practice_label = HudStyle.make_label("", PRACTICE_SIZE, HudStyle.GOLD)
	_practice_label.name = "PracticeStatus"
	_practice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_practice_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_practice_label.visible = tuning.practice_tools_enabled
	right_column.add_child(_practice_label)

	_party_box = HBoxContainer.new()
	_party_box.name = "Party"
	_party_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_party_box.add_theme_constant_override("separation", PANEL_GAP)
	_party_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_party_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_party_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_party_box.offset_bottom = -MARGIN
	_root.add_child(_party_box)

	var controls := HudStyle.make_label(_controls_text(), HINT_SIZE, HudStyle.TEXT)
	controls.name = "ControlsHint"
	controls.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	controls.grow_vertical = Control.GROW_DIRECTION_BEGIN
	controls.offset_left = MARGIN
	controls.offset_bottom = -MARGIN
	_root.add_child(controls)

	action_menu = ActionMenu.new()
	action_menu.name = "ActionMenu"
	action_menu.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	action_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	action_menu.grow_vertical = Control.GROW_DIRECTION_BEGIN
	action_menu.offset_bottom = -MENU_BOTTOM
	_root.add_child(action_menu)

	overlay = DebugOverlay.new()
	overlay.name = "DebugOverlay"
	_root.add_child(overlay)

	calibration = CalibrationPanel.new()
	calibration.name = "Calibration"
	_root.add_child(calibration)

	_build_end_screen()


## Builds the timeline portraits, party panels and enemy bars once the fighters are known.
## `data_by_id` maps combatant id -> CharacterData or EnemyData.
func build_fighters(mirror: CombatMirror, data_by_id: Dictionary) -> void:
	for id: int in mirror.fighters:
		var data: Resource = data_by_id.get(id)
		if data is CharacterData:
			_portraits[id] = AssetLoader.texture((data as CharacterData).portrait_path, Vector2i(24, 24))
			_colors[id] = (data as CharacterData).color
		elif data is EnemyData:
			_portraits[id] = AssetLoader.texture((data as EnemyData).portrait_path, Vector2i(24, 24))
			_colors[id] = (data as EnemyData).color
	# Panels in the same left-to-right order as the fighters on screen.
	var party: Array[int] = mirror.party_ids.duplicate()
	party.sort_custom(func(a: int, b: int) -> bool:
		return _view.screen_position(_view.home_of(a)).x < _view.screen_position(_view.home_of(b)).x)
	for id: int in party:
		var f := mirror.fighter(id)
		var panel := PartyPanel.new()
		panel.setup(id, String(f.display_name), _colors.get(id, Color.WHITE) as Color, _tuning.max_ap, _visuals)
		_party_box.add_child(panel)
		_party_panels[id] = panel
	for id: int in mirror.enemy_ids:
		var f := mirror.fighter(id)
		var row := VBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 4)
		var name_label := HudStyle.make_label(String(f.display_name), ENEMY_NAME_SIZE, (_colors.get(id, Color.WHITE) as Color).lightened(0.3))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var bar := HudStyle.bar(HudStyle.ENEMY_HP_FILL, ENEMY_BAR_HEIGHT)
		bar.custom_minimum_size.x = ENEMY_BAR_WIDTH
		var hp_label := HudStyle.make_label("", ENEMY_HP_SIZE)
		hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(name_label)
		row.add_child(bar)
		row.add_child(hp_label)
		_enemy_box.add_child(row)
		_enemy_rows[id] = {"bar": bar, "hp": hp_label, "row": row}


## Updates every bar, panel and the timeline from the mirror.
func refresh(mirror: CombatMirror, practice_text: String) -> void:
	var order: Array[int] = []
	if mirror.result.is_empty():
		order = mirror.turn_order
	_timeline.show_order(order, mirror, _portraits, _colors)
	for id: int in _party_panels:
		var panel := _party_panels[id] as PartyPanel
		panel.refresh(mirror.fighter(id), id == mirror.active_actor)
		panel.set_targeted(_targeted.has(id))
	for id: int in _enemy_rows:
		var f := mirror.fighter(id)
		var row: Dictionary = _enemy_rows[id]
		var bar: ProgressBar = row.bar
		bar.max_value = maxi(1, int(f.max_hp))
		bar.value = int(f.hp)
		(row.hp as Label).text = "HP %d / %d" % [int(f.hp), int(f.max_hp)] if bool(f.alive) else "DEFEATED"
	_practice_label.text = practice_text


func portrait(id: int) -> Texture2D:
	return _portraits.get(id) as Texture2D


func color_of(id: int) -> Color:
	return _colors.get(id, Color.WHITE) as Color


func show_banner(text: String) -> void:
	# A fading TEAM COUNTER banner from the previous turn never sits under a new attack banner.
	if _center_tween != null and _center_tween.is_valid():
		_center_tween.kill()
	_center_banner.visible = false
	_banner_label.text = text
	_banner.visible = true
	_banner.offset_left = 0.0
	_banner.offset_right = 0.0


func hide_banner() -> void:
	_banner.visible = false


## Big text in the middle of the screen (TEAM COUNTER) for `ms` milliseconds.
func show_center_banner(text: String, color: Color, ms: int) -> void:
	_center_banner.text = text
	_center_banner.label_settings.font_color = color
	_center_banner.visible = true
	_center_banner.modulate = Color.WHITE
	_center_banner.scale = Vector2.ONE
	if _center_tween != null and _center_tween.is_valid():
		_center_tween.kill()
	_center_tween = _center_banner.create_tween()
	_center_tween.tween_interval(float(ms) / 1000.0 * CENTER_BANNER_HOLD_SHARE)
	_center_tween.tween_property(_center_banner, "modulate:a", 0.0, float(ms) / 1000.0 * (1.0 - CENTER_BANNER_HOLD_SHARE))
	_center_tween.tween_callback(_center_banner.hide)


## A floating text that rises and fades over tuning popup_ms, at a world position.
func popup(text: String, world_pos: Vector3, color: Color, font_size: int = POPUP_SIZE) -> void:
	popup_screen(text, _view.screen_position(world_pos), color, font_size)


## A floating text at a HUD canvas position. It rises and fades over tuning popup_ms; popups in
## the same column stack (see _layout_popups).
func popup_screen(text: String, screen_pos: Vector2, color: Color, font_size: int = POPUP_SIZE) -> void:
	var label := _make_popup_label(text, color, font_size)
	_popups.append({"label": label, "base": screen_pos, "born_us": Time.get_ticks_usec()})
	_layout_popups()


func _process(_delta: float) -> void:
	if not _popups.is_empty():
		_layout_popups()


func _make_popup_label(text: String, color: Color, font_size: int) -> Label:
	var seconds := float(_tuning.popup_ms) / 1000.0
	var label := HudStyle.make_label(text, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(POPUP_WIDTH, 0.0)
	_popup_layer.add_child(label)
	label.reset_size()
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2.ONE * _visuals.popup_punch_scale
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "scale", Vector2.ONE, seconds * POPUP_PUNCH_SHARE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, seconds * (1.0 - POPUP_FADE_FROM_SHARE)).set_delay(seconds * POPUP_FADE_FROM_SHARE)
	tween.chain().tween_callback(label.queue_free)
	return label


## A damage number at a world position.
func damage_number(amount: int, world_pos: Vector3, color: Color) -> void:
	popup(str(amount), world_pos, color, DAMAGE_SIZE)


func set_rings(rings: Array[Dictionary]) -> void:
	_ring_layer.set_rings(rings, _visuals.ring_width_px)


## Shows or hides the lock icon, placed lock_icon_offset_px from a world position on screen.
func set_lock(shown: bool, world_pos: Vector3 = Vector3.ZERO) -> void:
	_lock_icon.visible = shown
	if shown:
		_lock_icon.position = _view.screen_position(world_pos) + _visuals.lock_icon_offset_px - _lock_icon.size * 0.5


## Highlights the party panels of the characters an enemy attack targets (empty clears).
func set_targeted(ids: Array[int]) -> void:
	_targeted = ids.duplicate()
	for id: int in _party_panels:
		(_party_panels[id] as PartyPanel).set_targeted(_targeted.has(id))


## Shows an arrow above each of these world positions (empty hides them all).
func set_target_arrows(heads: Array[Vector3]) -> void:
	while _target_arrows.size() < heads.size():
		var arrow := HudStyle.make_label("v", TARGET_MARKER_SIZE, HudStyle.LATE)
		_root.add_child(arrow)
		_target_arrows.append(arrow)
	for i: int in _target_arrows.size():
		var arrow := _target_arrows[i]
		arrow.visible = i < heads.size()
		if arrow.visible:
			arrow.reset_size()
			arrow.position = _view.screen_position(heads[i]) - Vector2(arrow.size.x * 0.5, arrow.size.y)


## Points at the enemy being targeted (only shown when there is a choice); -1 hides it.
func set_target_marker(world_pos: Vector3, shown: bool) -> void:
	_target_marker.visible = shown
	if shown:
		_target_marker.reset_size()
		_target_marker.position = _view.screen_position(world_pos) - Vector2(_target_marker.size.x * 0.5, _target_marker.size.y)


## The victory or defeat screen, with a one-line summary of the fight's defence.
func show_end(result: String, summary: String) -> void:
	var victory := result == "victory"
	_end_title.text = "VICTORY" if victory else "DEFEAT"
	_end_title.label_settings.font_color = VICTORY_COLOR if victory else DEFEAT_COLOR
	_end_summary.text = summary
	_end_hint.text = "%s  or  R:  fight again      F1: stats" % HudStyle.binding_text(&"menu_confirm")
	_end_screen.visible = true
	_end_screen.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_end_screen.create_tween().tween_property(_end_screen, "modulate:a", 1.0, float(_visuals.end_fade_ms) / 1000.0)
	# The F1 stats can be read on the end screen: draw them above its dim.
	_root.move_child(overlay, -1)


func is_end_shown() -> bool:
	return _end_screen.visible


## Draws the lock icon and a popup once, nearly invisible, so nothing compiles mid-fight.
func warm_up() -> void:
	_lock_icon.visible = true
	_lock_icon.modulate = Color(1.0, 1.0, 1.0, CombatView.WARM_UP_ALPHA)
	var label := _make_popup_label(" ", HudStyle.TEXT, POPUP_SIZE)
	label.position = Vector2(-POPUP_WIDTH, -100.0)


func finish_warm_up() -> void:
	_lock_icon.visible = false
	_lock_icon.modulate = Color.WHITE


## Places every live popup, newest first. Each rises popup_rise_px over its life from its spot
## (never above the ceiling). In a column, every older popup stays above every newer one with a
## small gap, pushed up as needed, so a column always reads oldest at the top and nothing
## overlaps. A popup that would be pushed past the ceiling (the attack banner, or the timeline)
## stops there and fades out quickly instead. One pass over the list: always terminates.
func _layout_popups() -> void:
	var now := Time.get_ticks_usec()
	var life := float(maxi(1, _tuning.popup_ms * 1000))
	var ceiling := _popup_ceiling()
	var placed: Array[Dictionary] = []
	var kept: Array[Dictionary] = []
	for i: int in range(_popups.size() - 1, -1, -1):
		var entry: Dictionary = _popups[i]
		if not is_instance_valid(entry.label) or (entry.label as Label).is_queued_for_deletion():
			continue
		var label := entry.label as Label
		var base: Vector2 = entry.base
		var half := label.size.y * 0.5
		var age := clampf(float(now - int(entry.born_us)) / life, 0.0, 1.0)
		var y := maxf(base.y - _visuals.popup_rise_px * (1.0 - (1.0 - age) * (1.0 - age)), ceiling + half)
		for newer: Dictionary in placed:
			if absf(float(newer.x) - base.x) < POPUP_WIDTH * POPUP_COLUMN_SHARE:
				y = minf(y, float(newer.top) - POPUP_GAP_PX - half)
		if y - half < ceiling:
			y = ceiling + half
			if not bool(entry.get("leaving", false)):
				entry["leaving"] = true
				var fade := label.create_tween()
				fade.tween_property(label, "modulate:a", 0.0, float(_tuning.popup_ms) / 1000.0 * POPUP_LEAVE_SHARE)
				fade.tween_callback(label.queue_free)
		label.position = Vector2(base.x - POPUP_WIDTH * 0.5, y - half)
		placed.append({"x": base.x, "top": y - half})
		kept.push_front(entry)
	_popups = kept


## Popups never go above this canvas y: below the timeline, and below the attack or TEAM COUNTER
## banner while one shows.
func _popup_ceiling() -> float:
	var ceiling := _timeline.get_global_rect().end.y
	if _banner.visible:
		ceiling = maxf(ceiling, _banner.get_global_rect().end.y)
	if _center_banner.visible:
		ceiling = maxf(ceiling, _center_banner.get_global_rect().end.y)
	return ceiling + POPUP_GAP_PX


## Control hints built from the Input Map, plus the two rules a new player needs first.
static func _controls_text() -> String:
	return "Parry   %s\nDodge   %s\nJump    %s\nGround wave: Jump only\nParry every hit: counterattack" % [
			HudStyle.binding_text(&"defend_parry"), HudStyle.binding_text(&"defend_dodge"),
			HudStyle.binding_text(&"defend_jump")]


func _build_end_screen() -> void:
	_end_screen = Control.new()
	_end_screen.name = "EndScreen"
	_end_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_screen.visible = false
	var dim := ColorRect.new()
	dim.color = END_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_screen.add_child(dim)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 24)
	_end_screen.add_child(column)
	_end_title = HudStyle.make_label("", END_TITLE_SIZE, VICTORY_COLOR)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_end_title)
	_end_summary = HudStyle.make_label("", END_SUMMARY_SIZE)
	_end_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_end_summary)
	_end_hint = HudStyle.make_label("", END_HINT_SIZE)
	_end_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_end_hint)
	_root.add_child(_end_screen)
