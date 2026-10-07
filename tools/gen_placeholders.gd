extends SceneTree
## Generates the placeholder art and sounds (DESIGN.md 5.3): pixel sprites drawn with Image and
## sounds synthesized into 16-bit mono WAV files. Every path comes from the data files: characters,
## enemies, the sound library and data/presentation/combat_visuals.tres (FX, stage and UI art).
## Only missing files are written, so real art dropped into assets/ is never overwritten.
## Every file draws from its own fixed seed, so re-runs give identical files.
## Run headless, importing before (so data classes resolve) and after (so Godot imports the files):
##   godot --headless --path . --import
##   godot --headless --path . -s tools/gen_placeholders.gd
##   godot --headless --path . --import
## Add "-- --force" after the script to regenerate everything (overwrites real art too).

const CHARACTER_DIR := "res://data/characters"
const ENEMY_DIR := "res://data/enemies"
const SFX_LIBRARY_PATH := "res://data/audio/sfx_library.tres"
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"

## Base seed; each file mixes in a hash of its own path.
const SEED := 20261006

# --- Sprite contract (shared with presentation) ---------------------------------------------

const CHARACTER_FRAME := Vector2i(32, 48)
const ENEMY_FRAME := Vector2i(64, 64)
const PORTRAIT_SIZE := Vector2i(24, 24)
const CHARACTER_POSES := ["idle", "ready", "parry", "dodge", "jump", "hurt", "strike", "down"]
const ENEMY_POSES := ["idle", "windup", "lunge", "contact", "hurt", "slam"]

## Drawing style per data id. Unknown characters get the duelist look, unknown enemies the husk.
const CHARACTER_STYLES := {"alder": "knight", "brin": "duelist", "cass": "mage"}
const ENEMY_STYLES := {"rotten_husk": "husk"}

## Portrait framing per style: sprite point placed at the portrait centre, zoom, and optional
## arm overrides (the knight lowers his shield so it does not cut across the bust).
const PORTRAIT_VIEWS := {
	"knight": {"focus": Vector2(17, 18), "zoom": 1.6, "arms": {"hf": Vector2(5, 12)}},
	"duelist": {"focus": Vector2(17.5, 19), "zoom": 1.7},
	"mage": {"focus": Vector2(16.5, 16), "zoom": 1.45},
	"husk": {"focus": Vector2(45, 31), "zoom": 1.45},
}

# --- Palette shared by every sprite -----------------------------------------------------------

const OUTLINE := Color("140f18")
const OUTLINE_HUSK := Color("10170b")
const LIGHTEN := 0.3
const DARKEN := 0.32
const SOFT_DARKEN := 0.14
## Far-side limbs are darkened by this much so they read as behind the body.
const BACK_SHADE := 0.3

# --- Character skeletons ----------------------------------------------------------------------
# Sprite pixels in a 32x48 frame, facing right, feet on row 47 (boot bottoms), centred on x 16.
# look = face direction in degrees (0 = right, -90 = up). tail = headband tail vector (duelist).
# toe = foot direction in degrees (0 = right).

const BODY_POSES := {
	"idle": {"hip": Vector2(16, 34), "neck": Vector2(16, 23), "head": Vector2(17, 17.5),
		"look": 0.0, "knee_b": Vector2(14, 40), "foot_b": Vector2(13, 46),
		"knee_f": Vector2(18, 40), "foot_f": Vector2(19, 46), "tail": Vector2(-5, 3), "toe": 0.0},
	"ready": {"hip": Vector2(15, 35), "neck": Vector2(17.5, 24.5), "head": Vector2(19.5, 19),
		"look": 5.0, "knee_b": Vector2(11, 41), "foot_b": Vector2(9, 46),
		"knee_f": Vector2(20, 40), "foot_f": Vector2(21, 46), "tail": Vector2(-6, 1), "toe": 0.0},
	"parry": {"hip": Vector2(14, 35), "neck": Vector2(15.5, 24), "head": Vector2(16.5, 18.5),
		"look": 0.0, "knee_b": Vector2(10, 41), "foot_b": Vector2(7, 46),
		"knee_f": Vector2(19, 40), "foot_f": Vector2(21, 46), "tail": Vector2(-6, -1), "toe": 0.0},
	"dodge": {"hip": Vector2(17, 38), "neck": Vector2(10.5, 29.5), "head": Vector2(7.5, 24),
		"look": -20.0, "knee_b": Vector2(11, 43), "foot_b": Vector2(6, 46),
		"knee_f": Vector2(23, 41), "foot_f": Vector2(27, 46), "tail": Vector2(6, -2), "toe": 0.0},
	"jump": {"hip": Vector2(16, 26), "neck": Vector2(16.5, 15.5), "head": Vector2(17.5, 10),
		"look": 10.0, "knee_b": Vector2(20, 30), "foot_b": Vector2(14, 34),
		"knee_f": Vector2(22, 27.5), "foot_f": Vector2(17, 32.5), "tail": Vector2(-4, 5), "toe": 10.0},
	"hurt": {"hip": Vector2(15, 35), "neck": Vector2(12, 24.5), "head": Vector2(9.5, 19.5),
		"look": -40.0, "knee_b": Vector2(13, 41), "foot_b": Vector2(10, 46),
		"knee_f": Vector2(18, 41), "foot_f": Vector2(21, 45), "tail": Vector2(5, -3), "toe": -15.0},
	"strike": {"hip": Vector2(9, 35), "neck": Vector2(13, 25), "head": Vector2(16, 19.5),
		"look": 0.0, "knee_b": Vector2(5, 41), "foot_b": Vector2(2, 46),
		"knee_f": Vector2(15, 40), "foot_f": Vector2(17, 46), "tail": Vector2(-7, 0), "toe": 0.0},
	"down": {"hip": Vector2(21, 43), "neck": Vector2(10, 42.5), "head": Vector2(5.5, 41.5),
		"look": -90.0, "knee_b": Vector2(26, 40), "foot_b": Vector2(30, 45),
		"knee_f": Vector2(26, 41), "foot_f": Vector2(29, 46), "tail": Vector2(-3, 4), "toe": -90.0},
}

## Hands relative to the shoulder; weapon angles in degrees (0 = right, -90 = up).
## Knight: wb = sword angle, wf = shield tilt, sw = shield width (1 = seen face on).
const KNIGHT_ARMS := {
	"idle": {"hf": Vector2(5, 7), "hb": Vector2(-3, 7), "wb": 115.0, "wf": 0.0, "sw": 0.75},
	"ready": {"hf": Vector2(6, 3), "hb": Vector2(-4, -6), "wb": -140.0, "wf": -5.0, "sw": 0.8},
	"parry": {"hf": Vector2(10, -1), "hb": Vector2(-4, 6), "wb": 150.0, "wf": 6.0, "sw": 1.0},
	"dodge": {"hf": Vector2(5, 3), "hb": Vector2(-4, -2), "wb": -110.0, "wf": -20.0, "sw": 0.7},
	"jump": {"hf": Vector2(4, 6), "hb": Vector2(-3, -4), "wb": -120.0, "wf": 10.0, "sw": 0.75},
	"hurt": {"hf": Vector2(6, -5), "hb": Vector2(-6, 1), "wb": 160.0, "wf": -35.0, "sw": 0.7},
	"strike": {"hf": Vector2(-3, 4), "hb": Vector2(8, 0), "wb": 0.0, "wf": 0.0, "sw": 0.6},
	"down": {"hf": Vector2(7, -3), "hb": Vector2(6, 3), "wb": 3.0, "wf": 90.0, "sw": 0.45},
}
## Duelist: wf / wb = front / back blade angles.
const DUELIST_ARMS := {
	"idle": {"hf": Vector2(4, 7), "hb": Vector2(-2, 7), "wf": 35.0, "wb": 145.0},
	"ready": {"hf": Vector2(6, 1), "hb": Vector2(-4, -3), "wf": -30.0, "wb": -135.0},
	"parry": {"hf": Vector2(6, 3), "hb": Vector2(10, 3), "wf": -55.0, "wb": -125.0},
	"dodge": {"hf": Vector2(6, -2), "hb": Vector2(-5, 1), "wf": -15.0, "wb": 120.0},
	"jump": {"hf": Vector2(5, 4), "hb": Vector2(-5, 0), "wf": 25.0, "wb": -150.0},
	"hurt": {"hf": Vector2(6, -4), "hb": Vector2(-5, -3), "wf": -70.0, "wb": -130.0},
	"strike": {"hf": Vector2(9, 0), "hb": Vector2(-5, 3), "wf": 0.0, "wb": 135.0},
	"down": {"hf": Vector2(7, 1), "hb": Vector2(3, 3), "wf": 15.0, "wb": 5.0},
}
## Mage: wf = staff angle (orb end), grip = where the front hand holds it (0 = bottom, 1 = top),
## grip_b = back hand on the staff (negative = the back hand is free, at hb).
const MAGE_ARMS := {
	"idle": {"hf": Vector2(6, 6), "hb": Vector2(-2, 7), "wf": -90.0, "grip": 0.55, "grip_b": -1.0},
	"ready": {"hf": Vector2(6, 2), "hb": Vector2(0, 0), "wf": -55.0, "grip": 0.55, "grip_b": 0.3},
	"parry": {"hf": Vector2(9, 0), "hb": Vector2(0, 0), "wf": -80.0, "grip": 0.5, "grip_b": 0.22,
		"ward": 1.0},
	"dodge": {"hf": Vector2(5, 2), "hb": Vector2(-5, 0), "wf": -55.0, "grip": 0.5, "grip_b": -1.0},
	"jump": {"hf": Vector2(5, 3), "hb": Vector2(-5, -1), "wf": -60.0, "grip": 0.5, "grip_b": -1.0},
	"hurt": {"hf": Vector2(5, -3), "hb": Vector2(-6, -2), "wf": -120.0, "grip": 0.5, "grip_b": -1.0},
	"strike": {"hf": Vector2(8, 0), "hb": Vector2(0, 0), "wf": 0.0, "grip": 0.67, "grip_b": 0.4},
	"down": {"hf": Vector2(1, 3), "hb": Vector2(4, 3), "wf": 0.0, "grip": 0.5, "grip_b": -1.0},
}
const ARMS_BY_STYLE := {"knight": KNIGHT_ARMS, "duelist": DUELIST_ARMS, "mage": MAGE_ARMS}
const STAFF_LENGTH := 28.0

# --- Enemy skeleton ---------------------------------------------------------------------------
# Drawn facing right in a 64x64 frame and mirrored, so the husk faces left. Feet on row 63.
# hump = control point of the curved back. tilt = head angle. claw_* = claw direction.
# eyes = glow strength (2 = wind-up glare). jaw = how far the mouth hangs open.

const HUSK_POSES := {
	"idle": {"hip": Vector2(30, 45), "hump": Vector2(25, 23), "chest": Vector2(37, 29),
		"head": Vector2(44, 32), "tilt": 12.0, "knee_b": Vector2(24, 53), "foot_b": Vector2(25, 62),
		"knee_f": Vector2(38, 53), "foot_f": Vector2(37, 62), "hand_f": Vector2(45, 49),
		"hand_b": Vector2(37, 49), "claw_f": 80.0, "claw_b": 88.0, "eyes": 1.0, "jaw": 0.6},
	"windup": {"hip": Vector2(27, 45), "hump": Vector2(19, 24), "chest": Vector2(30, 27),
		"head": Vector2(36, 25), "tilt": -18.0, "knee_b": Vector2(19, 53), "foot_b": Vector2(18, 62),
		"knee_f": Vector2(37, 54), "foot_f": Vector2(40, 62), "hand_f": Vector2(25, 12),
		"hand_b": Vector2(41, 42), "claw_f": -118.0, "claw_b": 60.0, "eyes": 2.0, "jaw": 2.0},
	"lunge": {"hip": Vector2(31, 47), "hump": Vector2(30, 29), "chest": Vector2(41, 33),
		"head": Vector2(48, 35), "tilt": 8.0, "knee_b": Vector2(21, 55), "foot_b": Vector2(13, 62),
		"knee_f": Vector2(44, 54), "foot_f": Vector2(46, 62), "hand_f": Vector2(56, 21),
		"hand_b": Vector2(28, 44), "claw_f": -32.0, "claw_b": 140.0, "eyes": 1.6, "jaw": 1.6},
	"contact": {"hip": Vector2(27, 47), "hump": Vector2(26, 31), "chest": Vector2(36, 35),
		"head": Vector2(42, 41), "tilt": 18.0, "knee_b": Vector2(18, 55), "foot_b": Vector2(11, 62),
		"knee_f": Vector2(40, 54), "foot_f": Vector2(42, 62), "hand_f": Vector2(54, 33),
		"hand_b": Vector2(25, 46), "claw_f": -4.0, "claw_b": 150.0, "eyes": 1.6, "jaw": 1.0},
	"hurt": {"hip": Vector2(27, 45), "hump": Vector2(18, 28), "chest": Vector2(27, 27),
		"head": Vector2(29, 19), "tilt": -45.0, "knee_b": Vector2(21, 53), "foot_b": Vector2(22, 62),
		"knee_f": Vector2(35, 54), "foot_f": Vector2(37, 62), "hand_f": Vector2(42, 21),
		"hand_b": Vector2(13, 35), "claw_f": -40.0, "claw_b": 200.0, "eyes": 0.4, "jaw": 2.0},
	"slam": {"hip": Vector2(24, 44), "hump": Vector2(23, 27), "chest": Vector2(35, 34),
		"head": Vector2(42, 36), "tilt": 30.0, "knee_b": Vector2(17, 53), "foot_b": Vector2(16, 62),
		"knee_f": Vector2(36, 53), "foot_f": Vector2(35, 62), "hand_f": Vector2(56, 60),
		"hand_b": Vector2(47, 61), "claw_f": 20.0, "claw_b": 25.0, "eyes": 1.6, "jaw": 1.6,
		"arms_front": true},
}
## Rot patches on the husk's body: [position along the back curve, offset to the belly side,
## radius, use bruise colour]. Fixed so they move with the body between frames.
const HUSK_ROT_SPOTS := [
	[0.22, 1.5, 1.2, false], [0.4, -2.5, 1.3, true], [0.62, -1.0, 1.0, false],
	[0.12, -1.5, 1.0, false],
]
## Bone nubs along the spine (positions on the back curve).
const HUSK_VERTEBRAE := [0.32, 0.46, 0.6, 0.74]
## Ribs on the belly side of the chest (positions on the back curve).
const HUSK_RIBS := [0.6, 0.7, 0.8, 0.9]
## Upper arm and forearm length; the claws are long enough to read at a glance.
const HUSK_ARM := 10.0
const HUSK_CLAW := 10.5

# --- Audio ------------------------------------------------------------------------------------

const MIX_RATE := 44100
const PEAK_DB := -3.0
## Phase that starts a partial at full level (a hard onset on sample 0).
const HARD := PI * 0.5

enum NoiseFilter { LOW, BAND, HIGH }

var _force := false
var _written := 0
var _kept := 0
var _failed := 0
var _rng := RandomNumberGenerator.new()

# Drawing state: shapes are drawn into _layer, which _finish_layer() shades, outlines and
# composites onto _canvas. Shape coordinates are in sprite space and mapped to pixels by
# pixel = sprite * _zoom + _offset, then mirrored horizontally when _mirror is set.
var _canvas: Image
var _layer: Image
var _zoom := 1.0
var _offset := Vector2.ZERO
var _mirror := false
## When true, shapes only paint over pixels already drawn in the current layer.
var _inside_only := false


func _init() -> void:
	_force = OS.get_cmdline_user_args().has("--force")
	_make_characters()
	_make_enemies()
	_make_fx()
	_make_env()
	_make_ui()
	_make_sounds()
	print("gen_placeholders: wrote %d, kept %d existing, %d failed" % [_written, _kept, _failed])
	quit(1 if _failed > 0 else 0)


# =============================================================================================
# Files
# =============================================================================================

## True if `path` should be written now (missing, or --force). Also seeds the RNG for it.
func _wants(path: String) -> bool:
	if path.is_empty():
		return false
	if not _force and FileAccess.file_exists(path):
		_kept += 1
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_rng.seed = SEED ^ path.hash()
	return true


func _report(err: Error, path: String) -> void:
	if err == OK:
		_written += 1
		print("  wrote ", path)
	else:
		_failed += 1
		push_error("gen_placeholders: could not write %s (error %d)" % [path, err])


func _save_png(img: Image, path: String) -> void:
	_report(img.save_png(path), path)


## Every resource in a data folder, sorted by file name.
func _load_folder(dir_path: String) -> Array[Resource]:
	var found: Array[Resource] = []
	var files := DirAccess.get_files_at(dir_path)
	files.sort()
	for file: String in files:
		var file_name := file.trim_suffix(".remap")
		if file_name.ends_with(".tres") or file_name.ends_with(".res"):
			var res := load(dir_path.path_join(file_name))
			if res != null:
				found.append(res)
	return found


func _make_characters() -> void:
	var list := _load_folder(CHARACTER_DIR)
	if list.is_empty():
		push_warning("gen_placeholders: no character data in %s" % CHARACTER_DIR)
	for res: Resource in list:
		var data := res as CharacterData
		if data == null:
			continue
		var style: String = CHARACTER_STYLES.get(data.id, "duelist")
		if _wants(data.sprite_path):
			_save_png(_character_sheet(style, data.color, data.sprite_hframes), data.sprite_path)
		if _wants(data.portrait_path):
			_save_png(_portrait(style, data.color, false), data.portrait_path)


func _make_enemies() -> void:
	for res: Resource in _load_folder(ENEMY_DIR):
		var data := res as EnemyData
		if data == null:
			continue
		var style: String = ENEMY_STYLES.get(data.id, "husk")
		if _wants(data.sprite_path):
			_save_png(_enemy_sheet(style, data.color, data.sprite_hframes), data.sprite_path)
		if _wants(data.portrait_path):
			_save_png(_portrait(style, data.color, true), data.portrait_path)


## The presentation data that names the FX, stage and UI art (its defaults if the file is missing).
func _visuals() -> CombatVisuals:
	var visuals: CombatVisuals = null
	if ResourceLoader.exists(VISUALS_PATH):
		visuals = load(VISUALS_PATH) as CombatVisuals
	if visuals == null:
		push_warning("gen_placeholders: no %s, using the CombatVisuals defaults" % VISUALS_PATH)
		visuals = CombatVisuals.new()
	return visuals


func _make_fx() -> void:
	var v := _visuals()
	if _wants(v.spark_path):
		_save_png(_spark(), v.spark_path)
	if _wants(v.shockwave_path):
		_save_png(_shockwave(), v.shockwave_path)
	if _wants(v.shadow_path):
		_save_png(_shadow(), v.shadow_path)
	if _wants(v.slash_path):
		_save_png(_slash(), v.slash_path)


func _make_env() -> void:
	var v := _visuals()
	if _wants(v.floor_tile_path):
		_save_png(_floor_tile(), v.floor_tile_path)
	if _wants(v.backdrop_path):
		_save_png(_backdrop(), v.backdrop_path)


func _make_ui() -> void:
	var v := _visuals()
	if _wants(v.lock_icon_path):
		_save_png(_lock_icon(), v.lock_icon_path)
	if _wants(v.ap_pip_path):
		_save_png(_ap_pip(true), v.ap_pip_path)
	if _wants(v.ap_pip_empty_path):
		_save_png(_ap_pip(false), v.ap_pip_empty_path)


func _make_sounds() -> void:
	var library := load(SFX_LIBRARY_PATH) as SfxLibrary
	if library == null:
		push_warning("gen_placeholders: no sound library at %s" % SFX_LIBRARY_PATH)
		return
	for cue: SfxCue in library.cues:
		if cue == null or not cue.path.ends_with(".wav") or not _wants(cue.path):
			continue
		var samples := _synth(cue.name)
		_report(_save_wav(samples, cue.path), cue.path)
		print("    %s" % _sound_stats(samples))


# =============================================================================================
# Drawing primitives
# =============================================================================================

func _begin_canvas(size: Vector2i, zoom: float = 1.0, offset: Vector2 = Vector2.ZERO,
		mirror: bool = false) -> void:
	_canvas = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	_canvas.fill(Color(0, 0, 0, 0))
	_layer = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	_layer.fill(Color(0, 0, 0, 0))
	_zoom = zoom
	_offset = offset
	_mirror = mirror
	_inside_only = false


## Sprite space to pixel space.
func _tp(p: Vector2) -> Vector2:
	var q := p * _zoom + _offset
	if _mirror:
		q.x = float(_canvas.get_width() - 1) - q.x
	return q


## Pixel space to sprite space.
func _inv(q: Vector2) -> Vector2:
	var x := q.x
	if _mirror:
		x = float(_canvas.get_width() - 1) - x
	return (Vector2(x, q.y) - _offset) / _zoom


## Pixel rectangle (clamped to the canvas) covering a sprite-space box.
func _pixel_rect(lo: Vector2, hi: Vector2) -> Rect2i:
	var a := _tp(lo)
	var b := _tp(hi)
	var x0 := clampi(floori(minf(a.x, b.x)) - 1, 0, _canvas.get_width())
	var y0 := clampi(floori(minf(a.y, b.y)) - 1, 0, _canvas.get_height())
	var x1 := clampi(ceili(maxf(a.x, b.x)) + 2, 0, _canvas.get_width())
	var y1 := clampi(ceili(maxf(a.y, b.y)) + 2, 0, _canvas.get_height())
	return Rect2i(x0, y0, x1 - x0, y1 - y0)


func _plot(x: int, y: int, col: Color) -> void:
	if x < 0 or y < 0 or x >= _layer.get_width() or y >= _layer.get_height():
		return
	if _inside_only and _layer.get_pixel(x, y).a < 0.5:
		return
	_layer.set_pixel(x, y, col)


## One sprite pixel (a block of pixels when zoomed).
func _block(x: int, y: int, col: Color) -> void:
	var size := maxi(1, roundi(_zoom))
	@warning_ignore("integer_division")
	var start := (size - 1) / 2
	for dy: int in size:
		for dx: int in size:
			_plot(x - start + dx, y - start + dy, col)


func _px(p: Vector2, col: Color) -> void:
	var q := _tp(p)
	_block(roundi(q.x), roundi(q.y), col)


## Tolerance so integer radii give round shapes.
func _eps() -> float:
	return 0.05 / _zoom


func _disc(c: Vector2, r: float, col: Color) -> void:
	var rect := _pixel_rect(c - Vector2(r, r), c + Vector2(r, r))
	var rr := r + _eps()
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if _inv(Vector2(x, y)).distance_to(c) <= rr:
				_plot(x, y, col)


## Ellipse with radii rx, ry rotated by angle_deg.
func _oval(c: Vector2, rx: float, ry: float, angle_deg: float, col: Color) -> void:
	var big := maxf(rx, ry)
	var rect := _pixel_rect(c - Vector2(big, big), c + Vector2(big, big))
	var a := deg_to_rad(angle_deg)
	var ex := rx + _eps()
	var ey := ry + _eps()
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var l := (_inv(Vector2(x, y)) - c).rotated(-a)
			if (l.x * l.x) / (ex * ex) + (l.y * l.y) / (ey * ey) <= 1.0:
				_plot(x, y, col)


## Thick segment with round ends (limbs, blades, staffs).
func _capsule(a: Vector2, b: Vector2, r: float, col: Color) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(r, r)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(r, r)
	var rect := _pixel_rect(lo, hi)
	var rr := r + _eps()
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var q := _inv(Vector2(x, y))
			if q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)) <= rr:
				_plot(x, y, col)


## Upper and lower limb segments.
func _limb(a: Vector2, b: Vector2, c: Vector2, r1: float, r2: float, col: Color) -> void:
	_capsule(a, b, r1, col)
	_capsule(b, c, r2, col)


func _poly(points: PackedVector2Array, col: Color) -> void:
	if points.size() < 3:
		return
	var lo := points[0]
	var hi := points[0]
	for p: Vector2 in points:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var rect := _pixel_rect(lo, hi)
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if Geometry2D.is_point_in_polygon(_inv(Vector2(x, y)), points):
				_plot(x, y, col)


## One-pixel line (one sprite pixel wide when zoomed).
func _line(a: Vector2, b: Vector2, col: Color) -> void:
	var ta := _tp(a)
	var tb := _tp(b)
	var steps := maxi(1, ceili(maxf(absf(tb.x - ta.x), absf(tb.y - ta.y))))
	for i: int in steps + 1:
		var q := ta.lerp(tb, float(i) / steps)
		_block(roundi(q.x), roundi(q.y), col)


## Points relative to `origin`, rotated by `angle_deg`.
func _rel(origin: Vector2, angle_deg: float, points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v: Vector2 in points:
		out.append(origin + v.rotated(deg_to_rad(angle_deg)))
	return out


func _rp(origin: Vector2, angle_deg: float, v: Vector2) -> Vector2:
	return origin + v.rotated(deg_to_rad(angle_deg))


func _dir(angle_deg: float) -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(angle_deg))


## Shades the current layer (light from the upper left), outlines it, composites it onto the
## canvas and clears it. soft adds a second, gentler shadow band for big shapes.
func _finish_layer(outline: Color = OUTLINE, shade: bool = true, soft: bool = false) -> void:
	var w := _layer.get_width()
	var h := _layer.get_height()
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y: int in h:
		for x: int in w:
			solid[y * w + x] = 1 if _layer.get_pixel(x, y).a > 0.5 else 0
	if shade:
		for y: int in h:
			for x: int in w:
				if solid[y * w + x] == 0:
					continue
				var lit := not _solid_at(solid, w, h, x - 1, y - 1)
				var dark := not _solid_at(solid, w, h, x + 1, y + 1)
				var c := _layer.get_pixel(x, y)
				if lit and not dark:
					_layer.set_pixel(x, y, c.lightened(LIGHTEN))
				elif dark and not lit:
					_layer.set_pixel(x, y, c.darkened(DARKEN))
				elif soft and not lit and not _solid_at(solid, w, h, x + 2, y + 2):
					_layer.set_pixel(x, y, c.darkened(SOFT_DARKEN))
	if outline.a > 0.0:
		for y: int in h:
			for x: int in w:
				if solid[y * w + x] == 1:
					continue
				if (_solid_at(solid, w, h, x - 1, y) or _solid_at(solid, w, h, x + 1, y)
						or _solid_at(solid, w, h, x, y - 1) or _solid_at(solid, w, h, x, y + 1)):
					_layer.set_pixel(x, y, outline)
	_canvas.blend_rect(_layer, Rect2i(0, 0, w, h), Vector2i.ZERO)
	_layer.fill(Color(0, 0, 0, 0))


func _solid_at(solid: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h and solid[y * w + x] == 1


## Composites the current layer as flat detail (no shading, no outline).
func _finish_detail() -> void:
	_finish_layer(Color(0, 0, 0, 0), false)


## Translucent halo blended straight onto the canvas (glowing eyes, the staff orb, dust).
func _glow(c: Vector2, r_in: float, r_out: float, col: Color, max_alpha: float) -> void:
	var rect := _pixel_rect(c - Vector2(r_out, r_out), c + Vector2(r_out, r_out))
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var d := _inv(Vector2(x, y)).distance_to(c)
			if d > r_out:
				continue
			var k := 1.0 if d <= r_in else 1.0 - (d - r_in) / maxf(r_out - r_in, 0.001)
			k = ceilf(k * 3.0) / 3.0
			var dst := _canvas.get_pixel(x, y)
			_canvas.set_pixel(x, y, dst.blend(Color(col, max_alpha * k)))


## Two-bone IK: the elbow (or knee) between `s` and `h`, bending toward the ground.
func _elbow(s: Vector2, h: Vector2, upper: float, fore: float) -> Vector2:
	var d := s.distance_to(h)
	if d < 0.001:
		return s + Vector2.DOWN * upper
	var along := (h - s) / d
	if d >= upper + fore - 0.01:
		return s + along * upper
	var x := (upper * upper - fore * fore + d * d) / (2.0 * d)
	var y := sqrt(maxf(0.0, upper * upper - x * x))
	var n := Vector2(-along.y, along.x)
	var e1 := s + along * x + n * y
	var e2 := s + along * x - n * y
	return e1 if e1.y >= e2.y else e2


func _bezier(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	return a.lerp(c, t).lerp(c.lerp(b, t), t)


# =============================================================================================
# Characters
# =============================================================================================

func _character_sheet(style: String, base: Color, frames: int) -> Image:
	var count := maxi(1, frames)
	var sheet := Image.create_empty(CHARACTER_FRAME.x * count, CHARACTER_FRAME.y, false,
			Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for i: int in count:
		var pose_name: String = CHARACTER_POSES[mini(i, CHARACTER_POSES.size() - 1)]
		var frame := _draw_character(style, base, pose_name, CHARACTER_FRAME, 1.0, Vector2.ZERO)
		sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, CHARACTER_FRAME),
				Vector2i(i * CHARACTER_FRAME.x, 0))
	return sheet


func _portrait(style: String, base: Color, enemy: bool) -> Image:
	var view: Dictionary = PORTRAIT_VIEWS.get(style, PORTRAIT_VIEWS["duelist"])
	var zoom: float = view["zoom"]
	var focus: Vector2 = view["focus"]
	var centre := Vector2(PORTRAIT_SIZE) * 0.5 - Vector2(0.5, 0.5)
	if enemy:
		# Mirroring happens after zoom/offset, so place the focus before the flip.
		var mirrored_centre := Vector2(float(PORTRAIT_SIZE.x - 1) - centre.x, centre.y)
		return _draw_enemy(style, base, "idle", PORTRAIT_SIZE, zoom, mirrored_centre - focus * zoom)
	return _draw_character(style, base, "idle", PORTRAIT_SIZE, zoom, centre - focus * zoom,
			view.get("arms", {}))


func _draw_character(style: String, base: Color, pose_name: String, size: Vector2i, zoom: float,
		offset: Vector2, arm_override: Dictionary = {}) -> Image:
	_begin_canvas(size, zoom, offset, false)
	var p := _character_pose(style, pose_name, arm_override)
	match style:
		"knight":
			_draw_knight(p, base)
		"mage":
			_draw_mage(p, base)
		_:
			_draw_duelist(p, base)
	return _canvas


## Merges the body pose with the style's arm pose and derives shoulders, hands and directions.
func _character_pose(style: String, pose_name: String,
		arm_override: Dictionary = {}) -> Dictionary:
	var p: Dictionary = (BODY_POSES[pose_name] as Dictionary).duplicate()
	var arms_by_pose: Dictionary = ARMS_BY_STYLE.get(style, DUELIST_ARMS)
	var arms: Dictionary = (arms_by_pose[pose_name] as Dictionary).duplicate()
	arms.merge(arm_override, true)
	p.merge(arms, true)
	var hip: Vector2 = p["hip"]
	var neck: Vector2 = p["neck"]
	var spine := (neck - hip).normalized()
	var fwd := Vector2(-spine.y, spine.x)
	var shoulder := neck.lerp(hip, 0.18)
	p["spine"] = spine
	p["fwd"] = fwd
	p["sh_f"] = shoulder - fwd * 0.5
	p["sh_b"] = shoulder + fwd * 0.5
	p["hand_f"] = shoulder + (arms["hf"] as Vector2)
	p["hand_b"] = shoulder + (arms["hb"] as Vector2)
	return p


## Leg from hip to knee to foot, with a boot pointing along `toe`.
func _leg(hip: Vector2, knee: Vector2, foot: Vector2, toe: Vector2, r_thigh: float,
		r_shin: float, col: Color, boot: Color, boot_r: float) -> void:
	_capsule(hip, knee, r_thigh, col)
	_capsule(knee, foot, r_shin, col)
	_capsule(foot - toe * 0.5, foot + toe * 2.0, boot_r, boot)


## Alder: heavy armour, big shield on the near arm, sword in the far hand.
func _draw_knight(p: Dictionary, base: Color) -> void:
	var armour := base
	var armour_b := base.darkened(BACK_SHADE)
	var steel := Color("d5dce8")
	var dark := Color("262b3e")
	var gold := Color("e5b84a")
	var helm := base.lightened(0.35)
	var hip: Vector2 = p["hip"]
	var neck: Vector2 = p["neck"]
	var head: Vector2 = p["head"]
	var fwd: Vector2 = p["fwd"]
	var spine: Vector2 = p["spine"]
	var look: float = p["look"]
	var toe := _dir(p["toe"])
	var sh_f: Vector2 = p["sh_f"]
	var sh_b: Vector2 = p["sh_b"]
	var hand_f: Vector2 = p["hand_f"]
	var hand_b: Vector2 = p["hand_b"]

	# Sword arm (far side): blade first so the gauntlet covers the grip.
	_sword(hand_b, p["wb"], 10.0, steel.darkened(0.12), gold.darkened(0.25))
	_limb(sh_b, _elbow(sh_b, hand_b, 5.0, 5.0), hand_b, 2.0, 1.8, armour_b)
	_disc(hand_b, 1.5, dark)
	_finish_layer()
	_leg(hip - fwd * 1.6, p["knee_b"], p["foot_b"], toe, 2.2, 2.0, armour_b, dark.darkened(0.2), 1.7)
	_finish_layer()
	_leg(hip + fwd * 1.6, p["knee_f"], p["foot_f"], toe, 2.2, 2.0, armour, dark, 1.7)
	_finish_layer()

	# Breastplate, armoured skirt and belt.
	var skirt := hip - spine * 3.5
	_poly(PackedVector2Array([hip - fwd * 4.3, hip + fwd * 4.3, skirt + fwd * 5.2,
			skirt - fwd * 5.0]), armour.darkened(0.15))
	_poly(PackedVector2Array([neck + fwd * 5.2, neck - fwd * 4.6, hip - fwd * 4.0,
			hip + fwd * 4.2]), armour)
	_capsule(hip - fwd * 4.0 + spine * 0.4, hip + fwd * 4.2 + spine * 0.4, 0.6, dark)
	_px(hip + fwd * 2.5 + spine * 0.4, gold)
	_inside_only = true
	_line(neck.lerp(hip, 0.25) + fwd * 1.0, neck.lerp(hip, 0.75) + fwd * 2.5, armour.lightened(0.18))
	_inside_only = false
	_finish_layer(OUTLINE, true, true)

	# Great helm with a crest, visor slit and a glint for the eye.
	_poly(_rel(head, look, [Vector2(-4.6, -2.0), Vector2(-3.0, -7.2), Vector2(1.8, -6.8),
			Vector2(0.8, -4.2)]), gold)
	_oval(head, 4.6, 5.0, look, helm)
	_inside_only = true
	_line(_rp(head, look, Vector2(0.4, 0.5)), _rp(head, look, Vector2(5.0, 0.5)), dark)
	_line(_rp(head, look, Vector2(2.6, 2.6)), _rp(head, look, Vector2(4.6, 2.6)), helm.darkened(0.35))
	_inside_only = false
	_finish_layer()
	_px(_rp(head, look, Vector2(3.2, 0.5)), Color("c4f4ff"))
	_finish_detail()

	# Shield arm (near side) with a pauldron.
	_disc(sh_f, 3.0, armour.lightened(0.12))
	_limb(sh_f, _elbow(sh_f, hand_f, 5.0, 5.0), hand_f, 2.0, 1.8, armour)
	_disc(hand_f, 1.5, dark)
	_finish_layer()
	var tilt: float = p["wf"]
	_heater(hand_f + _dir(tilt) * 1.0, tilt, p["sw"], steel, armour.darkened(0.28), gold)
	_finish_layer(OUTLINE, true, true)


func _sword(hand: Vector2, angle: float, length: float, blade: Color, hilt: Color) -> void:
	var d := _dir(angle)
	var n := Vector2(-d.y, d.x)
	_capsule(hand - d * 2.2, hand, 0.6, hilt)
	_capsule(hand + d * 1.6 - n * 2.6, hand + d * 1.6 + n * 2.6, 0.6, hilt)
	_capsule(hand + d * 2.2, hand + d * (length - 1.0), 1.0, blade)
	_poly(PackedVector2Array([hand + d * (length - 1.5) + n * 1.0, hand + d * (length + 0.8),
			hand + d * (length - 1.5) - n * 1.0]), blade)


## Heater shield: steel rim, coloured field, cross emblem. sx squashes it when seen at an angle.
func _heater(c: Vector2, tilt: float, sx: float, rim: Color, field: Color, emblem: Color) -> void:
	var shape := [Vector2(-5, -7), Vector2(5, -7), Vector2(5, -1), Vector2(3.6, 3.6),
			Vector2(0, 7.6), Vector2(-3.6, 3.6), Vector2(-5, -1)]
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for v: Vector2 in shape:
		outer.append(c + (v * Vector2(sx, 1.0)).rotated(deg_to_rad(tilt)))
		inner.append(c + (v * Vector2(sx, 1.0) * 0.74 + Vector2(0, -0.3)).rotated(deg_to_rad(tilt)))
	_poly(outer, rim)
	_poly(inner, field)
	_line(c + (Vector2(0, -4.5) * Vector2(sx, 1.0)).rotated(deg_to_rad(tilt)),
			c + (Vector2(0, 4.2) * Vector2(sx, 1.0)).rotated(deg_to_rad(tilt)), emblem)
	_line(c + (Vector2(-2.8, -1.6) * Vector2(sx, 1.0)).rotated(deg_to_rad(tilt)),
			c + (Vector2(2.8, -1.6) * Vector2(sx, 1.0)).rotated(deg_to_rad(tilt)), emblem)


## Brin: lean fighter with a blade in each hand and a headband whose tails trail behind.
func _draw_duelist(p: Dictionary, base: Color) -> void:
	var tunic := base
	var tunic_b := base.darkened(BACK_SHADE)
	var skin := Color("eab38a")
	var leather := Color("4a2c25")
	var hair := Color("2a1b1d")
	var pants := Color("3c3448")
	var boots := Color("6b4331")
	var steel := Color("e6edf4")
	var hilt := Color("caa04a")
	var hip: Vector2 = p["hip"]
	var neck: Vector2 = p["neck"]
	var head: Vector2 = p["head"]
	var fwd: Vector2 = p["fwd"]
	var spine: Vector2 = p["spine"]
	var look: float = p["look"]
	var toe := _dir(p["toe"])
	var sh_f: Vector2 = p["sh_f"]
	var sh_b: Vector2 = p["sh_b"]
	var hand_f: Vector2 = p["hand_f"]
	var hand_b: Vector2 = p["hand_b"]

	_blade(hand_b, p["wb"], 9.0, steel.darkened(0.15), hilt.darkened(0.25))
	var elbow_b := _elbow(sh_b, hand_b, 5.0, 5.0)
	_capsule(sh_b, elbow_b, 1.3, tunic_b)
	_capsule(elbow_b, hand_b, 1.2, leather.darkened(0.2))
	_disc(hand_b, 1.1, skin.darkened(BACK_SHADE))
	_finish_layer()
	_leg(hip - fwd * 1.0, p["knee_b"], p["foot_b"], toe, 1.5, 1.3, pants.darkened(0.25),
			boots.darkened(0.25), 1.4)
	_finish_layer()
	_leg(hip + fwd * 1.0, p["knee_f"], p["foot_f"], toe, 1.5, 1.3, pants, boots, 1.4)
	_finish_layer()

	# Tunic with flared skirt, belt and a strap across the chest.
	var skirt := hip - spine * 3.2
	_poly(PackedVector2Array([hip - fwd * 2.8, hip + fwd * 3.0, skirt + fwd * 3.8,
			skirt - fwd * 3.4]), tunic.darkened(0.12))
	_poly(PackedVector2Array([neck + fwd * 3.2, neck - fwd * 2.6, hip - fwd * 2.6,
			hip + fwd * 2.8]), tunic)
	_capsule(hip - fwd * 2.7 + spine * 0.4, hip + fwd * 2.9 + spine * 0.4, 0.6, leather)
	_inside_only = true
	_line(neck - fwd * 2.2 - spine * 0.6, hip + fwd * 2.6 + spine * 1.2, leather)
	_inside_only = false
	_finish_layer()

	# Head: headband tails, spiky hair, face, headband.
	var knot := _rp(head, look, Vector2(-3.6, -1.6))
	var tail: Vector2 = p["tail"]
	_line(knot, knot + tail, tunic)
	_line(knot + Vector2(0, 0.8), knot + tail * 0.75 + Vector2(0, 1.8), tunic.darkened(0.15))
	_disc(_rp(head, look, Vector2(-0.8, -0.5)), 4.4, hair)
	_poly(_rel(head, look, [Vector2(-3.0, -3.0), Vector2(-6.8, -4.2), Vector2(-4.2, -0.5)]), hair)
	_poly(_rel(head, look, [Vector2(-1.2, -4.0), Vector2(-3.4, -7.0), Vector2(0.8, -4.4)]), hair)
	_poly(_rel(head, look, [Vector2(-4.0, -0.5), Vector2(-6.4, 1.2), Vector2(-3.8, 1.8)]), hair)
	_oval(_rp(head, look, Vector2(1.0, 0.8)), 3.3, 3.5, look, skin)
	_poly(_rel(head, look, [Vector2(-1.0, -4.4), Vector2(4.4, -2.4), Vector2(3.6, -1.4),
			Vector2(0.6, -2.0)]), hair)
	_line(_rp(head, look, Vector2(-3.8, -1.7)), _rp(head, look, Vector2(3.9, -1.4)),
			tunic.lightened(0.1))
	_px(_rp(head, look, Vector2(2.6, 0.4)), Color("1a0f12"))
	_px(_rp(head, look, Vector2(2.6, 1.4)), Color("1a0f12"))
	_finish_layer()

	_blade(hand_f, p["wf"], 9.0, steel, hilt)
	var elbow_f := _elbow(sh_f, hand_f, 5.0, 5.0)
	_capsule(sh_f, elbow_f, 1.3, tunic)
	_capsule(elbow_f, hand_f, 1.2, leather)
	_disc(hand_f, 1.1, skin)
	_finish_layer()


func _blade(hand: Vector2, angle: float, length: float, steel: Color, hilt: Color) -> void:
	var d := _dir(angle)
	var n := Vector2(-d.y, d.x)
	_capsule(hand + n * 1.8, hand - n * 1.8, 0.5, hilt)
	_capsule(hand + d * 1.0, hand + d * (length - 1.2), 0.75, steel)
	_poly(PackedVector2Array([hand + d * (length - 1.8) + n * 0.8, hand + d * (length + 0.6),
			hand + d * (length - 1.8) - n * 0.8]), steel)


## Cass: long robe, wide-brimmed pointed hat and a staff with a glowing orb.
func _draw_mage(p: Dictionary, base: Color) -> void:
	var robe := base
	var robe_b := base.darkened(BACK_SHADE)
	var trim := base.darkened(0.45)
	var sash := Color("6b3d8f")
	var skin := Color("f1c9a3")
	var hair := Color("9a4b2a")
	var boots := Color("4a3428")
	var wood := Color("7c5232")
	var orb := Color("8ff1ff")
	var gold := Color("e9c75a")
	var hat := base.darkened(0.1)
	var hip: Vector2 = p["hip"]
	var neck: Vector2 = p["neck"]
	var head: Vector2 = p["head"]
	var fwd: Vector2 = p["fwd"]
	var spine: Vector2 = p["spine"]
	var look: float = p["look"]
	var toe := _dir(p["toe"])
	var sh_f: Vector2 = p["sh_f"]
	var sh_b: Vector2 = p["sh_b"]
	var hand_f: Vector2 = p["hand_f"]
	var foot_b: Vector2 = p["foot_b"]
	var foot_f: Vector2 = p["foot_f"]
	var knee_b: Vector2 = p["knee_b"]
	var knee_f: Vector2 = p["knee_f"]

	var staff_dir := _dir(p["wf"])
	var grip: float = p["grip"]
	var bottom := hand_f - staff_dir * (STAFF_LENGTH * grip)
	var top := hand_f + staff_dir * (STAFF_LENGTH * (1.0 - grip))
	var grip_b: float = p["grip_b"]
	var on_staff := grip_b >= 0.0
	var hand_b: Vector2 = bottom + staff_dir * (STAFF_LENGTH * grip_b) if on_staff else p["hand_b"]

	# Far sleeve (its hand is drawn last when it grips the staff).
	_limb(sh_b, _elbow(sh_b, hand_b, 5.0, 5.0), hand_b, 1.6, 1.9, robe_b)
	if not on_staff:
		_disc(hand_b, 1.1, skin.darkened(BACK_SHADE))
	_finish_layer()
	_capsule(foot_b - toe * 0.3, foot_b + toe * 1.8, 1.5, boots.darkened(0.2))
	_capsule(foot_f - toe * 0.3, foot_f + toe * 1.8, 1.5, boots)
	_finish_layer()

	# Robe: hull around shoulders, hips and legs, hem lifted so the boots show.
	var hem_b := foot_b - fwd * 3.0 + spine * 1.6
	var hem_f := foot_f + fwd * 3.2 + spine * 1.6
	var hull := Geometry2D.convex_hull(PackedVector2Array([neck + fwd * 2.6, neck - fwd * 2.6,
			hip + fwd * 3.8, hip - fwd * 3.6, knee_b - fwd * 3.0, knee_f + fwd * 3.0, hem_b, hem_f]))
	_poly(hull, robe)
	_inside_only = true
	_capsule(hem_b, hem_f, 1.2, trim)
	_capsule(hip - fwd * 5.0 + spine * 0.5, hip + fwd * 5.0 + spine * 0.5, 0.9, sash)
	_line(neck + fwd * 1.2, (hem_b + hem_f) * 0.5 + fwd * 1.6, trim)
	_disc(neck + fwd * 0.6 - spine * 0.5, 1.6, trim)
	_inside_only = false
	_finish_layer(OUTLINE, true, true)

	# Head: hair, face, wide brim and a pointed hat bent backwards.
	_capsule(_rp(head, look, Vector2(-2.4, 0.6)), _rp(head, look, Vector2(-3.4, 5.0)), 1.5, hair)
	_disc(_rp(head, look, Vector2(-1.2, 0.4)), 3.9, hair)
	_oval(_rp(head, look, Vector2(0.6, 0.7)), 3.4, 3.6, look, skin)
	_px(_rp(head, look, Vector2(2.4, 0.9)), Color("2a1a14"))
	_oval(_rp(head, look, Vector2(-0.3, -2.7)), 6.8, 1.5, look, hat)
	_poly(_rel(head, look, [Vector2(-4.0, -3.0), Vector2(3.6, -3.0), Vector2(1.8, -6.0),
			Vector2(-1.0, -8.8), Vector2(-4.6, -10.2), Vector2(-3.4, -6.4)]), hat)
	_line(_rp(head, look, Vector2(-3.7, -3.8)), _rp(head, look, Vector2(3.0, -3.8)), sash)
	_finish_layer()

	# Staff and orb, then the hands that hold it.
	_capsule(bottom, top, 0.7, wood)
	_disc(top, 2.4, gold)
	_disc(top + staff_dir * 0.6, 1.8, orb)
	_finish_layer()
	_limb(sh_f, _elbow(sh_f, hand_f, 5.0, 5.0), hand_f, 1.6, 1.9, robe)
	_disc(hand_f, 1.2, skin)
	_finish_layer()
	if on_staff:
		_disc(hand_b, 1.1, skin)
		_finish_layer()
	_glow(top + staff_dir * 0.6, 2.0, 4.5, orb, 0.35)
	_px(top + staff_dir * 0.6 + Vector2(-0.8, -0.8), Color.WHITE)
	_finish_detail()
	if float(p.get("ward", 0.0)) > 0.0:
		_ward_arc(hand_f + Vector2(-3.0, -3.0), 8.5, 70.0, orb)


## Arcane barrier in front of the mage (parry): a bright arc facing right with a soft halo.
func _ward_arc(c: Vector2, radius: float, half_span_deg: float, col: Color) -> void:
	var reach := radius + 2.0
	var rect := _pixel_rect(c - Vector2(reach, reach), c + Vector2(reach, reach))
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var d := _inv(Vector2(x, y)) - c
			var angle := absf(rad_to_deg(atan2(d.y, d.x)))
			if angle > half_span_deg:
				continue
			var taper := 1.0 if angle < half_span_deg * 0.6 else 0.55
			var off := absf(d.length() - radius)
			var dst := _canvas.get_pixel(x, y)
			if off <= 0.6:
				_canvas.set_pixel(x, y, dst.blend(Color(col.lightened(0.6), 0.95 * taper)))
			elif off <= 1.7:
				_canvas.set_pixel(x, y, dst.blend(Color(col, 0.4 * taper)))


# =============================================================================================
# Enemy
# =============================================================================================

func _enemy_sheet(style: String, base: Color, frames: int) -> Image:
	var count := maxi(1, frames)
	var sheet := Image.create_empty(ENEMY_FRAME.x * count, ENEMY_FRAME.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for i: int in count:
		var pose_name: String = ENEMY_POSES[mini(i, ENEMY_POSES.size() - 1)]
		var frame := _draw_enemy(style, base, pose_name, ENEMY_FRAME, 1.0, Vector2.ZERO)
		sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, ENEMY_FRAME), Vector2i(i * ENEMY_FRAME.x, 0))
	return sheet


## Enemies are drawn facing right and mirrored, so they face the party on the left.
func _draw_enemy(_style: String, base: Color, pose_name: String, size: Vector2i, zoom: float,
		offset: Vector2) -> Image:
	_begin_canvas(size, zoom, offset, true)
	_draw_husk(HUSK_POSES[pose_name], base, pose_name == "slam")
	return _canvas


## Rotten Husk: hunched, gaunt, rotting humanoid with long claws and glowing eyes.
func _draw_husk(p: Dictionary, base: Color, slam: bool) -> void:
	var skin := base
	var skin_b := base.darkened(0.38)
	var belly := base.lightened(0.18)
	var rot := base.darkened(0.55)
	var bruise := Color("5d4566")
	var bone := Color("e7dfbf")
	var rag := Color("3d3527")
	var gum := Color("3a1212")
	var hip: Vector2 = p["hip"]
	var hump: Vector2 = p["hump"]
	var chest: Vector2 = p["chest"]
	var head: Vector2 = p["head"]
	var tilt: float = p["tilt"]
	var jaw: float = p["jaw"]
	var sh_f := chest + Vector2(-1, 1.5)
	var sh_b := chest + Vector2(-3.5, 0)
	# In the slam both arms come down in front of the body so the two-handed smash reads.
	var arms_front: bool = p.get("arms_front", false)

	if not arms_front:
		_husk_arm(sh_b, p["hand_b"], p["claw_b"], skin_b, bone.darkened(0.35))
		_finish_layer(OUTLINE_HUSK)
	_husk_leg(hip - Vector2(2.0, 0), p["knee_b"], p["foot_b"], skin_b, bone.darkened(0.35))
	_finish_layer(OUTLINE_HUSK)
	_husk_leg(hip + Vector2(2.0, 0), p["knee_f"], p["foot_f"], skin, bone)
	_finish_layer(OUTLINE_HUSK)

	# Tattered rags hanging from the hips.
	_poly(PackedVector2Array([hip + Vector2(-5.5, -2), hip + Vector2(5.5, -2), hip + Vector2(4.5, 5),
			hip + Vector2(3.0, 3.5), hip + Vector2(1.5, 8), hip + Vector2(-0.5, 4.5),
			hip + Vector2(-2.5, 9), hip + Vector2(-4.0, 4.5), hip + Vector2(-5.5, 7)]), rag)
	_finish_layer(OUTLINE_HUSK)

	# Hunched, bony torso: discs along the curve of the back, vertebrae poking out of the spine.
	var samples := 24
	for i: int in samples + 1:
		var t := float(i) / samples
		_disc(_bezier(hip, hump, chest, t), _husk_radius(t), skin)
	for t: float in HUSK_VERTEBRAE:
		var c := _bezier(hip, hump, chest, t)
		var tangent := _husk_tangent(hip, hump, chest, t)
		var back := -Vector2(-tangent.y, tangent.x)
		var r := _husk_radius(t)
		_poly(PackedVector2Array([c + back * (r - 0.8) - tangent * 1.2, c + back * (r + 1.8),
				c + back * (r - 0.8) + tangent * 1.2]), bone.darkened(0.15))
	_inside_only = true
	for i: int in samples + 1:
		var t := float(i) / samples
		var c := _bezier(hip, hump, chest, t)
		var belly_side := _husk_belly(hip, hump, chest, t)
		var r := _husk_radius(t)
		_disc(c + belly_side * r * 0.6, r * 0.45, belly)
	for t: float in HUSK_RIBS:
		var c := _bezier(hip, hump, chest, t)
		var tangent := _husk_tangent(hip, hump, chest, t)
		var belly_side := _husk_belly(hip, hump, chest, t)
		_line(c + belly_side * 0.5 + tangent * 0.5, c + belly_side * (_husk_radius(t) - 0.3)
				- tangent * 1.8, rot)
	for spot: Array in HUSK_ROT_SPOTS:
		var t: float = spot[0]
		var c := _bezier(hip, hump, chest, t)
		_disc(c + _husk_belly(hip, hump, chest, t) * float(spot[1]), spot[2],
				bruise if spot[3] else rot)
	_inside_only = false
	_finish_layer(OUTLINE_HUSK, true, true)
	if arms_front:
		_husk_arm(sh_b, p["hand_b"], p["claw_b"], skin_b, bone.darkened(0.35))
		_finish_layer(OUTLINE_HUSK)

	# Head: skull, gaping mouth with teeth, hanging lower jaw, dark eye sockets.
	_poly(_rel(head, tilt, [Vector2(-2.0, 1.2), Vector2(5.8, 1.2 + jaw), Vector2(5.2, 3.4 + jaw * 1.6),
			Vector2(-1.2, 3.6)]), skin.darkened(0.12))
	_oval(head, 5.4, 4.2, tilt, skin)
	_poly(_rel(head, tilt, [Vector2(0.4, 0.7), Vector2(6.3, 0.2), Vector2(5.9, 1.6 + jaw * 1.4),
			Vector2(0.7, 2.1)]), gum)
	_poly(_rel(head, tilt, [Vector2(-2.6, -4.0), Vector2(3.4, -3.9), Vector2(5.6, -2.0),
			Vector2(-1.8, -2.6)]), skin.darkened(0.25))
	_inside_only = true
	_disc(_rp(head, tilt, Vector2(2.2, -1.0)), 1.3, gum.darkened(0.4))
	_disc(_rp(head, tilt, Vector2(4.4, -1.4)), 1.0, gum.darkened(0.4))
	_disc(_rp(head, tilt, Vector2(-2.2, -0.4)), 1.0, rot)
	_inside_only = false
	for x: float in [1.8, 3.2, 4.6, 5.8]:
		_px(_rp(head, tilt, Vector2(x, 1.0)), bone)
	for x: float in [2.5, 3.9, 5.3]:
		_px(_rp(head, tilt, Vector2(x, 1.5 + jaw * 1.2)), bone)
	_finish_layer(OUTLINE_HUSK)

	_husk_arm(sh_f, p["hand_f"], p["claw_f"], skin, bone)
	_finish_layer(OUTLINE_HUSK)

	if slam:
		_husk_impact(p["hand_f"], p["hand_b"])

	_husk_eye(_rp(head, tilt, Vector2(2.2, -1.0)), p["eyes"])
	_husk_eye(_rp(head, tilt, Vector2(4.4, -1.4)), float(p["eyes"]) * 0.7)


## Torso thickness along the back curve (0 = hips, 1 = chest): gaunt, swelling at the hump.
func _husk_radius(t: float) -> float:
	return lerpf(4.2, 5.4, t) + 1.8 * sin(t * PI)


func _husk_tangent(hip: Vector2, hump: Vector2, chest: Vector2, t: float) -> Vector2:
	var a := _bezier(hip, hump, chest, minf(t, 0.99))
	return (_bezier(hip, hump, chest, minf(t, 0.99) + 0.01) - a).normalized()


## Unit vector from the spine toward the belly at `t`.
func _husk_belly(hip: Vector2, hump: Vector2, chest: Vector2, t: float) -> Vector2:
	var tangent := _husk_tangent(hip, hump, chest, t)
	return Vector2(-tangent.y, tangent.x)


## Long gaunt arm ending in a big hand with three long, hooked claws.
func _husk_arm(sh: Vector2, hand: Vector2, claw_deg: float, col: Color, claw_col: Color) -> void:
	var elbow := _elbow(sh, hand, HUSK_ARM, HUSK_ARM)
	_capsule(sh, elbow, 2.2, col)
	_capsule(elbow, hand, 1.7, col)
	_disc(elbow, 1.9, col)
	for k: int in 3:
		var spread := (k - 1) * 26.0
		var d := _dir(claw_deg + spread)
		var reach := HUSK_CLAW if k == 1 else HUSK_CLAW * 0.8
		var bend := hand + d * (reach * 0.65)
		_capsule(hand + d * 1.0, bend, 0.75, claw_col)
		_capsule(bend, bend + _dir(claw_deg + spread + 28.0) * (reach * 0.4), 0.5, claw_col)
	_oval(hand, 2.4, 2.0, claw_deg, col)


func _husk_leg(hip: Vector2, knee: Vector2, foot: Vector2, col: Color, claw_col: Color) -> void:
	_capsule(hip, knee, 2.6, col)
	_capsule(knee, foot, 1.8, col)
	_disc(knee, 2.2, col)
	_capsule(foot + Vector2(-1.5, 0), foot + Vector2(2.5, 0), 1.3, col)
	_line(foot + Vector2(3.5, 0), foot + Vector2(5.0, 1.0), claw_col)
	_line(foot + Vector2(3.0, -1.0), foot + Vector2(4.5, -1.0), claw_col)


## Slam impact: flying rocks, cracks and dust where both hands hit the ground.
func _husk_impact(hand_f: Vector2, hand_b: Vector2) -> void:
	var ground := float(ENEMY_FRAME.y - 1)
	var rock := Color("5b5650")
	for offset: Vector2 in [Vector2(3, -8), Vector2(7, -5), Vector2(-4, -7), Vector2(-9, -4)]:
		_disc(Vector2(hand_f.x + offset.x, ground + offset.y), 1.1, rock)
	_finish_layer(OUTLINE_HUSK)
	for x: float in [hand_f.x, hand_b.x]:
		_line(Vector2(x - 6, ground), Vector2(x + 6, ground), Color("191714"))
	_finish_detail()
	for x: float in [hand_f.x + 5, hand_b.x - 5, (hand_f.x + hand_b.x) * 0.5]:
		_glow(Vector2(x, ground - 2.0), 1.5, 5.0, Color("b9ae8f"), 0.55)
	for k: int in 4:
		var a := -165.0 + k * 50.0
		_line(hand_f + _dir(a) * 6.0, hand_f + _dir(a) * 10.0, Color("e8e2c8"))
	_finish_detail()


## Glowing eye drawn over everything. power 2 = wind-up glare, under 0.7 = squint.
func _husk_eye(pos: Vector2, power: float) -> void:
	var core := Color("fffbb0")
	var halo := Color("ffc23a")
	if power < 0.7:
		_px(pos, Color("c9b24a"))
		_finish_detail()
		return
	_glow(pos, 0.5, 0.8 + power, halo, minf(0.55, 0.25 * power))
	_px(pos, core)
	if power >= 1.8:
		_px(pos + Vector2(1, 0), core)
		_px(pos + Vector2(0, -1), Color("ffe680"))
	_finish_detail()


# =============================================================================================
# FX, environment, UI
# =============================================================================================

## 16x16 star burst: white core, yellow rays, orange tips.
func _spark() -> Image:
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(7.5, 7.5)
	for y: int in 16:
		for x: int in 16:
			var d := Vector2(x, y) - c
			var r := d.length()
			var a := atan2(d.y, d.x)
			var reach := 2.4 + 5.6 * pow(absf(cos(2.0 * a)), 12.0) + 3.0 * pow(absf(sin(2.0 * a)), 16.0)
			var k := 1.0 - r / reach
			if k <= 0.0:
				continue
			if k > 0.55 or r < 1.8:
				img.set_pixel(x, y, Color.WHITE)
			elif k > 0.28:
				img.set_pixel(x, y, Color("fff27a"))
			else:
				img.set_pixel(x, y, Color(Color("ffb12e"), 0.85))
	return img


## 64x16 crest of a ground shockwave: bright leading edge fading into the ground, a few rocks.
func _shockwave() -> Image:
	var img := Image.create_empty(64, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x: int in 64:
		var u := (x + 0.5) / 64.0
		var crest := (13.0 * pow(sin(PI * u), 1.4) * (1.0 + 0.1 * sin(x * 0.9))
				+ _rng.randf_range(-0.6, 0.6))
		var top := 16.0 - crest
		for y: int in 16:
			var depth := y + 0.5 - top
			if depth < 0.0:
				continue
			var col: Color
			if depth < 1.5:
				col = Color("f4ffe6")
			elif depth < 3.5:
				col = Color(Color("c8ec90"), 0.9)
			else:
				var fade := clampf((depth - 3.5) / maxf(crest - 3.5, 1.0), 0.0, 1.0)
				col = Color(Color("8fc25a"), lerpf(0.75, 0.2, fade))
			img.set_pixel(x, y, col)
	for i: int in 6:
		var rx := _rng.randi_range(14, 50)
		var ry := _rng.randi_range(0, 3)
		img.set_pixel(rx, ry, Color("4a4a42"))
		img.set_pixel(rx + 1, ry, Color("6c6c60"))
		img.set_pixel(rx, ry + 1, Color("2c2c26"))
	return img


## 32x12 soft dark ellipse.
func _shadow() -> Image:
	var img := Image.create_empty(32, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y: int in 12:
		for x: int in 32:
			var dx := (x - 15.5) / 16.0
			var dy := (y - 5.5) / 6.0
			var d := dx * dx + dy * dy
			if d >= 1.0:
				continue
			var a := 0.6 * (1.0 - d)
			img.set_pixel(x, y, Color(0, 0, 0, ceilf(a * 8.0) / 8.0))
	return img


## 32x32 white crescent for strikes, swinging toward the right.
func _slash() -> Image:
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var outer_c := Vector2(9, 15.5)
	var inner_c := Vector2(4, 15.5)
	var outer_r := 15.5
	var inner_r := 14.5
	for y: int in 32:
		for x: int in 32:
			var q := Vector2(x, y)
			var d1 := q.distance_to(outer_c)
			var d2 := q.distance_to(inner_c)
			if d1 > outer_r or d2 < inner_r:
				continue
			var depth := outer_r - d1
			if depth < 1.3:
				img.set_pixel(x, y, Color.WHITE)
			elif depth < 3.0:
				img.set_pixel(x, y, Color(Color("e6f6ff"), 0.85))
			else:
				img.set_pixel(x, y, Color(Color("b9e2ff"), 0.5))
	return img


## 32x32 seamless dark stone slabs with mortar, cracks and moss.
@warning_ignore("integer_division")
func _floor_tile() -> Image:
	var size := 32
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var lattice := PackedFloat32Array()
	lattice.resize(64)
	for i: int in 64:
		lattice[i] = _rng.randf()
	var tints := PackedFloat32Array()
	tints.resize(8)
	for i: int in 8:
		tints[i] = _rng.randf_range(-0.05, 0.05)
	var stone := Color("3a3e47")
	var mortar := Color("1c1d22")
	var moss_dark := Color("2f4526")
	var moss_light := Color("4d6c33")
	for y: int in size:
		for x: int in size:
			var row := y / 16
			var lx := posmod(x + row * 8, 16)
			var ly := y % 16
			var brick := row * 4 + posmod(x + row * 8, size) / 16
			var n := _tile_noise(lattice, x, y, 8) * 0.6 + _tile_noise(lattice, x * 2, y * 2, 8) * 0.4
			var edge := mini(mini(lx, 15 - lx), mini(ly, 15 - ly))
			var col: Color
			if lx == 0 or ly == 0:
				col = mortar
			else:
				col = stone.lightened(tints[brick % 8] + 0.0) if tints[brick % 8] >= 0.0 \
						else stone.darkened(-tints[brick % 8])
				col = col.lightened((n - 0.5) * 0.12) if n >= 0.5 else col.darkened((0.5 - n) * 0.2)
				if lx == 1 or ly == 1:
					col = col.lightened(0.1)
				elif lx == 15 or ly == 15:
					col = col.darkened(0.2)
			# Moss creeps out of the mortar in small patches so tiling does not repeat one blob.
			var moss := (_tile_noise(lattice, x + 11, y + 5, 8) * 0.65
					+ _tile_noise(lattice, x + 3, y + 21, 4) * 0.35 - float(edge) * 0.08)
			if moss > 0.6:
				col = moss_light if moss > 0.68 else moss_dark
			img.set_pixel(x, y, col)
	# Two cracks, walked with wrap-around so the tile stays seamless.
	for crack: int in 2:
		var p := Vector2i(_rng.randi_range(0, size - 1), _rng.randi_range(0, size - 1))
		for i: int in 9:
			img.set_pixel(posmod(p.x, size), posmod(p.y, size), Color("23252b"))
			p += Vector2i(1 if _rng.randf() < 0.7 else 0, _rng.randi_range(-1, 1))
	return img


## Periodic value noise (period 32 px) on a lattice of `cells` x `cells`.
@warning_ignore("integer_division")
func _tile_noise(lattice: PackedFloat32Array, x: int, y: int, cells: int) -> float:
	var cell := 32 / cells
	var gx := posmod(x, 32 * 2) / float(cell)
	var gy := posmod(y, 32 * 2) / float(cell)
	var x0 := floori(gx)
	var y0 := floori(gy)
	var fx := smoothstep(0.0, 1.0, gx - x0)
	var fy := smoothstep(0.0, 1.0, gy - y0)
	var period := cells
	var v00 := lattice[posmod(y0, period) * 8 + posmod(x0, period)]
	var v10 := lattice[posmod(y0, period) * 8 + posmod(x0 + 1, period)]
	var v01 := lattice[posmod(y0 + 1, period) * 8 + posmod(x0, period)]
	var v11 := lattice[posmod(y0 + 1, period) * 8 + posmod(x0 + 1, period)]
	return lerpf(lerpf(v00, v10, fx), lerpf(v01, v11, fx), fy)


## 320x120 dark ruins on a transparent sky; tiles horizontally.
func _backdrop() -> Image:
	var w := 320
	var h := 120
	_begin_canvas(Vector2i(w, h))
	var far := Color("2a2a3a")
	var near := Color("16151e")
	var glow := Color("6f8f4a")
	# Far layer: towers with broken tops and an arcade.
	var towers := [[18, 16, 78], [70, 22, 96], [128, 14, 62], [196, 26, 104], [262, 18, 84]]
	for t: Array in towers:
		for shift: int in [-w, 0, w]:
			_ruined_tower(float(t[0] + shift), float(t[1]), float(t[2]), h, far)
	for shift: int in [-w, 0, w]:
		_arcade(150.0 + shift, 70.0, 40.0, h, far)
	_finish_layer(Color(0, 0, 0, 0), true)
	for win: Vector2 in [Vector2(76, 40), Vector2(203, 34), Vector2(205, 52), Vector2(24, 62)]:
		_glow(win, 0.5, 1.6, glow, 0.7)
	# Near layer: rubble, broken columns, a dead tree, an archway.
	for x: int in w:
		var top := 102.0 + 4.0 * sin(x * 0.07) + 2.0 * sin(x * 0.23 + 1.0) + _rng.randf_range(-1.0, 1.0)
		_capsule(Vector2(x, top), Vector2(x, h + 2), 0.5, near)
	var columns := [[40, 7, 40, 1.0], [104, 8, 28, -1.0], [232, 7, 48, 1.0], [300, 6, 22, -1.0]]
	for col_data: Array in columns:
		for shift: int in [-w, 0, w]:
			_broken_column(float(col_data[0] + shift), float(col_data[1]), float(col_data[2]),
					float(col_data[3]), h, near)
	for shift: int in [-w, 0, w]:
		_dead_tree(Vector2(168 + shift, 104), near)
		_archway(270.0 + shift, 36.0, 44.0, h, near)
	_finish_layer(Color(0, 0, 0, 0), true)
	return _canvas


func _ruined_tower(x: float, width: float, height: float, h: int, col: Color) -> void:
	var top := h - height
	var pts := PackedVector2Array([Vector2(x, h), Vector2(x, top + 6), Vector2(x + width * 0.25, top),
			Vector2(x + width * 0.4, top + 7), Vector2(x + width * 0.6, top + 3),
			Vector2(x + width * 0.75, top + 12), Vector2(x + width, top + 9), Vector2(x + width, h)])
	_poly(pts, col)
	for k: int in 3:
		var bx := x + width * (0.15 + 0.3 * k)
		_poly(PackedVector2Array([Vector2(bx, top + 4 + k), Vector2(bx + 3, top + 4 + k),
				Vector2(bx + 3, top - 1 + k), Vector2(bx, top - 1 + k)]), col)


func _arcade(x: float, width: float, height: float, h: int, col: Color) -> void:
	var top := h - height
	_poly(PackedVector2Array([Vector2(x, h), Vector2(x, top), Vector2(x + width * 0.7, top),
			Vector2(x + width * 0.8, top + 6), Vector2(x + width, top + 10), Vector2(x + width, h)]), col)
	# Arch openings cut out of the wall.
	for k: int in 3:
		var ax := x + 7.0 + k * 12.0
		var rect := _pixel_rect(Vector2(ax - 4, top + 8), Vector2(ax + 4, h - 6))
		for py: int in range(rect.position.y, rect.end.y):
			for px: int in range(rect.position.x, rect.end.x):
				var q := _inv(Vector2(px, py))
				var inside := absf(q.x - ax) <= 3.5 and q.y >= top + 14 and q.y <= h - 8
				inside = inside or (q.distance_to(Vector2(ax, top + 14)) <= 3.5 and q.y < top + 14)
				if inside:
					_layer.set_pixel(px, py, Color(0, 0, 0, 0))


func _broken_column(x: float, width: float, height: float, slant: float, h: int,
		col: Color) -> void:
	var top := h - height
	_poly(PackedVector2Array([Vector2(x, h), Vector2(x, top + 3 + slant * 3),
			Vector2(x + width, top + 3 - slant * 3),
			Vector2(x + width, h)]), col)
	_poly(PackedVector2Array([Vector2(x - 1.5, top + 8), Vector2(x + width + 1.5, top + 8),
			Vector2(x + width + 1.5, top + 11), Vector2(x - 1.5, top + 11)]), col)
	_poly(PackedVector2Array([Vector2(x - 2, h - 18), Vector2(x + width + 2, h - 18),
			Vector2(x + width + 2, h), Vector2(x - 2, h)]), col)


func _dead_tree(foot: Vector2, col: Color) -> void:
	_capsule(foot, foot + Vector2(2, -34), 2.0, col)
	_capsule(foot + Vector2(1, -18), foot + Vector2(-12, -30), 1.2, col)
	_capsule(foot + Vector2(-12, -30), foot + Vector2(-16, -38), 0.7, col)
	_capsule(foot + Vector2(2, -26), foot + Vector2(13, -36), 1.0, col)
	_capsule(foot + Vector2(13, -36), foot + Vector2(15, -44), 0.6, col)
	_capsule(foot + Vector2(2, -34), foot + Vector2(-2, -46), 0.8, col)
	_capsule(foot + Vector2(-6, -24), foot + Vector2(-9, -20), 0.6, col)


func _archway(x: float, width: float, height: float, h: int, col: Color) -> void:
	var top := h - height
	_poly(PackedVector2Array([Vector2(x, h), Vector2(x, top + 2), Vector2(x + width * 0.55, top),
			Vector2(x + width * 0.62, top + 9), Vector2(x + width, top + 14), Vector2(x + width, h)]), col)
	var c := Vector2(x + width * 0.5, top + 20)
	var rect := _pixel_rect(Vector2(x + 6, top + 10), Vector2(x + width - 6, h))
	for py: int in range(rect.position.y, rect.end.y):
		for px: int in range(rect.position.x, rect.end.x):
			var q := _inv(Vector2(px, py))
			if (absf(q.x - c.x) <= 10.0 and q.y >= c.y) or q.distance_to(c) <= 10.0:
				_layer.set_pixel(px, py, Color(0, 0, 0, 0))


## 12x12 padlock (steel shackle, gold body, keyhole).
func _lock_icon() -> Image:
	_begin_canvas(Vector2i(12, 12))
	var c := Vector2(5.5, 5.0)
	var rect := _pixel_rect(Vector2(1, 0), Vector2(10, 6))
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var d := Vector2(x, y).distance_to(c)
			if d >= 1.9 and d <= 3.4 and y <= 5:
				_plot(x, y, Color("b9c2cf"))
	_finish_layer()
	_poly(PackedVector2Array([Vector2(1.5, 4.5), Vector2(9.5, 4.5), Vector2(9.5, 10.5),
			Vector2(1.5, 10.5)]), Color("d9a93f"))
	_px(Vector2(5, 7), Color("3a2410"))
	_px(Vector2(6, 7), Color("3a2410"))
	_px(Vector2(5, 8), Color("3a2410"))
	_px(Vector2(6, 8), Color("3a2410"))
	_finish_layer()
	return _canvas


## 10x10 AP gem, filled (cyan facets) or empty (outline only).
func _ap_pip(filled: bool) -> Image:
	_begin_canvas(Vector2i(10, 10))
	var c := Vector2(4.5, 4.5)
	var base := Color("49cfff")
	for y: int in 10:
		for x: int in 10:
			var d := Vector2(x, y) - c
			var m := absf(d.x) + absf(d.y)
			if m > 4.1:
				continue
			if filled:
				var col := base
				if d.y < 0.0 and d.x < 0.0:
					col = base.lightened(0.35)
				elif d.y > 0.0 and d.x > 0.0:
					col = base.darkened(0.35)
				elif d.y > 0.0:
					col = base.darkened(0.15)
				_plot(x, y, col)
			elif m > 2.9:
				_plot(x, y, Color("6a8496"))
			else:
				_plot(x, y, Color(Color("0b1620"), 0.55))
	if filled:
		_plot(3, 3, Color.WHITE)
	_finish_layer(Color("0e2a3a"), false)
	return _canvas


# =============================================================================================
# Sounds
# =============================================================================================

func _synth(cue: String) -> PackedFloat32Array:
	match cue:
		"parry":
			return _sfx_parry()
		"parry_final":
			return _sfx_parry_final()
		"dodge":
			return _sfx_dodge()
		"jump":
			return _sfx_jump()
		"whiff":
			return _sfx_whiff()
		"locked":
			return _sfx_locked()
		"hurt":
			return _sfx_hurt()
		"strike":
			return _sfx_strike()
		"heavy_strike":
			return _sfx_heavy_strike()
		"counter":
			return _sfx_counter()
		"team_counter":
			return _sfx_team_counter()
		"alert":
			return _sfx_alert()
		"lunge":
			return _sfx_lunge()
		"slam":
			return _sfx_slam()
		"downed":
			return _sfx_downed()
		"ap_gain":
			return _sfx_ap_gain()
		"turn_start":
			return _sfx_turn_start()
		"menu_move":
			return _sfx_menu_move()
		"menu_confirm":
			return _sfx_menu_blip([880.0, 1320.0])
		"menu_cancel":
			return _sfx_menu_blip([660.0, 440.0])
		"victory":
			return _sfx_victory()
		"defeat":
			return _sfx_defeat()
		"metronome":
			return _sfx_metronome()
	return _sfx_menu_blip([1000.0, 1000.0])


func _buffer(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(roundi(seconds * MIX_RATE))
	b.fill(0.0)
	return b


## Sine whose pitch glides exponentially from f0 to f1 over `glide` seconds, with a linear attack
## and an exponential decay (time constant `decay`). phase HARD starts it at full level.
func _tone(b: PackedFloat32Array, start: float, f0: float, f1: float, glide: float, amp: float,
		attack: float, decay: float, phase: float = 0.0) -> void:
	var i0 := roundi(start * MIX_RATE)
	var ph := phase
	for i: int in range(i0, b.size()):
		var t := float(i - i0) / MIX_RATE
		var env := exp(-maxf(0.0, t - attack) / decay)
		if env < 0.0002:
			break
		if attack > 0.0 and t < attack:
			env = t / attack
		b[i] += amp * env * sin(ph)
		var f := f1
		if glide > 0.0 and t < glide:
			f = f0 * pow(f1 / f0, t / glide)
		ph += TAU * f / MIX_RATE


## Inharmonic partials (metal, bells). detune adds a slightly sharp twin for shimmer.
func _partials(b: PackedFloat32Array, start: float, base: float, ratios: Array, amps: Array,
		decays: Array, amp: float, detune: float = 0.0) -> void:
	for k: int in ratios.size():
		var f: float = base * float(ratios[k])
		var phase := HARD if k == 0 else _rng.randf() * TAU
		_tone(b, start, f, f, 0.0, amp * float(amps[k]), 0.0, decays[k], phase)
		if detune > 0.0:
			_tone(b, start, f + detune, f + detune, 0.0, amp * float(amps[k]) * 0.45, 0.0,
					float(decays[k]) * 1.3, _rng.randf() * TAU)


## Filtered noise burst. The state-variable filter's cutoff glides from c0 to c1 over the burst
## (or c0 -> c_mid during the attack, then c_mid -> c1).
func _noise(b: PackedFloat32Array, start: float, length: float, amp: float, attack: float,
		decay: float, mode: NoiseFilter, c0: float, c1: float, q: float = 0.707,
		c_mid: float = -1.0) -> void:
	var i0 := roundi(start * MIX_RATE)
	var i1 := mini(b.size(), i0 + roundi(length * MIX_RATE))
	var s1 := 0.0
	var s2 := 0.0
	var k := 1.0 / q
	for i: int in range(i0, i1):
		var t := float(i - i0) / MIX_RATE
		var env := exp(-maxf(0.0, t - attack) / decay)
		if attack > 0.0 and t < attack:
			env = t / attack
		var cutoff: float
		if c_mid > 0.0 and attack > 0.0:
			if t < attack:
				cutoff = c0 * pow(c_mid / c0, t / attack)
			else:
				cutoff = c_mid * pow(c1 / c_mid, (t - attack) / maxf(length - attack, 0.001))
		else:
			cutoff = c0 * pow(c1 / c0, t / maxf(length, 0.001))
		var g := tan(PI * minf(cutoff, MIX_RATE * 0.45) / MIX_RATE)
		var a1 := 1.0 / (1.0 + g * (g + k))
		var a2 := g * a1
		var a3 := g * a2
		var v0 := _rng.randf_range(-1.0, 1.0)
		var v3 := v0 - s2
		var v1 := a1 * s1 + a2 * v3
		var v2 := s2 + a2 * s1 + a3 * v3
		s1 = 2.0 * v1 - s1
		s2 = 2.0 * v2 - s2
		var out := v0 - k * v1 - v2
		if mode == NoiseFilter.LOW:
			out = v2
		elif mode == NoiseFilter.BAND:
			out = v1 * k
		b[i] += amp * env * out


## Crunchy crackle: many tiny band-passed noise grains.
func _crackle(b: PackedFloat32Array, start: float, span: float, count: int, amp: float,
		f_lo: float, f_hi: float) -> void:
	for g: int in count:
		var t := start + span * _rng.randf()
		var a := amp * _rng.randf_range(0.4, 1.0) * (1.0 - 0.7 * (t - start) / span)
		var f := _rng.randf_range(f_lo, f_hi)
		_noise(b, t, _rng.randf_range(0.002, 0.006), a, 0.0, 0.0015, NoiseFilter.BAND, f, f, 2.0)


func _lowpass(b: PackedFloat32Array, cutoff: float) -> void:
	var a := 1.0 - exp(-TAU * cutoff / MIX_RATE)
	var y := 0.0
	for i: int in b.size():
		y += a * (b[i] - y)
		b[i] = y


## Soft clipping for grit. Normalises first so `drive` means the same for every sound.
func _saturate(b: PackedFloat32Array, drive: float) -> void:
	var peak := _peak(b)
	if peak <= 0.0:
		return
	for i: int in b.size():
		b[i] = tanh(b[i] / peak * drive)


func _peak(b: PackedFloat32Array) -> float:
	var peak := 0.0
	for v: float in b:
		peak = maxf(peak, absf(v))
	return peak


## Removes DC, normalises to PEAK_DB and fades the tail out (fade_in only for non-critical cues).
func _master(b: PackedFloat32Array, fade_out: float = 0.015,
		fade_in: float = 0.0) -> PackedFloat32Array:
	var prev_in := 0.0
	var prev_out := 0.0
	for i: int in b.size():
		var x := b[i]
		var y := x - prev_in + 0.9995 * prev_out
		prev_in = x
		prev_out = y
		b[i] = y
	var peak := _peak(b)
	if peak > 0.0:
		var gain := db_to_linear(PEAK_DB) / peak
		for i: int in b.size():
			b[i] *= gain
	var n_in := roundi(fade_in * MIX_RATE)
	for i: int in mini(n_in, b.size()):
		b[i] *= float(i) / n_in
	var n_out := mini(roundi(fade_out * MIX_RATE), b.size())
	for j: int in n_out:
		var k := float(j) / n_out
		b[b.size() - 1 - j] *= k * k
	return b


func _save_wav(b: PackedFloat32Array, path: String) -> Error:
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 2)
	for i: int in b.size():
		bytes.encode_s16(i * 2, clampi(roundi(b[i] * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav.save_to_wav(path)


func _sound_stats(b: PackedFloat32Array) -> String:
	var peak := _peak(b)
	var onset := -1
	for i: int in b.size():
		if absf(b[i]) >= peak * 0.1:
			onset = i
			break
	var window := MIX_RATE / 20
	var best := 0.0
	var acc := 0.0
	for i: int in b.size():
		acc += b[i] * b[i]
		if i >= window:
			acc -= b[i - window] * b[i - window]
		best = maxf(best, acc)
	var rms := sqrt(best / float(mini(window, b.size())))
	return "%d ms, peak %.1f dBFS, onset sample %d, loudest 50 ms RMS %.1f dBFS" % [
			roundi(b.size() * 1000.0 / MIX_RATE), linear_to_db(peak), onset, linear_to_db(rms)]


# --- Cues --------------------------------------------------------------------------------------

func _sfx_parry() -> PackedFloat32Array:
	var b := _buffer(0.26)
	_noise(b, 0.0, 0.008, 0.8, 0.0, 0.0018, NoiseFilter.HIGH, 2500.0, 2500.0)
	_partials(b, 0.0, 1240.0, [1.0, 1.506, 2.27, 2.98, 3.43], [1.0, 0.75, 0.6, 0.45, 0.35],
			[0.13, 0.1, 0.075, 0.055, 0.045], 0.55, 3.5)
	_noise(b, 0.0, 0.12, 0.22, 0.0, 0.03, NoiseFilter.BAND, 7000.0, 5000.0, 1.5)
	_tone(b, 0.0, 520.0, 430.0, 0.03, 0.3, 0.0, 0.03, HARD)
	_tone(b, 0.0, 240.0, 160.0, 0.03, 0.35, 0.0, 0.022, HARD)
	# Soft clipping lifts the ring against the transient so the clang reads loud and bright.
	_saturate(b, 1.6)
	return _master(b, 0.02)


func _sfx_parry_final() -> PackedFloat32Array:
	var b := _buffer(0.52)
	_noise(b, 0.0, 0.01, 0.9, 0.0, 0.0022, NoiseFilter.HIGH, 2000.0, 2000.0)
	_partials(b, 0.0, 980.0, [1.0, 1.52, 2.31, 2.89, 3.6, 4.1], [1.0, 0.8, 0.6, 0.45, 0.35, 0.25],
			[0.3, 0.22, 0.17, 0.12, 0.09, 0.07], 0.5, 2.5)
	_noise(b, 0.0, 0.3, 0.3, 0.0, 0.08, NoiseFilter.BAND, 7500.0, 5000.0, 1.5)
	_tone(b, 0.0, 140.0, 48.0, 0.12, 0.9, 0.0, 0.11, HARD)
	_noise(b, 0.0, 0.12, 0.6, 0.0, 0.035, NoiseFilter.LOW, 500.0, 200.0)
	_saturate(b, 1.4)
	return _master(b, 0.04)


func _sfx_dodge() -> PackedFloat32Array:
	var b := _buffer(0.21)
	_noise(b, 0.0, 0.21, 1.0, 0.075, 0.05, NoiseFilter.BAND, 600.0, 900.0, 1.6, 2600.0)
	_noise(b, 0.01, 0.18, 0.4, 0.06, 0.04, NoiseFilter.BAND, 1500.0, 2000.0, 2.5, 4200.0)
	return _master(b, 0.03, 0.002)


func _sfx_jump() -> PackedFloat32Array:
	var b := _buffer(0.18)
	_tone(b, 0.0, 150.0, 70.0, 0.05, 0.9, 0.002, 0.04)
	_noise(b, 0.0, 0.06, 0.4, 0.0, 0.025, NoiseFilter.LOW, 700.0, 300.0)
	_noise(b, 0.015, 0.165, 0.55, 0.06, 0.05, NoiseFilter.BAND, 500.0, 3200.0, 1.8)
	return _master(b, 0.03, 0.001)


func _sfx_whiff() -> PackedFloat32Array:
	var b := _buffer(0.12)
	_noise(b, 0.0, 0.12, 1.0, 0.035, 0.03, NoiseFilter.BAND, 2500.0, 3000.0, 3.0, 5500.0)
	_noise(b, 0.0, 0.1, 0.3, 0.03, 0.025, NoiseFilter.HIGH, 4000.0, 6000.0)
	return _master(b, 0.025, 0.002)


func _sfx_locked() -> PackedFloat32Array:
	var b := _buffer(0.06)
	_noise(b, 0.0, 0.01, 1.0, 0.0, 0.004, NoiseFilter.LOW, 1200.0, 900.0)
	_tone(b, 0.0, 320.0, 260.0, 0.02, 0.6, 0.0, 0.012, HARD)
	_tone(b, 0.0, 190.0, 190.0, 0.0, 0.4, 0.0, 0.018, HARD)
	_lowpass(b, 1500.0)
	return _master(b, 0.015)


func _sfx_hurt() -> PackedFloat32Array:
	var b := _buffer(0.2)
	_tone(b, 0.0, 190.0, 55.0, 0.08, 1.0, 0.0, 0.06, HARD)
	_noise(b, 0.0, 0.1, 0.6, 0.0, 0.04, NoiseFilter.LOW, 900.0, 300.0)
	_crackle(b, 0.002, 0.07, 14, 0.5, 1800.0, 3200.0)
	_saturate(b, 2.0)
	return _master(b, 0.03)


func _sfx_strike() -> PackedFloat32Array:
	var b := _buffer(0.15)
	_noise(b, 0.0, 0.02, 0.8, 0.0, 0.006, NoiseFilter.HIGH, 2500.0, 2500.0)
	_tone(b, 0.0, 260.0, 110.0, 0.04, 0.8, 0.0, 0.035, HARD)
	_noise(b, 0.0, 0.12, 0.35, 0.0, 0.04, NoiseFilter.BAND, 5000.0, 3500.0, 2.0)
	_saturate(b, 1.5)
	return _master(b, 0.03)


func _sfx_heavy_strike() -> PackedFloat32Array:
	var b := _buffer(0.3)
	_noise(b, 0.0, 0.03, 0.9, 0.0, 0.008, NoiseFilter.HIGH, 1800.0, 1800.0)
	_tone(b, 0.0, 170.0, 45.0, 0.1, 1.0, 0.0, 0.09, HARD)
	_noise(b, 0.0, 0.2, 0.7, 0.0, 0.07, NoiseFilter.LOW, 600.0, 250.0)
	_crackle(b, 0.003, 0.05, 8, 0.45, 1500.0, 2800.0)
	_saturate(b, 2.2)
	_noise(b, 0.02, 0.28, 0.25, 0.01, 0.12, NoiseFilter.LOW, 220.0, 120.0)
	return _master(b, 0.05)


func _sfx_counter() -> PackedFloat32Array:
	var b := _buffer(0.35)
	_noise(b, 0.0, 0.008, 0.9, 0.0, 0.004, NoiseFilter.HIGH, 2500.0, 2500.0)
	_partials(b, 0.0, 860.0, [1.0, 1.47, 2.23, 2.76, 3.4], [0.9, 0.7, 0.55, 0.4, 0.3],
			[0.2, 0.15, 0.11, 0.08, 0.06], 0.45, 3.0)
	_tone(b, 0.0, 160.0, 55.0, 0.07, 1.0, 0.0, 0.07, HARD)
	_noise(b, 0.0, 0.15, 0.3, 0.0, 0.05, NoiseFilter.BAND, 6000.0, 4500.0, 1.5)
	_saturate(b, 1.5)
	return _master(b, 0.04)


func _sfx_team_counter() -> PackedFloat32Array:
	var b := _buffer(0.72)
	_noise(b, 0.0, 0.03, 0.8, 0.0, 0.01, NoiseFilter.BAND, 2000.0, 1500.0, 0.9)
	_tone(b, 0.0, 120.0, 38.0, 0.18, 1.0, 0.0, 0.18, HARD)
	_noise(b, 0.0, 0.35, 0.8, 0.0, 0.1, NoiseFilter.LOW, 450.0, 150.0)
	_partials(b, 0.0, 700.0, [1.0, 1.47, 2.23, 2.76, 3.4], [0.9, 0.7, 0.55, 0.4, 0.3],
			[0.4, 0.3, 0.22, 0.16, 0.12], 0.4, 2.0)
	_saturate(b, 1.3)
	for s: int in 18:
		var t := _rng.randf_range(0.05, 0.55)
		var f := _rng.randf_range(2400.0, 6000.0)
		_tone(b, t, f, f, 0.0, _rng.randf_range(0.06, 0.12), 0.004, _rng.randf_range(0.05, 0.12))
	_tone(b, 0.04, 1760.0, 1760.0, 0.0, 0.1, 0.02, 0.3)
	_tone(b, 0.04, 1764.0, 1764.0, 0.0, 0.1, 0.02, 0.3)
	return _master(b, 0.08)


func _sfx_alert() -> PackedFloat32Array:
	var b := _buffer(0.25)
	_noise(b, 0.0, 0.004, 0.4, 0.0, 0.0015, NoiseFilter.HIGH, 3000.0, 3000.0)
	_partials(b, 0.0, 1175.0, [1.0, 2.0, 3.01, 4.2], [1.0, 0.35, 0.18, 0.1],
			[0.12, 0.08, 0.05, 0.03], 0.6)
	_partials(b, 0.075, 1568.0, [1.0, 2.0, 3.01, 4.2], [1.0, 0.35, 0.18, 0.1],
			[0.15, 0.09, 0.05, 0.03], 0.55)
	return _master(b, 0.03)


func _sfx_lunge() -> PackedFloat32Array:
	var b := _buffer(0.15)
	_noise(b, 0.0, 0.15, 1.0, 0.05, 0.04, NoiseFilter.BAND, 400.0, 900.0, 1.4, 1600.0)
	_tone(b, 0.0, 95.0, 70.0, 0.1, 0.25, 0.02, 0.05)
	return _master(b, 0.03, 0.002)


func _sfx_slam() -> PackedFloat32Array:
	var b := _buffer(0.6)
	_noise(b, 0.0, 0.03, 0.6, 0.0, 0.015, NoiseFilter.BAND, 1200.0, 900.0, 0.9)
	_tone(b, 0.0, 95.0, 32.0, 0.2, 1.0, 0.0, 0.22, HARD)
	_noise(b, 0.0, 0.58, 0.7, 0.01, 0.25, NoiseFilter.LOW, 260.0, 110.0, 0.8)
	_crackle(b, 0.03, 0.28, 10, 0.25, 800.0, 2000.0)
	_saturate(b, 1.8)
	return _master(b, 0.08)


func _sfx_downed() -> PackedFloat32Array:
	var b := _buffer(0.5)
	_noise(b, 0.0, 0.08, 0.35, 0.04, 0.03, NoiseFilter.BAND, 1500.0, 500.0, 1.5)
	_tone(b, 0.06, 140.0, 50.0, 0.08, 1.0, 0.0, 0.08, HARD)
	_noise(b, 0.06, 0.1, 0.6, 0.0, 0.04, NoiseFilter.LOW, 500.0, 200.0)
	_tone(b, 0.07, 110.0, 98.0, 0.4, 0.45, 0.02, 0.25)
	_tone(b, 0.07, 220.0, 196.0, 0.4, 0.15, 0.02, 0.2)
	return _master(b, 0.08, 0.002)


func _sfx_ap_gain() -> PackedFloat32Array:
	var b := _buffer(0.15)
	_tone(b, 0.0, 1568.0, 1568.0, 0.0, 0.6, 0.003, 0.04)
	_tone(b, 0.0, 3136.0, 3136.0, 0.0, 0.2, 0.003, 0.025)
	_tone(b, 0.05, 2093.0, 2093.0, 0.0, 0.7, 0.003, 0.06)
	_tone(b, 0.05, 4186.0, 4186.0, 0.0, 0.2, 0.003, 0.035)
	_noise(b, 0.05, 0.08, 0.1, 0.0, 0.03, NoiseFilter.BAND, 8000.0, 8000.0, 2.0)
	return _master(b, 0.03)


func _sfx_turn_start() -> PackedFloat32Array:
	var b := _buffer(0.08)
	_tone(b, 0.0, 1300.0, 1300.0, 0.0, 0.8, 0.001, 0.018)
	_tone(b, 0.0, 2600.0, 2600.0, 0.0, 0.25, 0.001, 0.01)
	_noise(b, 0.0, 0.006, 0.2, 0.0, 0.003, NoiseFilter.BAND, 4000.0, 4000.0, 1.5)
	_lowpass(b, 6000.0)
	return _master(b, 0.02)


func _sfx_menu_move() -> PackedFloat32Array:
	var b := _buffer(0.04)
	_tone(b, 0.0, 1800.0, 1800.0, 0.0, 0.8, 0.0005, 0.009)
	_noise(b, 0.0, 0.004, 0.25, 0.0, 0.002, NoiseFilter.BAND, 5000.0, 5000.0, 1.5)
	return _master(b, 0.012)


## Two quick soft square-ish notes (confirm rises, cancel falls).
func _sfx_menu_blip(notes: Array) -> PackedFloat32Array:
	var b := _buffer(0.09)
	for k: int in notes.size():
		var f: float = notes[k]
		var t := 0.035 * k
		_tone(b, t, f, f, 0.0, 0.6, 0.002, 0.03 + 0.01 * k)
		_tone(b, t, f * 3.0, f * 3.0, 0.0, 0.18, 0.002, 0.02)
	_lowpass(b, 5000.0)
	return _master(b, 0.02)


func _sfx_victory() -> PackedFloat32Array:
	var b := _buffer(1.2)
	var notes := [523.25, 659.26, 783.99, 1046.5]
	for k: int in notes.size():
		var last := k == notes.size() - 1
		_pluck(b, 0.11 * k, notes[k], 0.7, 0.45 if last else 0.16)
	_pluck(b, 0.33, 1318.5, 0.35, 0.45)
	_pluck(b, 0.33, 1568.0, 0.3, 0.45)
	for s: int in 8:
		var f := _rng.randf_range(3000.0, 6000.0)
		_tone(b, _rng.randf_range(0.35, 0.8), f, f, 0.0, 0.05, 0.004, 0.08)
	return _master(b, 0.15, 0.002)


func _sfx_defeat() -> PackedFloat32Array:
	var b := _buffer(1.5)
	var notes := [392.0, 311.13, 261.63]
	for k: int in notes.size():
		_soft_note(b, 0.28 * k, notes[k], notes[k], 0.6, 0.3)
	_soft_note(b, 0.84, 130.81, 127.0, 0.55, 0.45)
	_soft_note(b, 0.84, 155.56, 151.0, 0.45, 0.45)
	_lowpass(b, 2500.0)
	return _master(b, 0.2, 0.002)


## Bell-like pluck (victory).
func _pluck(b: PackedFloat32Array, start: float, f: float, amp: float, decay: float) -> void:
	_tone(b, start, f, f, 0.0, amp, 0.004, decay)
	_tone(b, start, f * 2.0, f * 2.0, 0.0, amp * 0.45, 0.004, decay * 0.6)
	_tone(b, start, f * 3.0, f * 3.0, 0.0, amp * 0.25, 0.004, decay * 0.4)
	_tone(b, start, f * 4.0, f * 4.0, 0.0, amp * 0.12, 0.004, decay * 0.3)


## Soft triangle-like note with an optional downward droop (defeat).
func _soft_note(b: PackedFloat32Array, start: float, f0: float, f1: float, amp: float,
		decay: float) -> void:
	var glide := 0.5 if f1 != f0 else 0.0
	_tone(b, start, f0, f1, glide, amp, 0.02, decay)
	_tone(b, start, f0 * 3.0, f1 * 3.0, glide, amp * 0.11, 0.02, decay * 0.7)
	_tone(b, start, f0 * 5.0, f1 * 5.0, glide, amp * 0.04, 0.02, decay * 0.5)


func _sfx_metronome() -> PackedFloat32Array:
	var b := _buffer(0.03)
	_noise(b, 0.0, 0.003, 1.0, 0.0, 0.0008, NoiseFilter.HIGH, 3000.0, 3000.0)
	_tone(b, 0.0, 2800.0, 2800.0, 0.0, 0.7, 0.0, 0.004, HARD)
	_tone(b, 0.0, 1400.0, 1400.0, 0.0, 0.4, 0.0, 0.007, HARD)
	return _master(b, 0.008)
