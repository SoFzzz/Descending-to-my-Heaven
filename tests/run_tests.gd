extends SceneTree
# Ejecuta todos los métodos test_* de res://tests/test_*.gd. Sale con código 1 si algo falla.
func _init() -> void:
	var total := 0
	var failures := 0
	for file in DirAccess.get_files_at("res://tests"):
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
		var script: GDScript = load("res://tests/" + file)
		for method in script.get_script_method_list():
			if not String(method.name).begins_with("test_"):
				continue
			total += 1
			var case: TestCase = script.new()
			case.call(method.name)
			if case.failed:
				failures += 1
				print("FAIL %s::%s — %s" % [file, method.name, case.message])
	print("%d/%d passed" % [total - failures, total])
	quit(1 if failures > 0 else 0)
