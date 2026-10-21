extends TestCase
# Attack warnings (God of War style): two fixed colours, a ground warning that replaces the flat
# discs, and the warning level of each attack. The aura's rise / fade in a level is checked in
# tests/flow/boss_combo_flow.tscn.


func test_two_fixed_colours() -> void:
	assert_true(AttackWarning.color_for(AttackWarning.Level.DODGE).is_equal_approx(AttackWarning.YELLOW))
	assert_true(AttackWarning.color_for(AttackWarning.Level.ESCAPE).is_equal_approx(AttackWarning.RED))


func test_aura_never_pops_in() -> void:
	assert_almost(AttackWarning.rise_time(0.1), AttackWarning.AURA_MIN_RISE, 0.001, "even a short warning rises")
	assert_almost(AttackWarning.rise_time(2.0), 2.0 * AttackWarning.AURA_RISE_FRACTION)
	assert_true(AttackWarning.AURA_FADE >= 0.2, "and it fades out, it does not vanish")


func test_ground_warning_replaces_discs_strips_and_rings() -> void:
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.0
	disc.mesh = cyl
	var mat := AttackWarning.make_ground(disc, AttackWarning.Level.DODGE)
	assert_true(mat != null and disc.mesh is PlaneMesh, "disc -> warning plane")
	assert_almost((disc.mesh as PlaneMesh).size.x, 6.0)
	assert_eq(int(mat.get_shader_parameter(&"shape")), 0)
	var ring := MeshInstance3D.new()
	var big := CylinderMesh.new()
	big.top_radius = 9.6
	ring.mesh = big
	var ring_mat := AttackWarning.make_ground(ring, AttackWarning.Level.ESCAPE, 3.0)
	assert_eq(int(ring_mat.get_shader_parameter(&"shape")), 2, "inner radius -> ring")
	assert_almost(float(ring_mat.get_shader_parameter(&"inner")), 3.0 / 9.6)
	var strip := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.4, 0.02, 16.0)
	strip.mesh = box
	var strip_mat := AttackWarning.make_ground(strip, AttackWarning.Level.DODGE)
	assert_eq(int(strip_mat.get_shader_parameter(&"shape")), 1)
	assert_true((strip.mesh as PlaneMesh).size.is_equal_approx(Vector2(2.4, 16.0)))
	AttackWarning.set_progress(strip, 0.5)
	assert_almost(float(strip_mat.get_shader_parameter(&"progress")), 0.5)
	assert_true(AttackWarning.make_ground(MeshInstance3D.new(), 1) == null, "no mesh: nothing to convert")
	for n in [disc, ring, strip]:
		n.free()


func test_boss_warning_levels() -> void:
	# Red: the roll's i-frames cannot cover them (360-degree sweeps, the beam): move, do not roll.
	for f in ["bonedragon_tail_sweep", "ghidorah_tail_sweep", "ghidorah_beam"]:
		var a := load("res://resources/attacks/%s.tres" % f) as BossAttack
		assert_eq(a.warning, AttackWarning.Level.ESCAPE, f + " is red")
	for f in ["bonedragon_bite", "bonedragon_stomp", "blackhorn_slam", "blackhorn_pounce", "blackhorn_charge", "ghidorah_bite"]:
		var a := load("res://resources/attacks/%s.tres" % f) as BossAttack
		assert_eq(a.warning, AttackWarning.Level.DODGE, f + " is yellow")


func test_every_boss_ground_warning_uses_the_shader() -> void:
	for path in ["res://scenes/bosses/boss_bonedragon.tscn", "res://scenes/bosses/boss_blackhorn.tscn", "res://scenes/bosses/boss_ghidorah.tscn"]:
		# Boss._ready converts each one with make_ground: every authored warning must be convertible.
		var boss := (load(path) as PackedScene).instantiate() as Boss
		for a in boss.attacks:
			var tg := boss.get_node_or_null(NodePath("Telegraphs/" + String(a.id))) as MeshInstance3D
			assert_true(tg != null and AttackWarning.make_ground(tg, a.warning, a.telegraph_inner) != null,
					"%s: %s warning converts to the shader" % [path, a.id])
		boss.free()


func test_minion_special_attacks_warn_and_the_cast_cools_down() -> void:
	var cast := load("res://resources/attacks/minions/plague_cast.tres") as MinionAttack
	assert_eq(cast.warning, AttackWarning.Level.DODGE)
	assert_true(cast.cooldown >= 3.0, "the cast mixes in the melee")
	var claw := load("res://resources/attacks/minions/plague_claw.tres") as MinionAttack
	assert_eq(claw.warning, AttackWarning.Level.NONE, "a plain swing has no aura")


func test_hit_kind_without_a_player_is_normal() -> void:
	assert_eq(Minion.hit_kind(null), &"normal")
	var n := Node3D.new()
	assert_eq(Minion.hit_kind(n), &"normal")
	n.free()
