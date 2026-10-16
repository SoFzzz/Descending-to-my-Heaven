extends TestCase
# Ending dialogue box: speaker, name and text without prefix, in Spanish and English.

const Director := preload("res://scripts/game/ending_director.gd")


func _with_locale(locale: String, check: Callable) -> void:
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale(locale)
	check.call()
	TranslationServer.set_locale(previous)


func test_parse_line() -> void:
	var k := DialogueBox.parse_line("Kaelen: Hola, Elysia.")
	assert_eq(k["speaker"], &"kaelen")
	assert_eq(k["name"], "Kaelen")
	assert_eq(k["body"], "Hola, Elysia.", "without the prefix")
	var e := DialogueBox.parse_line("Elysia: Te esperaba.")
	assert_eq(e["speaker"], &"elysia")
	assert_eq(e["body"], "Te esperaba.")
	var n := DialogueBox.parse_line("El suelo tiembla.")
	assert_eq(n["speaker"], &"", "narrator")
	assert_eq(n["name"], "", "without name")
	assert_eq(n["body"], "El suelo tiembla.")


func test_colors_differ_per_speaker() -> void:
	var k := DialogueBox.color_for(&"kaelen")
	var e := DialogueBox.color_for(&"elysia")
	assert_true(k != e, "different colors")
	assert_true(k.r > k.b, "Kaelen reddish")
	assert_true(e.b > e.r, "Elysia bluish")


func _check_script(locale: String) -> void:
	var speakers := {}
	for entry in Director.ENDING_LINES:
		var raw := Director.localized(entry[0])
		assert_true(raw != entry[0], "%s translated to %s" % [entry[0], locale])
		var parsed := DialogueBox.parse_line(raw)
		var body: String = parsed["body"]
		assert_true(not body.is_empty(), "%s has text" % entry[0])
		assert_true(not body.contains("Kaelen:") and not body.contains("Elysia:"), "%s does not show the prefix" % entry[0])
		assert_true(body.length() <= 110, "%s fits in 2 lines (%d)" % [entry[0], body.length()])
		if parsed["speaker"] != &"":
			assert_eq(parsed["name"], String(parsed["speaker"]).capitalize(), "displayed name of %s" % entry[0])
		speakers[parsed["speaker"]] = true
	assert_true(speakers.has(&"kaelen") and speakers.has(&"elysia") and speakers.has(&""), "Kaelen, Elysia and the narrator speak")


func test_script_in_spanish_and_english() -> void:
	_with_locale("es", _check_script.bind("es"))
	_with_locale("en", _check_script.bind("en"))


func test_speaker_matches_in_both_languages() -> void:
	var es: Array = []
	var en: Array = []
	_with_locale("es", func() -> void:
		for entry in Director.ENDING_LINES:
			es.append(DialogueBox.parse_line(Director.localized(entry[0]))["speaker"]))
	_with_locale("en", func() -> void:
		for entry in Director.ENDING_LINES:
			en.append(DialogueBox.parse_line(Director.localized(entry[0]))["speaker"]))
	assert_eq(es, en, "same speaker in both languages")
