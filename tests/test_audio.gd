extends TestCase
# Pruebas de la lógica de audio que no necesita dispositivo de sonido ni escenas (Tarea 17).

const AM := preload("res://scripts/audio/audio_manager.gd")


func test_pitch_for_stays_within_variation() -> void:
	assert_almost(AM.pitch_for(0.1, 0.0), 1.0)
	assert_almost(AM.pitch_for(0.1, 1.0), 1.1)
	assert_almost(AM.pitch_for(0.1, -1.0), 0.9)
	assert_almost(AM.pitch_for(0.1, 5.0), 1.1, 0.001, "roll fuera de rango se recorta")
	assert_almost(AM.pitch_for(-0.5, 1.0), 1.0, 0.001, "variación negativa = sin variación")


func test_music_drops_10_db_when_paused() -> void:
	assert_almost(AM.pause_target_db(true), -10.0)
	assert_almost(AM.pause_target_db(false), 0.0)


func test_clear_duck_restores_the_music_bus() -> void:
	var audio := AM.new()
	var idx := AudioServer.get_bus_index(&"Music")
	var before := AudioServer.get_bus_volume_db(idx)
	audio._set_duck(-7.0)
	assert_almost(audio.get_duck_db(), -7.0)
	assert_almost(AudioServer.get_bus_volume_db(idx), -7.0, 0.01, "the duck lowers the music bus")
	audio.clear_duck()
	assert_almost(audio.get_duck_db(), 0.0)
	assert_almost(AudioServer.get_bus_volume_db(idx), 0.0, 0.01, "clear_duck gives the level back")
	AudioServer.set_bus_volume_db(idx, before)
	audio.free()


func test_pool_slot_prefers_free_player() -> void:
	var busy: Array[bool] = [true, true, false, true]
	assert_eq(AM.pick_pool_slot(busy, 0), 2)
	assert_eq(AM.pick_pool_slot(busy, 3), 2, "desde el cursor, dando la vuelta")


func test_pool_slot_reuses_oldest_when_all_busy() -> void:
	var busy: Array[bool] = [true, true, true]
	assert_eq(AM.pick_pool_slot(busy, 1), 1)
	assert_eq(AM.pick_pool_slot(busy, 4), 1, "el cursor da la vuelta")
	var empty: Array[bool] = []
	assert_eq(AM.pick_pool_slot(empty, 0), -1)


func test_footsteps_follow_speed() -> void:
	# A 5 m/s se recorren FOOTSTEP_STRIDE m en 0,4 s.
	var acc := 0.0
	var steps := 0
	for i in 60:   # 1 s a 60 fps
		acc = Player.footstep_progress(acc, 5.0, 1.0 / 60.0, true)
		if Player.footstep_due(acc):
			acc -= Player.FOOTSTEP_STRIDE
			steps += 1
	assert_eq(steps, 2)
	# El doble de velocidad, el doble de pasos.
	acc = 0.0
	steps = 0
	for i in 60:
		acc = Player.footstep_progress(acc, 10.0, 1.0 / 60.0, true)
		if Player.footstep_due(acc):
			acc -= Player.FOOTSTEP_STRIDE
			steps += 1
	assert_eq(steps, 5)


func test_no_footsteps_when_not_walking_or_too_slow() -> void:
	assert_almost(Player.footstep_progress(1.5, 5.0, 0.1, false), 0.0, 0.0001, "rodando/atacando reinicia")
	assert_almost(Player.footstep_progress(1.5, 0.2, 0.1, true), 0.0, 0.0001, "casi parada reinicia")
	assert_true(not Player.footstep_due(Player.FOOTSTEP_STRIDE - 0.01))
	assert_true(Player.footstep_due(Player.FOOTSTEP_STRIDE))


func test_impact_sound_plays_once_per_activation() -> void:
	var hb := Hitbox.new()
	hb.activate()
	assert_true(hb.claim_impact_sound(), "primera hurtbox tocada")
	assert_true(not hb.claim_impact_sound(), "segunda hurtbox del mismo golpe")
	hb.deactivate()
	hb.activate()
	assert_true(hb.claim_impact_sound(), "golpe nuevo")
	hb.free()


func test_impact_stream_depends_on_surface() -> void:
	var hb := Hitbox.new()
	var flesh := AudioStreamWAV.new()
	var metal := AudioStreamWAV.new()
	assert_true(hb.impact_stream_for(&"flesh") == null)
	hb.sfx_impact = flesh
	assert_true(hb.impact_stream_for(&"flesh") == flesh)
	assert_true(hb.impact_stream_for(&"metal") == flesh, "sin variante metálica usa la normal")
	hb.sfx_impact_metal = metal
	assert_true(hb.impact_stream_for(&"metal") == metal)
	assert_true(hb.impact_stream_for(&"bone") == flesh)
	hb.free()


func test_randomizers_have_their_variants() -> void:
	var grunt := load("res://resources/audio/monster_grunt.tres") as AudioStreamRandomizer
	assert_true(grunt != null)
	assert_eq(grunt.streams_count, 6)
	assert_eq(grunt.playback_mode, AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS)
	for path in ["sword_swing", "sword_hit", "sword_block"]:
		var r := load("res://resources/audio/%s.tres" % path) as AudioStreamRandomizer
		assert_true(r != null and r.streams_count == 3, path)


func test_ghidorah_beam_has_fire_and_impact_sounds() -> void:
	var beam := load("res://resources/attacks/ghidorah_beam.tres") as BossAttack
	assert_true(beam != null and beam.sfx_active != null and beam.sfx_hit != null)


func _wav_stats(path: String) -> Dictionary:
	# Pico y RMS (lineal 0..1) del WAV de 16 bits original (cabecera de 44 bytes; el recurso importado va comprimido).
	var data := FileAccess.get_file_as_bytes(path)
	var count := (data.size() - 44) / 2
	var peak := 0.0
	var sum := 0.0
	for i in count:
		var v := absf(float(data.decode_s16(44 + i * 2)) / 32768.0)
		peak = maxf(peak, v)
		sum += v * v
	return {"peak": peak, "rms": sqrt(sum / maxf(count, 1.0))}


func test_ui_sounds_exist_and_are_clearly_audible() -> void:
	var sounds := {
		"ui_move": [0.1, 0.5], "ui_confirm": [0.2, 0.8], "ui_back": [0.15, 0.6],
		"pause_open": [0.2, 0.8], "pause_close": [0.2, 0.8],
	}
	for name: String in sounds:
		var path := "res://assets/audio/sfx/ui/%s.wav" % name
		assert_true(ResourceLoader.exists(path), "%s existe" % name)
		var stream := load(path) as AudioStreamWAV
		assert_true(stream != null, "%s se carga como WAV" % name)
		if stream == null:
			continue
		var length := stream.get_length()
		assert_true(length >= sounds[name][0] and length <= sounds[name][1], "%s dura %.2f s (corto)" % [name, length])
		var stats := _wav_stats(path)
		assert_true(float(stats["peak"]) >= 0.4, "%s pico %.2f >= -8 dBFS" % [name, stats["peak"]])
		assert_true(float(stats["rms"]) >= 0.08, "%s RMS %.3f >= -22 dBFS" % [name, stats["rms"]])


func test_ui_manager_streams_point_to_those_files_and_volume_is_not_muted() -> void:
	assert_true(AM.UI_MOVE.resource_path.ends_with("ui_move.wav"))
	assert_true(AM.UI_CONFIRM.resource_path.ends_with("ui_confirm.wav"))
	assert_true(AM.UI_BACK.resource_path.ends_with("ui_back.wav"))
	assert_true(AM.UI_VOLUME_DB > -6.0, "el volumen del reproductor de interfaz no esta atenuado")
	assert_true(AudioServer.get_bus_index(&"UI") >= 0, "el bus UI existe")
	assert_true(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"UI")) > -6.0, "el bus UI no esta atenuado")
	assert_true(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"UI")), "el bus UI no esta silenciado")


func test_menu_theme_is_monochrome_skin04() -> void:
	var theme := load("res://scenes/ui/menu_theme.tres") as Theme
	var colors: Array[Color] = [theme.get_color(&"font_color", &"Button"), theme.get_color(&"font_color", &"Label"),
			theme.get_color(&"font_color", &"TitleLabel")]
	for c in colors:
		assert_true(maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b)) < 0.1, "texto gris/blanco, no morado: %s" % c)
		assert_true(c.v > 0.8, "texto claro")
