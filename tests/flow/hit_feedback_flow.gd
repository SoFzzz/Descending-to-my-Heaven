extends Node
## Impact pause and flash with the real tree: run with
##  godot --headless --path . res://tests/flow/hit_feedback_flow.tscn          (checks)
##  godot --path . res://tests/flow/hit_feedback_flow.tscn -- shots <folder>  (additionally, screenshots of the 3 arenas and a flash)
## Exits with code 1 if anything fails.

var _fails := 0
var _shots_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "shots":
		_shots_dir = args[1]
		DirAccess.make_dir_recursive_absolute(_shots_dir)
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
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)   # real clock, not the game's
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func _reset() -> void:
	HitStop.cancel()
	get_tree().paused = false
	Engine.time_scale = 1.0


func _flash_model() -> Node3D:
	var model := Node3D.new()
	model.name = "Model"
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.set_surface_override_material(0, (load("res://assets/materials/psx_base.tres") as ShaderMaterial).duplicate())
	model.add_child(mi)
	return model


func _run() -> void:
	var tree := get_tree()
	# 1. Impact pause: drops and returns by itself in ~60 real ms.
	_check(HitStop.request(tree), "hit-stop accepted")
	_check(is_equal_approx(Engine.time_scale, HitStop.SCALE), "time_scale lowered to %s" % HitStop.SCALE)
	_check(not HitStop.request(tree), "second request ignored (does not stack)")
	await _wait(0.2)
	_check(is_equal_approx(Engine.time_scale, 1.0), "time_scale restored to 1 after ~60 ms")
	_check(not HitStop.is_active(), "hit-stop inactive")

	# 2. Game pause in the middle of the impact.
	HitStop.request(tree)
	tree.paused = true
	await _wait(0.1)
	_check(is_equal_approx(Engine.time_scale, 1.0), "pausing mid-impact restores the time")
	tree.paused = false

	# 3. Scene change in the middle of the impact (GameState._swap_scene leaves 1.0; the driver survives and does not overwrite it).
	HitStop.request(tree)
	Engine.time_scale = 1.0
	await _wait(0.2)
	_check(is_equal_approx(Engine.time_scale, 1.0), "external reset + end of impact: stays at 1")

	# 4. Death (the death screen pauses the tree) in the middle of the impact.
	HitStop.request(tree)
	tree.paused = true
	await _wait(0.15)
	tree.paused = false
	_check(is_equal_approx(Engine.time_scale, 1.0), "pause from death mid-impact restores the time")

	# 5. Many consecutive requests never leave time slow.
	for i in 20:
		HitStop.request(tree)
		await _wait(0.016)
	await _wait(0.2)
	_check(is_equal_approx(Engine.time_scale, 1.0), "20 consecutive hits: time returns to 1")

	# 6. Flash with a real Tween.
	var model := _flash_model()
	add_child(model)
	HitFlash.flash(model, Color.RED)
	_check(HitFlash.amount(model) > 0.9, "flash at maximum when receiving the hit")
	await _wait(0.04)
	var mid := HitFlash.amount(model)
	_check(mid < 1.0 and mid > 0.0, "drops gradually (%.2f)" % mid)
	await _wait(0.3)
	_check(HitFlash.amount(model) == 0.0, "the flash turns off by itself (~0.1 s)")
	HitFlash.flash(model)
	model.queue_free()
	await _wait(0.05)
	_check(not HitStop.is_active(), "no stuck pause")

	# 7. Flash with the real boss and its Hurtbox.
	var boss_scene := load("res://scenes/bosses/boss_bonedragon.tscn") as PackedScene
	var boss := boss_scene.instantiate() as Boss
	add_child(boss)
	var m := boss.get_node("Model")
	var psx := load("res://scenes/levels/psx_test.gd")
	psx.apply_psx(m)
	var hb: Hurtbox = boss.find_children("*", "Hurtbox", true, false)[0]
	hb.receive_hit(5, null)
	_check(HitFlash.amount(m) > 0.9, "a hit on a boss Hurtbox makes it flash")
	await _wait(0.3)
	_check(HitFlash.amount(m) == 0.0, "the boss returns to its color")
	boss.queue_free()

	_reset()
	if _shots_dir != "":
		await _shots()
	print("FLOW: OK" if _fails == 0 else "FLOW: FAIL (%d)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


## Screenshots: each arena with its lighting, and a flash on a minion/boss.
func _shots() -> void:
	for n in [1, 2, 3]:
		var scene := (load("res://scenes/levels/arena_%d_gameplay.tscn" % n) as PackedScene).instantiate()
		get_tree().current_scene.add_child(scene)
		await _wait(2.0)
		_save("arena_%d_mood" % n)
		# Boss flash and defeated boss tint.
		var boss := scene.get_node_or_null(^"Boss") as Boss
		if boss:
			var hb: Hurtbox = boss.find_children("*", "Hurtbox", true, false)[0]
			HitFlash.flash(boss.get_node("Model"), HitFlash.COLOR_ENEMY, 2.0)
			await _wait(0.2)
			_save("arena_%d_flash" % n)
		(scene.get_node("Mood") as ArenaMood).show_defeat_tint()
		await _wait(3.0)
		_save("arena_%d_defeated_tint" % n)
		scene.queue_free()
		await _wait(0.5)


func _save(shot_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_shots_dir, shot_name])
