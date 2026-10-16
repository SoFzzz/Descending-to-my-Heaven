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


# --- Avance por pulsación -------------------------------------------------------------------

func _action(action_name: StringName, pressed := true) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = action_name
	e.pressed = pressed
	return e


func test_advance_events() -> void:
	assert_true(TW.is_advance_event(_action(&"attack")), "ataque")
	assert_true(TW.is_advance_event(_action(&"ui_accept")), "aceptar (Enter / Espacio / A)")
	assert_true(not TW.is_advance_event(_action(&"attack", false)), "soltar no avanza")
	assert_true(not TW.is_advance_event(_action(&"roll")), "rodar no avanza")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	assert_true(TW.is_advance_event(click), "clic izquierdo")
	click.button_index = MOUSE_BUTTON_RIGHT
	assert_true(not TW.is_advance_event(click), "clic derecho no")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	assert_true(TW.is_advance_event(enter), "Enter (ui_accept)")


func test_input_lock_window() -> void:
	assert_true(not TW.input_open(100, 250), "dentro del bloqueo")
	assert_true(TW.input_open(250, 250), "al terminar el bloqueo")


func test_press_completes_then_advances_once_and_never_by_time() -> void:
	var tw: Node = TW.new()
	var label := Label.new()
	var counts := {"finished": 0, "advanced": 0}
	tw.finished.connect(func() -> void: counts["finished"] += 1)
	tw.advanced.connect(func() -> void: counts["advanced"] += 1)
	tw.start(label, "Hola mundo, esto es una línea larga que tarda en salir", &"kaelen")
	assert_true(tw.is_revealing(), "revelando")
	assert_true(not tw.press_advance(), "la pulsación dentro del bloqueo se ignora")
	assert_true(tw.is_revealing(), "sigue revelando tras la pulsación bloqueada")
	tw._unlock_at_ms = 0
	assert_true(tw.press_advance(), "1ª pulsación completa la línea")
	assert_eq(counts["finished"], 1, "línea completa")
	assert_eq(counts["advanced"], 0, "completar no avanza")
	assert_eq(label.visible_characters, -1, "todo el texto visible")
	assert_true(not tw.press_advance(), "la misma ráfaga no salta la siguiente línea (bloqueo)")
	assert_eq(counts["advanced"], 0, "sin doble salto")
	tw._process(30.0)   # pasa el tiempo: nada avanza solo
	assert_eq(counts["advanced"], 0, "no avanza por tiempo")
	assert_true(tw.is_waiting(), "espera al jugador")
	tw._unlock_at_ms = 0
	assert_true(tw.press_advance(), "2ª pulsación avanza")
	assert_eq(counts["advanced"], 1, "avanzó una vez")
	tw._unlock_at_ms = 0
	assert_true(not tw.press_advance(), "sin línea no hay nada que avanzar")
	assert_eq(counts["advanced"], 1, "sigue siendo una")
	label.free()
	tw.free()


func test_forced_speaker_and_body_schedule() -> void:
	var plan: Dictionary = TW.build_schedule("Hola", &"elysia")
	var blips: Array = plan["blips"]
	assert_eq(blips.size(), 2, "H y l")
	assert_eq(blips[0]["speaker"], &"elysia", "voz forzada")
	var narr: Dictionary = TW.build_schedule("Hola", &"")
	assert_eq((narr["blips"] as Array).size(), 0, "narrador forzado sin voz")
	var times: PackedFloat32Array = (TW.build_schedule("Kaelen sin prefijo", &"kaelen"))["times"]
	assert_almost(times[0], 1.0 / TW.CHARS_PER_SECOND, 0.0001, "con voz forzada no hay prefijo instantáneo")


# --- Blips audibles ------------------------------------------------------------------------

## Pico y RMS (dBFS) de un stream, mezclando su reproducción real.
func _measure(stream: AudioStream) -> Dictionary:
	var playback := stream.instantiate_playback()
	playback.start(0.0)
	var frames := playback.mix_audio(1.0, 8192)
	var peak := 0.0
	var sum := 0.0
	var count := 0
	for f in frames:
		var v := maxf(absf(f.x), absf(f.y))
		if v > 0.0:
			count += 1
		peak = maxf(peak, v)
		sum += v * v
	var rms := sqrt(sum / maxf(float(count), 1.0))
	return {"frames": count, "peak_db": linear_to_db(maxf(peak, 0.000001)), "rms_db": linear_to_db(maxf(rms, 0.000001))}


func test_blips_are_audible() -> void:
	# Antes: pico -23 dBFS y RMS -34 dBFS, más -12/-15 dB de volumen = -35/-38 dBFS (inaudible).
	for voice in TW.VOICE_DEFS:
		var def: Dictionary = TW.VOICE_DEFS[voice]
		for file_name in def["files"]:
			var stream := load(TW.VOICE_DIR + file_name + ".ogg") as AudioStream
			assert_true(stream != null, "existe %s" % file_name)
			if stream == null:
				continue
			var m := _measure(stream)
			assert_true(m["frames"] > 2000, "%s tiene señal (%d frames)" % [file_name, m["frames"]])
			assert_true(m["peak_db"] >= -6.0 and m["peak_db"] <= -1.0, "%s pico %s dBFS" % [file_name, str(m["peak_db"])])
			assert_true(m["rms_db"] >= -22.0, "%s RMS %s dBFS" % [file_name, str(m["rms_db"])])
			assert_true(m["peak_db"] + float(def["volume_db"]) >= -12.0, "%s: pico ya con el volumen de la voz" % file_name)


func test_blip_bus_exists_and_is_not_muted() -> void:
	var idx := AudioServer.get_bus_index(TW.BLIP_BUS)
	assert_true(idx >= 0, "existe el bus de los blips")
	if idx >= 0:
		assert_true(not AudioServer.is_bus_mute(idx), "bus sin silenciar")
		assert_true(AudioServer.get_bus_volume_db(idx) > -20.0, "bus no atenuado")
