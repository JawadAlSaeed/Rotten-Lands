class_name AssetLoader
extends RefCounted
## Loads art from paths stored in data files. A missing file gives a visible checkerboard
## placeholder and one warning, never a crash. Replace art by dropping a file with the same name
## into assets/ and opening the editor once so Godot imports it.

static var _fallbacks: Dictionary = {}
static var _warned: Dictionary = {}


## The texture at `path`, or a magenta/black checkerboard if it is missing.
static func texture(path: String, fallback_size: Vector2i = Vector2i(32, 32)) -> Texture2D:
	if not path.is_empty() and ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	if not _warned.has(path):
		_warned[path] = true
		push_warning("AssetLoader: missing texture '%s', using placeholder" % path)
	return fallback_texture(fallback_size)


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
