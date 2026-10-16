extends TestCase
# Tests for Kaelen's defense: i-frames after taking a hit, armor during the attack and
# damage windows that start early.


func _make_player() -> Array:
	var p := Player.new()
	var s := Stamina.new()
	var h := Health.new()
	h.reset(100)
	var hb := Hurtbox.new()
	hb.health = h
	p.stamina = s
	p.health = h
	p.hurtbox = hb
	p._connect_components()
	return [p, s, h, hb]


func _free_all(nodes: Array) -> void:
	for n in nodes:
		(n as Node).free()


# After a hit in MOVE: HURT and HURT_IFRAMES s of invulnerability, which continue after HURT ends.
func test_hurt_grants_iframes() -> void:
	var n := _make_player()
	var p: Player = n[0]
	var h: Health = n[2]
	h.take_damage(20)
	assert_eq(p.state, Player.State.HURT)
	assert_true(p.is_invulnerable(), "invulnerable on entering HURT")
	assert_true(h.invulnerable, "Health also becomes invulnerable")
	h.take_damage(20)
	assert_eq(h.current, 80, "a second hit during the i-frames does not subtract")
	p._advance_hurt(Player.HURT_DURATION + 0.01)
	p._tick_hurt_iframes(Player.HURT_DURATION + 0.01)
	assert_eq(p.state, Player.State.MOVE, "when HURT ends she can act")
	assert_true(p.is_invulnerable(), "still invulnerable after HURT")
	assert_true(p.try_roll(), "she can roll even while invulnerable")
	p._tick_hurt_iframes(Player.HURT_IFRAMES - Player.HURT_DURATION - 0.05)
	assert_true(p.is_invulnerable(), "still within HURT_IFRAMES")
	p._advance_roll(Player.ROLL_DURATION)
	p._tick_hurt_iframes(0.1)
	assert_true(not p.is_invulnerable(), "after HURT_IFRAMES she is vulnerable again")
	assert_true(not h.invulnerable, "Health is vulnerable again")
	_free_all(n)


# The four sources (roll, hit i-frames, victory, god) combine without switching each other off.
func test_hurt_iframes_combine_with_other_sources() -> void:
	var n := _make_player()
	var p: Player = n[0]
	var h: Health = n[2]
	h.take_damage(20)
	p._advance_hurt(Player.HURT_DURATION + 0.01)
	p._tick_hurt_iframes(Player.HURT_DURATION + 0.01)
	assert_true(p.try_roll(), "rolls during the hit i-frames")
	p._advance_roll(0.1)
	p._advance_roll(Player.ROLL_DURATION)   # the roll ends and switches off its i-frames
	assert_eq(p.state, Player.State.MOVE)
	assert_true(p.is_invulnerable(), "ending the roll does not switch off the hit i-frames")
	p._on_boss_defeated(null)
	p._tick_hurt_iframes(Player.HURT_IFRAMES)   # the hit i-frames end
	assert_true(p.is_invulnerable(), "ending the hit i-frames does not switch off the victory")
	assert_true(h.invulnerable, "Health stays invulnerable because of the victory")
	_free_all(n)


func test_hurt_iframes_do_not_cancel_god() -> void:
	var n := _make_player()
	var p: Player = n[0]
	var h: Health = n[2]
	h.take_damage(20)
	p._god = true
	p._tick_hurt_iframes(Player.HURT_IFRAMES + 0.1)
	assert_true(p.is_invulnerable(), "god stays active when the hit i-frames end")
	assert_true(h.invulnerable)
	_free_all(n)


# Armor: a hit during ATTACK does not interrupt it and subtracts ATTACK_DAMAGE_TAKEN_MULT of the damage.
func test_attack_hyper_armor() -> void:
	var n := _make_player()
	var p: Player = n[0]
	var h: Health = n[2]
	var hb: Hurtbox = n[3]
	assert_true(p.try_attack())
	assert_almost(hb.damage_multiplier, Player.ATTACK_DAMAGE_TAKEN_MULT, 0.001, "multiplier in ATTACK")
	hb.receive_hit(20, null)
	assert_eq(h.current, 90, "subtracts half")
	assert_eq(p.state, Player.State.ATTACK, "the hit does not interrupt the attack")
	assert_true(p.is_invulnerable(), "the hit in ATTACK also gives i-frames")
	p._advance_attack(Player.HIT_END[0] + Player.COMBO_WINDOW + 0.01)
	assert_eq(p.state, Player.State.MOVE, "the attack ends normally")
	assert_almost(hb.damage_multiplier, 1.0, 0.001, "on leaving ATTACK it returns to 1.0")
	_free_all(n)


func test_attack_hyper_armor_still_dies() -> void:
	var n := _make_player()
	var p: Player = n[0]
	var h: Health = n[2]
	var hb: Hurtbox = n[3]
	h.current = 8
	p._last_hp = 8
	assert_true(p.try_attack())
	hb.receive_hit(20, null)
	assert_eq(h.current, 0)
	assert_eq(p.state, Player.State.DEAD, "if the hit kills her, she dies anyway")
	assert_almost(hb.damage_multiplier, 1.0, 0.001, "on dying it returns to 1.0")
	assert_true(not p.is_invulnerable(), "the fatal hit gives no i-frames")
	_free_all(n)


# Each hit's damage window starts early in game time and is derived from the clip time.
func test_attack_windows_start_early() -> void:
	var limits: Array[float] = [0.35, 0.40, 0.40]
	for i in 3:
		assert_true(Player.HIT_START[i] <= limits[i], "hit %d starts at %.3f s" % [i + 1, Player.HIT_START[i]])
		var expected: float = (Player.CLIP_HIT_START[i] - Player.ATTACK_CLIP_START[i]) / Player.ATTACK_ANIM_SPEED[i]
		assert_almost(Player.HIT_START[i], expected, 0.0001, "HIT_START %d derived from the clip" % i)
		expected = (Player.CLIP_HIT_END[i] - Player.ATTACK_CLIP_START[i]) / Player.ATTACK_ANIM_SPEED[i]
		assert_almost(Player.HIT_END[i], expected, 0.0001, "HIT_END %d derived from the clip" % i)
		assert_true(Player.HIT_END[i] > Player.HIT_START[i], "window %d not empty" % i)
