extends GutTest
## Asset files (DESIGN 5.3): every sprite, portrait and sound path in the data points at a file
## that exists, and the import settings keep pixel art sharp (no VRAM compression, no mipmaps, not
## even when a texture is used in 3D) and sounds crisp (WAV kept as PCM).
## Until the placeholder generator has created res://assets these tests are pending, not failing.

const DATA_DIR := "res://data"
const ASSETS_DIR := "res://assets"
const SPRITES_DIR := "res://assets/sprites"
const SFX_DIR := "res://assets/audio"
const NO_ASSETS := "res://assets does not exist yet (run tools/gen_placeholders.gd); asset checks skipped"


func _assets_missing() -> bool:
	if DirAccess.dir_exists_absolute(ASSETS_DIR):
		return false
	pending(NO_ASSETS)
	return true


func _files(dir_path: String, suffix: String) -> PackedStringArray:
	var files := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return files
	for file: String in dir.get_files():
		if file.ends_with(suffix):
			files.append(dir_path.path_join(file))
	for sub: String in dir.get_directories():
		files.append_array(_files(dir_path.path_join(sub), suffix))
	return files


## Every file path stored in the data: String properties exported as file paths, found by walking
## each resource and its sub-resources. Returns {path: "where it was found"}.
func _data_paths() -> Dictionary:
	var found := {}
	for file: String in _files(DATA_DIR, ".tres"):
		var res := ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_IGNORE)
		_collect_paths(res, file, found, {})
	return found


func _collect_paths(value: Variant, where: String, found: Dictionary, visited: Dictionary) -> void:
	if value is Array:
		for item: Variant in value:
			_collect_paths(item, where, found, visited)
		return
	if not value is Resource:
		return
	var res := value as Resource
	if visited.has(res.get_instance_id()):
		return
	visited[res.get_instance_id()] = true
	for prop: Dictionary in res.get_property_list():
		if not (int(prop.usage) & PROPERTY_USAGE_STORAGE):
			continue
		var prop_name := String(prop.name)
		var prop_value: Variant = res.get(prop_name)
		var hint := int(prop.hint)
		if typeof(prop_value) == TYPE_STRING and (hint == PROPERTY_HINT_FILE_PATH or hint == PROPERTY_HINT_FILE):
			if not String(prop_value).is_empty():
				found[String(prop_value)] = "%s (%s)" % [where, prop_name]
		elif prop_value is Resource or prop_value is Array:
			if prop_name != "script":
				_collect_paths(prop_value, where, found, visited)


func test_data_paths_are_plain_res_paths_under_assets() -> void:
	# Needs no asset files: DESIGN 5.3 stores raw res:// paths (never uid://) so files can be
	# replaced by name.
	var paths := _data_paths()
	assert_gt(paths.size(), 10, "found the asset paths in the data")
	for path: String in paths:
		assert_true(path.begins_with(ASSETS_DIR + "/"), "%s: %s is a res://assets/... path" % [paths[path], path])
		assert_true(path.get_extension() in ["png", "wav", "ogg", "mp3"], "%s: %s has an asset extension" % [paths[path], path])


func test_every_data_path_exists() -> void:
	if _assets_missing():
		return
	var paths := _data_paths()
	# 3 characters and 1 enemy with a sprite and a portrait each, plus the sound cues.
	assert_gt(paths.size(), 10, "found the asset paths in the data")
	for path: String in paths:
		assert_true(ResourceLoader.exists(path), "%s points at %s, which does not exist" % [paths[path], path])


func test_sprite_imports_keep_pixel_art_sharp() -> void:
	if _assets_missing():
		return
	var pngs := _files(SPRITES_DIR, ".png")
	assert_gt(pngs.size(), 0, "found sprites under %s" % SPRITES_DIR)
	for png: String in pngs:
		assert_true(FileAccess.file_exists(png + ".import"), "%s has been imported" % png)
	var imports := _files(SPRITES_DIR, ".import")
	for path: String in imports:
		var cfg := ConfigFile.new()
		assert_eq(cfg.load(path), OK, "%s parses" % path)
		if String(cfg.get_value("remap", "importer", "")) != "texture":
			continue
		assert_eq(int(cfg.get_value("params", "compress/mode", -1)), 0, "%s: compress/mode must be 0 (lossless, no VRAM compression)" % path)
		assert_eq(int(cfg.get_value("params", "detect_3d/compress_to", -1)), 0, "%s: detect_3d/compress_to must be 0 (stay uncompressed in 3D)" % path)
		assert_eq(cfg.get_value("params", "mipmaps/generate", true), false, "%s: mipmaps/generate must be false" % path)


func test_sound_imports_keep_pcm() -> void:
	if _assets_missing():
		return
	var imports := _files(SFX_DIR, ".wav.import")
	assert_gt(imports.size(), 0, "found imported sounds under %s" % SFX_DIR)
	for path: String in imports:
		var cfg := ConfigFile.new()
		assert_eq(cfg.load(path), OK, "%s parses" % path)
		assert_eq(int(cfg.get_value("params", "compress/mode", -1)), 0, "%s: compress/mode must be 0 (PCM)" % path)
