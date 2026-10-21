extends TestCase
# Texts of the intro, the floor narration and the tutorial: every key used in code exists in
# localization/translations.csv in both languages, and the speaker prefixes match.

const CSV := "res://localization/translations.csv"


func _rows() -> Dictionary:
	var out := {}
	var f := FileAccess.open(CSV, FileAccess.READ)
	if f == null:
		return out
	f.get_csv_line()   # header
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 3 and not row[0].is_empty():
			out[row[0]] = [row[1], row[2]]
	return out


func _used_keys() -> Array[String]:
	var keys: Array[String] = []
	for entry in IntroDirector.LINES:
		keys.append(entry[0])
	keys.append("INTRO_SKIP")
	for entry in Tutorial.STEPS:
		keys.append(entry[0])
	keys.append("TUT_MOUSE")
	var consts := (load("res://scripts/game/arena_gameplay.gd") as GDScript).get_script_constant_map()
	assert_true(consts.has("LORE_KEYS"), "arena_gameplay names its floor narration")
	for k in (consts.get("LORE_KEYS", {}) as Dictionary).values():
		keys.append(k)
	keys.append("ACT_HEAVY_ATTACK")
	return keys


func test_every_key_is_translated() -> void:
	var rows := _rows()
	assert_true(not rows.is_empty(), "the csv loads")
	for key in _used_keys():
		assert_true(rows.has(key), "%s exists" % key)
		if rows.has(key):
			assert_true(not String(rows[key][0]).is_empty() and not String(rows[key][1]).is_empty(), "%s in es and en" % key)


func test_intro_speakers() -> void:
	var rows := _rows()
	for entry in IntroDirector.LINES:
		var es := String(rows.get(entry[0], ["", ""])[0])
		var en := String(rows.get(entry[0], ["", ""])[1])
		var kaelen := int(entry[1]) == 1
		assert_eq(es.begins_with("Kaelen:"), kaelen, "%s es speaker matches its shot" % entry[0])
		assert_eq(en.begins_with("Kaelen:"), kaelen, "%s en speaker matches its shot" % entry[0])
