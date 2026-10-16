extends TestCase
# Boss repel reaction (BossRepel + Boss + Player.apply_shove).


func _repel() -> BossRepel:
	var r := BossRepel.new()
	r.threshold_fraction = 0.10
	r.window = 4.0
	r.cooldown = 7.0
	r.burst_hits = 3
	r.burst_window = 3.0
	r.glue_time = 7.0
	return r


func test_fires_when_threshold_reached() -> void:
	var r := _repel()   # 10 % of 600 = 60
	assert_true(not r.register_damage(20, 600), "20 is not enough")
	r.tick(1.5)
	assert_true(not r.register_damage(20, 600), "40 is not enough")
	r.tick(1.4)   # the first hit leaves the 3 s window of consecutive hits
	assert_true(r.register_damage(36, 600), "76 within the damage window fires")


func test_fires_on_three_quick_hits() -> void:
	var r := _repel()
	assert_true(not r.register_damage(10, 2000))
	r.tick(1.0)
	assert_true(not r.register_damage(10, 2000), "two hits are not enough")
	r.tick(1.0)
	assert_true(r.register_damage(10, 2000), "three hits in 3 s fire even if they do little damage")


func test_slow_hits_do_not_count_as_burst() -> void:
	var r := _repel()
	for i in 4:
		assert_true(not r.register_damage(5, 2000), "hits spaced 1.6 s apart do not fire")
		r.tick(1.6)


func test_fires_when_glued_to_the_boss() -> void:
	var r := _repel()
	var fired := false
	for i in 13:
		fired = r.register_proximity(0.5, true)
	assert_true(not fired, "6.5 s stuck close does not fire yet")
	assert_true(r.register_proximity(0.5, true), "7 s stuck close fires")
	r.trigger()
	assert_almost(r.glue_seconds(), 0.0)


func test_glue_drains_when_away() -> void:
	var r := _repel()
	for i in 50:
		r.register_proximity(0.1, true)   # 5 s
	for i in 20:
		r.register_proximity(0.1, false)  # 2 s away = -4 s
	assert_almost(r.glue_seconds(), 1.0, 0.001, "moving away drains it at double speed")
	for i in 80:
		r.register_proximity(0.1, true)
	assert_true(not r.register_proximity(0.1, true, true), "blocked does not fire")
	assert_true(r.is_due(2000), "but it stays pending")


func test_window_forgets_old_hits() -> void:
	var r := _repel()
	r.register_damage(30, 400)
	r.tick(4.5)
	assert_eq(r.recent_damage(), 0, "the hit left the window")
	assert_true(not r.register_damage(36, 400), "36 alone does not reach 10 % of 400")


func test_no_fire_during_cooldown() -> void:
	var r := _repel()
	assert_true(r.register_damage(80, 400))
	r.trigger()
	assert_true(r.on_cooldown())
	assert_true(not r.register_damage(200, 400), "on cooldown it does not fire")
	assert_true(not r.register_proximity(20.0, true), "nor for being stuck close")
	r.tick(7.1)
	assert_true(not r.on_cooldown())
	assert_eq(r.recent_damage(), 0, "what is received during cooldown does not count")
	assert_true(r.register_damage(40, 400), "after the cooldown it fires again (10 % of 400)")


func test_blocked_counts_but_does_not_fire() -> void:
	var r := _repel()
	assert_true(not r.register_damage(80, 400, true), "blocked does not fire")
	assert_true(r.is_due(400), "but it stays pending")


func test_push_velocity_outward_and_radius() -> void:
	var v := BossRepel.push_velocity(Vector3.ZERO, Vector3(3.0, 1.0, 0.0), 6.0, 10.0)
	assert_almost(v.x, 10.0, 0.001, "outward")
	assert_almost(v.y, 0.0, 0.001, "horizontal")
	assert_eq(BossRepel.push_velocity(Vector3.ZERO, Vector3(7.0, 0.0, 0.0), 6.0, 10.0), Vector3.ZERO, "outside the radius")
	var f := BossRepel.push_velocity(Vector3.ZERO, Vector3.ZERO, 6.0, 10.0, Vector3(0.0, 0.0, -1.0))
	assert_almost(f.length(), 10.0, 0.001, "on top: uses the fallback direction")


func _boss() -> Boss:
	var boss := (load("res://scenes/bosses/boss_bonedragon.tscn") as PackedScene).instantiate() as Boss
	boss.health = boss.get_node(^"Health") as Health
	boss.health.reset(500)
	return boss


func test_boss_queues_repel_on_burst() -> void:
	var boss := _boss()
	boss._register_repel_damage(20)
	assert_true(not boss._pending_repel)
	boss._register_repel_damage(36)
	assert_true(boss._pending_repel, "56 >= 50 (10 % of 500): reaction pending")
	boss.free()


func test_boss_no_repel_in_phase_roar_or_dead() -> void:
	var boss := _boss()
	boss.state = Boss.State.ROAR
	assert_true(not boss.can_repel(), "during the phase roar")
	boss._register_repel_damage(100)
	assert_true(not boss._pending_repel, "it is not queued during the roar")
	boss.state = Boss.State.CHASE
	boss._pending_roar = true
	assert_true(not boss.can_repel(), "with the phase transition pending")
	boss._pending_roar = false
	boss.state = Boss.State.DEAD
	assert_true(not boss.can_repel(), "dead")
	boss.state = Boss.State.RECOVER
	assert_true(boss.can_repel(), "it can cut the recovery: that is what stops the chaining")
	boss.state = Boss.State.TELEGRAPH
	assert_true(boss.can_repel(), "and the warning of an attack")
	boss.free()


func test_boss_repel_is_invulnerable() -> void:
	var boss := _boss()
	boss.state = Boss.State.CHASE
	boss.start_repel()
	assert_true(boss.repelling and boss.state == Boss.State.ROAR, "roars")
	assert_eq(boss.phase, 1, "it does not change phase")
	assert_eq(boss.repel_count, 1)
	boss._on_hurt(50, null)
	assert_eq(boss.health.current, 500, "invulnerable while roaring")
	boss.free()


func test_shove_pushes_player_away() -> void:
	var p := Player.new()
	assert_true(p.apply_shove(Vector3(10.0, 0.0, 0.0), 0.4))
	assert_eq(p.state, Player.State.HURT, "no control during the push")
	assert_true(p.velocity.x > 9.0, "she is thrown outward")
	assert_true(p.apply_shove(Vector3(10.0, 0.0, 0.0), 0.4, 3.0))
	assert_almost(p.velocity.y, 3.0, 0.001, "with a small hop upward")
	var half := Player.shove_velocity_at(Vector3(10.0, 0.0, 0.0), 0.4, 0.2)
	assert_almost(half.x, 5.0, 0.001, "decays linearly")
	p._advance_hurt(0.39)
	assert_eq(p.state, Player.State.HURT, "lasts as long as the push")
	p.free()


func test_roll_dodges_shove() -> void:
	var p := Player.new()
	var s := Stamina.new()
	p.stamina = s
	assert_true(p.try_roll())
	p._advance_roll(0.1)
	assert_true(not p.apply_shove(Vector3(10.0, 0.0, 0.0), 0.4), "the roll i-frames dodge it")
	assert_eq(p.state, Player.State.ROLL)
	p.free()
	s.free()


func test_shove_travels_about_four_and_a_half_metres() -> void:
	var boss := _boss()
	var travelled := boss.repel_force * boss.repel_push_time * 0.5
	assert_true(travelled >= 4.0 and travelled <= 5.0, "push of ~4.5 m, not 2 m: %s" % travelled)
	assert_true(boss.repel_radius >= 6.5, "reaches Kaelen even at sword-hit range")
	boss.free()


func test_repel_shockwave_comes_after_a_warning() -> void:
	var boss := _boss()
	boss.state = Boss.State.CHASE
	boss.start_repel()
	assert_true(boss.repel_push_delay >= 0.25 and boss.repel_push_delay <= 0.5, "short warning before the shockwave")
	assert_almost(boss._repel_push_left, boss.repel_push_delay, 0.001, "the shockwave waits for the warning")
	boss.free()


func test_roll_must_be_timed_for_the_shockwave() -> void:
	# The wave leaves repel_push_delay s after the roar: the roll only dodges it if its i-frames
	# (0.05-0.40 s) cover that instant.
	var p := Player.new()
	var s := Stamina.new()
	p.stamina = s
	assert_true(p.try_roll())
	p._advance_roll(0.3)
	assert_true(not p.apply_shove(Vector3(10.0, 0.0, 0.0), 0.5), "0.3 s into the roll: dodges")
	p._advance_roll(0.2)   # 0.5 s: outside the i-frames
	assert_true(p.apply_shove(Vector3(10.0, 0.0, 0.0), 0.5), "late roll: the shockwave pushes her")
	p.free()
	s.free()
