extends TestCase
# Rayo de Ghidorah: apertura del efecto y que coincida con la hitbox (1.5 x 1.5 x 20 m).


func test_open_progress() -> void:
	assert_almost(BeamVfx.open_progress(0.0), 0.0)
	assert_almost(BeamVfx.open_progress(BeamVfx.OPEN_TIME * 0.5), 0.5)
	assert_almost(BeamVfx.open_progress(5.0), 1.0, 0.0001, "no pasa de 1")
	assert_almost(BeamVfx.open_progress(1.0, 0.0), 1.0, 0.0001, "duracion 0 = abierto")


func test_beam_visual_matches_hitbox() -> void:
	var scene := load("res://scenes/bosses/boss_ghidorah.tscn") as PackedScene
	var boss := scene.instantiate()
	var attack := load("res://resources/attacks/ghidorah_beam.tres") as BossAttack
	var visual := boss.get_node_or_null(attack.visual_path) as BeamVfx
	assert_true(visual != null, "BeamVisual es un BeamVfx")
	assert_true(not visual.visible, "oculto fuera de ACTIVE")
	assert_almost(visual.beam_length, 20.0, 0.0001, "largo = hitbox")
	var hitbox := boss.get_node(attack.hitbox_path) as Node3D
	var box := (hitbox.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	# El rayo sale de visual.position hacia -Z y debe cubrir el largo de la caja.
	assert_almost(visual.position.z - visual.beam_length, hitbox.position.z - box.size.z * 0.5, 0.0001, "punta del rayo")
	assert_almost(visual.position.z, hitbox.position.z + box.size.z * 0.5, 0.0001, "origen del rayo")
	boss.free()
