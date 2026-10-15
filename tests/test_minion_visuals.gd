extends TestCase
# Visuales del esbirro: elección de clip, escalas de velocidad y montaje del modelo (sin escena .tscn).

const S := MinionBrain.State


func test_clip_kind_by_state() -> void:
	assert_eq(Minion.clip_kind(S.IDLE, 0.0), &"idle")
	assert_eq(Minion.clip_kind(S.IDLE, 3.0), &"idle")
	assert_eq(Minion.clip_kind(S.CHASE, 3.0), &"walk")
	assert_eq(Minion.clip_kind(S.CIRCLE, 2.0), &"walk")
	assert_eq(Minion.clip_kind(S.CHASE, 0.0), &"idle", "quieto en persecución -> idle")
	assert_eq(Minion.clip_kind(S.ATTACK, 0.0), &"attack")
	assert_eq(Minion.clip_kind(S.RECOVER, 0.0), &"attack", "el golpe termina durante RECOVER")
	assert_eq(Minion.clip_kind(S.STUNNED, 0.0), &"hurt")
	assert_eq(Minion.clip_kind(S.DEAD, 0.0), &"death")


func test_walk_speed_scale_is_proportional_and_clamped() -> void:
	assert_almost(Minion.walk_speed_scale(3.5, 3.5, 1.0), 1.0)
	assert_almost(Minion.walk_speed_scale(2.1, 3.5, 1.0), 0.6)
	assert_almost(Minion.walk_speed_scale(3.5, 3.5, 0.5), 0.5, 0.001, "walk_anim_speed multiplica")
	assert_almost(Minion.walk_speed_scale(0.1, 3.5, 1.0), Minion.WALK_SCALE_MIN)
	assert_almost(Minion.walk_speed_scale(99.0, 3.5, 1.0), Minion.WALK_SCALE_MAX)
	assert_almost(Minion.walk_speed_scale(2.0, 0.0, 0.7), 0.7, 0.001, "sin move_speed no divide")


func test_fit_speed_only_speeds_up() -> void:
	assert_almost(Minion.fit_speed(3.2, 1.6), 2.0)
	assert_almost(Minion.fit_speed(0.8, 1.6), 1.0, 0.001, "un clip corto no se ralentiza")
	assert_almost(Minion.fit_speed(0.0, 1.6), 1.0)
	assert_almost(Minion.fit_speed(1.0, 0.0), 1.0)


func test_defaults_keep_placeholder_behavior() -> void:
	var minion := Minion.new()
	assert_true(minion.model_scene == null)
	assert_true(minion.weapon_scene == null)
	assert_true(minion.sfx_attack == null and minion.sfx_hurt == null and minion.sfx_death == null)
	assert_almost(minion.model_yaw_offset, PI)
	assert_true(minion.tint.is_equal_approx(Color.WHITE))
	# Sin modelo todo es no-op: no revienta ni cambia el estado.
	minion._setup_visuals()
	minion._update_animation(true)
	minion._play_death()
	minion._play_sfx(null)
	assert_true(minion._model_root == null)
	assert_true(minion._anim == null)
	assert_eq(minion.state, S.IDLE)
	minion.free()


func test_attach_model_without_holder_fails_gracefully() -> void:
	var minion := Minion.new()
	var inst := Node3D.new()
	assert_true(not minion._attach_model(inst))
	inst.free()
	minion.free()


func test_attach_model_hides_placeholder_and_configures_clips() -> void:
	var minion := Minion.new()
	minion.model_scale = 1.5
	var holder := Node3D.new()
	holder.name = "Model"
	minion.add_child(holder)
	var body := MeshInstance3D.new()
	body.name = "Body"
	holder.add_child(body)
	var visor := MeshInstance3D.new()
	visor.name = "Visor"
	holder.add_child(visor)

	var rig := Node3D.new()
	var player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	library.add_animation(&"idle", Animation.new())
	library.add_animation(&"walk", Animation.new())
	library.add_animation(&"attack", Animation.new())
	player.add_animation_library(&"", library)
	rig.add_child(player)

	assert_true(minion._attach_model(rig))
	assert_true(not body.visible)
	assert_true(not visor.visible)
	assert_true(rig.get_parent() == holder)
	assert_almost(rig.rotation.y, PI)
	assert_almost(rig.scale.x, 1.5)
	assert_true(minion._anim == player)
	assert_eq(player.get_animation(&"idle").loop_mode, Animation.LOOP_LINEAR)
	assert_eq(player.get_animation(&"walk").loop_mode, Animation.LOOP_LINEAR)
	assert_eq(player.get_animation(&"attack").loop_mode, Animation.LOOP_NONE)
	minion.free()


func test_apply_tint_multiplies_modulate_color() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var mat := (load("res://assets/materials/psx_base.tres") as ShaderMaterial).duplicate() as ShaderMaterial
	mat.set_shader_parameter("modulate_color", Color(0.5, 1.0, 1.0, 1.0))
	mi.set_surface_override_material(0, mat)
	var root := Node3D.new()
	root.add_child(mi)

	Minion._apply_tint(root, Color(1, 1, 1, 1))
	assert_true((mat.get_shader_parameter("modulate_color") as Color).is_equal_approx(Color(0.5, 1.0, 1.0, 1.0)), "blanco no cambia nada")
	Minion._apply_tint(root, Color(0.5, 0.5, 1.0, 1.0))
	var result := mat.get_shader_parameter("modulate_color") as Color
	assert_true(result.is_equal_approx(Color(0.25, 0.5, 1.0, 1.0)), "multiplica por el tinte")
	root.free()


func test_attach_weapon_needs_the_bone() -> void:
	var minion := Minion.new()
	var rig := Node3D.new()
	var skeleton := Skeleton3D.new()
	rig.add_child(skeleton)
	var weapon := Node3D.new()
	assert_true(minion._attach_weapon(rig, weapon) == null, "sin hueso no se engancha")
	# glTF import renames "mixamorig:RightHand" to "mixamorig_RightHand": the export still finds it.
	skeleton.add_bone("mixamorig_RightHand")
	var attachment := minion._attach_weapon(rig, weapon)
	assert_true(attachment != null)
	assert_true(weapon.get_parent() != null and weapon.get_parent().get_parent() == attachment, "arma bajo WeaponGrip")
	assert_eq(attachment.bone_name, "mixamorig_RightHand")
	rig.free()
	minion.free()
