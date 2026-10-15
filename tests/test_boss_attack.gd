extends TestCase
# BossAttack con avance (embestida / salto) y ventana de las hurtboxes expuestas (lógica pura de Boss).


func test_advance_defaults_to_zero() -> void:
	var a := BossAttack.new()
	assert_almost(a.advance_distance, 0.0)
	assert_almost(a.advance_at(0.5), 0.0, 0.0001, "sin avance no se mueve")
	assert_true(not a.opener and not a.exposes_hurtboxes and a.extra_hitbox_paths.is_empty() and a.visual_path.is_empty())


func test_advance_is_proportional_to_progress() -> void:
	var a := BossAttack.new()
	a.advance_distance = 12.0
	assert_almost(a.advance_at(0.0), 0.0)
	assert_almost(a.advance_at(0.25), 3.0)
	assert_almost(a.advance_at(1.0), 12.0)
	assert_almost(a.advance_at(1.7), 12.0, 0.0001, "no pasa del total")
	assert_almost(a.advance_at(-1.0), 0.0, 0.0001)


func test_gate_window() -> void:
	assert_true(Boss.gate_open(true, 0.0))
	assert_true(Boss.gate_open(false, 0.1), "margen tras el ataque")
	assert_true(not Boss.gate_open(false, 0.0))


func test_attack_resources_with_advance() -> void:
	var charge := load("res://resources/attacks/blackhorn_charge.tres") as BossAttack
	var pounce := load("res://resources/attacks/blackhorn_pounce.tres") as BossAttack
	var slam := load("res://resources/attacks/blackhorn_slam.tres") as BossAttack
	assert_almost(charge.advance_distance, 12.0)
	assert_almost(pounce.advance_distance, 3.0)
	assert_almost(slam.advance_distance, 0.0)
	assert_true(charge.opener and pounce.opener and slam.opener, "embestida, salto y golpe al suelo abren")
	assert_eq(pounce.extra_hitbox_paths.size(), 2, "garras con el salto")
	var beam := load("res://resources/attacks/ghidorah_beam.tres") as BossAttack
	assert_true(beam.opener, "el rayo abre")
	assert_eq(beam.visual_path, NodePath("BeamVisual"))
	assert_true((load("res://resources/attacks/ghidorah_bite.tres") as BossAttack).exposes_hurtboxes, "las cabezas bajan al morder")
	for file in ["bonedragon_bite", "bonedragon_stomp", "bonedragon_tail_sweep"]:
		var d := load("res://resources/attacks/%s.tres" % file) as BossAttack
		assert_true(not d.opener and d.advance_distance == 0.0 and not d.exposes_hurtboxes, file + ": el Bone Dragon no cambia")
