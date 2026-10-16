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
