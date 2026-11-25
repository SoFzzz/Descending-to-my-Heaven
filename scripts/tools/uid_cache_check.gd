extends SceneTree
## Diagnosis of the local import cache (.godot/imported, not versioned): for every model (.glb,
## .gltf, .fbx) it compares the uid that its imported scene stores for each dependency (the textures it
## extracted) with the uid that dependency has now (.import / .uid). A mismatch makes Godot print
## "In external resource #N, invalid UID ... using text path instead" when loading the model. It
## happens when a texture .import gets a new uid after the model was imported, for example a .import
## restored with `git restore` after Godot regenerated it. The repo is not wrong: reimport the model.
##
##   godot --headless --path . -s res://scripts/tools/uid_cache_check.gd
##
## Exit code 0 if the cache is coherent, 1 if any model is stale (the list and the fix are printed).

const SKIP_DIRS := [".godot", "_source", "export"]


func _initialize() -> void:
	var models: Array[String] = []
	_walk("res://", models)
	var stale := {}   # model -> Array of lines
	var checked := 0
	for model in models:
		for dep in ResourceLoader.get_dependencies(model):
			var parts := dep.split("::")
			if parts.size() < 3 or parts[0].is_empty():
				continue
			checked += 1
			var real_id := ResourceLoader.get_resource_uid(parts[2])
			var real := ResourceUID.id_to_text(real_id) if real_id != ResourceUID.INVALID_ID else "<none>"
			if real != parts[0]:
				if not stale.has(model):
					stale[model] = []
				stale[model].append("    %s: cache %s, now %s" % [parts[2], parts[0], real])
	print("uid_cache_check: %d models, %d dependencies with uid, %d stale models" % [models.size(), checked, stale.size()])
	for model in stale:
		print("STALE %s" % model)
		for line in stale[model]:
			print(line)
	if not stale.is_empty():
		print("Fix: reimport each stale model (editor: select it > Import dock > Reimport), or delete its")
		print("  .godot/imported/<file>-*.scn and .md5 and run: godot --headless --path . --import")
	quit(1 if not stale.is_empty() else 0)


func _walk(dir: String, out: Array[String]) -> void:
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or d in SKIP_DIRS:
			continue
		_walk(dir.path_join(d), out)
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() in ["glb", "gltf", "fbx"]:
			out.append(dir.path_join(f))
