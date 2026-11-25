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


# Design change (AGENTS.md 18.3, wave 1): the Bone Dragon's bite lunges forward (before, no Bone
# Dragon attack moved it). It still has no openers or exposed hurtboxes, and the stomp and the tail
# sweep stay put. The bite's ground warning is a lane that covers the lunge, like the pounce's.
func test_bonedragon_bite_lunges_and_its_warning_covers_it() -> void:
	for file in ["bonedragon_bite", "bonedragon_stomp", "bonedragon_tail_sweep"]:
		var d := load("res://resources/attacks/%s.tres" % file) as BossAttack
		assert_true(not d.opener and not d.exposes_hurtboxes, file + ": no openers, no exposed hurtboxes")
	var bite := load("res://resources/attacks/bonedragon_bite.tres") as BossAttack
	assert_true(bite.advance_distance >= 1.0 and bite.advance_distance <= 2.0, "the bite lunges 1-2 m")
	assert_almost((load("res://resources/attacks/bonedragon_stomp.tres") as BossAttack).advance_distance, 0.0)
	assert_almost((load("res://resources/attacks/bonedragon_tail_sweep.tres") as BossAttack).advance_distance, 0.0)
	var boss := (load("res://scenes/bosses/boss_bonedragon.tscn") as PackedScene).instantiate() as Boss
	var hb := boss.get_node(bite.hitbox_path) as Node3D
	var radius := ((hb.get_node(^"CollisionShape3D") as CollisionShape3D).shape as SphereShape3D).radius
	var tg := boss.get_node(^"Telegraphs/bite") as MeshInstance3D
	var lane := (tg.mesh as BoxMesh).size
	assert_true(lane.x >= radius * 2.0 - 0.01, "the lane is as wide as the bite sphere")
	# Measured with scripts/tools/boss_hitbox_map.gd (animation + lunge): the bite touches Kaelen from
	# the body (z ≈ 0) to 6 m ahead, i.e. its max_range plus the lunge.
	assert_true(tg.position.z + lane.z * 0.5 >= -0.35, "the lane starts at the body")
	assert_true(tg.position.z - lane.z * 0.5 <= -(bite.max_range + bite.advance_distance) + 0.01, "and reaches max_range + the lunge")
	boss.free()
