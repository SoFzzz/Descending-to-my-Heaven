extends TestCase
# BossTactics: elección de meta por utilidad, histéresis, caducidad y enfriamiento.

const G := BossTactics.Goal


func _ctx(extra := {}) -> Dictionary:
	var ctx := {distance = 5.0, health_ratio = 1.0, phase = 1, minions_alive = 0, recent_damage = 0.0, since_repel = 99.0}
	ctx.merge(extra, true)
	return ctx


func _best(scores: Dictionary) -> int:
	var best := G.ATTACK
	for g in scores.keys():
		if scores[g] > scores[best]:
			best = g
	return best


func test_default_is_attack() -> void:
	assert_eq(_best(BossTactics.score_goals(_ctx())), G.ATTACK)


func test_fleeing_far_prefers_cut_off() -> void:
	var scores := BossTactics.score_goals(_ctx({distance = 11.0, fleeing = true}))
	assert_eq(_best(scores), G.CUT_OFF)
	assert_true(scores[G.CUT_OFF] > scores[G.ATTACK])


func test_fleeing_close_does_not_cut_off() -> void:
	var scores := BossTactics.score_goals(_ctx({distance = 4.0, fleeing = true}))
	assert_almost(scores[G.CUT_OFF], 0.0)


func test_long_combo_prefers_wait() -> void:
	assert_eq(_best(BossTactics.score_goals(_ctx({recent_damage = 0.2}))), G.WAIT)


func test_after_repel_prefers_wait() -> void:
	assert_eq(_best(BossTactics.score_goals(_ctx({since_repel = 1.0}))), G.WAIT)
	assert_eq(_best(BossTactics.score_goals(_ctx({since_repel = 6.0}))), G.ATTACK, "pasada la recuperación vuelve a atacar")


func test_passive_kaelen_prefers_wait() -> void:
	assert_eq(_best(BossTactics.score_goals(_ctx({distance = 9.0, passive = true}))), G.WAIT)


func test_phase_two_is_more_aggressive() -> void:
	var p1 := BossTactics.score_goals(_ctx({recent_damage = 0.2, phase = 1}))
	var p2 := BossTactics.score_goals(_ctx({recent_damage = 0.2, phase = 2}))
	assert_true(p2[G.WAIT] < p1[G.WAIT], "esperar vale menos")
	assert_true(p2[G.ATTACK] > p1[G.ATTACK], "atacar vale más")


func test_pincer_needs_minions_and_kaelen_with_them() -> void:
	assert_almost(BossTactics.score_goals(_ctx({distance = 9.0, with_minions = true}))[G.PINCER], 0.0, 0.0001, "sin esbirros")
	assert_almost(BossTactics.score_goals(_ctx({distance = 9.0, minions_alive = 2}))[G.PINCER], 0.0, 0.0001, "ella no va con ellos")
	var s := BossTactics.score_goals(_ctx({distance = 9.0, with_minions = true, minions_alive = 2}))
	assert_eq(_best(s), G.PINCER)


func test_update_reevaluates_every_half_second() -> void:
	var t := BossTactics.new()
	var ctx := _ctx({distance = 11.0, fleeing = true})
	t.goal_time = 5.0
	assert_true(not t.update(0.3, ctx), "aún no toca")
	assert_eq(t.goal, G.ATTACK)
	assert_true(t.update(0.3, ctx), "a los 0.6 s sí")
	assert_eq(t.goal, G.CUT_OFF)
	assert_eq(t.entries[G.CUT_OFF], 1)


func test_min_hold_prevents_immediate_switch() -> void:
	var t := BossTactics.new()
	t.reevaluate(_ctx({distance = 11.0, fleeing = true}))   # goal_time = 0 < MIN_HOLD
	assert_eq(t.goal, G.ATTACK, "acaba de entrar en ATTACK: se mantiene")
	t.goal_time = BossTactics.MIN_HOLD
	t.reevaluate(_ctx({distance = 11.0, fleeing = true}))
	assert_eq(t.goal, G.CUT_OFF)


func test_hysteresis_keeps_current_goal_on_a_near_tie() -> void:
	var t := BossTactics.new()
	t.goal_time = 2.0
	# ATTACK 1.0 × 1.3 = 1.3 contra WAIT 1.1 (pasiva a 9 m): se queda.
	t.reevaluate(_ctx({distance = 9.0, passive = true}))
	assert_eq(t.goal, G.ATTACK)
	# Con una diferencia clara (WAIT 1.4 + 1.1) cambia.
	t.reevaluate(_ctx({distance = 9.0, passive = true, recent_damage = 0.2}))
	assert_eq(t.goal, G.WAIT)


func test_no_flicker_with_stable_context() -> void:
	var t := BossTactics.new()
	var ctx := _ctx({distance = 11.0, fleeing = true})
	var changes := 0
	for i in 12:   # 6 s
		if t.update(0.5, ctx):
			changes += 1
	# ATTACK → CUT_OFF, caduca a los 4 s → ATTACK (enfriamiento) y se queda: pocos cambios en 6 s.
	assert_true(changes <= 3, "cambios: %d" % changes)


func test_goal_expires_and_goes_on_cooldown() -> void:
	var t := BossTactics.new()
	t.goal_time = 2.0
	var ctx := _ctx({recent_damage = 0.2})
	t.reevaluate(ctx)
	assert_eq(t.goal, G.WAIT)
	t.goal_time = BossTactics.MAX_TIME[G.WAIT]
	t.reevaluate(ctx)
	assert_eq(t.goal, G.ATTACK, "caducó")
	t.goal_time = 5.0
	t.reevaluate(ctx)
	assert_eq(t.goal, G.ATTACK, "en enfriamiento no vuelve a esperar enseguida")


func test_goal_without_reason_is_dropped() -> void:
	var t := BossTactics.new()
	t.goal_time = 2.0
	t.reevaluate(_ctx({recent_damage = 0.2}))
	assert_eq(t.goal, G.WAIT)
	t.goal_time = 1.0
	t.reevaluate(_ctx())   # ya no hay motivo para esperar
	assert_eq(t.goal, G.ATTACK)


func test_time_in_goal_is_accumulated() -> void:
	var t := BossTactics.new()
	t.update(0.2, _ctx())
	t.update(0.2, _ctx())
	assert_almost(t.time_in_goal[G.ATTACK], 0.4)


func test_ambush_conditions() -> void:
	assert_true(BossTactics.is_ambush(true, false, 8.0, 3.0))
	assert_true(not BossTactics.is_ambush(false, false, 8.0, 3.0), "no está distraída")
	assert_true(not BossTactics.is_ambush(true, true, 8.0, 3.0), "huyendo no es emboscada")
	assert_true(not BossTactics.is_ambush(true, false, 2.0, 3.0), "ya está encima")
	assert_true(not BossTactics.is_ambush(true, false, 30.0, 3.0), "demasiado lejos")


func test_wait_point_backs_off_when_too_close_and_circles() -> void:
	var player := Vector3.ZERO
	var close := Vector3(0, 0, 4)   # el jefe a 4 m
	var p := BossTactics.wait_point(close, player, 1.0)
	assert_true(Vector2(p.x, p.z).length() > 4.0, "se aleja hasta el anillo de espera")
	assert_true(absf(p.x) > 0.5, "y rodea (componente tangencial)")
	var far := BossTactics.wait_point(Vector3(0, 0, 14), player, -1.0)
	assert_true(Vector2(far.x, far.z).length() < 14.0, "si está más lejos que el anillo se acerca")


func test_cut_off_point_keeps_boss_height() -> void:
	var p := BossTactics.cut_off_point(Vector3(5, 0, 5), Vector3(0, 2, 0))
	assert_eq(p, Vector3(5, 2, 5))


func test_brain_multipliers_scale_the_score() -> void:
	var a := BossAttack.new()
	a.id = &"tail_sweep"
	a.max_range = 5.0
	a.base_weight = 1.0
	assert_almost(BossBrain.score(a, 2.0, &"", 0.0, 1, {&"tail_sweep": 2.0}), 2.0)
	assert_almost(BossBrain.score(a, 2.0, &"", 0.0, 1, {&"bite": 5.0}), 1.0, 0.0001, "otro id no cuenta")
