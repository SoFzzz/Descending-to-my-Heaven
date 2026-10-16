extends Node
## Real death flow with the autoloads (GameState, AudioManager, Events): run with
##  godot --headless --path . res://tests/flow/death_flow.tscn          (checks)
##  godot --path . res://tests/flow/death_flow.tscn -- shots <folder>  (additionally, screenshots)
## Exits with code 1 if anything fails.

var _fails := 0
var _shots_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "shots":
		_shots_dir = args[1]
		DirAccess.make_dir_recursive_absolute(_shots_dir)
	_detach.call_deferred()


## It is taken out of the current scene (which GameState frees on scene change) and the flow starts.
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


## Waits until `cond` is true or `timeout` s pass (real time). Fade-outs are tweens stepped per frame, so
## a fixed sleep can fire before the tween's last step after a long frame.
func _wait_until(cond: Callable, timeout: float) -> void:
	var waited := 0.0
	while not cond.call() and waited < timeout:
		await _wait(0.05)
		waited += 0.05


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
	# 1. Enter arena 2 with full health and stamina, HUD included.
	await _load_arena(2)
	var level := _scene()
	var player: Player = level.get_node("Kaelen")
	_check(level.scene_file_path.ends_with("arena_2_gameplay.tscn"), "arena 2 loaded")
	_check(player.health.current == player.health.max_value and player.health.max_value == 70, "full health (70)")
	_check(is_equal_approx(player.stamina.current, player.stamina.max_value), "stamina full")
	_check(is_equal_approx(player.get_node("HUD/Bars/Frame/HealthBar").value, 1.0), "HUD full health")
	_check(is_equal_approx(player.get_node("HUD/Bars/Frame/StaminaBar").value, 1.0), "HUD stamina full")
	# 2. Boss music plays; Kaelen dies.
	level._on_boss_state_changed(Boss.State.CHASE)
	await _wait(2.5)
	_check(_audio_playing() == 1 and AudioManager.get_current_music() == level.boss_music, "the boss music plays")
	_kill()
	await _wait_until(func() -> bool: return _audio_playing() == 0, 3.0)
	_check(_audio_playing() == 0, "after dying the boss music stops (players: %d)" % _audio_playing())
	_check(level.get_node("Ambience").playing == false, "the ambience stops")
	level._on_boss_state_changed(Boss.State.ACTIVE)   # the boss detects the fallen Kaelen
	await _wait(0.3)
	_check(_audio_playing() == 0, "the boss does not restart its music with Kaelen dead")
	_check(not GameState.death_screen.buttons_visible(), "the buttons do not appear yet")
	await _wait(2.4)
	var ds: Node = GameState.death_screen
	_check(ds.is_active() and ds.buttons_visible(), "the death screen appears with buttons")
	_check(get_tree().paused, "game paused")
	var retry: Button = ds.get_node("%Retry")
	_check(get_viewport().gui_get_focus_owner() == retry, "initial focus on Retry")
	_check(ds.get_node("Root/Center/Panel/Box").get_child_count() == 3, "3 buttons")
	await _shot("death_screen")
	# Keyboard navigation: ui_down moves the focus.
	var down := InputEventAction.new()
	down.action = &"ui_down"
	down.pressed = true
	Input.parse_input_event(down)
	await _wait(0.2)
	_check(get_viewport().gui_get_focus_owner() == ds.get_node("%Menu"), "ui_down moves to Back to menu")
	await _shot("death_screen_menu_focus")
	# 3. Retry three times in a row.
	for attempt in 3:
		retry = GameState.death_screen.get_node("%Retry")
		retry.pressed.emit()
		await _wait(2.2)
		level = _scene()
		player = level.get_node("Kaelen")
		_check(level.scene_file_path.ends_with("arena_2_gameplay.tscn"), "retry %d: same arena" % attempt)
		_check(player.health.current == 70 and is_equal_approx(player.stamina.current, player.stamina.max_value), "retry %d: health and stamina full" % attempt)
		_check(not get_tree().paused and not GameState.death_screen.is_active(), "retry %d: no pause or screen" % attempt)
		level._on_boss_state_changed(Boss.State.CHASE)   # the boss detects Kaelen
		await _wait(2.5)
		_check(_audio_playing() == 1 and AudioManager.get_current_music() == level.boss_music, "retry %d: a single player with the boss music" % attempt)
		_kill()
		await _wait_until(func() -> bool: return _audio_playing() == 0, 3.0)
		_check(_audio_playing() == 0, "retry %d: silence after dying" % attempt)
		await _wait(2.6)
	# 4. Back to the menu.
	GameState.death_screen.get_node("%Menu").pressed.emit()
	await _wait(3.0)
	_check(_scene().scene_file_path.ends_with("main_menu.tscn"), "returns to the main menu")
	_check(_audio_playing() == 1 and AudioManager.get_current_music() != null, "the menu music plays (players: %d)" % _audio_playing())
	_check(not get_tree().paused, "menu without pause")
	# Idle music uses a single player, also after repeated and different play_music calls.
	AudioManager.stop_music(0.0)
	var track_a := load("res://assets/audio/bgm/boss1_ancient_creature_battle_loop.ogg") as AudioStream
	var track_b := load("res://assets/audio/bgm/boss2_hellhound_battle_loop.ogg") as AudioStream
	AudioManager.play_music(track_a, 0.0)
	AudioManager.play_music(track_a, 0.0)
	AudioManager.play_music(track_b, 0.0)
	_check(_audio_playing() == 1, "single music player after changing track")
	AudioManager.stop_music(0.0)
	_check(_audio_playing() == 0, "stop_music(0) silences it")
	# The music slider keeps the pause attenuation (moving it while paused used to undo it).
	get_tree().paused = true
	await _wait(0.4)
	UserSettings.set_volume(&"Music", 0.5, false)
	var music_idx := AudioServer.get_bus_index(&"Music")
	_check(absf(AudioServer.get_bus_volume_db(music_idx) - (linear_to_db(0.5) + AudioManager.PAUSE_MUSIC_DROP_DB)) < 0.1,
			"music slider while paused keeps the pause drop")
	get_tree().paused = false
	UserSettings.set_volume(&"Music", 1.0, false)
	# 5. Enter arena 3 from scratch: health 40 full.
	await _load_arena(3)
	player = _scene().get_node("Kaelen")
	_check(player.health.current == 40 and player.health.max_value == 40, "arena 3: full health (40)")
	print("FLOW: %s" % ("OK" if _fails == 0 else "%d failures" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)
