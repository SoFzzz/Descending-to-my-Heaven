extends Node
## Moving between floors with the real autoloads:
##  godot --headless --path . res://tests/flow/floor_climb_flow.tscn
## 1. Exterior: walking into the temple door, Kaelen keeps walking in (directed) and arena 1 opens.
## 2. Arena 1 arrival: she walks in from the entry landing under the open gate; the boss and the
##    waves wait; the gate rises behind her.
## 3. Boss down: the next floor is preloaded; past the exit gate she climbs the stairs on her own
##    and arena 2 opens with its own arrival walk.
## Exits with code 1 if anything fails.

var _fails := 0


func _ready() -> void:
	_detach.call_deferred()


func _detach() -> void:
	var tree := get_tree()
	reparent(tree.root)
	var placeholder := Node.new()
	tree.root.add_child(placeholder)
	tree.current_scene = placeholder
	_run()


func _check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		_fails += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _wait_until(cond: Callable, timeout: float) -> float:
	var t := 0.0
	while not cond.call() and t < timeout:
		await _wait(0.1)
		t += 0.1
	return t


func _scene() -> Node:
	return get_tree().current_scene


func _player() -> Player:
	return _scene().get_node_or_null(^"Kaelen") as Player if _scene() else null


func _run() -> void:
	await _wait(0.3)
	# 1. Exterior -> temple door.
	GameState._set_scene_index(0)
	GameState._swap_scene(GameState.scene_for_level(0))
	await _wait(1.0)
	_check(GameState._preloading == GameState.scene_for_level(1), "exterior: arena 1 preloads in the background")
	var exit := _scene().get_node("Level/ExitTrigger") as Area3D
	var p := _player()
	var feet := exit.global_position.y - 1.2   # the trigger is a 3 m tall box on the threshold
	p.global_position = Vector3(exit.global_position.x, feet, exit.global_position.z + 3.0)
	p.face_point(exit.global_position)
	await _wait(0.2)
	p.global_position = Vector3(exit.global_position.x, feet, exit.global_position.z + 0.5)
	await _wait(0.3)
	_check(p.is_cutscene() and p.is_scripted_walking(), "exterior: she walks into the temple by herself")
	await _wait_until(func() -> bool: return _scene() != null and _scene().scene_file_path.ends_with("arena_1_gameplay.tscn"), 8.0)
	_check(_scene().scene_file_path.ends_with("arena_1_gameplay.tscn"), "exterior -> arena 1")

	# 2. Arena 1 arrival.
	await _wait(0.1)
	var arena := _scene()
	p = _player()
	var boss := arena.get_node("Boss") as Boss
	_check(arena.get(&"arriving") == true and p.is_cutscene(), "arena 1: arrival walk in progress")
	_check(boss.process_mode == Node.PROCESS_MODE_DISABLED, "arena 1: the boss waits")
	_check(not Orchestrator._active, "arena 1: no waves yet")
	var start := arena.get_node("Level/PlayerStart") as Node3D
	var took := await _wait_until(func() -> bool: return arena.get(&"arriving") == false, 8.0)
	_check(arena.get(&"arriving") == false, "arena 1: arrival done in %.1f s" % took)
	_check(not p.is_cutscene(), "arena 1: control is back")
	var off := Vector2(p.global_position.x - start.global_position.x, p.global_position.z - start.global_position.z).length()
	_check(off < 0.6, "arena 1: she stops at PlayerStart (%.2f m)" % off)
	_check(Orchestrator._active and boss.process_mode != Node.PROCESS_MODE_DISABLED, "arena 1: the fight starts")

	# 3. Boss down -> preload -> climb -> arena 2.
	p._god = true
	boss.health.take_damage(1 << 20)
	await _wait_until(func() -> bool: return arena.get(&"arena_cleared") == true, 15.0)
	_check(arena.get(&"arena_cleared") == true, "arena 1: cleared")
	_check(GameState._preloading == GameState.scene_for_level(2), "arena 1: arena 2 preloads when the boss falls")
	await _wait(arena.GATE_OPEN_DELAY + arena.GATE_OPEN_TIME + 0.3)
	var climb := arena.get_node("Level/ClimbTrigger") as Area3D
	_check(climb != null, "arena 1: climb trigger past the exit gate")
	p.global_position = Vector3(climb.global_position.x, p.global_position.y, climb.global_position.z + 1.5)
	await _wait(0.1)
	p.global_position = Vector3(climb.global_position.x, p.global_position.y, climb.global_position.z)
	await _wait(0.4)
	_check(p.is_cutscene() and p.is_scripted_walking(), "arena 1: she climbs the stairs by herself")
	var y0 := p.global_position.y
	await _wait(2.0)
	_check(p.global_position.y > y0 + 1.0, "arena 1: going up the stairs (%.1f m)" % (p.global_position.y - y0))
	await _wait_until(func() -> bool: return _scene() != null and _scene().scene_file_path.ends_with("arena_2_gameplay.tscn"), 12.0)
	_check(_scene().scene_file_path.ends_with("arena_2_gameplay.tscn"), "arena 1 -> arena 2")
	await _wait(0.1)
	_check(_scene().get(&"arriving") == true, "arena 2: arrival walk")
	await _wait_until(func() -> bool: return _scene().get(&"arriving") == false, 8.0)
	_check(not _player().is_cutscene(), "arena 2: control is back after the arrival")
	_check(not GameState.cutscene_active, "arena 2: pause allowed again")

	# A retry does not replay the arrival.
	GameState.reload_current_arena()
	await _wait_until(func() -> bool: return _player() != null and _player() != p, 5.0)
	await _wait(1.0)
	_check(_scene().get(&"arriving") == false and not _player().is_cutscene(), "retry: no arrival walk")

	print("FLOW: OK" if _fails == 0 else "FLOW: FAIL (%d)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
