extends TestCase
# Task 13: attacks and scenes of Blackhorn and Ghidorah (7.4, 8.2). The advance, the openers and the
# exposed hurtboxes live in Boss / BossAttack (see test_boss_attack.gd).
# Structure and data only: runtime behaviour is checked with the verification harness.

const ATTACK_DIR := "res://resources/attacks/"
const BLACKHORN := "res://scenes/bosses/boss_blackhorn.tscn"
const GHIDORAH := "res://scenes/bosses/boss_ghidorah.tscn"


func _attack(file: String) -> BossAttack:
	return load(ATTACK_DIR + file) as BossAttack


func _scene(path: String) -> Boss:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Boss


func _shape(boss: Node, path: String) -> Shape3D:
	var node := boss.get_node_or_null(NodePath(path + "/CollisionShape3D")) as CollisionShape3D
	return node.shape if node else null


# --- Attack resources ---------------------------------------------------------------------------

func test_blackhorn_attack_ranges() -> void:
	var slam := _attack("blackhorn_slam.tres")
	var pounce := _attack("blackhorn_pounce.tres")
	var charge := _attack("blackhorn_charge.tres")
	assert_true(slam != null and pounce != null and charge != null, "the 3 resources load as BossAttack")
	if slam == null or pounce == null or charge == null:
		return
	assert_eq(slam.id, &"slam")
	assert_almost(slam.min_range, 0.0)
	assert_almost(slam.max_range, 4.0)
	assert_eq(pounce.id, &"pounce")
	assert_almost(pounce.min_range, 2.0)
	assert_almost(pounce.max_range, 7.0)
	assert_eq(charge.id, &"charge")
	assert_almost(charge.min_range, 8.0)
	assert_almost(charge.max_range, 16.0)
	assert_eq(slam.phase_min, 1)
	assert_eq(pounce.phase_min, 1)
	assert_eq(charge.phase_min, 2, "the charge only in phase 2")


func test_ghidorah_attack_ranges() -> void:
	var bite := _attack("ghidorah_bite.tres")
	var tail := _attack("ghidorah_tail_sweep.tres")
	var beam := _attack("ghidorah_beam.tres")
	assert_true(bite != null and tail != null and beam != null, "the 3 resources load as BossAttack")
	if bite == null or tail == null or beam == null:
		return
	assert_eq(bite.id, &"bite")
	assert_almost(bite.min_range, 0.0)
	assert_almost(bite.max_range, 5.0)
	assert_eq(tail.id, &"tail_sweep")
	assert_almost(tail.max_range, 8.0)
	assert_true(tail.lateral, "the sweep covers the sides")
	assert_true(tail.spin_degrees > 0.0, "the sweep rotates the body")
	assert_eq(beam.id, &"beam")
	assert_almost(beam.min_range, 8.0)
	assert_almost(beam.max_range, 20.0)


func test_attack_timings_are_sane() -> void:
	for file in ["blackhorn_slam", "blackhorn_pounce", "blackhorn_charge", "ghidorah_bite", "ghidorah_tail_sweep", "ghidorah_beam"]:
		var a := _attack(file + ".tres")
		assert_true(a != null, file)
		if a == null:
			continue
		assert_true(a.telegraph_time >= 0.9, file + ": legible telegraph (>= 0.9 s)")
		assert_true(a.active_time > 0.0 and a.recovery_time > 0.0, file + ": positive windows")
		assert_true(a.damage > 0, file + ": does damage")
		assert_true(a.base_weight > 0.0, file)
		assert_true(not a.hitbox_path.is_empty(), file + ": hitbox_path")
		assert_true(a.animation != &"", file + ": animation")


# --- Scenes ------------------------------------------------------------------------------------

func _check_attack_wiring(boss: Boss, label: String) -> void:
	assert_eq(boss.attacks.size(), 3, label + ": 3 attacks")
	var anim := boss.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_true(anim != null, label + ": AnimationPlayer in the model")
	for attack in boss.attacks:
		var hb := boss.get_node_or_null(attack.hitbox_path) as Hitbox
		assert_true(hb != null, "%s: hitbox of %s" % [label, attack.id])
		if hb:
			assert_eq(hb.damage, attack.damage, "%s: hitbox damage = attack damage (%s)" % [label, attack.id])
			assert_eq(hb.collision_layer, 32, "%s: enemy_hitbox layer" % label)
			assert_eq(hb.collision_mask, 64, "%s: detects player_hurtbox" % label)
			assert_true(not hb.monitoring, "%s: %s starts inactive" % [label, attack.id])
		assert_true(boss.get_node_or_null(NodePath("Telegraphs/" + String(attack.id))) is Node3D, "%s: telegraph of %s" % [label, attack.id])
		if anim:
			assert_true(anim.has_animation(attack.animation), "%s: clip %s exists" % [label, attack.animation])
	if anim:
		for clip in [boss.idle_animation, boss.roar_animation, boss.death_animation]:
			assert_true(anim.has_animation(clip), "%s: clip %s" % [label, clip])


func test_blackhorn_scene() -> void:
	var boss := _scene(BLACKHORN)
	assert_true(boss != null, "boss_blackhorn.tscn loads as Boss")
	if boss == null:
		return
	assert_eq(boss.max_health, 625)
	assert_eq(boss.display_name, "Blackhorn")
	var nav := boss.get_node(^"NavigationAgent3D") as NavigationAgent3D
	assert_eq(nav.navigation_layers, 2, "large navigation layer")
	_check_attack_wiring(boss, "blackhorn")
	assert_eq(boss.collision_layer, 8, "boss layer")
	var cap := (boss.get_node(^"CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	assert_almost(cap.radius, 0.7)
	assert_almost(cap.height, 3.2)
	var hurt := _shape(boss, "BodyHurtbox") as CapsuleShape3D
	assert_true(hurt != null, "body hurtbox (capsule)")
	if hurt:
		assert_almost(hurt.radius, 1.0)
		assert_almost(hurt.height, 3.2)
	assert_almost((_shape(boss, "SlamHitbox") as SphereShape3D).radius, 3.8, 0.001, "slam: sphere r 3.8 (covers up to its max_range)")
	assert_almost((_shape(boss, "PounceHitbox") as BoxShape3D).size.x, 3.2)
	assert_almost((_shape(boss, "PounceHitbox") as BoxShape3D).size.y, 2.4)
	assert_almost((_shape(boss, "PounceHitbox") as BoxShape3D).size.z, 5.0, 0.001, "pounce 3.2 x 2.4 x 5 (from flush against the body)")
	var charge := (_shape(boss, "ChargeHitbox") as BoxShape3D).size
	assert_almost(charge.x, 2.4)
	assert_almost(charge.y, 2.5)
	assert_almost(charge.z, 4.0, 0.001, "charge 2.4 x 2.5 x 4")
	for claw in ["ClawLHitbox", "ClawRHitbox"]:
		var s := _shape(boss, claw) as SphereShape3D
		assert_true(s != null, claw)
		if s:
			assert_almost(s.radius, 0.6, 0.001, "claws r 0.6")
	assert_true(boss.get_node_or_null(^"LockOnPoint") is Marker3D)
	assert_eq(boss.walk_animation, &"run", "Blackhorn only runs (never walk)")
	assert_true(boss.settle_on_death, "rests the body on the ground when dying")
	assert_eq(boss.collision_mask & 2, 2, "does not pass through Kaelen (player layer in the mask)")
	assert_true(boss.get_node_or_null(^"AttackDriver") == null, "the AttackDriver no longer exists")
	boss.free()


func test_ghidorah_scene() -> void:
	var boss := _scene(GHIDORAH)
	assert_true(boss != null, "boss_ghidorah.tscn loads as Boss")
	if boss == null:
		return
	assert_eq(boss.max_health, 750)
	assert_eq(boss.display_name, "Mecha King Ghidorah")
	assert_eq((boss.get_node(^"NavigationAgent3D") as NavigationAgent3D).navigation_layers, 2)
	_check_attack_wiring(boss, "ghidorah")
	var cap := (boss.get_node(^"CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	assert_almost(cap.radius, 1.4, 0.001, "torso capsule (the real body has a ~1.2 m radius)")
	assert_almost(cap.height, 5.0)
	var model := boss.get_node(^"Model") as Node3D
	assert_almost(model.scale.y, 1.95, 0.001, "model scale x1.95 (8.1 m tall, ~14 m with the tail)")
	assert_almost((_shape(boss, "BiteHitbox") as BoxShape3D).size.z, 7.0, 0.001, "bite: fixed zone 7 m deep (from flush against the body to 5 m)")
	assert_almost((_shape(boss, "BeamHitbox") as BoxShape3D).size.z, 2.0, 0.001, "beam: short zone that travels with the impact")
	assert_almost((_shape(boss, "BeamHitbox") as BoxShape3D).size.x, 1.5)
	assert_almost((_shape(boss, "TailSweepHitbox") as BoxShape3D).size.z, 6.6, 0.001, "tail from 3 m (safe spot by the body) to the telegraph edge (9.6 m)")
	# Heads: hurtbox only (sphere r 1.0), closed until the head comes down.
	for head in ["HeadCHurtbox", "HeadLHurtbox", "HeadRHurtbox"]:
		var hurt := boss.get_node_or_null(NodePath(head)) as Hurtbox
		assert_true(hurt != null, head)
		if hurt == null:
			continue
		assert_almost((_shape(boss, head) as SphereShape3D).radius, 1.0, 0.001, head + " r 1.0")
		assert_true(not hurt.monitorable, head + " closed at the start")
		assert_true(boss.get_node_or_null(NodePath(head + "/CollisionShape3D")).get_parent() == hurt)
	assert_true(boss.get_node_or_null(^"TorsoHurtbox") is Hurtbox, "torso always reachable")
	assert_true((boss.get_node(^"TorsoHurtbox") as Hurtbox).monitorable)
	for leg in ["LegLHurtbox", "LegRHurtbox"]:
		assert_true(boss.get_node_or_null(NodePath(leg)) is Hurtbox, leg)
		assert_true((boss.get_node(NodePath(leg)) as Hurtbox).monitorable)
	assert_true(boss.get_node_or_null(^"AttackDriver") == null, "the AttackDriver no longer exists")
	assert_eq(boss.gated_hurtboxes.size(), 3, "the 3 heads can only be hit during the bite")
	for path in boss.gated_hurtboxes:
		assert_true(boss.get_node_or_null(path) is Hurtbox, str(path))
	var lock := boss.get_node(^"LockOnPoint") as Marker3D
	assert_true(lock.position.y > 2.0 and lock.position.y < 5.0, "LockOnPoint on the torso, at mid height")
	boss.free()
