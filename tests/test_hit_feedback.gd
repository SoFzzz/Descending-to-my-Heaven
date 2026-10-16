extends TestCase
# Feedback de combate (partes sin árbol): color del parpadeo y encuadre de cámara. La pausa de impacto y el
# parpadeo con Tween necesitan árbol: tests/flow/hit_feedback_flow.tscn.


func test_player_flash_is_red_and_enemy_white() -> void:
	var player := Node3D.new()
	player.add_to_group(&"player")
	var hb := Hurtbox.new()
	player.add_child(hb)
	assert_eq(HitFlash.color_for(hb), HitFlash.COLOR_PLAYER)
	var enemy := Node3D.new()
	enemy.add_to_group(&"enemy")
	var hb2 := Hurtbox.new()
	enemy.add_child(hb2)
	assert_eq(HitFlash.color_for(hb2), HitFlash.COLOR_ENEMY)
	player.free()
	enemy.free()


func test_camera_arm_grows_for_far_bosses_only() -> void:
	assert_almost(CameraRig.boss_arm_extra(5.0), 0.0, 0.0001, "cerca no cambia")
	assert_almost(CameraRig.boss_arm_extra(8.0), 0.0, 0.0001)
	assert_almost(CameraRig.boss_arm_extra(13.0), 2.0, 0.0001, "5 m de más = 2 m de brazo")
	assert_almost(CameraRig.boss_arm_extra(40.0), CameraRig.ARM_EXTRA_MAX, 0.0001, "tope")
