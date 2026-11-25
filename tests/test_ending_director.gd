extends TestCase
# Pure parts of the ending (EndingDirector) and its "only once" guard, without a real scene.

const Director := preload("res://scripts/game/ending_director.gd")


func test_can_start_conditions() -> void:
	assert_true(Director.can_start(false, true, true), "player, cleared arena, first time")
	assert_true(not Director.can_start(true, true, true), "already played")
	assert_true(not Director.can_start(false, false, true), "not Kaelen")
	assert_true(not Director.can_start(false, true, false), "arena not cleared")


func test_yaw_toward() -> void:
	assert_almost(Director.yaw_toward(Vector3.ZERO, Vector3(0, 0, 2)), 0.0, 0.001, "toward +Z")
	assert_almost(Director.yaw_toward(Vector3.ZERO, Vector3(0, 0, -2)), PI, 0.001, "toward -Z")
	assert_almost(Director.yaw_toward(Vector3.ZERO, Vector3(2, 5, 0)), PI / 2.0, 0.001, "ignores height")
	assert_almost(Director.yaw_toward(Vector3.ONE, Vector3.ONE, 1.25), 1.25, 0.001, "same point: fallback")


func test_total_duration_is_a_minimum_without_waiting_for_the_player() -> void:
	# No longer fixed: it is only the line reveal + entrance + embrace; the rest depends on the key presses.
	var d: float = Director.total_duration()
	assert_true(d >= 25.0 and d <= 120.0, "minimum duration %s outside 25-120 s" % str(d))
	assert_true(d > Director.EMBRACE_FADE_TIME + Director.EMBRACE_BLACK_HOLD, "includes the text reveal")


func test_script_shots_are_valid() -> void:
	assert_true(Director.line_count() >= 14 and Director.line_count() <= 20, "between 14 and 20 lines: %d" % Director.line_count())
	for entry in Director.ENDING_LINES:
		assert_true(int(entry[1]) == 1 or int(entry[1]) == 2, "shot 1 or 2 in %s" % entry[0])


func test_play_runs_only_once() -> void:
	# Without a tree or nodes: the first call sets _played and finishes without hanging; the second does nothing.
	var dir: Node = Director.new()
	dir.play()
	assert_true(dir._played, "first call")
	dir.play()
	assert_true(dir._played, "second call does not break")
	dir.free()


func test_every_line_has_its_own_moving_shot() -> void:
	assert_eq(Director.SHOT_KINDS.size(), Director.line_count(), "one shot kind per line")
	# Consecutive lines never reuse the same shot kind, so the picture changes with each line.
	for i in range(1, Director.SHOT_KINDS.size()):
		assert_true(Director.SHOT_KINDS[i] != Director.SHOT_KINDS[i - 1], "line %d changes the shot" % i)


func test_shots_look_at_the_speaker_and_drift() -> void:
	var k := Vector3(0, 1.55, 0)
	var e := Vector3(0, 1.42, -3.5)   # Elysia on the altar, Kaelen on her mark
	for kind in [&"face", &"side", &"over", &"low"]:
		for who in [&"kaelen", &"elysia"]:
			var target := e if who == &"elysia" else k
			var t0: Transform3D = Director.shot_transform(kind, 0.0, k, e, who, Vector3(3.5, 2.2, 3.0))
			var forward := -t0.basis.z
			var to_target := (target - t0.origin).normalized()
			assert_true(forward.dot(to_target) > 0.9, "%s shot looks at the speaker %s" % [kind, who])
			var t1: Transform3D = Director.shot_transform(kind, 5.0, k, e, who, Vector3(3.5, 2.2, 3.0))
			assert_true(t0.origin.distance_to(t1.origin) > 0.05, "%s shot drifts" % kind)


func test_feet_stop_keeps_the_gap_on_the_line_to_kaelen() -> void:
	var kaelen := Vector3(0, 0, 0)
	var feet := Vector3(0, 0.5, -3)
	var stop: Vector3 = Director.feet_stop(feet, kaelen, 1.35)
	assert_almost(stop.z, -1.35, 0.001, "stops 1.35 m from Kaelen")
	assert_almost(stop.x, 0.0, 0.001, "on the line between them")
	assert_true(Director.feet_stop(Vector3(0, 0, -1.0), kaelen, 1.35).is_equal_approx(Vector3(0, 0, -1.0)), "already closer: stays")
