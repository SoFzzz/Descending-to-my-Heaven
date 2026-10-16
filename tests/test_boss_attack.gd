extends TestCase
# BossAttack with advance (charge / pounce) and the exposed-hurtbox window (pure Boss logic).


func test_advance_defaults_to_zero() -> void:
	var a := BossAttack.new()
	assert_almost(a.advance_distance, 0.0)
	assert_almost(a.advance_at(0.5), 0.0, 0.0001, "without advance it does not move")
	assert_true(not a.opener and not a.exposes_hurtboxes and a.extra_hitbox_paths.is_empty() and a.visual_path.is_empty())


func test_advance_is_proportional_to_progress() -> void:
	var a := BossAttack.new()
	a.advance_distance = 12.0
	assert_almost(a.advance_at(0.0), 0.0)
	assert_almost(a.advance_at(0.25), 3.0)
	assert_almost(a.advance_at(1.0), 12.0)
	assert_almost(a.advance_at(1.7), 12.0, 0.0001, "does not exceed the total")
	assert_almost(a.advance_at(-1.0), 0.0, 0.0001)


func test_gate_window() -> void:
	assert_true(Boss.gate_open(true, 0.0))
	assert_true(Boss.gate_open(false, 0.1), "margin after the attack")
	assert_true(not Boss.gate_open(false, 0.0))


func test_attack_resources_with_advance() -> void:
	var charge := load("res://resources/attacks/blackhorn_charge.tres") as BossAttack
	var pounce := load("res://resources/attacks/blackhorn_pounce.tres") as BossAttack
	var slam := load("res://resources/attacks/blackhorn_slam.tres") as BossAttack
	assert_almost(charge.advance_distance, 12.0)
	assert_almost(pounce.advance_distance, 3.0)
	assert_almost(slam.advance_distance, 0.0)
	assert_true(charge.opener and pounce.opener and slam.opener, "charge, pounce and slam open")
	assert_eq(pounce.extra_hitbox_paths.size(), 2, "claws with the pounce")
	var beam := load("res://resources/attacks/ghidorah_beam.tres") as BossAttack
	assert_true(beam.opener, "the beam opens")
	assert_eq(beam.visual_path, NodePath("BeamVisual"))
	assert_true((load("res://resources/attacks/ghidorah_bite.tres") as BossAttack).exposes_hurtboxes, "the heads lower when biting")
	for file in ["bonedragon_bite", "bonedragon_stomp", "bonedragon_tail_sweep"]:
		var d := load("res://resources/attacks/%s.tres" % file) as BossAttack
		assert_true(not d.opener and d.advance_distance == 0.0 and not d.exposes_hurtboxes, file + ": the Bone Dragon does not change")
