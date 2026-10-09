class_name CombatView
extends Node3D
## The 3D stage (phase 1: simple and readable; HD-2D comes in phase 3): tiled floor, far
## backdrop, dark ambient light with light fog, one directional light, the fixed 3/4 camera, the
## fighters (party on the left facing right, enemies on the right) and short-lived effects
## (sparks, slashes, ground-wave crests). All art comes from data paths via AssetLoader.

## Effect animation shape: a slash grows to this scale, a spark shrinks to this one.
const SLASH_GROWTH: float = 1.3
const SPARK_END_SCALE: float = 0.4
## Effects drawn for one frame at fight start so the first parry has no compile hitch.
const WARM_UP_ALPHA: float = 0.02

var camera: CombatCamera

var _visuals: CombatVisuals
var _fighters: Dictionary = {}
var _spark_texture: Texture2D
var _slash_texture: Texture2D
var _wave_texture: Texture2D
var _wave_crests: Array[Sprite3D] = []
var _rng := RandomNumberGenerator.new()


## Builds the stage. Call once before adding fighters.
func build(visuals: CombatVisuals) -> void:
	_visuals = visuals
	_rng.randomize()
	_spark_texture = AssetLoader.texture(visuals.spark_path, Vector2i(16, 16))
	_slash_texture = AssetLoader.texture(visuals.slash_path, Vector2i(32, 32))
	_wave_texture = AssetLoader.texture(visuals.shockwave_path, Vector2i(64, 16))

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = visuals.background_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = visuals.ambient_color
	env.ambient_light_energy = visuals.ambient_energy
	env.fog_enabled = true
	env.fog_light_color = visuals.fog_color
	env.fog_density = visuals.fog_density
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.light_color = visuals.light_color
	light.light_energy = visuals.light_energy
	light.rotation_degrees = visuals.light_rotation_degrees
	light.shadow_enabled = false
	add_child(light)

	camera = CombatCamera.new()
	camera.name = "Camera"
	camera.setup(visuals.camera_position, visuals.camera_target, visuals.camera_fov)
	add_child(camera)
	camera.current = true

	_build_floor()
	_build_backdrop()
	for i: int in visuals.wave_crest_count:
		var crest := _effect_sprite(_wave_texture, BaseMaterial3D.BILLBOARD_FIXED_Y)
		crest.name = "WaveCrest%d" % i
		crest.offset = Vector2(0.0, float(_wave_texture.get_height()) * 0.5)
		crest.visible = false
		add_child(crest)
		_wave_crests.append(crest)


## Adds the view for one fighter (from a combat_started fighter entry and its data resource).
func add_fighter(id: int, is_party: bool, slot: int, data: Resource) -> FighterView:
	var view := FighterView.new()
	view.name = "Fighter%d" % id
	view.position = _home_for(is_party, slot)
	add_child(view)
	if is_party:
		var c := data as CharacterData
		view.setup(id, true, c.sprite_path, c.sprite_hframes, Vector2i(32, 48), c.sprite_pixel_size,
				not _visuals.party_art_faces_right, _visuals)
	else:
		var e := data as EnemyData
		view.setup(id, false, e.sprite_path, e.sprite_hframes, Vector2i(64, 64), e.sprite_pixel_size,
				not _visuals.enemy_art_faces_left, _visuals)
	_fighters[id] = view
	return view


func fighter(id: int) -> FighterView:
	return _fighters.get(id) as FighterView


## Home spot (feet) of a fighter.
func home_of(id: int) -> Vector3:
	var v := fighter(id)
	return v.position if v != null else Vector3.ZERO


## Where an enemy lunge connects with these party targets (their centre, in front of them).
func contact_point(target_ids: Array[int]) -> Vector3:
	if target_ids.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for id: int in target_ids:
		sum += home_of(id)
	return sum / float(target_ids.size()) + Vector3(_visuals.contact_gap, 0.0, 0.0)


## Where a party member stands to strike this enemy.
func strike_point(enemy_id: int) -> Vector3:
	return home_of(enemy_id) - Vector3(_visuals.strike_gap, 0.0, 0.0)


## Screen position (HUD canvas pixels) of a world point.
func screen_position(world: Vector3) -> Vector2:
	if camera == null:
		return Vector2.ZERO
	return camera.unproject_position(world)


## Sets every fighter's down/greyed look from the mirror (outside enemy attacks).
func sync_alive(mirror: CombatMirror) -> void:
	for id: int in _fighters:
		var v := fighter(id)
		var alive := mirror.is_alive(id)
		v.set_grey(0.0 if alive else 1.0)
		if v.is_party:
			v.set_pose(FighterView.CharPose.IDLE if alive else FighterView.CharPose.DOWN)
		else:
			v.set_pose(EnemyChoreography.Pose.IDLE if alive else EnemyChoreography.Pose.HURT)


## A burst of sparks flying out from `at`.
func spawn_sparks(at: Vector3, count: int, alpha: float = 1.0) -> void:
	for i: int in count:
		var spark := _effect_sprite(_spark_texture, BaseMaterial3D.BILLBOARD_ENABLED)
		spark.position = at
		spark.modulate = Color(1.0, 1.0, 1.0, alpha)
		add_child(spark)
		var angle := _rng.randf_range(0.0, TAU)
		var dist := _visuals.spark_spread * _rng.randf_range(0.5, 1.0)
		var dir := Vector3(cos(angle), sin(angle) * 0.8 + 0.2, _rng.randf_range(-0.3, 0.3)).normalized()
		var seconds := float(_visuals.spark_ms) / 1000.0
		var tween := spark.create_tween().set_parallel(true)
		tween.tween_property(spark, "position", at + dir * dist, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(spark, "modulate:a", 0.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(spark, "scale", Vector3.ONE * SPARK_END_SCALE, seconds)
		tween.chain().tween_callback(spark.queue_free)


## A slash arc at `at`, mirrored for strikes going left, appearing after `delay_ms`. Returns its
## tween (set_speed_scale(0) on it freezes the slash for a hit-stop).
func spawn_slash(at: Vector3, facing_right: bool = true, alpha: float = 1.0, delay_ms: int = 0) -> Tween:
	var slash := _effect_sprite(_slash_texture, BaseMaterial3D.BILLBOARD_ENABLED)
	slash.position = at
	slash.flip_h = not facing_right
	slash.scale = Vector3.ONE * _visuals.slash_scale
	slash.modulate = Color(1.0, 1.0, 1.0, alpha)
	slash.visible = delay_ms <= 0
	add_child(slash)
	var seconds := float(_visuals.slash_ms) / 1000.0
	var tween := slash.create_tween()
	if delay_ms > 0:
		tween.tween_interval(float(delay_ms) / 1000.0)
		tween.tween_callback(slash.show)
	tween.tween_property(slash, "scale", Vector3.ONE * _visuals.slash_scale * SLASH_GROWTH, seconds)
	tween.parallel().tween_property(slash, "modulate:a", 0.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(slash.queue_free)
	return tween


## Places the ground-wave crests (one per point) at this opacity.
func set_wave(points: Array[Vector3], alpha: float) -> void:
	for i: int in _wave_crests.size():
		var crest := _wave_crests[i]
		if i < points.size():
			crest.visible = true
			crest.position = points[i]
			crest.modulate = Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))
		else:
			crest.visible = false


func hide_wave() -> void:
	for crest: Sprite3D in _wave_crests:
		crest.visible = false


## Draws every effect once, nearly invisible, so their materials are compiled before the first
## parry. Call at fight start; the effects remove themselves.
func warm_up() -> void:
	var spot := _visuals.camera_target + Vector3(0.0, 0.0, -2.0)
	spawn_sparks(spot, 1, WARM_UP_ALPHA)
	spawn_slash(spot, true, WARM_UP_ALPHA)
	var points: Array[Vector3] = [spot]
	set_wave(points, WARM_UP_ALPHA)
	for id: int in _fighters:
		fighter(id).flash(1, Color.WHITE, WARM_UP_ALPHA)


## Ends the warm-up started by warm_up().
func finish_warm_up() -> void:
	hide_wave()


func _home_for(is_party: bool, slot: int) -> Vector3:
	var list: Array[Vector3] = _visuals.party_positions if is_party else _visuals.enemy_positions
	if list.is_empty():
		return Vector3(-3.0 if is_party else 3.0, 0.0, 0.0)
	if slot < list.size():
		return list[slot]
	# More fighters than authored spots: continue the line of the last two.
	var last := list[list.size() - 1]
	var step := Vector3(0.0, 0.0, 1.3) if list.size() < 2 else last - list[list.size() - 2]
	return last + step * float(slot - list.size() + 1)


func _build_floor() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(_visuals.floor_size, _visuals.floor_size)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = AssetLoader.texture(_visuals.floor_tile_path, Vector2i(32, 32))
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.texture_repeat = true
	var tiles := _visuals.floor_size / maxf(0.01, _visuals.floor_tile_world_size)
	mat.uv1_scale = Vector3(tiles, tiles, 1.0)
	mat.roughness = 1.0
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	floor_mesh.mesh = mesh
	floor_mesh.material_override = mat
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_mesh)


func _build_backdrop() -> void:
	var tex := AssetLoader.texture(_visuals.backdrop_path, Vector2i(320, 120))
	var backdrop := Sprite3D.new()
	backdrop.name = "Backdrop"
	backdrop.texture = tex
	backdrop.pixel_size = _visuals.backdrop_pixel_size
	backdrop.centered = true
	backdrop.offset = Vector2(0.0, float(tex.get_height()) * 0.5)
	backdrop.position = _visuals.backdrop_position
	backdrop.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	backdrop.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(backdrop)


func _effect_sprite(texture: Texture2D, billboard: BaseMaterial3D.BillboardMode) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = texture
	s.pixel_size = _visuals.fx_pixel_size
	s.billboard = billboard
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.no_depth_test = true
	s.render_priority = 1
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return s
