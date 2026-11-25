extends Node
## UI checks that need a real SceneTree: HUD bars follow their sources and the options menu drops
## a half-finished key capture when it is hidden from outside.
##   godot --headless --path . res://tests/flow/ui_flow.tscn
## Exits with code 1 if anything fails.

var _fails := 0


func _ready() -> void:
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		_fails += 1


func _run() -> void:
	var hud: Hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	var boss_health := Health.new()
	boss_health.max_value = 200
	boss_health.current = 200
	add_child(hud)
	hud._on_health_changed(25, 100)
	hud._on_stamina_changed(50.0, 100.0)
	_check(is_equal_approx(hud.get_node(^"Bars/Frame/HealthBar").value, 0.25), "health bar follows health")
	_check(is_equal_approx(hud.get_node(^"Bars/Frame/StaminaBar").value, 0.5), "stamina bar follows stamina")
	hud.show_boss("Blackhorn", boss_health)
	boss_health.current = 100
	boss_health.changed.emit(100, 200)
	var style: Dictionary = Hud.BOSS_BAR_STYLES["Blackhorn"]
	var expected := Hud.fill_width(0.5, style[&"fill"].x, style[&"fill"].y, Hud.BOSS_BAR_WIDTH / style[&"scale"])
	_check(is_equal_approx(hud.get_node(^"BossBar/Bar/Clip").size.x, expected), "boss fill follows boss health")
	var bar: Control = hud.get_node(^"BossBar/Bar")
	_check(is_equal_approx(bar.size.x * bar.scale.x, Hud.BOSS_BAR_WIDTH), "boss bar keeps its length")
	_check(hud.get_node(^"BossBar").visible, "boss bar shown")
	hud.hide_boss()
	_check(not hud.get_node(^"BossBar").visible, "boss bar hidden")
	_check(not boss_health.changed.is_connected(hud._on_boss_changed), "hide_boss disconnects")
	hud.free()
	boss_health.free()
	_check_options_capture()
	await _check_menu_navigation()
	print("FLOW: OK" if _fails == 0 else "FLOW: FAIL (%d)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _check_options_capture() -> void:
	var options := OptionsMenu.new()
	add_child(options)
	options.open()
	options._begin_capture(&"attack", GameSettings.SLOT_KB, options._rows[[&"attack", GameSettings.SLOT_KB]])
	_check(options.is_capturing(), "capture started")
	options.visible = false   # e.g. the pause menu closing underneath
	_check(not options.is_capturing(), "hiding the menu cancels the capture")
	options.free()


## Arrow navigation: every neighbour stays inside the menu, nothing wraps, and walking down from any tab
## ends on Restore / Back; the pause buttons behind the options cannot take the focus while it is open.
func _check_menu_navigation() -> void:
	var options := OptionsMenu.new()
	add_child(options)
	options.open()
	for tab in OptionsMenu.TAB_KEYS.size():
		options._select_tab(tab)
		var node: Control = options._tab_buttons[tab]
		var steps := 0
		while node != options._back and node != options._restore and steps < 40:
			var next := node.get_node_or_null(node.focus_neighbor_bottom) as Control
			if next == null or next == node or not options.is_ancestor_of(next):
				break
			node = next
			steps += 1
		_check(node == options._back or node == options._restore, "tab %d: walking down ends on the bottom buttons (%d steps)" % [tab, steps])
		var first: Control = options._tab_buttons[0]
		_check(first.get_node(first.focus_neighbor_left) == first, "first tab: left stays put")
		var back: Control = options._back
		_check(back.get_node(back.focus_neighbor_bottom) == back and back.get_node(back.focus_neighbor_right) == back,
			"Back: down and right stay put")
	options.free()

	var pause := (load("res://scenes/ui/pause_menu.tscn") as PackedScene).instantiate()
	add_child(pause)
	pause._open_options()
	_check(pause._continue.focus_mode == Control.FOCUS_NONE and pause._quit.focus_mode == Control.FOCUS_NONE,
		"pause buttons cannot take focus behind the options")
	pause._on_options_closed()
	_check(pause._continue.focus_mode == Control.FOCUS_ALL, "pause buttons focusable again")
	_check(pause._continue.get_node(pause._continue.focus_neighbor_top) == pause._continue, "pause: up from the first stays put")
	pause.free()

	var menu := (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	var start: Button = menu.get_node(^"%Start")
	var quit: Button = menu.get_node(^"%Quit")
	_check(start.get_node(start.focus_neighbor_top) == start, "main menu: up from Start stays put")
	_check(quit.get_node(quit.focus_neighbor_bottom) == quit, "main menu: down from Quit stays put")
	_check(start.get_node(start.focus_neighbor_left) == start, "main menu: left stays put")
	menu.free()
