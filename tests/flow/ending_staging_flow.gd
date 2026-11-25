extends Node
## The ending's staging, frame by frame, in arena 3 with the real tree:
##  godot --headless --path . res://tests/flow/ending_staging_flow.tscn
## The lines are advanced by emitting the box's `advanced` (the press logic is in dialogue_flow).
## Checks that the procedural moves stay physically sound: Kaelen and Elysia never overlap, Elysia's
## feet never cut into the altar step while she comes down, and the beats happen (tremors, the
## step down, the embrace lean). Exits with code 1 if anything fails.

const MIN_GAP := 0.3         # m between Kaelen and the middle of Elysia's body (they touch in the embrace, never overlap)
const LINE_TIME := 0.7       # s per line (enough for the beats' tweens to run)

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


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Horizontal distance from Kaelen to the middle of Elysia's body (her model origin is not her body).
func _body_gap(director: Node, player: Node3D, elysia: Node3D) -> float:
	var c: Vector3 = director.get(&"_elysia_center_local")
	return _flat(player.global_position, elysia.global_transform * Vector3(c.x, 0.0, c.z))


## Floor point under the middle of her body (her model origin is a metre from it and leaning pivots about the feet).
func _feet(director: Node, elysia: Node3D) -> Vector3:
	var c: Vector3 = director.get(&"_elysia_center_local")
	return elysia.global_transform * Vector3(c.x, 0.0, c.z)


func _run() -> void:
	var scene := (load("res://scenes/levels/arena_3_gameplay.tscn") as PackedScene).instantiate()
	get_tree().current_scene.add_child(scene)
	await _wait(1.5)
	Orchestrator.end_arena()
	var director := scene.get_node(^"EndingDirector")
	var elysia := scene.get_node(^"Level/Ending/Elysia") as Node3D
	var player := scene.get(&"player") as Player
	var room := get_tree().get_first_node_in_group(EndingRoom.GROUP)
	var step := scene.find_child("AltarStep", true, false) as CSGBox3D
	_check(step != null, "altar step found")
	var step_top := step.global_position.y + step.size.y * 0.5
	var edge_z := step.global_position.z + step.size.z * 0.5   # the step's front edge (toward Kaelen)
	scene.set(&"arena_cleared", true)
	director.play()
	await _wait(director.CUT_FADE_OUT + director.CUT_FADE_IN + director.LEAD_IN_TIME + 0.2)
	var box := director.get(&"_box") as DialogueBox
	var min_gap := INF
	var lowest_on_step := INF
	var kicked := false
	var start_pos := elysia.global_position
	for i in director.ENDING_LINES.size():
		var t := 0.0
		while t < LINE_TIME:
			await get_tree().process_frame
			t += get_process_delta_time()
			min_gap = minf(min_gap, _body_gap(director, player, elysia))
			var feet := _feet(director, elysia)   # under her body: her model origin is a metre away from it
			if feet.z < edge_z - 0.02:   # still above the step
				lowest_on_step = minf(lowest_on_step, feet.y - step_top)
			if room and float(room.get(&"_kick_left")) > 0.0:
				kicked = true
		if i < director.ENDING_LINES.size() - 1:
			box.advanced.emit()
	_check(kicked, "tremors shake the room")
	_check(min_gap >= MIN_GAP, "they never overlap (closest %.2f m)" % min_gap)
	_check(lowest_on_step >= -0.03, "Elysia's feet never cut into the step (lowest %.3f m)" % lowest_on_step)
	var end_gap := _body_gap(director, player, elysia)
	_check(absf(end_gap - director.HUG_BODY_GAP) < 0.05, "she ends in Kaelen's arms (%.2f m)" % end_gap)
	var hug := player.find_child("HugArms", true, false) as HugArms
	_check(hug != null and hug.influence > 0.95, "Kaelen's arms are around her")
	_check(absf(_feet(director, elysia).y - player.global_position.y) < 0.1, "she stepped down to Kaelen's floor")
	_check(elysia.global_position.distance_to(start_pos) > 0.8, "she moved from the altar")
	var model := player.get_node(^"Model") as Node3D
	_check(absf(model.rotation.x - director.EMBRACE_LEAN) < 0.02 and absf(elysia.rotation.x - director.EMBRACE_LEAN) < 0.02,
			"both lean into the embrace")
	_check(not (player.get_node(^"Model/Armature/Skeleton3D/RightHand/SwordGrip") as Node3D).visible, "the greatsword is out of her hand")
	print("FLOW: OK" if _fails == 0 else "FLOW: FAIL (%d)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
