extends Node
## Flujo real de muerte con los autoloads (GameState, AudioManager, Events): ejecutar con
##   godot --headless --path . res://tests/flow/death_flow.tscn          (comprobaciones)
##   godot --path . res://tests/flow/death_flow.tscn -- shots <carpeta>  (además, capturas)
## Sale con código 1 si algo falla.

var _fails := 0
var _shots_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "shots":
		_shots_dir = args[1]
		DirAccess.make_dir_recursive_absolute(_shots_dir)
	_detach.call_deferred()


## Se saca de la escena actual (que GameState libera al cambiar de escena) y empieza el flujo.
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
	await get_tree().create_timer(seconds, true, false, true).timeout


func _scene() -> Node:
	return get_tree().current_scene


func _audio_playing() -> int:
	return AudioManager.playing_music_count()


func _load_arena(index: int) -> void:
	GameState._set_scene_index(index)
	GameState._swap_scene(GameState.scene_for_level(index))
	await _wait(1.0)


func _kill() -> void:
	var player: Player = _scene().get_node("Kaelen")
	player.health.take_damage(9999)


func _shot(name: String) -> void:
	if _shots_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots_dir, name])


func _run() -> void:
	await _wait(0.5)
	# 1. Entrar a la arena 2 con vida y estamina llenas, HUD incluido.
	await _load_arena(2)
	var level := _scene()
	var player: Player = level.get_node("Kaelen")
	_check(level.scene_file_path.ends_with("arena_2_gameplay.tscn"), "arena 2 cargada")
	_check(player.health.current == player.health.max_value and player.health.max_value == 70, "vida llena (70)")
	_check(is_equal_approx(player.stamina.current, player.stamina.max_value), "estamina llena")
	_check(is_equal_approx(player.get_node("HUD/Bars/Frame/HealthBar").value, 1.0), "HUD vida llena")
	_check(is_equal_approx(player.get_node("HUD/Bars/Frame/StaminaBar").value, 1.0), "HUD estamina llena")
	# 2. Música del jefe suena; Kaelen muere.
	level._on_boss_state_changed(Boss.State.CHASE)
	await _wait(2.5)
	_check(_audio_playing() == 1 and AudioManager.get_current_music() == level.boss_music, "suena la música del jefe")
	_kill()
	await _wait(0.8)
	_check(_audio_playing() == 0, "tras morir se para la música del jefe (reproductores: %d)" % _audio_playing())
	_check(level.get_node("Ambience").playing == false, "se para el ambiente")
	level._on_boss_state_changed(Boss.State.ACTIVE)   # el jefe detecta a Kaelen caída
	await _wait(0.3)
	_check(_audio_playing() == 0, "el jefe no reinicia su música con Kaelen muerta")
	_check(not GameState.death_screen.buttons_visible(), "los botones aún no aparecen")
	await _wait(2.4)
	var ds: Node = GameState.death_screen
	_check(ds.is_active() and ds.buttons_visible(), "aparece la pantalla de muerte con botones")
	_check(get_tree().paused, "juego en pausa")
	var retry: Button = ds.get_node("%Retry")
	_check(get_viewport().gui_get_focus_owner() == retry, "foco inicial en Reintentar")
	_check(ds.get_node("Root/Column/Center/Panel/Box").get_child_count() == 3, "3 botones")
	await _shot("death_screen")
	# Navegación con teclado: ui_down mueve el foco.
	var down := InputEventAction.new()
	down.action = &"ui_down"
	down.pressed = true
	Input.parse_input_event(down)
	await _wait(0.2)
	_check(get_viewport().gui_get_focus_owner() == ds.get_node("%Menu"), "ui_down pasa a Volver al menú")
	await _shot("death_screen_menu_focus")
	# 3. Reintentar tres veces seguidas.
	for attempt in 3:
		retry = GameState.death_screen.get_node("%Retry")
		retry.pressed.emit()
		await _wait(2.2)
		level = _scene()
		player = level.get_node("Kaelen")
		_check(level.scene_file_path.ends_with("arena_2_gameplay.tscn"), "reintento %d: misma arena" % attempt)
		_check(player.health.current == 70 and is_equal_approx(player.stamina.current, player.stamina.max_value), "reintento %d: vida y estamina llenas" % attempt)
		_check(not get_tree().paused and not GameState.death_screen.is_active(), "reintento %d: sin pausa ni pantalla" % attempt)
		level._on_boss_state_changed(Boss.State.CHASE)   # el jefe detecta a Kaelen
		await _wait(2.5)
		_check(_audio_playing() == 1 and AudioManager.get_current_music() == level.boss_music, "reintento %d: un único reproductor con la música del jefe" % attempt)
		_kill()
		await _wait(0.8)
		_check(_audio_playing() == 0, "reintento %d: silencio tras morir" % attempt)
		await _wait(2.6)
	# 4. Volver al menú.
	GameState.death_screen.get_node("%Menu").pressed.emit()
	await _wait(3.0)
	_check(_scene().scene_file_path.ends_with("main_menu.tscn"), "vuelve al menú principal")
	_check(_audio_playing() == 1 and AudioManager.get_current_music() != null, "suena la música del menú (reproductores: %d)" % _audio_playing())
	_check(not get_tree().paused, "menú sin pausa")
	# 5. Entrar a la arena 3 desde cero: vida 40 llena.
	await _load_arena(3)
	player = _scene().get_node("Kaelen")
	_check(player.health.current == 40 and player.health.max_value == 40, "arena 3: vida llena (40)")
	print("FLOW: %s" % ("OK" if _fails == 0 else "%d fallos" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)
