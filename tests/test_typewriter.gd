extends TestCase
# Pure Typewriter logic: speaker, letters that sound, pauses and reveal plan.

const TW := preload("res://scripts/ui/typewriter.gd")


func test_speaker_detection() -> void:
	assert_eq(TW.speaker_of("Kaelen: \"Hola\""), &"kaelen", "Kaelen")
	assert_eq(TW.speaker_of("Elysia: \"Hola\""), &"elysia", "Elysia")
	assert_eq(TW.speaker_of("Tres pisos de acero"), &"", "narrator")
	assert_eq(TW.speaker_of("Kaelen sonrió"), &"", "without a colon it is not a speaker")
	assert_eq(TW.prefix_length("Kaelen: \"Hola\""), 8, "prefijo + espacio")
	assert_eq(TW.prefix_length("Narrador"), 0, "without prefix")


func test_voiced_characters() -> void:
	for c in ["a", "Z", "ñ", "é", "7"]:
		assert_true(TW.is_voiced(c), "%s must sound" % c)
	for c in [" ", ".", ",", "!", "?", "…", "\"", "\n", ":"]:
		assert_true(not TW.is_voiced(c), "'%s' must not sound" % c)


func test_blip_every_two_letters() -> void:
	assert_true(TW.should_blip(0) and not TW.should_blip(1) and TW.should_blip(2) and not TW.should_blip(3), "1ª, 3ª, 5ª")


func test_pauses_on_punctuation() -> void:
	assert_almost(TW.pause_after("Hola, mundo", 4), TW.PAUSE_SHORT, 0.0001, "coma")
	assert_almost(TW.pause_after("Hola. Adiós", 4), TW.PAUSE_LONG, 0.0001, "period")
	assert_almost(TW.pause_after("Hola", 1), 0.0, 0.0001, "letra")
	# "..." pauses only after the last period; the closing quote does not cancel it.
	assert_almost(TW.pause_after("a...", 1), 0.0, 0.0001, "1st period of ...")
	assert_almost(TW.pause_after("a...", 3), TW.PAUSE_LONG, 0.0001, "last period")
	assert_almost(TW.pause_after("a.\"", 1), TW.PAUSE_LONG, 0.0001, "period before quote")


func test_schedule_blips_and_speakers() -> void:
	var text := "Kaelen: \"Hola\"\nElysia: \"Ya\""
	var plan: Dictionary = TW.build_schedule(text)
	var blips: Array = plan["blips"]
	# Kaelen: H, l -> 2 blips ("Hola": H(0) o(1) l(2) a(3)); Elysia: Y(0) a(1) -> 1 blip.
	assert_eq(blips.size(), 3, "number of blips")
	assert_eq(blips[0]["speaker"], &"kaelen")
	assert_eq(text[blips[0]["index"]], "H", "first blip on the H")
	assert_eq(text[blips[1]["index"]], "l", "second blip on the l")
	assert_eq(blips[2]["speaker"], &"elysia")
	assert_eq(text[blips[2]["index"]], "Y", "Elysia's blip on the Y")
	assert_eq((plan["times"] as PackedFloat32Array).size(), text.length(), "one instant per character")


func test_narrator_has_no_blips_and_prefix_is_instant() -> void:
	var narr: Dictionary = TW.build_schedule("Tres pisos de acero")
	assert_eq((narr["blips"] as Array).size(), 0, "narrator without voice")
	var plan: Dictionary = TW.build_schedule("Kaelen: Hola")
	var times: PackedFloat32Array = plan["times"]
	assert_almost(times[0], times[7], 0.0001, "the prefix appears at once")
	assert_almost(times[8], 1.0 / TW.CHARS_PER_SECOND, 0.0001, "first letter at the first step")


func test_schedule_speed_and_pauses() -> void:
	var plan: Dictionary = TW.build_schedule("abc")
	assert_almost(plan["duration"], 3.0 / TW.CHARS_PER_SECOND, 0.0001, "30 characters/s")
	var with_pause: Dictionary = TW.build_schedule("ab. cd")
	assert_almost(with_pause["duration"], 6.0 / TW.CHARS_PER_SECOND + TW.PAUSE_LONG, 0.0001, "pause after the period")
	var times: PackedFloat32Array = with_pause["times"]
	assert_true(times[4] - times[2] >= TW.PAUSE_LONG, "the pause delays the next character")


func test_visible_count() -> void:
	var times := PackedFloat32Array([0.125, 0.25, 0.25, 0.5])
	assert_eq(TW.visible_count(times, 0.0), 0)
	assert_eq(TW.visible_count(times, 0.25), 3)
	assert_eq(TW.visible_count(times, 9.0), 4)


func test_default_voices_exist() -> void:
	var voices: Dictionary = TW.default_voices()
	assert_true(voices.has(&"kaelen") and voices.has(&"elysia"), "voices of Kaelen and Elysia")
	assert_true(voices[&"kaelen"]["pitch"] < voices[&"elysia"]["pitch"], "Kaelen deeper")


# --- Advance by key press -------------------------------------------------------------------

func _action(action_name: StringName, pressed := true) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = action_name
	e.pressed = pressed
	return e


func test_advance_events() -> void:
	assert_true(TW.is_advance_event(_action(&"attack")), "attack")
	assert_true(TW.is_advance_event(_action(&"ui_accept")), "accept (Enter / Space / A)")
	assert_true(not TW.is_advance_event(_action(&"attack", false)), "releasing does not advance")
	assert_true(not TW.is_advance_event(_action(&"roll")), "rolling does not advance")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	assert_true(TW.is_advance_event(click), "left click")
	click.button_index = MOUSE_BUTTON_RIGHT
	assert_true(not TW.is_advance_event(click), "right click no")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	assert_true(TW.is_advance_event(enter), "Enter (ui_accept)")


func test_input_lock_window() -> void:
	assert_true(not TW.input_open(100, 250), "inside the lock")
	assert_true(TW.input_open(250, 250), "when the lock ends")


func test_press_completes_then_advances_once_and_never_by_time() -> void:
	var tw: Node = TW.new()
	var label := Label.new()
	var counts := {"finished": 0, "advanced": 0}
	tw.finished.connect(func() -> void: counts["finished"] += 1)
	tw.advanced.connect(func() -> void: counts["advanced"] += 1)
	tw.start(label, "Hola mundo, esto es una línea larga que tarda en salir", &"kaelen")
	assert_true(tw.is_revealing(), "revealing")
	assert_true(not tw.press_advance(), "a press within the lock is ignored")
	assert_true(tw.is_revealing(), "keeps revealing after the blocked press")
	tw._unlock_at_ms = 0
	assert_true(tw.press_advance(), "1st press completes the line")
	assert_eq(counts["finished"], 1, "line complete")
	assert_eq(counts["advanced"], 0, "completing does not advance")
	assert_eq(label.visible_characters, -1, "all the text visible")
	assert_true(not tw.press_advance(), "the same burst does not skip the next line (lock)")
	assert_eq(counts["advanced"], 0, "no double skip")
	tw._process(30.0)   # time passes: nothing advances by itself
	assert_eq(counts["advanced"], 0, "does not advance by time")
	assert_true(tw.is_waiting(), "waits for the player")
	tw._unlock_at_ms = 0
	assert_true(tw.press_advance(), "2nd press advances")
	assert_eq(counts["advanced"], 1, "advanced once")
	tw._unlock_at_ms = 0
	assert_true(not tw.press_advance(), "with no line there is nothing to advance")
	assert_eq(counts["advanced"], 1, "still just one")
	label.free()
	tw.free()


func test_forced_speaker_and_body_schedule() -> void:
	var plan: Dictionary = TW.build_schedule("Hola", &"elysia")
	var blips: Array = plan["blips"]
	assert_eq(blips.size(), 2, "H y l")
	assert_eq(blips[0]["speaker"], &"elysia", "forced voice")
	var narr: Dictionary = TW.build_schedule("Hola", &"")
	assert_eq((narr["blips"] as Array).size(), 0, "forced narrator without voice")
	var times: PackedFloat32Array = (TW.build_schedule("Kaelen sin prefijo", &"kaelen"))["times"]
	assert_almost(times[0], 1.0 / TW.CHARS_PER_SECOND, 0.0001, "with a forced voice there is no instant prefix")


# --- Audible blips ------------------------------------------------------------------------

## Peak and RMS (dBFS) of a stream, mixing its actual playback.
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
	# Before: peak -23 dBFS and RMS -34 dBFS, plus -12/-15 dB volume = -35/-38 dBFS (inaudible).
	for voice in TW.VOICE_DEFS:
		var def: Dictionary = TW.VOICE_DEFS[voice]
		for file_name in def["files"]:
			var stream := load(TW.VOICE_DIR + file_name + ".ogg") as AudioStream
			assert_true(stream != null, "%s exists" % file_name)
			if stream == null:
				continue
			var m := _measure(stream)
			assert_true(m["frames"] > 2000, "%s has signal (%d frames)" % [file_name, m["frames"]])
			assert_true(m["peak_db"] >= -6.0 and m["peak_db"] <= -1.0, "%s peak %s dBFS" % [file_name, str(m["peak_db"])])
			assert_true(m["rms_db"] >= -22.0, "%s RMS %s dBFS" % [file_name, str(m["rms_db"])])
			assert_true(m["peak_db"] + float(def["volume_db"]) >= -12.0, "%s: peak already with the voice volume" % file_name)


func test_blip_bus_exists_and_is_not_muted() -> void:
	var idx := AudioServer.get_bus_index(TW.BLIP_BUS)
	assert_true(idx >= 0, "the blip bus exists")
	if idx >= 0:
		assert_true(not AudioServer.is_bus_mute(idx), "bus not muted")
		assert_true(AudioServer.get_bus_volume_db(idx) > -20.0, "bus not attenuated")


func test_empty_text_completes_at_once() -> void:
	var tw: Node = TW.new()
	var label := Label.new()
	var counts := {"finished": 0}
	tw.finished.connect(func() -> void: counts["finished"] += 1)
	tw.start(label, "", &"kaelen")
	assert_eq(counts["finished"], 1, "empty line finishes immediately")
	assert_true(tw.is_waiting(), "and waits for the player")
	label.free()
	tw.free()


func test_freed_label_does_not_break_the_reveal() -> void:
	var tw: Node = TW.new()
	var label := Label.new()
	tw.start(label, "Hola mundo", &"kaelen")
	label.free()
	tw._process(10.0)
	assert_true(tw.is_waiting(), "the reveal still completes")
	tw.free()

