extends TestCase
# Display settings: window mode, windowed size (multiples of 640x360), VSync and FPS cap are saved,
# loaded and validated. Loose instances are used (outside the tree nothing touches the real window).

const TMP := "user://test_display.cfg"


func _fresh() -> GameSettings:
	var settings := GameSettings.new()
	settings.save_path = TMP
	return settings


func _done(settings: GameSettings) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	TranslationServer.set_locale("es")
	settings.free()


func _write(section_values: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for key: String in section_values:
		cfg.set_value("display", key, section_values[key])
	cfg.save(TMP)


func test_defaults() -> void:
	var settings := _fresh()
	assert_eq(settings.window_mode, GameSettings.MODE_WINDOWED)
	assert_eq(settings.window_scale, 2)
	assert_true(settings.vsync)
	assert_eq(settings.fps_limit, 0)
	_done(settings)


func test_save_and_load_round_trip() -> void:
	var settings := _fresh()
	settings.set_window_mode(GameSettings.MODE_EXCLUSIVE)
	settings.set_window_scale(3)
	settings.set_vsync(false)
	settings.set_fps_limit(60)
	var loaded := _fresh()
	assert_true(loaded.load_settings())
	assert_eq(loaded.window_mode, GameSettings.MODE_EXCLUSIVE)
	assert_eq(loaded.window_scale, 3)
	assert_true(not loaded.vsync)
	assert_eq(loaded.fps_limit, 60)
	loaded.free()
	_done(settings)


func test_corrupt_values_fall_back_to_defaults() -> void:
	_write({"window_mode": 9, "window_scale": 5, "vsync": "yes", "fps_limit": 144})
	var settings := _fresh()
	settings.load_settings()
	assert_eq(settings.window_mode, GameSettings.MODE_WINDOWED)
	assert_eq(settings.window_scale, GameSettings.DEFAULT_SCALE)
	assert_true(settings.vsync)
	assert_eq(settings.fps_limit, 0)
	_write({"window_mode": "full", "window_scale": 2.5, "vsync": 3, "fps_limit": -30})
	settings.load_settings()
	assert_eq(settings.window_mode, GameSettings.MODE_WINDOWED)
	assert_eq(settings.window_scale, GameSettings.DEFAULT_SCALE)
	assert_true(settings.vsync)
	assert_eq(settings.fps_limit, 0)
	_done(settings)


func test_setters_reject_invalid_values() -> void:
	var settings := _fresh()
	settings.set_window_mode(7, false)
	settings.set_window_scale(0, false)
	settings.set_fps_limit(45, false)
	assert_eq(settings.window_mode, GameSettings.MODE_WINDOWED)
	assert_eq(settings.window_scale, GameSettings.DEFAULT_SCALE)
	assert_eq(settings.fps_limit, 0)
	_done(settings)


func test_resolutions_are_integer_multiples_of_the_base() -> void:
	for scale in GameSettings.WINDOW_SCALES:
		var size := GameSettings.scale_size(scale)
		assert_eq(size.x, 640 * scale)
		assert_eq(size.y, 360 * scale)
		assert_eq(size.x * 9, size.y * 16, "16:9 at %dx" % scale)
	assert_eq(GameSettings.scale_size(2), Vector2i(1280, 720))
	assert_eq(GameSettings.scale_size(3), Vector2i(1920, 1080))
	assert_eq(GameSettings.scale_size(4), Vector2i(2560, 1440))


func test_only_scales_that_fit_the_screen_are_offered() -> void:
	assert_eq(GameSettings.scales_that_fit(Vector2i(1920, 1040)), [1, 2] as Array[int])
	assert_eq(GameSettings.scales_that_fit(Vector2i(2560, 1400)), [1, 2, 3] as Array[int])
	assert_eq(GameSettings.scales_that_fit(Vector2i(3840, 2100)), [1, 2, 3, 4] as Array[int])
	assert_eq(GameSettings.scales_that_fit(Vector2i(500, 300)), [1] as Array[int], "1x always available")


func test_toggle_fullscreen() -> void:
	var settings := _fresh()
	settings.toggle_fullscreen()
	assert_eq(settings.window_mode, GameSettings.MODE_FULLSCREEN)
	settings.toggle_fullscreen()
	assert_eq(settings.window_mode, GameSettings.MODE_WINDOWED)
	_done(settings)


func test_display_changed_signal_fires() -> void:
	var settings := _fresh()
	var count := [0]
	settings.display_changed.connect(func() -> void: count[0] += 1)
	settings.set_vsync(false, false)
	settings.set_fps_limit(30, false)
	assert_eq(count[0], 2)
	_done(settings)


func test_display_translations_exist_in_both_languages() -> void:
	var settings := _fresh()
	var keys: Array[String] = ["OPT_TAB_DISPLAY", "DISP_MODE", "DISP_MODE_WINDOWED", "DISP_MODE_FULLSCREEN",
			"DISP_MODE_EXCLUSIVE", "DISP_RESOLUTION", "DISP_VSYNC", "DISP_FPS", "DISP_ON", "DISP_OFF",
			"DISP_UNLIMITED", "DISP_HINT"]
	settings.set_locale("es", false)
	var spanish: Array[String] = []
	for key in keys:
		var text := TranslationServer.translate(StringName(key))
		assert_true(text != key, "es translation for " + key)
		spanish.append(text)
	assert_eq(TranslationServer.translate(&"OPT_TAB_DISPLAY"), "Pantalla")
	settings.set_locale("en", false)
	for i in keys.size():
		var text := TranslationServer.translate(StringName(keys[i]))
		assert_true(text != keys[i], "en translation for " + keys[i])
		assert_true(text != spanish[i] or keys[i] == "DISP_ON", "en differs from es for " + keys[i])
	assert_eq(TranslationServer.translate(&"OPT_TAB_DISPLAY"), "Display")
	_done(settings)
