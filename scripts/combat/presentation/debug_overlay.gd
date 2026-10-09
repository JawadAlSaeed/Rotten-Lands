class_name DebugOverlay
extends PanelContainer
## F1 stats overlay (DESIGN.md 3.1, 3.2 and 7.1): defence success per action, mean and spread of
## successful timing offsets, rolling median of recent parries, lag compensation, fps, vsync mode,
## audio latency and the longest frame of the last enemy attack, plus the cue toggles
## (R training ring, saved; F telegraph flash, T timing readout and L motion sounds, this session
## only). It sits in the right column, under the practice status, clear of the fighters.

const TEXT_SIZE: int = 16
const TITLE_SIZE: int = 20
const WIDTH: float = 340.0
const TOP: float = 345.0
const MARGIN: float = 24.0
const ACTIONS: Array[int] = [Defense.Outcome.PARRY, Defense.Outcome.DODGE, Defense.Outcome.JUMP]

var _body: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, 0.0)
	add_theme_stylebox_override("panel", HudStyle.panel(Color(0.02, 0.02, 0.04, 0.7), HudStyle.JUMP, 2, 12))
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_left = -WIDTH - MARGIN
	offset_right = -MARGIN
	offset_top = TOP
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	column.add_child(HudStyle.make_label("DEFENCE STATS  (F1 closes)", TITLE_SIZE, HudStyle.JUMP))
	_body = HudStyle.make_label("", TEXT_SIZE)
	column.add_child(_body)
	visible = false


func toggle() -> void:
	visible = not visible


## Rebuilds the text. `longest_frame_ms` is from the last (or current) enemy attack. On the end
## screen (`ended`) the toggle keys do not apply, so the last lines say how to fight again.
func update_text(stats: DefenseStats, tuning: Tuning, options: CombatOptions, longest_frame_ms: float, ended: bool = false) -> void:
	if not visible:
		return
	var lines := PackedStringArray()
	for action: int in ACTIONS:
		var presses := stats.press_count(action)
		var line := "%-6s %3d / %-3d  %5.1f%%" % [Defense.outcome_name(action).capitalize(),
				stats.success_count(action), presses, stats.success_percent(action)]
		lines.append(line)
		if stats.success_count(action) > 0:
			lines.append("       mean %+.1f ms  sd %.1f ms" % [stats.mean_ms(action), stats.stddev_ms(action)])
	lines.append("Whiffs %d: early %d, late %d, wrong %d" % [stats.whiffs,
			stats.whiff_count(DefenseJudge.Reason.EARLY), stats.whiff_count(DefenseJudge.Reason.LATE),
			stats.whiff_count(DefenseJudge.Reason.WRONG_ACTION)])
	lines.append("Locked presses %d" % stats.locked_presses)
	if stats.recent_parry_us.is_empty():
		lines.append("Parry median (last %d): -" % DefenseStats.RECENT_PARRY_COUNT)
	else:
		lines.append("Parry median (last %d): %+.1f ms" % [stats.recent_parry_us.size(), stats.recent_parry_median_ms()])
	if not stats.recent_all_us.is_empty():
		lines.append("All presses median (last %d): %+.1f ms" % [stats.recent_all_us.size(), stats.recent_all_median_ms()])
	var source := "calibrated (F2)" if PlayerSettings.is_calibrated() else "tuning default"
	lines.append("Lag compensation: %d ms" % PlayerSettings.latency_compensation_ms(tuning))
	lines.append("    (%s)" % source)
	lines.append("FPS %d   VSync %s" % [Engine.get_frames_per_second(), _vsync_name()])
	lines.append("Audio latency %.1f ms" % (AudioServer.get_output_latency() * 1000.0))
	lines.append("Longest frame, last attack: %.1f ms" % longest_frame_ms)
	lines.append("")
	if ended:
		lines.append("%s or R: fight again" % HudStyle.binding_text(&"menu_confirm"))
		_body.text = "\n".join(lines)
		return
	lines.append("[R] Training ring: %s (saved)" % _on_off(PlayerSettings.show_timing_ring(tuning)))
	lines.append("[F] Telegraph flash: %s" % _on_off(options.telegraph_flash))
	lines.append("[T] Timing readout: %s" % _on_off(options.timing_readout))
	lines.append("[L] Enemy motion sounds: %s" % _on_off(options.motion_sounds))
	_body.text = "\n".join(lines)


static func _on_off(value: bool) -> String:
	return "ON" if value else "OFF"


static func _vsync_name() -> String:
	if DisplayServer.get_name() == "headless":
		return "n/a (headless)"
	match DisplayServer.window_get_vsync_mode():
		DisplayServer.VSYNC_DISABLED:
			return "off"
		DisplayServer.VSYNC_ENABLED:
			return "on"
		DisplayServer.VSYNC_ADAPTIVE:
			return "adaptive"
		DisplayServer.VSYNC_MAILBOX:
			return "mailbox"
	return "?"
