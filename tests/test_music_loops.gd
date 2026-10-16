extends TestCase
# Todas las pistas de música (y la de la pantalla de muerte) están en bucle: el reproductor pasa de
# la última muestra a la primera sin parar, sin silencio ni salto, y nada reinicia la pista a mano.

const TRACKS := [
	"res://assets/audio/bgm/boss1_ancient_creature_battle_loop.ogg",
	"res://assets/audio/bgm/boss2_hellhound_battle_loop.ogg",
	"res://assets/audio/bgm/boss3_battlefield_loop_seamless.ogg",
	"res://assets/audio/bgm/menu_sadness_piano_loop.ogg",
	"res://assets/audio/bgm/ending_celtic_melancholy_loop.ogg",
	"res://assets/audio/bgm/exterior_forest_night.ogg",
	"res://assets/audio/bgm/death_screen_loop.ogg",
]
const MIX_RATE := 44100.0


func test_every_track_has_loop_enabled() -> void:
	for path in TRACKS:
		var stream := load(path) as AudioStreamOggVorbis
		assert_true(stream != null, path)
		if stream == null:
			continue
		assert_true(stream.loop, "loop activado: %s" % path)
		assert_true(stream.get_length() > 10.0, "duración razonable: %s" % path)


func test_tracks_wrap_past_their_end_and_keep_playing() -> void:
	for path in TRACKS:
		var stream := load(path) as AudioStreamOggVorbis
		var pb := stream.instantiate_playback()
		pb.start(0.0)
		# Se salta a 0,25 s del final y se "avanza el tiempo" 0,5 s: pasa el final de la pista.
		pb.seek(stream.get_length() - 0.25)
		var frames := pb.mix_audio(1.0, int(MIX_RATE * 0.5))
		assert_true(pb.is_playing(), "sigue sonando tras su final: %s" % path)
		assert_true(pb.get_loop_count() >= 1, "dio la vuelta: %s" % path)
		assert_true(pb.get_playback_position() < 1.0, "posición vuelve al principio: %s" % path)
		var peak := 0.0
		var max_step := 0.0
		var prev := Vector2.ZERO
		for i in frames.size():
			peak = maxf(peak, absf(frames[i].x))
			if i > 256:   # el arranque tras seek() no cuenta, la costura sí
				max_step = maxf(max_step, absf(frames[i].x - prev.x))
			prev = frames[i]
		assert_true(peak > 0.02, "sin silencio en la costura: %s" % path)
		assert_true(max_step < 0.5, "sin salto brusco en la costura: %s" % path)


func test_nothing_restarts_music_when_a_track_finishes() -> void:
	# El bucle lo hace el propio stream: ni el gestor de audio ni las escenas escuchan `finished`.
	for path in ["res://scripts/audio/audio_manager.gd", "res://scripts/ui/death_screen.gd",
			"res://scripts/game/arena_gameplay.gd", "res://scripts/game/level_gameplay.gd"]:
		var text := FileAccess.get_file_as_string(path)
		assert_true(not text.contains(".finished.connect") and not text.contains("&\"finished\""), path)


func test_audio_manager_uses_single_music_player_when_idle() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var audio := tree.root.get_node_or_null(^"AudioManager")
	if audio == null:
		return
	var stream := load(TRACKS[0]) as AudioStream
	audio.play_music(stream, 0.0)
	audio.play_music(stream, 0.0)
	audio.play_music(load(TRACKS[1]) as AudioStream, 0.0)
	assert_eq(audio.playing_music_count(), 1, "un único reproductor tras cambiar de pista")
	audio.stop_music(0.0)
	assert_eq(audio.playing_music_count(), 0)
