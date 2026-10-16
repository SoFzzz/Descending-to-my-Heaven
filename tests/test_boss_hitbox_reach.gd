extends TestCase
# Boss damage zones: they cover what the attack shows and leave no gaps next to the body
# (checked against the scene geometry; the animated map is in scripts/tools/boss_hitbox_map.gd).

const KAELEN_RADIUS := 0.3


func _boss(path: String) -> Node3D:
	return (load(path) as PackedScene).instantiate() as Node3D


## True if the capsule of Kaelen at `feet` (floor, boss frame) touches the shape of hitbox `name`.
func _reaches(boss: Node3D, hitbox: String, feet: Vector3) -> bool:
	var hb := boss.get_node(hitbox) as Node3D
	var cs := hb.get_node(^"CollisionShape3D") as CollisionShape3D
	var xf := hb.transform * cs.transform
	for i in 5:
		var l := xf.affine_inverse() * (feet + Vector3(0.0, lerpf(0.4, 1.3, i / 4.0), 0.0))
		var d := INF
		if cs.shape is SphereShape3D:
			d = maxf(l.length() - (cs.shape as SphereShape3D).radius, 0.0)
		elif cs.shape is BoxShape3D:
			var h := (cs.shape as BoxShape3D).size * 0.5
			d = Vector3(maxf(absf(l.x) - h.x, 0.0), maxf(absf(l.y) - h.y, 0.0), maxf(absf(l.z) - h.z, 0.0)).length()
		if d <= KAELEN_RADIUS:
			return true
	return false


func test_blackhorn_slam_reaches_its_whole_range() -> void:
	var boss := _boss("res://scenes/bosses/boss_blackhorn.tscn")
	var slam := load("res://resources/attacks/blackhorn_slam.tres") as BossAttack
	for angle in [0.0, 60.0, 120.0, 180.0, 270.0]:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(angle))
		assert_true(_reaches(boss, "SlamHitbox", dir * slam.max_range), "slam reaches %s m (%s degrees)" % [slam.max_range, angle])
	boss.free()


func test_blackhorn_pounce_starts_beside_the_body() -> void:
	var boss := _boss("res://scenes/bosses/boss_blackhorn.tscn")
	assert_true(_reaches(boss, "PounceHitbox", Vector3(0.0, 0.0, -0.8)), "flush from the front")
	assert_true(_reaches(boss, "PounceHitbox", Vector3(1.5, 0.0, -0.5)), "flush against the side")
	assert_true(_reaches(boss, "PounceHitbox", Vector3(1.4, 0.0, -3.5)), "3.2 m lane, not 2")
	assert_true(_reaches(boss, "ChargeHitbox", Vector3(1.0, 0.0, -0.3)), "the charge starts flush against the boss")
	boss.free()


func test_bonedragon_has_no_safe_spot_under_its_attacks() -> void:
	var boss := _boss("res://scenes/bosses/boss_bonedragon.tscn")
	var stomp := load("res://resources/attacks/bonedragon_stomp.tres") as BossAttack
	var tail := load("res://resources/attacks/bonedragon_tail_sweep.tres") as BossAttack
	assert_true(_reaches(boss, "StompHitbox", Vector3(0.0, 0.0, -stomp.max_range)), "stomp reaches its max_range")
	assert_true(_reaches(boss, "StompHitbox", Vector3(2.7, 0.0, 0.0)), "and the side")
	# The tail starts at the body (z 0) and reaches the edge of the warning; the 360-degree sweep covers the rest.
	assert_true(_reaches(boss, "TailSweepHitbox", Vector3(0.0, 0.0, 0.3)), "tail: flush against the body")
	assert_true(_reaches(boss, "TailSweepHitbox", Vector3(0.0, 0.0, tail.max_range)), "tail: up to its max_range")
	var bite := boss.get_node(^"Model/metarig/Skeleton3D/SkullAttach/BiteHitbox/CollisionShape3D") as CollisionShape3D
	assert_true((bite.shape as SphereShape3D).radius >= 1.6, "the bite covers +-2 m, not just the snout line")
	boss.free()


func test_ghidorah_tail_has_no_hole_at_the_body() -> void:
	var boss := _boss("res://scenes/bosses/boss_ghidorah.tscn")
	var tail := load("res://resources/attacks/ghidorah_tail_sweep.tres") as BossAttack
	for z in [0.4, 1.5, 3.0, 5.0, tail.max_range]:
		assert_true(_reaches(boss, "TailSweepHitbox", Vector3(0.0, 0.0, z)), "tail reaches %s m" % z)
	boss.free()


func test_bosses_are_tougher_than_before() -> void:
	# Difficulty figures (see docs/): more health, shorter warnings and recoveries, little dead time.
	var expected := {
		"res://scenes/bosses/boss_bonedragon.tscn": 500,
		"res://scenes/bosses/boss_blackhorn.tscn": 625,
		"res://scenes/bosses/boss_ghidorah.tscn": 750,
	}
	for path in expected:
		var boss := (load(path) as PackedScene).instantiate() as Boss
		assert_eq(boss.max_health, expected[path], path)
		assert_true(boss.attack_cooldown <= 0.35, "little dead time between attacks")
		for a in boss.attacks:
			assert_true(a.recovery_time <= 1.1 and a.telegraph_time <= 1.5, "%s: telegraph and recovery bounded" % a.id)
		boss.free()
