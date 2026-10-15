extends TestCase
# Lógica pura del Typewriter: hablante, letras que suenan, pausas y plan de revelación.

const TW := preload("res://scripts/ui/typewriter.gd")


func test_speaker_detection() -> void:
	assert_eq(TW.speaker_of("Kaelen: \"Hola\""), &"kaelen", "Kaelen")
	assert_eq(TW.speaker_of("Elysia: \"Hola\""), &"elysia", "Elysia")
	assert_eq(TW.speaker_of("Tres pisos de acero"), &"", "narrador")
	assert_eq(TW.speaker_of("Kaelen sonrió"), &"", "sin dos puntos no es hablante")
	assert_eq(TW.prefix_length("Kaelen: \"Hola\""), 8, "prefijo + espacio")
	assert_eq(TW.prefix_length("Narrador"), 0, "sin prefijo")


func test_voiced_characters() -> void:
	for c in ["a", "Z", "ñ", "é", "7"]:
		assert_true(TW.is_voiced(c), "%s debe sonar" % c)
	for c in [" ", ".", ",", "!", "?", "…", "\"", "\n", ":"]:
		assert_true(not TW.is_voiced(c), "'%s' no debe sonar" % c)


func test_blip_every_two_letters() -> void:
	assert_true(TW.should_blip(0) and not TW.should_blip(1) and TW.should_blip(2) and not TW.should_blip(3), "1ª, 3ª, 5ª")


func test_pauses_on_punctuation() -> void:
	assert_almost(TW.pause_after("Hola, mundo", 4), TW.PAUSE_SHORT, 0.0001, "coma")
	assert_almost(TW.pause_after("Hola. Adiós", 4), TW.PAUSE_LONG, 0.0001, "punto")
	assert_almost(TW.pause_after("Hola", 1), 0.0, 0.0001, "letra")
	# "..." pausa solo tras el último punto; la comilla de cierre no la anula.
	assert_almost(TW.pause_after("a...", 1), 0.0, 0.0001, "1er punto de ...")
	assert_almost(TW.pause_after("a...", 3), TW.PAUSE_LONG, 0.0001, "último punto")
	assert_almost(TW.pause_after("a.\"", 1), TW.PAUSE_LONG, 0.0001, "punto antes de comilla")


func test_schedule_blips_and_speakers() -> void:
	var text := "Kaelen: \"Hola\"\nElysia: \"Ya\""
	var plan: Dictionary = TW.build_schedule(text)
	var blips: Array = plan["blips"]
	# Kaelen: H, l -> 2 blips ("Hola": H(0) o(1) l(2) a(3)); Elysia: Y(0) a(1) -> 1 blip.
	assert_eq(blips.size(), 3, "número de blips")
	assert_eq(blips[0]["speaker"], &"kaelen")
	assert_eq(text[blips[0]["index"]], "H", "primer blip en la H")
	assert_eq(text[blips[1]["index"]], "l", "segundo blip en la l")
	assert_eq(blips[2]["speaker"], &"elysia")
	assert_eq(text[blips[2]["index"]], "Y", "blip de Elysia en la Y")
	assert_eq((plan["times"] as PackedFloat32Array).size(), text.length(), "un instante por carácter")


func test_narrator_has_no_blips_and_prefix_is_instant() -> void:
	var narr: Dictionary = TW.build_schedule("Tres pisos de acero")
	assert_eq((narr["blips"] as Array).size(), 0, "narrador sin voz")
	var plan: Dictionary = TW.build_schedule("Kaelen: Hola")
	var times: PackedFloat32Array = plan["times"]
	assert_almost(times[0], times[7], 0.0001, "el prefijo aparece de golpe")
	assert_almost(times[8], 1.0 / TW.CHARS_PER_SECOND, 0.0001, "primera letra al primer paso")


func test_schedule_speed_and_pauses() -> void:
	var plan: Dictionary = TW.build_schedule("abc")
	assert_almost(plan["duration"], 3.0 / TW.CHARS_PER_SECOND, 0.0001, "30 caracteres/s")
	var with_pause: Dictionary = TW.build_schedule("ab. cd")
	assert_almost(with_pause["duration"], 6.0 / TW.CHARS_PER_SECOND + TW.PAUSE_LONG, 0.0001, "pausa tras el punto")
	var times: PackedFloat32Array = with_pause["times"]
	assert_true(times[4] - times[2] >= TW.PAUSE_LONG, "la pausa retrasa el siguiente carácter")


func test_visible_count() -> void:
	var times := PackedFloat32Array([0.125, 0.25, 0.25, 0.5])
	assert_eq(TW.visible_count(times, 0.0), 0)
	assert_eq(TW.visible_count(times, 0.25), 3)
	assert_eq(TW.visible_count(times, 9.0), 4)


func test_default_voices_exist() -> void:
	var voices: Dictionary = TW.default_voices()
	assert_true(voices.has(&"kaelen") and voices.has(&"elysia"), "voces de Kaelen y Elysia")
	assert_true(voices[&"kaelen"]["pitch"] < voices[&"elysia"]["pitch"], "Kaelen más grave")
