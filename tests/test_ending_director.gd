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


func test_total_duration_is_a_minimum_without_waiting_for_the_player() -> void:
	# Ya no es fija: es solo el revelado de las lineas + entrada + abrazo; el resto depende de las pulsaciones.
	var d: float = Director.total_duration()
	assert_true(d >= 25.0 and d <= 120.0, "duracion minima %s fuera de 25-120 s" % str(d))
	assert_true(d > Director.EMBRACE_FADE_TIME + Director.EMBRACE_BLACK_HOLD, "incluye el revelado de los textos")


func test_script_shots_are_valid() -> void:
	assert_true(Director.line_count() >= 14 and Director.line_count() <= 20, "entre 14 y 20 lineas: %d" % Director.line_count())
	for entry in Director.ENDING_LINES:
		assert_true(int(entry[1]) == 1 or int(entry[1]) == 2, "plano 1 o 2 en %s" % entry[0])


func test_play_runs_only_once() -> void:
	# Sin árbol ni nodos: la primera llamada marca _played y termina sin colgarse; la segunda no hace nada.
	var dir: Node = Director.new()
	dir.play()
	assert_true(dir._played, "primera llamada")
	dir.play()
	assert_true(dir._played, "segunda llamada no rompe")
	dir.free()
