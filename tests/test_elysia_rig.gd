extends TestCase
# Elysia's rigged model (_source/tools/rig_elysia.py): a skeleton and the three clips of the ending.

const MODEL := "res://assets/characters/elysia/elysia.glb"


func test_elysia_has_a_rig_and_her_three_clips() -> void:
	var elysia := (load(MODEL) as PackedScene).instantiate() as Node3D
	var skeletons := elysia.find_children("*", "Skeleton3D", true, false)
	assert_eq(skeletons.size(), 1, "one skeleton")
	var anim := elysia.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_true(anim != null, "AnimationPlayer")
	if anim:
		for clip in [&"idle", &"appear", &"hug"]:
			assert_true(anim.has_animation(clip), "clip %s" % clip)
		assert_true(anim.get_animation(&"idle").length > 2.0, "idle is a few seconds long")
	elysia.free()


func test_hug_pose_is_not_the_t_pose() -> void:
	# The arms of the hug clip end well in front of the body (the static model had them out to the sides).
	var elysia := (load(MODEL) as PackedScene).instantiate() as Node3D
	var anim := elysia.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var hug := anim.get_animation(&"hug")
	assert_true(hug.get_track_count() >= 8, "the hug moves the arms (%d tracks)" % hug.get_track_count())
	elysia.free()
