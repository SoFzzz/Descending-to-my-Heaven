extends TestCase
# All music tracks (and the death screen one) loop: the player goes from
# the last sample to the first without stopping, with no silence or jump, and nothing restarts the track by hand.

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
		assert_true(stream.loop, "loop enabled: %s" % path)
		assert_true(stream.get_length() > 10.0, "reasonable duration: %s" % path)


func test_tracks_wrap_past_their_end_and_keep_playing() -> void:
	for path in TRACKS:
		var stream := load(path) as AudioStreamOggVorbis
		var pb := stream.instantiate_playback()
		pb.start(0.0)
		# It seeks to 0.25 s before the end and "advances time" 0.5 s: it passes the end of the track.
		pb.seek(stream.get_length() - 0.25)
		var frames := pb.mix_audio(1.0, int(MIX_RATE * 0.5))
		assert_true(pb.is_playing(), "still playing after its end: %s" % path)
		assert_true(pb.get_loop_count() >= 1, "it wrapped around: %s" % path)
		assert_true(pb.get_playback_position() < 1.0, "position returns to the start: %s" % path)
		var peak := 0.0
		var max_step := 0.0
		var prev := Vector2.ZERO
		for i in frames.size():
			peak = maxf(peak, absf(frames[i].x))
			if i > 256:   # the start after seek() does not count, the seam does
				max_step = maxf(max_step, absf(frames[i].x - prev.x))
			prev = frames[i]
		assert_true(peak > 0.02, "no silence at the seam: %s" % path)
		assert_true(max_step < 0.5, "no abrupt jump at the seam: %s" % path)


func test_nothing_restarts_music_when_a_track_finishes() -> void:
	# The loop is done by the stream itself: neither the audio manager nor the scenes listen to `finished`.
	for path in ["res://scripts/audio/audio_manager.gd", "res://scripts/ui/death_screen.gd",
			"res://scripts/game/arena_gameplay.gd", "res://scripts/game/level_gameplay.gd"]:
		var text := FileAccess.get_file_as_string(path)
		assert_true(not text.contains(".finished.connect") and not text.contains("&\"finished\""), path)

