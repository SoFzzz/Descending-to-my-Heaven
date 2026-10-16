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
	assert_eq(Player.combo_damage(0), 20, "hit 1")
	assert_eq(Player.combo_damage(1), 20, "hit 2")
	assert_eq(Player.combo_damage(2), 36, "hit 3")
	assert_eq(Player.combo_damage(3), 20, "starts over")


func test_attack_needs_stamina() -> void:
	var n := _make_player()
	var p: Player = n[0]
	(n[1] as Stamina).current = 0.0
	assert_true(not p.try_attack(), "try_attack with 0 stamina")
	assert_eq(p.state, Player.State.MOVE)
	_free_all(n)


func test_attack_spends_stamina() -> void:
	var n := _make_player()
	var p: Player = n[0]
	var s: Stamina = n[1]
	assert_true(p.try_attack(), "try_attack with full stamina")
	assert_eq(p.state, Player.State.ATTACK)
	assert_almost(s.current, 80.0)
	_free_all(n)


# Chaining inside the window after a hit moves to the next one; outside it, it returns to MOVE.
func test_combo_chains_inside_window() -> void:
	var n := _make_player()
	var p: Player = n[0]
	assert_true(p.try_attack())
	assert_true(not p.try_attack(), "it does not chain before the damage window ends")
	p._advance_attack(Player.HIT_END[0] + 0.05)
	assert_true(p.try_attack(), "chains within the window")
	assert_eq(p.combo_index, 1)
	p._advance_attack(Player.HIT_END[1] + Player.COMBO_WINDOW + 0.01)
	assert_eq(p.state, Player.State.MOVE, "past the window it returns to MOVE")
	assert_true(p.try_attack())
	assert_eq(p.combo_index, 0, "the combo starts over")
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
	assert_eq(p.state, Player.State.ROLL, "the stored roll is executed when the hit ends")
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
	assert_eq(p.state, Player.State.MOVE, "after 0.2 s the order is discarded")
	_free_all(n)


# Outside the attack, damage stuns her (HURT); during the attack it no longer interrupts it (armor, see
# test_player_defense.gd).
func test_damage_in_move_enters_hurt() -> void:
	var n := _make_player()
	var p: Player = n[0]
	var h: Health = n[2]
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
		p._tick_hurt_iframes(Player.HURT_IFRAMES)   # each hit gives i-frames: let them pass
	assert_eq(p.state, Player.State.DEAD)
	assert_eq(p.death_count, 1, "dies only once")
	assert_true(not p.try_attack(), "no control when dying")
	assert_true(not p.try_roll(), "no control when dying")
	_free_all(n)
