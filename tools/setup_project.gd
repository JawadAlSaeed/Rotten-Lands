extends SceneTree
## Writes the project settings this game depends on into project.godot. Run headless:
##   godot --headless --path . -s tools/setup_project.gd
## Game input actions are only added if missing (remaps made in the editor are kept).
## Built-in ui_* actions, importer defaults and latency settings are always (re)applied.

const DEADZONE := 0.5


func _init() -> void:
	var actions := {
		"defend_parry": [_key(KEY_SPACE), _joy(JOY_BUTTON_RIGHT_SHOULDER)],
		"defend_dodge": [_key(KEY_SHIFT), _joy(JOY_BUTTON_B)],
		"defend_jump": [_key(KEY_W), _joy(JOY_BUTTON_A)],
		"menu_up": [_key(KEY_UP), _key(KEY_W), _joy(JOY_BUTTON_DPAD_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)],
		"menu_down": [_key(KEY_DOWN), _key(KEY_S), _joy(JOY_BUTTON_DPAD_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)],
		"menu_left": [_key(KEY_LEFT), _key(KEY_A), _joy(JOY_BUTTON_DPAD_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)],
		"menu_right": [_key(KEY_RIGHT), _key(KEY_D), _joy(JOY_BUTTON_DPAD_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)],
		"menu_confirm": [_key(KEY_ENTER), _key(KEY_KP_ENTER), _key(KEY_E), _joy(JOY_BUTTON_A)],
		"menu_cancel": [_key(KEY_ESCAPE), _key(KEY_Q), _key(KEY_BACKSPACE), _joy(JOY_BUTTON_B)],
		"debug_overlay": [_key(KEY_F1), _joy(JOY_BUTTON_BACK)],
	}
	var added := 0
	for action: String in actions:
		var setting := "input/" + action
		if ProjectSettings.has_setting(setting):
			continue
		ProjectSettings.set_setting(setting, {"deadzone": DEADZONE, "events": actions[action]})
		added += 1

	# Godot's built-in UI actions: remove Space (it is the parry key, it must never click a menu
	# button) and add the pad's A/B so focus-driven controls work on a gamepad.
	ProjectSettings.set_setting("input/ui_accept", {"deadzone": DEADZONE,
		"events": [_key(KEY_ENTER), _key(KEY_KP_ENTER), _joy(JOY_BUTTON_A)]})
	ProjectSettings.set_setting("input/ui_select", {"deadzone": DEADZONE,
		"events": [_joy(JOY_BUTTON_Y)]})
	ProjectSettings.set_setting("input/ui_cancel", {"deadzone": DEADZONE,
		"events": [_key(KEY_ESCAPE), _joy(JOY_BUTTON_B)]})

	# Pixel art: no VRAM compression, no mipmaps, even when Godot sees a texture used in 3D.
	ProjectSettings.set_setting("importer_defaults/texture", {
		"compress/mode": 0,
		"detect_3d/compress_to": 0,
		"mipmaps/generate": false,
	})
	# Keep synthesized sounds as plain PCM (the default QOA compression blurs sharp clicks).
	ProjectSettings.set_setting("importer_defaults/wav", {"compress/mode": 0})

	# Lower input-to-screen lag: Mailbox vsync (no tearing, main loop not throttled, so input is
	# pumped more often). Capped so the GPU does not run flat out on a simple scene.
	ProjectSettings.set_setting("display/window/vsync/vsync_mode", DisplayServer.VSYNC_MAILBOX)
	ProjectSettings.set_setting("application/run/max_fps", 480)

	var err := ProjectSettings.save()
	print("setup_project: added %d game actions, save result %d" % [added, err])
	quit(0 if err == OK else 1)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.device = -1
	return e


func _joy(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.device = -1
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	e.device = -1
	return e
