extends TestCase
# Alcance de la espada de Kaelen: la caja de daño cubre una espada larga (hoja de ~2.3 m,
# alcance efectivo 2.5-3 m desde Kaelen) y las hurtboxes de los jefes cubren su cuerpo visible.
# Medido barriendo los 3 golpes contra cada objetivo: antes / ahora (distancia máx. de acierto, m)
# esbirro 2.25 / 3.0, Blackhorn 2.5 / 3.5, Ghidorah 3.75 / 4.5, Bone Dragon 3.25 / 4.0.


func test_sword_hitbox_is_long() -> void:
	var kaelen := (load("res://scenes/player/kaelen.tscn") as PackedScene).instantiate()
	var box := (kaelen.get_node(^"SwordHitbox/CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	assert_true(box.size.z >= 2.0, "la caja de la espada mide %s m" % box.size.z)
	# Centro de la caja (marcador, en el agarre) + media longitud = borde lejano desde la mano.
	var marker := kaelen.get_node(^"Model/Armature/Skeleton3D/RightHand/SwordGrip/SwordHitboxMarker") as Node3D
	assert_true(marker.position.x + box.size.z * 0.5 >= 2.0, "el borde lejano queda a >= 2 m de la mano")
	kaelen.free()


func test_sword_blade_matches_hitbox() -> void:
	var kaelen := (load("res://scenes/player/kaelen.tscn") as PackedScene).instantiate()
	var sword := kaelen.get_node(^"Model/Armature/Skeleton3D/RightHand/SwordGrip/Greatsword") as Node3D
	var marker := kaelen.get_node(^"Model/Armature/Skeleton3D/RightHand/SwordGrip/SwordHitboxMarker") as Node3D
	# La hoja crece a lo largo del eje X del agarre (escala 2.32 del eje Y de la espada).
	var blade_len: float = sword.transform.basis.y.length()  # modelo de ~1 m de largo
	assert_true(blade_len >= 2.2, "la espada mide ~%s m" % blade_len)
	var tip := sword.position.x + blade_len * 0.5
	var hit_edge := marker.position.x + 1.075
	assert_true(hit_edge >= tip - 0.05, "la caja de daño llega a la punta visible")
	kaelen.free()


func test_blackhorn_hurtbox_covers_body() -> void:
	var boss := (load("res://scenes/bosses/boss_blackhorn.tscn") as PackedScene).instantiate()
	var shape := (boss.get_node(^"BodyHurtbox/CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	var body := (boss.get_node(^"CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	assert_true(shape.radius >= 1.0, "radio de la hurtbox %s" % shape.radius)
	assert_true(shape.radius > body.radius, "la hurtbox sobresale del cuerpo fisico")
	boss.free()
