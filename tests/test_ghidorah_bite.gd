extends TestCase
# Ghidorah bite: the damage zone covers from flush against the body up to the attack's max_range,
# and does not depend on the head height (before it followed the jaw, almost at ground level at 3.5 m).

const KAELEN_RADIUS := 0.3


func _box_dist(shape: BoxShape3D, xf: Transform3D, p: Vector3) -> float:
	var l := xf.affine_inverse() * p
	var h := shape.size * 0.5
	return Vector3(maxf(absf(l.x) - h.x, 0.0), maxf(absf(l.y) - h.y, 0.0), maxf(absf(l.z) - h.z, 0.0)).length()


## True if the capsule of Kaelen's hurtbox (r 0.30, axes from 0.4 to 1.3 m) touches the box.
func _reaches(boss: Node3D, feet: Vector3) -> bool:
	var hb := boss.get_node(^"BiteHitbox") as Node3D
	var shape := (hb.get_node(^"CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	var xf := hb.transform * (hb.get_node(^"CollisionShape3D") as CollisionShape3D).transform
	for i in 8:
		if _box_dist(shape, xf, feet + Vector3(0.0, lerpf(0.4, 1.3, i / 7.0), 0.0)) <= KAELEN_RADIUS:
			return true
	return false


func test_bite_covers_close_range() -> void:
	var boss := (load("res://scenes/bosses/boss_ghidorah.tscn") as PackedScene).instantiate() as Node3D
	var bite := load("res://resources/attacks/ghidorah_bite.tres") as BossAttack
	assert_true(boss.get_node(^"BiteHitbox/CollisionShape3D").shape is BoxShape3D, "fixed zone, not a sphere at the jaw")
	for z in [0.0, -1.8, -2.0, -3.0, -4.0, -bite.max_range]:
		assert_true(_reaches(boss, Vector3(0.0, 0.0, z)), "reaches Kaelen at %s m ahead" % absf(z))
	assert_true(_reaches(boss, Vector3(1.8, 0.0, 0.0)), "flush against the side of the body")
	assert_true(_reaches(boss, Vector3(1.5, 0.0, -2.0)), "at 2 m and 1.5 m to the side")
	assert_true(not _reaches(boss, Vector3(0.0, 0.0, -(bite.max_range + 1.5))), "beyond range it does not")
	boss.free()


func test_boss_stops_inside_bite_range() -> void:
	var boss := (load("res://scenes/bosses/boss_ghidorah.tscn") as PackedScene).instantiate() as Boss
	var bite := load("res://resources/attacks/ghidorah_bite.tres") as BossAttack
	assert_true(boss.engage_range <= bite.max_range, "stops at bite distance")
	boss.free()
