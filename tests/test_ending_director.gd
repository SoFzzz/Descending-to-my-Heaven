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
