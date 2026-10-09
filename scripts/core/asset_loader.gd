class_name AssetLoader
extends RefCounted
## Loads art from paths stored in data files. A missing file gives a visible checkerboard
## placeholder and one warning, never a crash. Replace art by dropping a file with the same name
## into assets/ (run_game.bat or opening the editor imports it). A dropped-in file that has not
## been imported yet is read straight from disk, so it still shows up in a run from the editor.

static var _fallbacks: Dictionary = {}
static var _raw: Dictionary = {}
static var _warned: Dictionary = {}


## The texture at `path`, or a magenta/black checkerboard of `fallback_size` if it is missing.
static func texture(path: String, fallback_size: Vector2i = Vector2i(32, 32)) -> Texture2D:
	if not path.is_empty():
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				return tex
		var raw := _raw_texture(path)
		if raw != null:
			return raw
	_warn_once(path, "AssetLoader: missing texture '%s', using placeholder" % path)
	return fallback_texture(fallback_size)


## A magenta/black checkerboard (4 px squares), cached per size.
@warning_ignore("integer_division")
static func fallback_texture(size: Vector2i) -> Texture2D:
	if _fallbacks.has(size):
		return _fallbacks[size]
	var img := Image.create(maxi(1, size.x), maxi(1, size.y), false, Image.FORMAT_RGBA8)
	for y: int in img.get_height():
		for x: int in img.get_width():
			var magenta := ((x / 4) + (y / 4)) % 2 == 0
			img.set_pixel(x, y, Color(1, 0, 1) if magenta else Color(0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	_fallbacks[size] = tex
	return tex


## Reads an image file that exists on disk but has no import yet (null if there is none).
static func _raw_texture(path: String) -> Texture2D:
	if _raw.has(path):
		return _raw[path]
	var tex: Texture2D = null
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
			_warn_once(path, "AssetLoader: '%s' is not imported yet; read the raw file" % path)
	_raw[path] = tex
	return tex


static func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(message)
