extends GutHookScript
## Fails the run if any test file did not load (GUT otherwise skips a file with a parse error
## and still reports success).

const TEST_DIR := "res://tests/unit"


func run() -> void:
	var expected := _count_tests(TEST_DIR)
	var loaded: int = gut.get_test_collector().scripts.size()
	if loaded != expected:
		push_error("Only %d of %d test scripts loaded. A test file or a script it uses failed to compile." % [loaded, expected])
		set_exit_code(1)


func _count_tests(path: String) -> int:
	var count := 0
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	for file: String in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			count += 1
	for sub: String in dir.get_directories():
		count += _count_tests(path.path_join(sub))
	return count
