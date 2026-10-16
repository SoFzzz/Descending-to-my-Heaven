extends TestCase
# Ajustes del jugador (GameSettings): guardar / cargar, reasignar controles, volumen en el bus,
# idioma y utilidades de la cámara. Las pruebas corren antes de que exista el árbol, así que se usan
# instancias sueltas con un archivo temporal; se restauran el InputMap, el idioma y los buses al terminar.

const TMP := "user://test_settings.cfg"
const ED := preload("res://scripts/game/ending_director.gd")


func _fresh() -> GameSettings:
	InputMap.load_from_project_settings()
	var settings := GameSettings.new()
	settings.save_path = TMP
	return settings


func _cleanup(settings: GameSettings) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	InputMap.load_from_project_settings()
	settings.reset_audio_defaults()
	settings.apply_volumes()
	TranslationServer.set_locale("es")
	settings.free()


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func test_rebind_keyboard_replaces_the_slot() -> void:
	var settings := _fresh()
	assert_eq(settings.rebind(&"roll", GameSettings.SLOT_KB, _key(KEY_SHIFT)), &"")
	var events := settings.slot_events(&"roll", GameSettings.SLOT_KB)
	assert_eq(events.size(), 1)
	assert_eq((events[0] as InputEventKey).physical_keycode, KEY_SHIFT)
	assert_true(InputMap.event_is_action(_key(KEY_SHIFT), &"roll"), "the InputMap uses the new key")
	assert_true(not InputMap.event_is_action(_key(KEY_SPACE), &"roll"), "the old key no longer rolls")
	assert_true(settings.slot_events(&"roll", GameSettings.SLOT_PAD).size() >= 1, "the gamepad slot is untouched")
	_cleanup(settings)


func test_rebind_to_a_used_key_swaps_the_actions() -> void:
	var settings := _fresh()
	var swapped := settings.rebind(&"roll", GameSettings.SLOT_KB, _key(KEY_Q))   # Q was lock-on
	assert_eq(swapped, &"lock_on")
	assert_true(InputMap.event_is_action(_key(KEY_Q), &"roll"))
	assert_true(not InputMap.event_is_action(_key(KEY_Q), &"lock_on"))
	assert_true(InputMap.event_is_action(_key(KEY_SPACE), &"lock_on"), "lock-on takes the old roll key")
	_cleanup(settings)


func test_rebind_gamepad_button_and_axes_are_fixed() -> void:
	var settings := _fresh()
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_LEFT_SHOULDER
	assert_eq(settings.rebind(&"roll", GameSettings.SLOT_PAD, pad), &"")
	assert_eq(settings.slot_text(&"roll", GameSettings.SLOT_PAD), "LB")
	assert_eq(settings.rebind(&"move_left", GameSettings.SLOT_PAD, pad), &"!", "the sticks cannot be reassigned")
	assert_eq(settings.rebind(&"roll", GameSettings.SLOT_KB, pad), &"!", "a button does not fit the keyboard slot")
	assert_eq(settings.slot_text(&"move_left", GameSettings.SLOT_PAD), "LS")
	_cleanup(settings)


func test_capture_filters_events() -> void:
	var release := _key(KEY_F)
	release.pressed = false
	assert_true(GameSettings.capture(release) == null, "releases are ignored")
	var echo := _key(KEY_F)
	echo.echo = true
	assert_true(GameSettings.capture(echo) == null, "echoes are ignored")
	assert_true(GameSettings.capture(_key(KEY_F)) is InputEventKey)
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 1.0
	assert_true(GameSettings.capture(stick) == null, "sticks are not bindable")
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 0.3
	assert_true(GameSettings.capture(trigger) == null, "a half-pressed trigger does not count")
	trigger.axis_value = 1.0
	var captured := GameSettings.capture(trigger)
	assert_true(captured != null and GameSettings.slot_of(captured) == GameSettings.SLOT_PAD)
	assert_eq(GameSettings.event_name(captured), "RT")


func test_save_and_load_round_trip() -> void:
	var settings := _fresh()
	settings.set_volume(&"Music", 0.35, false)
	settings.set_look_sensitivity(1.5, false)
	settings.set_locale("en", false)
	settings.rebind(&"attack", GameSettings.SLOT_KB, _key(KEY_F))
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_LEFT_SHOULDER
	settings.rebind(&"roll", GameSettings.SLOT_PAD, pad)
	assert_true(settings.save_settings(), "the file is written")
	assert_true(FileAccess.file_exists(TMP))
	# New session: project defaults in the InputMap and a new object that loads the file.
	InputMap.load_from_project_settings()
	TranslationServer.set_locale("es")
	var loaded := GameSettings.new()
	loaded.save_path = TMP
	assert_true(loaded.load_settings(), "the file is read")
	assert_almost(loaded.get_volume(&"Music"), 0.35)
	assert_almost(loaded.look_sensitivity, 1.5)
	assert_eq(loaded.locale, "en")
	assert_eq(TranslationServer.get_locale(), "en", "the language is applied on load")
	assert_true(InputMap.event_is_action(_key(KEY_F), &"attack"), "the keyboard binding is restored")
	assert_eq(loaded.slot_text(&"roll", GameSettings.SLOT_PAD), "LB")
	loaded.free()
	_cleanup(settings)


func test_missing_file_keeps_project_defaults() -> void:
	var settings := _fresh()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	assert_true(not settings.load_settings())
	assert_eq(settings.locale, "es")
	assert_almost(settings.get_volume(&"Master"), 1.0)
	assert_true(InputMap.event_is_action(_key(KEY_SPACE), &"roll"))
	_cleanup(settings)


func test_restore_default_bindings() -> void:
	var settings := _fresh()
	settings.rebind(&"roll", GameSettings.SLOT_KB, _key(KEY_Z))
	settings.restore_default_bindings()
	assert_true(InputMap.event_is_action(_key(KEY_SPACE), &"roll"))
	assert_true(not InputMap.event_is_action(_key(KEY_Z), &"roll"))
	_cleanup(settings)


func test_volume_is_applied_to_the_bus() -> void:
	var settings := _fresh()
	var idx := AudioServer.get_bus_index(&"SFX")
	assert_true(idx >= 0, "the SFX bus exists")
	settings.set_volume(&"SFX", 0.5, false)
	assert_almost(AudioServer.get_bus_volume_db(idx), linear_to_db(0.5), 0.01)
	settings.set_volume(&"SFX", 0.0, false)
	assert_almost(AudioServer.get_bus_volume_db(idx), -80.0, 0.01, "0 is silence")
	settings.set_volume(&"SFX", 7.0, false)
	assert_almost(settings.get_volume(&"SFX"), 1.0, 0.0001, "clamped to 1")
	assert_almost(AudioServer.get_bus_volume_db(idx), 0.0, 0.01)
	_cleanup(settings)


func test_language_changes_what_tr_returns() -> void:
	var settings := _fresh()
	settings.set_locale("en", false)
	assert_eq(TranslationServer.translate(&"MENU_START"), "Start")
	assert_eq(TranslationServer.translate(&"DEATH_TITLE"), "YOU DIED")
	assert_eq(TranslationServer.translate(&"DEATH_RETRY"), "Retry")
	settings.set_locale("es", false)
	assert_eq(TranslationServer.translate(&"MENU_START"), "Iniciar")
	assert_eq(TranslationServer.translate(&"DEATH_TITLE"), "HAS MUERTO")
	assert_eq(TranslationServer.translate(&"DEATH_MENU"), "Volver al menú")
	assert_eq(TranslationServer.translate(&"DEATH_QUIT"), "Salir del juego")
	settings.set_locale("xx", false)
	assert_eq(settings.locale, "es", "an unknown language falls back to Spanish")
	_cleanup(settings)


func test_every_key_has_both_languages() -> void:
	var file := FileAccess.open("res://localization/translations.csv", FileAccess.READ)
	assert_true(file != null, "the CSV exists")
	if file == null:
		return
	assert_eq(file.get_csv_line(), PackedStringArray(["keys", "es", "en"]))
	var count := 0
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < 3:
			continue
		count += 1
		assert_true(not row[1].is_empty() and not row[2].is_empty(), "%s has es and en" % row[0])
	assert_true(count > 60, "the table has the game texts")


func test_ending_texts_keep_the_speaker_prefix_in_both_languages() -> void:
	for loc in ["es", "en"]:
		TranslationServer.set_locale(loc)
		var lines: PackedStringArray = ED.localized(ED.SHOT_2_TEXT).split("\n")
		assert_eq(lines.size(), 2, "two lines in " + loc)
		assert_eq(Typewriter.speaker_of(lines[0]), &"kaelen", loc)
		assert_eq(Typewriter.speaker_of(lines[1]), &"elysia", loc)
		assert_eq(ED.localized(ED.SHOT_1_TEXT).split("\n").size(), 2, "narration in " + loc)
	TranslationServer.set_locale("es")


func test_credits_section_titles_are_translated() -> void:
	TranslationServer.set_locale("en")
	var out := Credits.localize("Intro\n\n\nEquipo\n\nAutor: X. Licencia: CC0.\nAutor y licencia por confirmar.")
	assert_true("Team" in out, "section title")
	assert_true("Author: X. License: CC0." in out, "tokens")
	assert_true("Author and license to be confirmed." in out)
	TranslationServer.set_locale("es")
	assert_eq(Credits.localize("Equipo\nAutor: X"), "Equipo\nAutor: X", "Spanish is unchanged")


func test_camera_stick_curve_keeps_direction_and_softens() -> void:
	assert_eq(CameraRig.stick_look(Vector2.ZERO), Vector2.ZERO)
	assert_almost(CameraRig.stick_look(Vector2(0.5, 0.0)).x, 0.25)
	assert_almost(CameraRig.stick_look(Vector2(0.0, -1.0)).y, -1.0)
