extends TestCase
# Partes puras del final (EndingDirector) y su guarda de "una sola vez", sin escena real.

const Director := preload("res://scripts/game/ending_director.gd")


func test_can_start_conditions() -> void:
	assert_true(Director.can_start(false, true, true), "jugador, arena despejada, primera vez")
	assert_true(not Director.can_start(true, true, true), "ya reproducido")
	assert_true(not Director.can_start(false, false, true), "no es Kaelen")
	assert_true(not Director.can_start(false, true, false), "arena sin despejar")


func test_yaw_toward() -> void:
	assert_almost(Director.yaw_toward(Vector3.ZERO, Vector3(0, 0, 2)), 0.0, 0.001, "hacia +Z")
	assert_almost(Director.yaw_toward(Vector3.ZERO, Vector3(0, 0, -2)), PI, 0.001, "hacia -Z")
	assert_almost(Director.yaw_toward(Vector3.ZERO, Vector3(2, 5, 0)), PI / 2.0, 0.001, "ignora la altura")
	assert_almost(Director.yaw_toward(Vector3.ONE, Vector3.ONE, 1.25), 1.25, 0.001, "mismo punto: fallback")


func test_total_duration_in_range() -> void:
	var d: float = Director.total_duration()
	assert_true(d >= 10.0 and d <= 14.0, "duración %s fuera de 10-14 s" % str(d))


func test_play_runs_only_once() -> void:
	# Sin árbol ni nodos: la primera llamada marca _played y termina sin colgarse; la segunda no hace nada.
	var dir: Node = Director.new()
	dir.play()
	assert_true(dir._played, "primera llamada")
	dir.play()
	assert_true(dir._played, "segunda llamada no rompe")
	dir.free()
