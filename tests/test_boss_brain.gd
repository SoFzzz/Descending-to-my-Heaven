extends TestCase
# BossBrain tests (utility-based attack selection, spec §8.2) and the phase-2 rule.


func _attack(id: StringName, min_range: float, max_range: float, weight: float, phase_min := 1, lateral := false) -> BossAttack:
	var a := BossAttack.new()
	a.id = id
	a.min_range = min_range
	a.max_range = max_range
	a.base_weight = weight
	a.phase_min = phase_min
	a.lateral = lateral
	return a


func test_out_of_range_scores_zero() -> void:
	var a := _attack(&"bite", 0.0, 4.0, 1.0)
	assert_almost(BossBrain.score(a, 5.0, &"", 0.0, 1), 0.0, 0.0001, "farther than max_range")
	var b := _attack(&"far", 3.0, 8.0, 1.0)
	assert_almost(BossBrain.score(b, 2.0, &"", 0.0, 1), 0.0, 0.0001, "closer than min_range")
	assert_almost(BossBrain.score(b, 5.0, &"", 0.0, 1), 1.0, 0.0001, "within range it is worth the base weight")


func test_repeat_penalty() -> void:
	var a := _attack(&"bite", 0.0, 4.0, 2.0)
	assert_almost(BossBrain.score(a, 2.0, &"stomp", 0.0, 1), 2.0)
	assert_almost(BossBrain.score(a, 2.0, &"bite", 0.0, 1), 0.6, 0.0001, "x 0.3 if it was the last one")


func test_phase2_multiplier() -> void:
	var a := _attack(&"bite", 0.0, 4.0, 1.0)
	assert_almost(BossBrain.score(a, 2.0, &"", 0.0, 2), 1.25)
	assert_almost(BossBrain.score(a, 2.0, &"bite", 0.0, 2), 0.375, 0.0001, "combines with the penalty")


func test_lateral_bonus() -> void:
	var a := _attack(&"tail", 0.0, 5.0, 1.0, 1, true)
	var b := _attack(&"bite", 0.0, 5.0, 1.0)
	assert_almost(BossBrain.score(a, 2.0, &"", -0.5, 1), 1.25, 0.0001, "1 + 0.5 × |bias|")
	assert_almost(BossBrain.score(b, 2.0, &"", -0.5, 1), 1.0, 0.0001, "only the lateral ones")


func test_choose_never_returns_out_of_range() -> void:
	var brain := BossBrain.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var attacks: Array[BossAttack] = [_attack(&"near", 0.0, 3.0, 5.0), _attack(&"far", 6.0, 10.0, 1.0)]
	for i in 100:
		var chosen := brain.choose(attacks, 8.0, 1, rng)
		assert_true(chosen != null and chosen.id == &"far", "at 8 m only far is valid")
	assert_true(brain.choose(attacks, 4.5, 1, rng) == null, "none in range -> null")


func test_choose_only_from_top_two() -> void:
	var brain := BossBrain.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var attacks: Array[BossAttack] = [
		_attack(&"low", 0.0, 6.0, 0.5),
		_attack(&"high", 0.0, 6.0, 1.0),
		_attack(&"mid", 0.0, 6.0, 0.8),
	]
	var counts := {&"low": 0, &"high": 0, &"mid": 0}
	for i in 200:
		var chosen := brain.choose(attacks, 3.0, 1, rng)
		counts[chosen.id] += 1
	assert_eq(counts[&"low"], 0, "the lowest score never comes out")
	assert_true(counts[&"high"] > 0 and counts[&"mid"] > 0, "the two best come out: %s" % str(counts))


func test_phase_min_filter() -> void:
	var brain := BossBrain.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var attacks: Array[BossAttack] = [_attack(&"basic", 0.0, 6.0, 0.1), _attack(&"rage", 0.0, 6.0, 10.0, 2)]
	for i in 50:
		assert_eq(brain.choose(attacks, 2.0, 1, rng).id, &"basic", "in phase 1 the phase 2 one does not come out")
	var seen_rage := false
	for i in 50:
		if brain.choose(attacks, 2.0, 2, rng).id == &"rage":
			seen_rage = true
	assert_true(seen_rage, "in phase 2 it can come out")


func test_dodge_bias_average() -> void:
	var brain := BossBrain.new()
	assert_almost(brain.dodge_bias, 0.0)
	brain.record_dodge(1)
	brain.record_dodge(1)
	brain.record_dodge(-1)
	assert_almost(brain.dodge_bias, 0.333, 0.001)
	# Only the last 6 count.
	for i in 6:
		brain.record_dodge(-1)
	assert_almost(brain.dodge_bias, -1.0)


func test_boss_phase_change_at_half() -> void:
	assert_true(not BossBrain.should_enter_phase2(201, 400, 1), "above 50 %")
	assert_true(BossBrain.should_enter_phase2(200, 400, 1), "at 50 % it enters phase 2")
	assert_true(BossBrain.should_enter_phase2(120, 400, 1), "below too, if still in phase 1")
	assert_true(not BossBrain.should_enter_phase2(150, 400, 2), "only once: already in phase 2")
	assert_true(not BossBrain.should_enter_phase2(0, 400, 1), "dead does not change phase")


# --- Opener attacks (long range) while the boss is still approaching ---------------------------

func _opener(id: StringName, min_range: float, max_range: float, phase_min := 1) -> BossAttack:
	var a := _attack(id, min_range, max_range, 1.0, phase_min)
	a.opener = true
	return a


func test_approaching_only_considers_openers() -> void:
	var brain := BossBrain.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var attacks: Array[BossAttack] = [_attack(&"bite", 0.0, 9.0, 5.0), _opener(&"beam", 8.0, 20.0)]
	for i in 30:
		assert_eq(brain.choose(attacks, 8.5, 1, rng, true).id, &"beam", "approaching at 8.5 m: only the opener")
	assert_true(brain.choose(attacks, 5.0, 1, rng, true) == null, "at 5 m the opener does not reach: keeps approaching")


func test_not_approaching_uses_every_attack() -> void:
	var brain := BossBrain.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var attacks: Array[BossAttack] = [_attack(&"bite", 0.0, 9.0, 5.0), _opener(&"beam", 8.0, 20.0)]
	var seen := {}
	for i in 60:
		seen[brain.choose(attacks, 8.5, 1, rng).id] = true
	assert_true(seen.has(&"bite") and seen.has(&"beam"), "it has arrived: all valid attacks compete")


func test_opener_is_never_repeated_while_approaching() -> void:
	var brain := BossBrain.new()
	var rng := RandomNumberGenerator.new()
	var attacks: Array[BossAttack] = [_opener(&"beam", 8.0, 20.0)]
	brain.last_attack_id = &"beam"
	assert_true(brain.choose(attacks, 12.0, 1, rng, true) == null, "after the beam it approaches instead of repeating")
	brain.last_attack_id = &"bite"
	assert_eq(brain.choose(attacks, 12.0, 1, rng, true).id, &"beam")


func test_opener_respects_phase_and_range() -> void:
	var brain := BossBrain.new()
	var rng := RandomNumberGenerator.new()
	var attacks: Array[BossAttack] = [_opener(&"charge", 8.0, 16.0, 2)]
	assert_true(brain.choose(attacks, 12.0, 1, rng, true) == null, "phase 1: no charge")
	assert_eq(brain.choose(attacks, 12.0, 2, rng, true).id, &"charge")
	assert_true(brain.choose(attacks, 17.0, 2, rng, true) == null, "farther than max_range: it approaches")
	assert_true(brain.choose(attacks, 7.0, 2, rng, true) == null, "closer than min_range")
