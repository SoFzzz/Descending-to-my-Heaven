extends Node
## The ending moves Kaelen to her mark only while the screen is black: she never travels visibly.
## Runs the real arena 3 and samples her position and the black overlay every frame.
##   godot --headless --path . res://tests/flow/ending_cut_flow.tscn
## Exits with code 1 if anything fails.

var _fails := 0


func _ready() -> void:
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		_fails += 1


func _run() -> void:
	var arena := (load("res://scenes/levels/arena_3_gameplay.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var director: Node = arena.get_node("EndingDirector")
	var player: Player = arena.player
	var mark := arena.get_node("Level/Ending/KaelenEndPoint") as Node3D
	var cam_1 := arena.get_node("Level/Ending/EndingCam1") as Camera3D
	player.global_position = mark.global_position + Vector3(0, 0, 6)   # in the corridor
	var start_pos := player.global_position
	arena.arena_cleared = true
	var placed := {"alpha": -1.0, "pos": Vector3.ZERO}   # a lambda captures plain variables by value
	director.actors_placed.connect(func() -> void:
		placed["alpha"] = director._overlay.modulate.a
		placed["pos"] = player.global_position)
	director.play()

	var moved_while_visible := false
	var first_clear_pos := Vector3.INF
	var seen_black := false
	var frames := 0
	while frames < 600 and first_clear_pos == Vector3.INF:
		await get_tree().process_frame
		frames += 1
		var overlay: ColorRect = director._overlay
		if overlay == null:
			continue
		var alpha := overlay.modulate.a
		if alpha >= 0.999:
			seen_black = true
		# Before the cut is complete, any frame that is not fully black must still show Kaelen at start.
		if float(placed["alpha"]) < 0.0 and alpha < 0.999 and player.global_position.distance_to(start_pos) > 0.01:
			moved_while_visible = true
		if seen_black and alpha < 0.999:
			first_clear_pos = player.global_position

	_check(seen_black, "the screen goes fully black")
	_check(float(placed["alpha"]) >= 0.999, "Kaelen is placed while the overlay is fully black (alpha %.2f)" % placed["alpha"])
	_check(not moved_while_visible, "Kaelen never moves in a frame where the screen is visible")
	_check((placed["pos"] as Vector3).distance_to(mark.global_position) < 0.05, "she is on her mark when placed")
	_check(first_clear_pos != Vector3.INF and first_clear_pos.distance_to(mark.global_position) < 0.05,
			"in the first frame the screen is no longer black she is already on her mark")
	_check(cam_1.current, "the first shot camera is current when the picture returns")
	_check(player.is_cutscene(), "Kaelen is locked")
	_check(not arena.player.get_node(^"HUD").visible, "HUD hidden")
	print("FLOW: OK" if _fails == 0 else "FLOW: FAIL (%d)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
