extends Node
## Final con dialogo en la arena 3 real: avance solo por pulsacion, sin doble salto, blips sonando.
##   godot --path . res://tests/flow/dialogue_flow.tscn -- shots <carpeta>   (ventana: mide el bus UI y guarda capturas)
##   godot --headless --path . res://tests/flow/dialogue_flow.tscn            (sin audio: solo la logica)
## Sale con codigo 1 si algo falla.

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


## Completa la linea actual (esperando el bloqueo) y comprueba que sigue en la misma.
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
	_check(box != null and box.modulate.a > 0.9, "la caja de dialogo aparece")
	box.advanced.connect(func() -> void: _advances += 1)

	# Linea 1: narrador, sin nombre, no avanza sola.
	_check(not box.name_label.visible and box.current_speaker == &"", "narrador sin nombre")
	await _wait(6.0)
	_check(box.typewriter.is_waiting() and _advances == 0, "la linea completa espera al jugador (6 s sin pulsar)")
	_check(box.marker.visible, "indicador de continuar visible")
	await _save("narrador")

	# Pulsar durante el revelado completa; pulsar de nuevo avanza; doble pulsacion no salta dos.
	await _next_line()
	_check(_advances == 1, "una pulsacion = una linea")
	_check(box.current_speaker == &"kaelen" and box.name_label.text == "Kaelen", "habla Kaelen")
	_check(not box.text_label.text.begins_with("Kaelen"), "texto sin prefijo")
	var m := await _measure_blips(1.2)
	var windowed := DisplayServer.get_name() != "headless"
	print("KAELEN blips=%d playing=%s bus UI peak=%.1f dB" % [m["blips"], str(m["playing"]), m["peak"]])
	_check(m["blips"] >= 2, "Kaelen emite blips")
	if windowed:
		_check(m["playing"], "el reproductor de blips esta sonando")
		_check(m["peak"] > -30.0, "pico en el bus UI audible (%.1f dB)" % m["peak"])
	await _wait(1.0)
	await _save("kaelen")
	await _wait(0.3)
	var before := _advances
	await _press()
	await _press()
	await _wait(0.05)
	_check(_advances - before <= 1, "dos pulsaciones seguidas no saltan dos lineas")

	# Elysia.
	_check(box.current_speaker == &"elysia" and box.name_label.text == "Elysia", "habla Elysia")
	m = await _measure_blips(1.2)
	print("ELYSIA blips=%d playing=%s bus UI peak=%.1f dB" % [m["blips"], str(m["playing"]), m["peak"]])
	_check(m["blips"] >= 2, "Elysia emite blips")
	if windowed:
		_check(m["peak"] > -30.0, "pico de Elysia audible (%.1f dB)" % m["peak"])
	await _wait(1.5)
	await _save("elysia")

	# Ingles: avanzar hasta la linea 8 (Elysia, la mas larga).
	TranslationServer.set_locale("en")
	while _advances < 7:
		await _complete_line()
		await _next_line()
	await _wait(3.5)
	print("EN: ", box.name_label.text, " | ", box.text_label.text)
	_check(box.current_speaker != &"" and not box.text_label.text.contains(":"), "ingles: nombre y texto sin prefijo")
	await _save("english")
	TranslationServer.set_locale("es")
	print("FLOW: OK" if _fails == 0 else "FLOW: FAIL (%d)" % _fails)
	tree.quit(1 if _fails > 0 else 0)
