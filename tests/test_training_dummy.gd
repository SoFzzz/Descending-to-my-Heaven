extends TestCase
# Training dummy of the tutorial: the Straw Reaper's model (a scarecrow) with the same collision,
# hurtbox and lock-on point as before. Its fixed pose and facing are checked in intro_tutorial_flow.

const DUMMY := "res://scenes/enemies/training_dummy.tscn"


func test_dummy_uses_the_straw_reaper_model() -> void:
	var dummy := (load(DUMMY) as PackedScene).instantiate() as Node3D
	var reaper := dummy.get_node_or_null(^"Model/StrawReaper") as Node3D
	assert_true(reaper != null, "Model/StrawReaper")
	assert_eq(reaper.scene_file_path, "res://assets/minions/straw_reaper/straw_reaper.glb")
	assert_almost(absf(reaper.rotation.y), PI, 0.001, "turned PI like the minions (the model faces +Z)")
	var anim := reaper.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_true(anim != null and anim.has_animation(dummy.get(&"POSE_CLIP")), "it has the pose clip")
	assert_true(dummy.get_node_or_null(^"Mesh") == null, "the old capsule mesh is gone")
	dummy.free()


func test_dummy_keeps_its_combat_shape() -> void:
	var dummy := (load(DUMMY) as PackedScene).instantiate() as Node3D
	assert_true(dummy.is_in_group(&"lockable"), "lockable")
	assert_true(not dummy.is_in_group(&"enemy"), "the Orchestrator does not count it")
	var hurtbox := dummy.get_node(^"Hurtbox") as Hurtbox
	assert_eq(hurtbox.surface, &"straw", "straw impact effects")
	var shape := (hurtbox.get_node(^"CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	assert_almost(shape.radius, 0.4)
	assert_almost(shape.height, 1.8)
	assert_true(dummy.get_node_or_null(^"LockOnPoint") != null)
	dummy.free()
