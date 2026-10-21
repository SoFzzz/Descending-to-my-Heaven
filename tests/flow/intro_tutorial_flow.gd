extends Node
## New run: the intro, then the controls tutorial on the exterior path, with the real autoloads:
##  godot --headless --path . res://tests/flow/intro_tutorial_flow.tscn
## Lines are advanced by emitting the box's `advanced`; the tutorial steps are driven by doing what
## each hint asks. Exits with code 1 if anything fails.

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


func _wait_step(tutorial: Tutorial, key: String, timeout: float) -> bool:
	var t := 0.0
	while tutorial.current_key() != key and t < timeout:
		await _wait(0.1)
		t += 0.1
	return tutorial.current_key() == key


func _run() -> void:
	TranslationServer.set_locale("es")
	GameState.intro_pending = true
	GameState._set_scene_index(0)
	GameState._swap_scene(GameState.scene_for_level(0))
	await _wait(0.6)
	var scene := get_tree().current_scene
	var intro := scene.get_node(^"IntroDirector") as IntroDirector
	var tutorial := scene.get_node(^"Tutorial") as Tutorial
	var player := scene.get(&"player") as Player
	# --- Intro ---
	_check(intro.is_playing(), "intro: plays on a new run")
	_check(not GameState.intro_pending, "intro: consumed (only once)")
	_check(player.is_cutscene() and GameState.cutscene_active, "intro: Kaelen locked, no pause")
	_check(not bool(player.get_node(^"HUD").get(&"visible")), "intro: HUD hidden")
	_check(get_viewport().get_camera_3d().name == "IntroAerial", "intro: aerial shot")
	_check(tutorial.current_key() == "", "tutorial: waits for the intro")
	var box := intro.get(&"_box") as DialogueBox
	var lines := 0
	while intro.is_playing() and lines < 12:
		await _wait(1.0)
		if lines == 3:
			_check(get_viewport().get_camera_3d().name == "IntroClose", "intro: close shot on Kaelen's lines")
			_check(box.current_speaker == &"kaelen", "intro: Kaelen speaks")
		if not is_instance_valid(box):
			break
		box.advanced.emit()
		lines += 1
	await _wait(2.0)
	_check(not intro.is_playing(), "intro: ends after its %d lines (%d presses)" % [IntroDirector.LINES.size(), lines])
	_check(not player.is_cutscene() and not GameState.cutscene_active, "intro: control back")
	_check(bool(player.get_node(^"HUD").get(&"visible")), "intro: HUD back")
	_check(get_viewport().get_camera_3d() == player.get_node(^"CameraRig/SpringArm3D/Camera3D"), "intro: Kaelen's camera")

	# --- Tutorial ---
	_check(await _wait_step(tutorial, "TUT_MOVE", 2.0), "tutorial: first hint is moving")
	var key_label := tutorial.get(&"_key_label") as Label
	_check(key_label.text == "W A S D", "tutorial: shows the current move keys (%s)" % key_label.text)
	player.global_position += player.get_facing() * 3.5
	_check(await _wait_step(tutorial, "TUT_CAMERA", 2.0), "tutorial: moving done")
	var rig := player.get_node(^"CameraRig") as CameraRig
	for i in 10:
		rig.rotate_view(0.12, 0.0)
		await get_tree().process_frame
	_check(await _wait_step(tutorial, "TUT_ROLL", 2.0), "tutorial: camera done")
	player.stamina.current = player.stamina.max_value
	player.try_roll()
	_check(await _wait_step(tutorial, "TUT_ATTACK", 2.0), "tutorial: roll done")
	await _wait(0.8)
	var dummy := tutorial.get(&"_dummy") as Node3D
	_check(dummy != null and is_instance_valid(dummy), "tutorial: training dummy beside the path")
	_check(key_label.text == "Clic izq.", "tutorial: attack shows the mouse binding (%s)" % key_label.text)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	tutorial._input(pad)
	_check(key_label.text == "X / RB", "tutorial: with a gamepad it shows its buttons (%s)" % key_label.text)
	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.pressed = true
	tutorial._input(key)
	var hurt := dummy.get_node(^"Hurtbox") as Hurtbox
	hurt.receive_hit(20, player)
	await _wait(0.1)
	hurt.receive_hit(20, player)
	_check(await _wait_step(tutorial, "TUT_HEAVY", 2.0), "tutorial: attacking done")
	_check(is_instance_valid(dummy), "tutorial: the dummy does not break")
	player.stamina.current = player.stamina.max_value
	player.try_heavy_attack()
	_check(await _wait_step(tutorial, "TUT_LOCK", 2.0), "tutorial: heavy attack done")
	await _wait(Player.HEAVY_END + 0.2)
	player.get_node("LockOn").target = dummy
	Input.action_press(&"move_right")
	_check(await _wait_step(tutorial, "TUT_HEAL", 4.0), "tutorial: lock and strafe done")
	Input.action_release(&"move_right")
	player.get_node("LockOn").target = null
	_check(await _wait_step(tutorial, "TUT_WARN", Tutorial.INFO_TIME + 1.0), "tutorial: heal hint moves on")
	_check(await _wait_step(tutorial, "TUT_GO", Tutorial.INFO_TIME + 1.0), "tutorial: aura hint moves on")
	await _wait(Tutorial.GO_TIME + 0.6)
	_check(tutorial.step >= Tutorial.STEPS.size(), "tutorial: finished")

	# A scene loaded without a new run (tests, debugging) has no intro.
	GameState._swap_scene(GameState.scene_for_level(0))
	await _wait(0.6)
	var again := get_tree().current_scene.get_node(^"IntroDirector") as IntroDirector
	_check(not again.is_playing() and not (get_tree().current_scene.get(&"player") as Player).is_cutscene(), "no intro outside a new run")
	print("FLOW: OK" if _fails == 0 else "FLOW: FAIL (%d)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
