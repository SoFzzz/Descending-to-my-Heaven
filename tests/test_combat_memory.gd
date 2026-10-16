extends TestCase
# CombatMemory: prediction and behaviour detection (pure logic, simulated at 10 Hz).

const DT := 0.1


func _ctx(player: Vector3, boss := Vector3.ZERO, extra := {}) -> Dictionary:
	var ctx := {player_pos = player, boss_pos = boss, boss_forward = Vector3.FORWARD}
	ctx.merge(extra, true)
	return ctx


## Kaelen moves at `velocity` m/s for `seconds` from `start`; returns the memory.
func _run(start: Vector3, velocity: Vector3, seconds: float, extra := {}, mem: CombatMemory = null) -> CombatMemory:
	var m := mem if mem else CombatMemory.new()
	var pos := start
	for i in int(seconds / DT):
		pos += velocity * DT
		m.observe(DT, _ctx(pos, Vector3.ZERO, extra))
	return m


func test_velocity_is_smoothed_and_prediction_leads() -> void:
	var m := _run(Vector3(0, 0, -6), Vector3(5, 0, 0), 2.0)
	assert_almost(m.speed, 5.0, 0.3, "speed converges to the real one")
	var ahead := m.predict(1.0)
	assert_almost(ahead.x - m.position.x, 5.0, 0.4, "at 1 s it is ~5 m ahead")
	assert_almost(ahead.z, m.position.z, 0.2)


func test_prediction_standing_still_is_her_position() -> void:
	var m := _run(Vector3(2, 0, 3), Vector3.ZERO, 1.0)
	assert_almost(m.predict(1.0).distance_to(m.position), 0.0, 0.05)


func test_prediction_speed_is_capped() -> void:
	var m := _run(Vector3(0, 0, -6), Vector3(0, 0, -20), 1.5)
	assert_true(m.predict(1.0).distance_to(m.position) <= CombatMemory.MAX_LEAD_SPEED + 0.01, "a roll does not trigger the prediction")


func test_prediction_is_limited_by_bounds() -> void:
	var m := _run(Vector3(0, 0, -6), Vector3(5, 0, 0), 2.0)
	var clamped := m.predict(1.0, func(p: Vector3) -> Vector3: return CombatMemory.clamp_to_disc(p, Vector3.ZERO, 8.0))
	assert_true(Vector2(clamped.x, clamped.z).length() <= 8.01, "inside the arena")


func test_clamp_to_disc() -> void:
	var p := CombatMemory.clamp_to_disc(Vector3(20, 1, 0), Vector3.ZERO, 10.0)
	assert_almost(p.x, 10.0)
	assert_almost(p.y, 1.0)
	assert_eq(CombatMemory.clamp_to_disc(Vector3(3, 0, 4), Vector3.ZERO, 10.0), Vector3(3, 0, 4))


func test_running_away_is_fleeing() -> void:
	var m := _run(Vector3(0, 0, -6), Vector3(0, 0, -5), 3.0)
	assert_true(m.fleeing, "moves away steadily")
	assert_eq(m.behavior, CombatMemory.Behavior.FLEEING)


func test_running_toward_the_boss_is_not_fleeing() -> void:
	var m := _run(Vector3(0, 0, -14), Vector3(0, 0, 5), 2.0)
	assert_true(not m.fleeing)


func test_a_short_step_back_is_not_fleeing() -> void:
	var m := _run(Vector3(0, 0, -6), Vector3(0, 0, -5), 0.4)
	assert_true(not m.fleeing, "less than FLEE_TIME s")


func test_fleeing_is_forgotten_after_calm() -> void:
	var m := _run(Vector3(0, 0, -6), Vector3(0, 0, -5), 3.0)
	assert_true(m.fleeing)
	_run(m.position, Vector3.ZERO, 2.0, {}, m)
	assert_true(not m.fleeing, "standing still for a while stops being fleeing")


func test_locked_on_minion_is_with_minions() -> void:
	var m := _run(Vector3(0, 0, -8), Vector3.ZERO, 0.5, {minions = [Vector3(1, 0, -9)], locked_minion = true})
	assert_true(m.with_minions)
	assert_eq(m.behavior, CombatMemory.Behavior.WITH_MINIONS)
	assert_true(m.distracted, "attentive to the minions")


func test_striking_nearby_minion_is_with_minions() -> void:
	var m := _run(Vector3(0, 0, -8), Vector3.ZERO, 0.5, {minions = [Vector3(1, 0, -9)], player_attacking = true})
	assert_true(m.with_minions)


func test_minion_much_closer_than_boss_is_with_minions() -> void:
	var m := _run(Vector3(0, 0, -10), Vector3.ZERO, 0.5, {minions = [Vector3(0, 0, -12)]})
	assert_true(m.with_minions, "the minion is at 2 m and the boss at 10")


func test_minion_far_away_is_not_with_minions() -> void:
	var m := _run(Vector3(0, 0, -10), Vector3.ZERO, 0.5, {minions = [Vector3(0, 0, 8)]})
	assert_true(not m.with_minions)


func test_heading_toward_a_minion_is_with_minions() -> void:
	var m := _run(Vector3(0, 0, -6), Vector3(4, 0, 0), 1.5, {minions = [Vector3(12, 0, -6)]})
	assert_true(m.with_minions, "heads determinedly toward the minion")


func test_glued_after_staying_close() -> void:
	var m := _run(Vector3(0, 0, -2.5), Vector3.ZERO, 2.5)
	assert_true(m.glued)
	assert_eq(m.behavior, CombatMemory.Behavior.GLUED)


func test_passive_far_and_not_attacking() -> void:
	var m := _run(Vector3(0, 0, -11), Vector3.ZERO, 3.5)
	assert_true(m.passive)
	assert_eq(m.behavior, CombatMemory.Behavior.PASSIVE)
	var attacker := _run(Vector3(0, 0, -11), Vector3.ZERO, 3.5, {player_attacking = true})
	assert_true(not attacker.passive, "attacking is not passive")


func test_turned_away_is_distracted() -> void:
	# Kaelen at -Z facing -Z (back to the boss, who is at the origin).
	var m := _run(Vector3(0, 0, -8), Vector3.ZERO, 0.5, {player_facing = Vector3(0, 0, -1)})
	assert_true(m.distracted)
	var facing_boss := _run(Vector3(0, 0, -8), Vector3.ZERO, 0.5, {player_facing = Vector3(0, 0, 1)})
	assert_true(not facing_boss.distracted)


func test_circling_the_boss() -> void:
	var m := CombatMemory.new()
	var angle := 0.0
	for i in 20:
		angle += 0.1 * 0.9   # ~0.9 rad/s a 4 m: 3.6 m/s tangential
		m.observe(DT, _ctx(Vector3(cos(angle), 0, sin(angle)) * 4.0))
	assert_true(m.circling)
	var straight := _run(Vector3(0, 0, -4), Vector3(0, 0, -3), 1.5)
	assert_true(not straight.circling, "moving away in a straight line is not circling")


func test_feed_samples_at_ten_hertz() -> void:
	var m := CombatMemory.new()
	var sampled := 0
	for i in 60:
		if m.feed(1.0 / 60.0, _ctx(Vector3(0, 0, -5))):
			sampled += 1
	assert_true(sampled >= 9 and sampled <= 11, "~10 samples in 1 s, got %d" % sampled)


func test_reset_forgets_everything() -> void:
	var m := _run(Vector3(0, 0, -6), Vector3(0, 0, -5), 3.0)
	m.reset()
	assert_true(not m.fleeing)
	assert_eq(m.samples, 0)
	assert_eq(m.behavior, CombatMemory.Behavior.NEUTRAL)
