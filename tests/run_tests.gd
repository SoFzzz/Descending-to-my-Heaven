extends SceneTree
# Runs every test_* method of res://tests/test_*.gd. Exits with code 1 if anything fails.
func _init() -> void:
	var total := 0
	var failures := 0
	for file in DirAccess.get_files_at("res://tests"):
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
		var script: GDScript = load("res://tests/" + file)
		# A file that does not compile has no methods: without this it would be skipped silently.
		if script == null or not script.can_instantiate():
			total += 1
			failures += 1
			print("FAIL %s — could not be loaded (parse error)" % file)
			continue
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
