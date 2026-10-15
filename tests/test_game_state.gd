extends TestCase
# GameState se instancia directamente (no el autoload). FakeGameState sustituye _change_scene para
# que las pruebas no cambien de escena: solo anota la ruta pedida y simula que la escena existe.

const GameStateScript := preload("res://scripts/game/game_state.gd")


class FakeGameState extends "res://scripts/game/game_state.gd":
	var requested: Array[String] = []

	func _change_scene(path: String) -> bool:
		last_requested_scene = path
		requested.append(path)
		return true


class MissingSceneGameState extends "res://scripts/game/game_state.gd":
	func _change_scene(path: String) -> bool:
		last_requested_scene = path
		return false


func test_max_hp_by_level() -> void:
	var gs: Node = GameStateScript.new()
	gs.current_level = 0
	assert_eq(gs.get_player_max_hp(), 100, "nivel 0")
	gs.current_level = 1
	assert_eq(gs.get_player_max_hp(), 70, "nivel 1")
	gs.current_level = 2
	assert_eq(gs.get_player_max_hp(), 40, "nivel 2")
	gs.free()


func test_level_clamped() -> void:
	var gs: Node = GameStateScript.new()
	gs.current_level = 7
	assert_eq(gs.get_player_max_hp(), 40, "por encima de 2 usa la vida del nivel 2")
	gs.current_level = -3
	assert_eq(gs.get_player_max_hp(), 100, "por debajo de 0 usa la vida del nivel 0")
	gs.free()


func test_new_game_resets_level() -> void:
	var gs := FakeGameState.new()
	gs.current_level = 2
	gs.scene_index = 3
	gs.start_new_game()
	assert_eq(gs.current_level, 0, "nivel")
	assert_eq(gs.scene_index, 0, "escena: exterior")
	assert_eq(gs.last_requested_scene, GameStateScript.LEVEL_SCENES[0], "pide el exterior")
	gs.free()


func test_scene_for_level() -> void:
	var gs: Node = GameStateScript.new()
	for i in GameStateScript.LEVEL_SCENES.size():
		assert_eq(gs.scene_for_level(i), GameStateScript.LEVEL_SCENES[i], "índice %d" % i)
	assert_eq(gs.scene_for_level(-1), "", "índice negativo")
	assert_eq(gs.scene_for_level(4), "", "índice fuera de rango")
	# Relación índice de escena → nivel de vida: exterior y arena 1 = 0, arena 2 = 1, arena 3 = 2.
	assert_eq(gs.level_for_scene(0), 0, "exterior")
	assert_eq(gs.level_for_scene(1), 0, "arena 1")
	assert_eq(gs.level_for_scene(2), 1, "arena 2")
	assert_eq(gs.level_for_scene(3), 2, "arena 3")
	gs.free()


func test_advance_level_sequence() -> void:
	var gs := FakeGameState.new()
	gs.start_new_game()
	var expected_levels := [0, 1, 2]   # tras avanzar a arena 1, 2 y 3
	for step in 3:
		gs.advance_level()
		assert_eq(gs.scene_index, step + 1, "paso %d: escena" % step)
		assert_eq(gs.current_level, expected_levels[step], "paso %d: nivel" % step)
		assert_eq(gs.last_requested_scene, GameStateScript.LEVEL_SCENES[step + 1], "paso %d: ruta" % step)
	# Desde arena 3 no hay más arenas: no rompe, no sale de rango y pide el final (créditos o menú).
	gs.advance_level()
	assert_eq(gs.scene_index, 3, "sigue en arena 3")
	assert_eq(gs.current_level, 2, "nivel sigue en 2")
	assert_true(gs.last_requested_scene == GameStateScript.CREDITS_SCENE \
			or gs.last_requested_scene == GameStateScript.MAIN_MENU_SCENE, "pide el final: %s" % gs.last_requested_scene)
	gs.free()


func test_advance_keeps_state_if_scene_missing() -> void:
	# Si _change_scene no puede cambiar (escena inexistente), el estado no avanza.
	var gs := MissingSceneGameState.new()
	gs.scene_index = 1
	gs.current_level = 0
	gs.advance_level()
	assert_eq(gs.scene_index, 1, "no avanza si la escena no existe")
	assert_eq(gs.current_level, 0, "nivel sin cambios")
	gs.free()


func test_cutscene_blocks_pause() -> void:
	var gs: Node = GameStateScript.new()
	assert_true(gs.can_pause(), "sin secuencia se puede pausar")
	gs.cutscene_active = true
	assert_true(not gs.can_pause(), "durante la secuencia no")
	gs.free()
