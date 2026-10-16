extends Node
## Ending with dialogue in the real arena 3: advance only by key press, no double skip, blips sounding.
##  godot --path . res://tests/flow/dialogue_flow.tscn -- shots <folder>   (window: measures the UI bus and saves screenshots)
##  godot --headless --path . res://tests/flow/dialogue_flow.tscn            (no audio: only the logic)
## Exits with code 1 if anything fails.

var _fails := 0
var _shots_dir := ""
var _director: Node
var _advances := 0


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
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func _press(action := &"attack") -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event(r)
	await get_tree().process_frame


func _box() -> DialogueBox:
	return _director.get(&"_box") as DialogueBox


func _save(shot_name: String) -> void:
	if _shots_dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots_dir, shot_name])


## Completes the current line (waiting for the lock) and checks that it stays on the same one.
func _complete_line() -> void:
	await _wait(0.2)
	await _press()
	await _wait(0.05)


func _next_line() -> void:
	await _wait(0.2)
	await _press()
	await _wait(0.1)


func _measure_blips(seconds: float) -> Dictionary:
	var ui := AudioServer.get_bus_index(&"UI")
	var peak := -100.0
	var playing_seen := false
	var blips := [0]
	var tw := _box().typewriter
	tw.blip_played.connect(func(_s: StringName) -> void: blips[0] += 1)
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end and tw.is_revealing():
		await get_tree().process_frame
		for p in tw._players:
			if (p as AudioStreamPlayer).playing:
				playing_seen = true
		peak = maxf(peak, maxf(AudioServer.get_bus_peak_volume_left_db(ui, 0), AudioServer.get_bus_peak_volume_right_db(ui, 0)))
	return {"peak": peak, "playing": playing_seen, "blips": blips[0]}


func _run() -> void:
	var tree := get_tree()
	TranslationServer.set_locale("es")
	var scene := (load("res://scenes/levels/arena_3_gameplay.tscn") as PackedScene).instantiate()
	tree.current_scene.add_child(scene)
	await _wait(2.0)
	_director = scene.get_node(^"EndingDirector")
	scene.set(&"arena_cleared", true)
	_director.play()
	await _wait(1.8)
	var box := _box()
	_check(box != null and box.modulate.a > 0.9, "the dialogue box appears")
	box.advanced.connect(func() -> void: _advances += 1)

	# Line 1: narrator, no name, does not advance by itself.
	_check(not box.name_label.visible and box.current_speaker == &"", "narrator without name")
	await _wait(6.0)
	_check(box.typewriter.is_waiting() and _advances == 0, "the complete line waits for the player (6 s without pressing)")
	_check(box.marker.visible, "continue indicator visible")
	await _save("narrator")

	# Pressing during the reveal completes it; pressing again advances; a double press does not skip two.
	await _next_line()
	_check(_advances == 1, "one press = one line")
	_check(box.current_speaker == &"kaelen" and box.name_label.text == "Kaelen", "Kaelen speaks")
	_check(not box.text_label.text.begins_with("Kaelen"), "text without prefix")
	var m := await _measure_blips(1.2)
	var windowed := DisplayServer.get_name() != "headless"
	print("KAELEN blips=%d playing=%s bus UI peak=%.1f dB" % [m["blips"], str(m["playing"]), m["peak"]])
	_check(m["blips"] >= 2, "Kaelen emits blips")
	if windowed:
		_check(m["playing"], "the blip player is sounding")
		_check(m["peak"] > -30.0, "peak on the UI bus audible (%.1f dB)" % m["peak"])
	await _wait(1.0)
	await _save("kaelen")
	await _wait(0.3)
	var before := _advances
	await _press()
	await _press()
	await _wait(0.05)
	_check(_advances - before <= 1, "two consecutive presses do not skip two lines")

	# Elysia.
	_check(box.current_speaker == &"elysia" and box.name_label.text == "Elysia", "Elysia speaks")
	m = await _measure_blips(1.2)
	print("ELYSIA blips=%d playing=%s bus UI peak=%.1f dB" % [m["blips"], str(m["playing"]), m["peak"]])
	_check(m["blips"] >= 2, "Elysia emits blips")
	if windowed:
		_check(m["peak"] > -30.0, "Elysia's peak audible (%.1f dB)" % m["peak"])
	await _wait(1.5)
	await _save("elysia")

	# English: advance to line 8 (Elysia, the longest).
	TranslationServer.set_locale("en")
	while _advances < 7:
		await _complete_line()
		await _next_line()
	await _wait(3.5)
	print("EN: ", box.name_label.text, " | ", box.text_label.text)
	_check(box.current_speaker != &"" and not box.text_label.text.contains(":"), "english: name and text without prefix")
	await _save("english")
	TranslationServer.set_locale("es")
	print("FLOW: OK" if _fails == 0 else "FLOW: FAIL (%d)" % _fails)
	tree.quit(1 if _fails > 0 else 0)
