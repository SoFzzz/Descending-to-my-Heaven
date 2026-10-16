extends TestCase
# Caja de diálogo del final: hablante, nombre y texto sin prefijo, en español e inglés.

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
	assert_eq(k["body"], "Hola, Elysia.", "sin el prefijo")
	var e := DialogueBox.parse_line("Elysia: Te esperaba.")
	assert_eq(e["speaker"], &"elysia")
	assert_eq(e["body"], "Te esperaba.")
	var n := DialogueBox.parse_line("El suelo tiembla.")
	assert_eq(n["speaker"], &"", "narrador")
	assert_eq(n["name"], "", "sin nombre")
	assert_eq(n["body"], "El suelo tiembla.")


func test_colors_differ_per_speaker() -> void:
	var k := DialogueBox.color_for(&"kaelen")
	var e := DialogueBox.color_for(&"elysia")
	assert_true(k != e, "colores distintos")
	assert_true(k.r > k.b, "Kaelen rojizo")
	assert_true(e.b > e.r, "Elysia azulada")


func _check_script(locale: String) -> void:
	var speakers := {}
	for entry in Director.ENDING_LINES:
		var raw := Director.localized(entry[0])
		assert_true(raw != entry[0], "%s traducida al %s" % [entry[0], locale])
		var parsed := DialogueBox.parse_line(raw)
		var body: String = parsed["body"]
		assert_true(not body.is_empty(), "%s con texto" % entry[0])
		assert_true(not body.contains("Kaelen:") and not body.contains("Elysia:"), "%s no muestra el prefijo" % entry[0])
		assert_true(body.length() <= 110, "%s cabe en 2 líneas (%d)" % [entry[0], body.length()])
		if parsed["speaker"] != &"":
			assert_eq(parsed["name"], String(parsed["speaker"]).capitalize(), "nombre mostrado de %s" % entry[0])
		speakers[parsed["speaker"]] = true
	assert_true(speakers.has(&"kaelen") and speakers.has(&"elysia") and speakers.has(&""), "hablan Kaelen, Elysia y el narrador")


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
	assert_eq(es, en, "el mismo hablante en ambos idiomas")
