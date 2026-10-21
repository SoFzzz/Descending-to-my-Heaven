extends TestCase
# Kaelen's sword reach: the damage box covers a long sword (blade of ~1.95 m since 2026-10-20; the
# 2.3 m one read as too big; effective reach ≈ 2.35 m from Kaelen) and the boss hurtboxes cover
# their visible body.
# Measured by sweeping the 3 hits against each target: before / now (max hit distance, m)
# minion 2.25 / 3.0, Blackhorn 2.5 / 3.5, Ghidorah 3.75 / 4.5, Bone Dragon 3.25 / 4.0.


func test_sword_hitbox_is_long() -> void:
	var kaelen := (load("res://scenes/player/kaelen.tscn") as PackedScene).instantiate()
	var box := (kaelen.get_node(^"SwordHitbox/CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	assert_true(box.size.z >= 1.8, "the sword box measures %s m" % box.size.z)
	# Box center (marker, at the grip) + half the length = far edge from the hand.
	var marker := kaelen.get_node(^"Model/Armature/Skeleton3D/RightHand/SwordGrip/SwordHitboxMarker") as Node3D
	assert_true(marker.position.x + box.size.z * 0.5 >= 1.75, "the far edge is at >= 1.75 m from the hand")
	kaelen.free()


func test_sword_blade_matches_hitbox() -> void:
	var kaelen := (load("res://scenes/player/kaelen.tscn") as PackedScene).instantiate()
	var sword := kaelen.get_node(^"Model/Armature/Skeleton3D/RightHand/SwordGrip/Greatsword") as Node3D
	var marker := kaelen.get_node(^"Model/Armature/Skeleton3D/RightHand/SwordGrip/SwordHitboxMarker") as Node3D
	# The blade grows along the grip's X axis (1.95 scale of the sword's Y axis).
	var blade_len: float = sword.transform.basis.y.length()  # model about 1 m long
	assert_true(blade_len >= 1.9, "the sword measures ~%s m" % blade_len)
	var box := (kaelen.get_node(^"SwordHitbox/CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	var tip := sword.position.x + blade_len * 0.5
	var hit_edge := marker.position.x + box.size.z * 0.5
	assert_true(hit_edge >= tip - 0.05, "the damage box reaches the visible tip")
	kaelen.free()


func test_blackhorn_hurtbox_covers_body() -> void:
	var boss := (load("res://scenes/bosses/boss_blackhorn.tscn") as PackedScene).instantiate()
	var shape := (boss.get_node(^"BodyHurtbox/CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	var body := (boss.get_node(^"CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	assert_true(shape.radius >= 1.0, "hurtbox radius %s" % shape.radius)
	assert_true(shape.radius > body.radius, "the hurtbox sticks out of the physical body")
	boss.free()
