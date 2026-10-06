class_name FighterView
extends Node3D
## One fighter on the stage: a billboard sprite whose frame is the pose, a shadow blob, and the
## flash / glow / greyed-out looks. The node itself stays at the fighter's home spot;
## `body_offset` moves the body (dashes, lunges, dodges, jumps) and the shadow follows on the floor.
## Poses are frame indices of the one-row sheet (DESIGN.md 5.3).

## Frames of a character sheet.
enum CharPose {
	IDLE,
	READY,
	PARRY,
	DODGE,
	JUMP,
	HURT,
	STRIKE,
	DOWN,
}

const SHADER := preload("res://scripts/combat/presentation/fighter_sprite.gdshader")
const SHADOW_HEIGHT := 0.02
## The shadow shrinks to this scale when the body is this high (world units) or higher.
const SHADOW_MIN_SCALE := 0.55
const SHADOW_FADE_HEIGHT := 1.6

## Combatant id this view shows.
var fighter_id: int = -1
var is_party: bool = true
## Body position relative to home (the node's position).
var body_offset: Vector3 = Vector3.ZERO:
	set = set_body_offset

var _sprite: Sprite3D
var _shadow: Sprite3D
var _material: ShaderMaterial
var _hframes: int = 1
var _frame_height_px: float = 48.0
var _pixel_size: float = 0.045
var _head_factor: float = 1.0
var _base_pose: int = 0
var _override_pose: int = -1
var _override_until_us: int = 0
var _flash_until_us: int = 0
var _flash_length_us: int = 1
var _flash_strength: float = 1.0


## Builds the sprite and shadow. `fallback_size` is the sheet size to fake if the art is missing.
func setup(id: int, party: bool, sheet_path: String, hframes: int, frame_size: Vector2i,
		pixel_size: float, flip: bool, visuals: CombatVisuals) -> void:
	fighter_id = id
	is_party = party
	_hframes = maxi(1, hframes)
	_pixel_size = pixel_size
	_head_factor = visuals.head_height_factor
	var texture := AssetLoader.texture(sheet_path, Vector2i(frame_size.x * _hframes, frame_size.y))
	_frame_height_px = float(texture.get_height())

	_sprite = Sprite3D.new()
	_sprite.name = "Body"
	_sprite.texture = texture
	_sprite.hframes = _hframes
	_sprite.pixel_size = pixel_size
	_sprite.centered = true
	_sprite.offset = Vector2(0.0, _frame_height_px * 0.5)
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.flip_h = flip
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("sprite_texture", texture)
	_material.set_shader_parameter("glow_color", visuals.windup_glow_color)
	_sprite.material_override = _material
	add_child(_sprite)

	_shadow = Sprite3D.new()
	_shadow.name = "Shadow"
	_shadow.texture = AssetLoader.texture(visuals.shadow_path, Vector2i(32, 12))
	var frame_width := float(texture.get_width()) / float(_hframes) * pixel_size
	_shadow.pixel_size = frame_width * visuals.shadow_width_factor / float(maxi(1, _shadow.texture.get_width()))
	_shadow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_shadow.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.position = Vector3(0.0, SHADOW_HEIGHT, 0.0)
	add_child(_shadow)
	set_pose(0)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var pose := _base_pose
	if _override_pose >= 0:
		if now < _override_until_us:
			pose = _override_pose
		else:
			_override_pose = -1
	_sprite.frame = clampi(pose, 0, _hframes - 1)
	var flash := 0.0
	if now < _flash_until_us:
		flash = _flash_strength * float(_flash_until_us - now) / float(_flash_length_us)
	_material.set_shader_parameter("flash_amount", clampf(flash, 0.0, 1.0))


## The pose shown when no timed pose is playing.
func set_pose(frame: int) -> void:
	_base_pose = frame
	if _sprite != null and _override_pose < 0:
		_sprite.frame = clampi(frame, 0, _hframes - 1)


## Shows `frame` for `ms` milliseconds (real time), then goes back to the base pose.
func play_pose(frame: int, ms: int) -> void:
	_override_pose = frame
	_override_until_us = Time.get_ticks_usec() + ms * 1000
	_sprite.frame = clampi(frame, 0, _hframes - 1)


func clear_timed_pose() -> void:
	_override_pose = -1


func set_body_offset(value: Vector3) -> void:
	body_offset = value
	if _sprite == null:
		return
	_sprite.position = value
	_shadow.position = Vector3(value.x, SHADOW_HEIGHT, value.z)
	var lift := clampf(value.y / SHADOW_FADE_HEIGHT, 0.0, 1.0)
	_shadow.scale = Vector3.ONE * lerpf(1.0, SHADOW_MIN_SCALE, lift)


## White (or coloured) flash that fades over `ms` milliseconds of real time.
func flash(ms: int, color: Color = Color.WHITE, strength: float = 1.0) -> void:
	_flash_length_us = maxi(1, ms * 1000)
	_flash_until_us = Time.get_ticks_usec() + _flash_length_us
	_flash_strength = strength
	_material.set_shader_parameter("flash_color", color)
	_material.set_shader_parameter("flash_amount", clampf(strength, 0.0, 1.0))


## Wind-up glow strength (0..1).
func set_glow(amount: float) -> void:
	_material.set_shader_parameter("glow_amount", clampf(amount, 0.0, 1.0))


## Greyed-out look for a downed fighter (0..1).
func set_grey(amount: float) -> void:
	_material.set_shader_parameter("grey_amount", clampf(amount, 0.0, 1.0))


func set_tint(color: Color) -> void:
	_material.set_shader_parameter("tint", color)


## Height of the sprite in world units.
func sprite_height() -> float:
	return _frame_height_px * _pixel_size


## Where the body is now (feet), in world space.
func body_position() -> Vector3:
	return global_position + body_offset


## Above the head, for popups and icons.
func head_position() -> Vector3:
	return body_position() + Vector3(0.0, sprite_height() * _head_factor, 0.0)


## Middle of the body, for sparks and rings.
func centre_position() -> Vector3:
	return body_position() + Vector3(0.0, sprite_height() * 0.5, 0.0)
