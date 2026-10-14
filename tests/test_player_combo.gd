extends TestCase
# Kaelen's combo tests (damage per hit, stamina cost, input buffer and damage taken).


func _make_player() -> Array:
	var p := Player.new()
	var s := Stamina.new()
	var h := Health.new()
	h.reset(100)
	p.stamina = s
	p.health = h
	p._connect_components()
	return [p, s, h]


func _free_all(nodes: Array) -> void:
	for n in nodes:
		(n as Node).free()


func test_combo_damage_sequence() -> void:
	assert_eq(Player.combo_damage(0), 10, "golpe 1")
	assert_eq(Player.combo_damage(1), 10, "golpe 2")
	assert_eq(Player.combo_damage(2), 18, "golpe 3")
	assert_eq(Player.combo_damage(3), 10, "vuelve a empezar")


func test_attack_needs_stamina() -> void:
	var n := _make_player()
	var p: Player = n[0]
	(n[1] as Stamina).current = 0.0
	assert_true(not p.try_attack(), "try_attack con estamina 0")
	assert_eq(p.state, Player.State.MOVE)
	_free_all(n)


func test_attack_spends_stamina() -> void:
	var n := _make_player()
	var p: Player = n[0]
	var s: Stamina = n[1]
	assert_true(p.try_attack(), "try_attack con estamina llena")
	assert_eq(p.state, Player.State.ATTACK)
	assert_almost(s.current, 80.0)
	_free_all(n)


# Chaining inside the window after a hit moves to the next one; outside it, it returns to MOVE.
func test_combo_chains_inside_window() -> void:
	var n := _make_player()
	var p: Player = n[0]
	assert_true(p.try_attack())
	assert_true(not p.try_attack(), "no se encadena antes de que termine la ventana de daño")
	p._advance_attack(Player.HIT_END[0] + 0.05)
	assert_true(p.try_attack(), "encadena dentro de la ventana")
	assert_eq(p.combo_index, 1)
	p._advance_attack(Player.HIT_END[1] + Player.COMBO_WINDOW + 0.01)
	assert_eq(p.state, Player.State.MOVE, "pasada la ventana vuelve a MOVE")
	assert_true(p.try_attack())
	assert_eq(p.combo_index, 0, "el combo vuelve a empezar")
	_free_all(n)


# A roll pressed during an attack is buffered for ~0.2 s and runs when returning to MOVE.
func test_buffered_roll() -> void:
	var n := _make_player()
	var p: Player = n[0]
	assert_true(p.try_attack())
	var total: float = Player.HIT_END[0] + Player.COMBO_WINDOW
	p._advance_attack(total - 0.1)
	p.buffer_action(&"roll")
	p._advance_attack(0.15)
	assert_eq(p.state, Player.State.ROLL, "la rodada guardada se ejecuta al terminar el golpe")
	_free_all(n)


func test_buffered_roll_expires() -> void:
	var n := _make_player()
	var p: Player = n[0]
	assert_true(p.try_attack())
	p.buffer_action(&"roll")
	var t := 0.0
	while p.state == Player.State.ATTACK and t < 5.0:
		p._advance_attack(0.05)
		t += 0.05
	assert_eq(p.state, Player.State.MOVE, "pasados 0.2 s la orden se descarta")
	_free_all(n)


func test_damage_interrupts_attack_with_hurt() -> void:
	var n := _make_player()
	var p: Player = n[0]
	var h: Health = n[2]
	assert_true(p.try_attack())
	h.take_damage(20)
	assert_eq(p.state, Player.State.HURT)
	p._advance_hurt(Player.HURT_DURATION + 0.01)
	assert_eq(p.state, Player.State.MOVE)
	_free_all(n)


func test_death_is_terminal() -> void:
	var n := _make_player()
	var p: Player = n[0]
	var h: Health = n[2]
	for i in 5:
		h.take_damage(20)
	assert_eq(p.state, Player.State.DEAD)
	assert_eq(p.death_count, 1, "muere una sola vez")
	assert_true(not p.try_attack(), "sin control al morir")
	assert_true(not p.try_roll(), "sin control al morir")
	_free_all(n)
