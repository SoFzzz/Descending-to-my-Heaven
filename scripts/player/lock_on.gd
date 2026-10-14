class_name LockOn
extends Node
## Kaelen's target lock (spec §7.5). Child of Kaelen. Targets are in the "lockable" group and have
## a Marker3D child named "LockOnPoint" (chest or torso).
## It is released only if the target was freed, left the tree, is no longer "lockable", its Health
## died, or it moved farther than 15 m (25 m if it is in the "boss" group).

const MAX_RANGE := 15.0
const MAX_RANGE_BOSS := 25.0
## When acquiring: the target must be within this angle from the camera's forward direction.
const ACQUIRE_HALF_ANGLE := deg_to_rad(60.0)

signal target_changed(target: Node3D)

var target: Node3D
## Where the distance is measured from. If null, the parent (Kaelen) is used.
var origin: Node3D


func _physics_process(_delta: float) -> void:
	validate()


static func max_range_for(is_boss: bool) -> float:
	return MAX_RANGE_BOSS if is_boss else MAX_RANGE


## Point to aim at: the target's LockOnPoint or, if it has none, its origin.
static func aim_point(node: Node3D) -> Vector3:
	var point := node.get_node_or_null(^"LockOnPoint") as Node3D
	return (point if point else node).global_position


## Locks the nearest "lockable" within range and in front of the camera, or releases the current one.
func toggle() -> void:
	if target != null:
		_set_target(null)
		return
	_set_target(find_best_target())


func find_best_target() -> Node3D:
	var from := _origin()
	if from == null or not from.is_inside_tree():
		return null
	var camera := from.get_viewport().get_camera_3d()
	var best: Node3D = null
	var best_dist := INF
	for node in from.get_tree().get_nodes_in_group(&"lockable"):
		var candidate := node as Node3D
		if candidate == null or not candidate.is_inside_tree() or _is_dead(candidate):
			continue
		var point := aim_point(candidate)
		var dist := from.global_position.distance_to(candidate.global_position)
		if dist > max_range_for(candidate.is_in_group(&"boss")) or dist >= best_dist:
			continue
		if camera and not _in_front_of(camera, point):
			continue
		best = candidate
		best_dist = dist
	return best


func validate() -> void:
	if target == null:
		return
	if not is_instance_valid(target):
		_set_target(null)
		return
	# Outside the tree (tests) the target is not required to be in the tree.
	if is_inside_tree() and not target.is_inside_tree():
		_set_target(null)
		return
	if not target.is_in_group(&"lockable") or _is_dead(target):
		_set_target(null)
		return
	var from := _origin()
	if from == null:
		return
	if _distance(from, target) > max_range_for(target.is_in_group(&"boss")):
		_set_target(null)


func _set_target(value: Node3D) -> void:
	if value == target and is_instance_valid(value):
		return
	target = value
	target_changed.emit(target)


func _origin() -> Node3D:
	if origin:
		return origin
	return get_parent() as Node3D


# Inside the tree it uses global positions; outside (tests) local ones, which match when there is no parent.
static func _distance(a: Node3D, b: Node3D) -> float:
	if a.is_inside_tree() and b.is_inside_tree():
		return a.global_position.distance_to(b.global_position)
	return a.position.distance_to(b.position)


static func _is_dead(node: Node) -> bool:
	var health := node.get_node_or_null(^"Health") as Health
	return health != null and health.is_dead()


static func _in_front_of(camera: Camera3D, point: Vector3) -> bool:
	var to_point := point - camera.global_position
	to_point.y = 0.0
	var forward := -camera.global_basis.z
	forward.y = 0.0
	if to_point.length_squared() < 0.0001 or forward.length_squared() < 0.0001:
		return true
	return forward.normalized().angle_to(to_point.normalized()) <= ACQUIRE_HALF_ANGLE
