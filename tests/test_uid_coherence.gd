extends TestCase
# UID coherence of the project files: every `ext_resource` with a uid in a .tscn/.tres points to the
# uid its target really has (.import / .uid / scene header), and no two files share a uid. A broken
# pair makes Godot print "invalid UID ... using text path instead" when loading. Only versioned files are
# read; a stale local import cache (.godot/imported) is checked by scripts/tools/uid_cache_check.gd.

const SKIP_DIRS := [".godot", "_source", "export"]
const EXT_RE := "\\[ext_resource[^\\]]*\\]"


func _walk(dir: String, exts: Array, out: Array[String]) -> void:
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or d in SKIP_DIRS:
			continue
		_walk(dir.path_join(d), exts, out)
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() in exts:
			out.append(dir.path_join(f))


func _attr(tag: String, key: String) -> String:
	var re := RegEx.create_from_string(key + "=\"([^\"]*)\"")
	var m := re.search(tag)
	return m.get_string(1) if m else ""


func test_ext_resource_uids_match_their_targets() -> void:
	var files: Array[String] = []
	_walk("res://", ["tscn", "tres"], files)
	assert_true(files.size() > 50, "scenes and resources found (%d)" % files.size())
	var re := RegEx.create_from_string(EXT_RE)
	var checked := 0
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for m in re.search_all(text):
			var tag := m.get_string()
			var uid := _attr(tag, "uid")
			var target := _attr(tag, "path")
			if uid.is_empty() or target.is_empty():
				continue
			checked += 1
			var real_id := ResourceLoader.get_resource_uid(target)
			var real := ResourceUID.id_to_text(real_id) if real_id != ResourceUID.INVALID_ID else "<none>"
			assert_eq(real, uid, "%s -> %s" % [path, target])
	assert_true(checked > 0, "uids checked (%d)" % checked)


func test_no_two_files_share_a_uid() -> void:
	var files: Array[String] = []
	_walk("res://", ["import", "uid"], files)
	var owner := {}
	for path in files:
		var uid := ""
		var text := FileAccess.get_file_as_string(path)
		if path.ends_with(".uid"):
			uid = text.strip_edges()
		else:
			uid = _attr(text, "uid")
			assert_true(not uid.is_empty(), "%s has no uid" % path)
		if uid.is_empty():
			continue
		assert_true(not owner.has(uid), "%s repeats the uid of %s" % [path, owner.get(uid, "")])
		owner[uid] = path

