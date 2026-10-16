extends TestCase
# GameState is instantiated directly (not the autoload). FakeGameState replaces _change_scene so
# tests do not change scene: it only records the requested path and simulates that the scene exists.

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
	assert_eq(gs.get_player_max_hp(), 100, "level 0")
	gs.current_level = 1
	assert_eq(gs.get_player_max_hp(), 70, "level 1")
	gs.current_level = 2
	assert_eq(gs.get_player_max_hp(), 40, "level 2")
	gs.free()


func test_level_clamped() -> void:
	var gs: Node = GameStateScript.new()
	gs.current_level = 7
	assert_eq(gs.get_player_max_hp(), 40, "above 2 it uses the level 2 health")
	gs.current_level = -3
	assert_eq(gs.get_player_max_hp(), 100, "below 0 it uses the level 0 health")
	gs.free()


func test_new_game_resets_level() -> void:
	var gs := FakeGameState.new()
	gs.current_level = 2
	gs.scene_index = 3
	assert_true(gs.start_new_game(), "reports that the change started")
	assert_eq(gs.current_level, 0, "level")
	assert_eq(gs.scene_index, 0, "scene: exterior")
	assert_eq(gs.last_requested_scene, GameStateScript.LEVEL_SCENES[0], "asks for the exterior")
	gs.free()


func test_scene_for_level() -> void:
	var gs: Node = GameStateScript.new()
	for i in GameStateScript.LEVEL_SCENES.size():
		assert_eq(gs.scene_for_level(i), GameStateScript.LEVEL_SCENES[i], "index %d" % i)
	assert_eq(gs.scene_for_level(-1), "", "negative index")
	assert_eq(gs.scene_for_level(4), "", "index out of range")
	# Scene index -> life level relation: exterior and arena 1 = 0, arena 2 = 1, arena 3 = 2.
	assert_eq(gs.level_for_scene(0), 0, "exterior")
	assert_eq(gs.level_for_scene(1), 0, "arena 1")
	assert_eq(gs.level_for_scene(2), 1, "arena 2")
	assert_eq(gs.level_for_scene(3), 2, "arena 3")
	gs.free()


func test_advance_level_sequence() -> void:
	var gs := FakeGameState.new()
	gs.start_new_game()
	var expected_levels := [0, 1, 2]   # after advancing to arena 1, 2 and 3
	for step in 3:
		gs.advance_level()
		assert_eq(gs.scene_index, step + 1, "step %d: scene" % step)
		assert_eq(gs.current_level, expected_levels[step], "step %d: level" % step)
		assert_eq(gs.last_requested_scene, GameStateScript.LEVEL_SCENES[step + 1], "step %d: path" % step)
	# From arena 3 there are no more arenas: it does not break, does not go out of range and asks for the ending (credits or menu).
	gs.advance_level()
	assert_eq(gs.scene_index, 3, "stays in arena 3")
	assert_eq(gs.current_level, 2, "level stays at 2")
	assert_true(gs.last_requested_scene == GameStateScript.CREDITS_SCENE \
			or gs.last_requested_scene == GameStateScript.MAIN_MENU_SCENE, "asks for the ending: %s" % gs.last_requested_scene)
	gs.free()


func test_advance_keeps_state_if_scene_missing() -> void:
	# If _change_scene cannot change (nonexistent scene), the state does not advance.
	var gs := MissingSceneGameState.new()
	gs.scene_index = 1
	gs.current_level = 0
	gs.advance_level()
	assert_eq(gs.scene_index, 1, "does not advance if the scene does not exist")
	assert_eq(gs.current_level, 0, "level unchanged")
	gs.free()


func test_cutscene_blocks_pause() -> void:
	var gs: Node = GameStateScript.new()
	assert_true(gs.can_pause(), "without a sequence it can be paused")
	gs.cutscene_active = true
	assert_true(not gs.can_pause(), "not during the sequence")
	gs.free()
