extends TestSuite
## Loads every script in the project. A parse error anywhere fails the build,
## including in files no test happens to exercise.


func test_all_scripts_compile() -> void:
	var paths: PackedStringArray = []
	_collect("res://src", paths)
	_collect("res://tools", paths)
	check(paths.size() > 20, "expected to find the project's scripts, found %d" % paths.size())
	for path in paths:
		var script: Variant = load(path)
		check(script is GDScript and (script as GDScript).can_instantiate(), "does not compile: " + path)


func _collect(dir_path: String, into: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path + "/" + sub, into)
	for file in dir.get_files():
		if file.ends_with(".gd"):
			into.append(dir_path + "/" + file)
