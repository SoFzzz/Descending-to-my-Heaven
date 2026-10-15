extends TestCase
# Mordida de Ghidorah: la zona de daño cubre desde pegado al cuerpo hasta el max_range del ataque,
# no depende de la altura de la cabeza (antes seguia a la mandibula, casi a ras de suelo a 3.5 m).

const KAELEN_RADIUS := 0.3


func _box_dist(shape: BoxShape3D, xf: Transform3D, p: Vector3) -> float:
	var l := xf.affine_inverse() * p
	var h := shape.size * 0.5
	return Vector3(maxf(absf(l.x) - h.x, 0.0), maxf(absf(l.y) - h.y, 0.0), maxf(absf(l.z) - h.z, 0.0)).length()


## True si la capsula de la hurtbox de Kaelen (r 0.30, ejes de 0.4 a 1.3 m) toca la caja.
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
	assert_true(boss.get_node(^"BiteHitbox/CollisionShape3D").shape is BoxShape3D, "zona fija, no una esfera en la mandibula")
	for z in [0.0, -1.8, -2.0, -3.0, -4.0, -bite.max_range]:
		assert_true(_reaches(boss, Vector3(0.0, 0.0, z)), "alcanza a Kaelen a %s m delante" % absf(z))
	assert_true(_reaches(boss, Vector3(1.8, 0.0, 0.0)), "pegada al costado del cuerpo")
	assert_true(_reaches(boss, Vector3(1.5, 0.0, -2.0)), "a 2 m y 1.5 m al lado")
	assert_true(not _reaches(boss, Vector3(0.0, 0.0, -(bite.max_range + 1.5))), "mas alla del rango no")
	boss.free()


func test_boss_stops_inside_bite_range() -> void:
	var boss := (load("res://scenes/bosses/boss_ghidorah.tscn") as PackedScene).instantiate() as Boss
	var bite := load("res://resources/attacks/ghidorah_bite.tres") as BossAttack
	assert_true(boss.engage_range <= bite.max_range, "se detiene a distancia de mordida")
	boss.free()
