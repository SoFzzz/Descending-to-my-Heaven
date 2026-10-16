extends TestCase
# Flask de curación de Kaelen: cargas, porcentaje, estados bloqueados, interrupciones, relleno,
# acción "heal" (teclado y mando), traducción y contador del HUD.


func _make() -> Array:
	var p := Player.new()
	var h := Health.new()
	var s := Stamina.new()
	h.max_value = 100
	h.current = 100
	p.health = h
	p.stamina = s
	return [p, h, s]


func _free(nodes: Array) -> void:
	for n: Node in nodes:
		n.free()


func _key(code: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	return event


func test_starts_with_ten_charges() -> void:
	var n := _make()
	assert_eq((n[0] as Player).heal_charges, 10)
	assert_eq(Player.HEAL_CHARGES, 10)
	_free(n)


func test_full_health_does_not_spend_a_charge() -> void:
	var n := _make()
	var p: Player = n[0]
	assert_true(not p.try_heal(), "vida llena: no empieza")
	assert_eq(p.heal_blocked_reason(), "full")
	assert_eq(p.heal_charges, 10)
	_free(n)


func test_heals_the_right_fraction_at_each_level() -> void:
	assert_eq(Player.heal_amount(100), 38)
	assert_eq(Player.heal_amount(70), 27)
	assert_eq(Player.heal_amount(40), 15)
	assert_true(Player.heal_amount(1) >= 1)
	var n := _make()
	var p: Player = n[0]
	var h: Health = n[1]
	h.current = 20
	assert_true(p.try_heal())
	p._advance_heal(Player.HEAL_DURATION * 0.5)
	assert_eq(h.current, 20, "a media bebida todavía no cura")
	assert_eq(p.heal_charges, 10, "ni gasta la carga")
	p._advance_heal(Player.HEAL_DURATION)
	assert_eq(h.current, 58)
	assert_eq(p.heal_charges, 9)
	assert_true(not p.is_healing())
	_free(n)


func test_heal_never_exceeds_max() -> void:
	var n := _make()
	var p: Player = n[0]
	var h: Health = n[1]
	h.current = 90
	assert_true(p.try_heal())
	p._advance_heal(Player.HEAL_DURATION + 0.01)
	assert_eq(h.current, 100)
	assert_eq(p.heal_charges, 9)
	_free(n)


func test_scaled_to_arena_3_max_hp() -> void:
	var n := _make()
	var p: Player = n[0]
	var h: Health = n[1]
	h.reset(40)
	h.current = 5
	assert_true(p.try_heal())
	p._advance_heal(Player.HEAL_DURATION + 0.01)
	assert_eq(h.current, 20, "15 de 40 en la arena 3")
	_free(n)


func test_blocked_in_other_states() -> void:
	var n := _make()
	var p: Player = n[0]
	var h: Health = n[1]
	h.current = 30
	for state: Player.State in [Player.State.ROLL, Player.State.ATTACK, Player.State.HURT, Player.State.DEAD]:
		p.state = state
		assert_true(not p.try_heal(), "bloqueado en estado %d" % state)
	p.state = Player.State.MOVE
	p.set_cutscene(true)
	assert_true(not p.try_heal(), "bloqueado en escena dirigida")
	p.set_cutscene(false)
	p.heal_charges = 0
	assert_true(not p.try_heal(), "sin cargas")
	assert_eq(p.heal_blocked_reason(), "empty")
	p.heal_charges = 10
	assert_true(p.try_heal(), "en MOVE con vida baja sí")
	assert_true(not p.try_heal(), "no se puede empezar otra a la vez")
	_free(n)


func test_hit_interrupts_without_spending() -> void:
	var n := _make()
	var p: Player = n[0]
	var h: Health = n[1]
	h.current = 50
	p._connect_components()
	assert_true(p.try_heal())
	h.take_damage(10)   # el golpe lo interrumpe (HURT)
	assert_eq(p.state, Player.State.HURT)
	assert_true(not p.is_healing())
	assert_eq(p.heal_charges, 10, "la carga no se pierde")
	assert_eq(h.current, 40)
	_free(n)


func test_roll_and_attack_cancel_the_drink() -> void:
	var n := _make()
	var p: Player = n[0]
	var h: Health = n[1]
	h.current = 50
	assert_true(p.try_heal())
	assert_true(p.try_roll())
	assert_true(not p.is_healing())
	assert_eq(p.heal_charges, 10)
	p.state = Player.State.MOVE
	assert_true(p.try_heal())
	assert_true(p.try_attack())
	assert_true(not p.is_healing())
	assert_eq(h.current, 50)
	_free(n)


func test_refill_restores_charges_and_emits() -> void:
	var n := _make()
	var p: Player = n[0]
	p.heal_charges = 3
	var seen: Array[int] = []
	p.heal_charges_changed.connect(func(c: int, _m: int) -> void: seen.append(c))
	p.refill_heals()
	assert_eq(p.heal_charges, 10)
	assert_eq(seen, [10] as Array[int])
	_free(n)


func test_new_level_scene_gives_ten_charges() -> void:
	# Entrar a una arena o reintentar reconstruye a Kaelen: las cargas vuelven a 10.
	var scene := load("res://scenes/player/kaelen.tscn") as PackedScene
	var p := scene.instantiate() as Player
	p.heal_charges = 2
	p.refill_heals()   # lo que hace level_gameplay._refill_player
	assert_eq(p.heal_charges, 10)
	p.free()
	var fresh := scene.instantiate() as Player
	assert_eq(fresh.heal_charges, 10, "Kaelen nueva empieza con 10")
	fresh.free()


func test_health_heal_helper() -> void:
	var h := Health.new()
	h.current = 10
	assert_eq(h.heal(30), 30)
	assert_eq(h.heal(500), 60)
	assert_eq(h.current, 100)
	assert_eq(h.heal(5), 0)
	h.current = 0
	assert_eq(h.heal(5), 0, "no revive")
	h.free()


func test_heal_action_has_keyboard_and_gamepad_events() -> void:
	InputMap.load_from_project_settings()
	assert_true(InputMap.has_action(&"heal"))
	assert_true(InputMap.event_is_action(_key(KEY_R, true), &"heal"), "R cura")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_Y
	pad.pressed = true
	assert_true(InputMap.event_is_action(pad, &"heal"), "Y cura")
	Input.parse_input_event(_key(KEY_R, true))
	Input.flush_buffered_events()
	assert_true(Input.is_action_pressed(&"heal"), "el evento de teclado activa la acción")
	Input.parse_input_event(_key(KEY_R, false))
	Input.flush_buffered_events()


func test_heal_is_remappable_and_translated() -> void:
	assert_true(GameSettings.REMAP_ACTIONS.has(&"heal"))
	assert_true(OptionsMenu.ACTION_KEYS.has(&"heal"))
	var key: String = OptionsMenu.ACTION_KEYS[&"heal"]
	var found := false
	for line in FileAccess.get_file_as_string("res://localization/translations.csv").split("\n"):
		var cols := line.strip_edges().split(",")
		if cols.size() >= 3 and cols[0] == key:
			found = true
			assert_true(not cols[1].is_empty() and not cols[2].is_empty(), "es y en")
	assert_true(found, "ACT_HEAL en el CSV")


func test_hud_counter_text_and_dimming() -> void:
	assert_eq(Hud.heal_text(10), "x10")
	assert_eq(Hud.heal_text(-2), "x0")
	assert_almost(Hud.heal_alpha(3), 1.0)
	assert_true(Hud.heal_alpha(0) < 0.5, "se atenúa a 0")
	var hud: Hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	# Sin árbol los @onready no se resuelven: se enlazan a mano.
	hud._heal_box = hud.get_node(^"Heal") as Control
	hud._heal_count = hud.get_node(^"Heal/Count") as Label
	hud._on_heal_charges_changed(7, 10)
	assert_eq((hud.get_node(^"Heal/Count") as Label).text, "x7")
	hud._on_heal_charges_changed(0, 10)
	assert_true((hud.get_node(^"Heal") as Control).modulate.a < 0.5)
	hud.free()


func test_healing_does_not_feed_the_orchestrator_intensity() -> void:
	# La intensidad del orquestador sube con player_damaged (daño recibido); curarse no emite nada
	# y Player._on_health_changed ignora los aumentos de vida.
	var n := _make()
	var p: Player = n[0]
	var h: Health = n[1]
	h.current = 50
	p._connect_components()
	var model := OrchestratorModel.new()
	var before := model.intensity
	p.try_heal()
	p._advance_heal(Player.HEAL_DURATION + 0.01)
	assert_eq(model.intensity, before)
	assert_eq(h.current, 88)
	_free(n)
