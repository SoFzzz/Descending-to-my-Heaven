class_name HugArms
extends SkeletonModifier3D
## Kaelen's arms around Elysia for the ending's embrace. A SkeletonModifier3D child of Kaelen's
## Skeleton3D: after the animation has written the pose it bends both arms (a two-bone solver:
## shoulder, elbow, wrist) so the hands meet behind `partner`'s back. Elysia's model has no rig, so
## only Kaelen's arms move; the rest of Kaelen keeps playing her clip. `influence` (0..1) blends the
## hug in and out; it starts at 0 and the ending director raises it.
##
## Everything is computed in world space from the bones' current poses, so it does not depend on the
## skeleton's axes (the Mixamo armature is rotated and scaled).

## Bone name suffixes of the two arms (the bones are "mixamorig_<side><part>").
const SIDES: Array[String] = ["Left", "Right"]
## Where the wrists go, relative to the partner's origin (her feet): behind her back (BACK_OFFSET m
## away from Kaelen), LATERAL m to the side of Kaelen's shoulder (they almost meet), at the given
## height (the two differ a little so the hands overlap instead of colliding).
const BACK_OFFSET := 0.02
const LATERAL := 0.17
const HEIGHTS := {"Left": 1.08, "Right": 1.17}
## Elbows go out to the side and down: weights of the pole direction.
const POLE_SIDE := 1.0
const POLE_DOWN := 0.6
const POLE_BACK := 0.2
## Stance: how much of the arm's length the hands hang (fraction), how far in front of the hand (forward) and
## to the side the sword's point enters the floor, and the blade's direction in the hand (the greatsword's
## hitbox marker in the SwordGrip).
const STANCE_REACH := 0.96
const PLANT_FORWARD := 0.3
const PLANT_SIDE := 0.2
const BLADE_LOCAL := Vector3(0.84, 0.08, 0.02)

## Relaxed stance instead of the hug (used while she talks to Elysia): arms hanging, eyes on `partner`, the
## greatsword planted in the floor beside her foot instead of held up.
var stance := false
## Only in stance mode: 0 = the relaxed stance, 1 = the hug. The wrist target and the elbow pole are blended
## in world space, so the hand travels in an arc from her side to Elysia's back (blending the bone rotations
## instead swung the arm through odd angles).
var hug_blend := 1.0
var partner: Node3D
## Where the middle of her body is, in the partner's local space (x, z): Elysia's model origin is not
## at her body (the mesh's center is almost a metre behind it), so the hands aim at the body, not the origin.
var center_local := Vector3.ZERO


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or partner == null or not is_instance_valid(partner):
		return
	for side in SIDES:
		_solve_arm(skeleton, side)


## World point in the middle of her body at her feet's height.
func body_anchor() -> Vector3:
	return partner.global_transform * Vector3(center_local.x, 0.0, center_local.z)


## World position where `side`'s wrist should end, given that shoulder's world position.
func wrist_target(side: String, shoulder: Vector3) -> Vector3:
	var basis := partner.global_basis
	var front := basis.z.normalized()   # her front faces Kaelen
	var lateral := basis.x.normalized()
	var anchor := body_anchor()
	var s := signf((shoulder - anchor).dot(lateral))
	if s == 0.0:
		s = 1.0 if side == "Left" else -1.0
	return anchor - front * BACK_OFFSET + Vector3.UP * float(HEIGHTS[side]) + lateral * s * LATERAL


func elbow_pole(side: String, shoulder: Vector3) -> Vector3:
	var basis := partner.global_basis
	var lateral := basis.x.normalized()
	var s := signf((shoulder - body_anchor()).dot(lateral))
	if s == 0.0:
		s = 1.0 if side == "Left" else -1.0
	return lateral * s * POLE_SIDE + Vector3.DOWN * POLE_DOWN - basis.z.normalized() * POLE_BACK


func _solve_arm(skeleton: Skeleton3D, side: String) -> void:
	var arm := skeleton.find_bone("mixamorig_%sArm" % side)
	var fore := skeleton.find_bone("mixamorig_%sForeArm" % side)
	var hand := skeleton.find_bone("mixamorig_%sHand" % side)
	if arm < 0 or fore < 0 or hand < 0:
		return
	var to_world := skeleton.global_transform
	var shoulder := to_world * skeleton.get_bone_global_pose(arm).origin
	var elbow_now := to_world * skeleton.get_bone_global_pose(fore).origin
	var wrist_now := to_world * skeleton.get_bone_global_pose(hand).origin
	var l1 := shoulder.distance_to(elbow_now)
	var l2 := elbow_now.distance_to(wrist_now)
	var target := Vector3.ZERO
	var pole := Vector3.ZERO
	if stance:
		var frame := _stance_frame(skeleton, side, shoulder)
		target = shoulder + Vector3.DOWN * (l1 + l2) * STANCE_REACH - frame[1] * 0.03 + frame[0] * 0.02
		pole = (frame[1] * 0.12 - frame[0] * 1.0 + Vector3.DOWN * 0.2).normalized()
		if hug_blend > 0.0:
			var hug_pole := elbow_pole(side, shoulder).normalized()
			target = target.lerp(wrist_target(side, shoulder), hug_blend)
			pole = pole.lerp(hug_pole, hug_blend)
	else:
		target = wrist_target(side, shoulder)
		pole = elbow_pole(side, shoulder)
	var elbow := elbow_position(shoulder, target, l1, l2, pole)
	var reach := shoulder + (target - shoulder).normalized() * minf(shoulder.distance_to(target), (l1 + l2) * 0.995)
	_aim(skeleton, arm, fore, elbow - shoulder)
	_aim(skeleton, fore, hand, reach - elbow)
	if stance and side == "Right" and hug_blend < 1.0:
		_plant_blade(skeleton, hand, reach, 1.0 - hug_blend)


## [forward, outward] unit vectors (world, horizontal) of a stance: forward toward the partner, outward
## from the body toward `side`'s shoulder.
func _stance_frame(skeleton: Skeleton3D, side: String, shoulder: Vector3) -> Array[Vector3]:
	var other := skeleton.find_bone("mixamorig_%sArm" % ("Left" if side == "Right" else "Right"))
	var forward := (partner.global_position - skeleton.global_position)
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else skeleton.global_basis.z
	var out := Vector3.ZERO
	if other >= 0:
		out = shoulder - skeleton.global_transform * skeleton.get_bone_global_pose(other).origin
	out.y = 0.0
	out = out.normalized() if out.length_squared() > 0.0001 else forward.cross(Vector3.UP)
	return [forward, out]


## Turns the hand so the sword's blade runs from the fist down into the floor a little in front of and beside her.
func _plant_blade(skeleton: Skeleton3D, hand: int, wrist: Vector3, weight: float) -> void:
	var floor_y := skeleton.global_position.y
	var frame := _stance_frame(skeleton, "Right", wrist)
	var point := Vector3(wrist.x, floor_y, wrist.z) + frame[0] * PLANT_FORWARD + frame[1] * PLANT_SIDE
	var wanted := skeleton.global_basis.inverse() * (point - wrist).normalized()
	var parent := skeleton.get_bone_parent(hand)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis.orthonormalized()
	var current := skeleton.get_bone_global_pose(hand).basis.orthonormalized()
	var blade_now := current * BLADE_LOCAL.normalized()
	var turned := Basis(Quaternion(blade_now, wanted.normalized())) * current
	var frame_basis := parent_basis * skeleton.get_bone_rest(hand).basis.orthonormalized()
	var planted := (frame_basis.inverse() * turned).get_rotation_quaternion()
	var animated := (frame_basis.inverse() * current).get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(hand, animated.slerp(planted, weight))


## Elbow of a two-bone chain (upper length `l1`, lower `l2`) from `shoulder` to `target`, bent toward
## `pole`. The target is clamped to what the chain can reach.
static func elbow_position(shoulder: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var to_target := target - shoulder
	var d := clampf(to_target.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.995)
	var axis := to_target.normalized() if to_target.length_squared() > 0.000001 else Vector3.FORWARD
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var perp := pole - axis * pole.dot(axis)
	perp = perp.normalized() if perp.length_squared() > 0.000001 else Vector3.UP
	return shoulder + axis * a + perp * h


## Turns `bone` so the segment toward `child` points along `direction` (world space): the shortest
## rotation from the rest direction, so the bone does not twist.
func _aim(skeleton: Skeleton3D, bone: int, child: int, direction: Vector3) -> void:
	var dir_skel := (skeleton.global_transform.basis.inverse() * direction).normalized()
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	var frame := parent_basis * skeleton.get_bone_rest(bone).basis.orthonormalized()
	var wanted := (frame.inverse() * dir_skel).normalized()
	var along := skeleton.get_bone_rest(child).origin.normalized()
	skeleton.set_bone_pose_rotation(bone, Quaternion(along, wanted))
