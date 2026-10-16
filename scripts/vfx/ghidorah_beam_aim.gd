class_name GhidorahBeamAim
extends Node
## Mecha King Ghidorah's beam: it comes out of the central head's mouth and its impact point SWEEPS
## the ground, from near Ghidorah to where Kaelen was (and a bit beyond). The telegraph line
## (the red line on the ground) is fixed at TRACK_FRACTION of the telegraph, like the boss's turn,
## and no longer chases Kaelen. On firing, the impact advances along that line during ACTIVE and the
## damage zone (`Hitbox`, a short box) travels with it: it only hits where the beam is passing, once
## per shot (the Hitbox already hits each hurtbox only once per activation). The effect (`BeamVfx`)
## keeps coming out of the mouth and its end follows the impact. Direct child of the boss and last
## sibling (processed after it). It only moves nodes; it does not touch `boss.gd` or `boss_attack.gd`.

const MIN_LENGTH := 1.0

@export var attack_id: StringName = &"beam"
@export var hitbox_path := NodePath("BeamHitbox")
@export var visual_path := NodePath("BeamVisual")
@export var telegraph_path := NodePath("Telegraphs/beam")
@export var hit_zone_path := NodePath("Telegraphs/beam/HitZone")
## Bone of the central head and distance (m) from that bone to the mouth, along its +Z axis.
@export var head_bone: StringName = &"頭"
@export var mouth_distance := 0.9
## Width of the beam / its damage zone (m) and height above the ground where the beam's axis ends.
@export var thickness := 1.5
@export var ground_clearance := 0.35
## The impact starts `start_distance` m from the boss, ends `overshoot` m past Kaelen's fixed
## point, and the accompanying damage zone measures hit_height (height) x hit_length (length
## along the line).
@export var start_distance := 2.5
@export var overshoot := 2.0
@export var hit_height := 2.4
@export var hit_length := 2.0

var target_ground := Vector3.ZERO   # ground point where Kaelen was (fixed at the end of the telegraph)
var locked := false
var progress := 0.0                 # 0-1: how much of the sweep the impact has covered

var _boss: Node3D
var _hitbox: Node3D
var _visual: BeamVfx
var _telegraph: Node3D
var _hit_zone: Node3D
var _skeleton: Skeleton3D
var _head_idx := -1
var _attack: BossAttack
var _telegraph_time := 0.0
var _player: Node3D
var _sweep_time := 0.0


## Beam line: from `mouth` to the ground point `target` (the axis ends `clearance` m above it).
## Returns {origin, end, direction, length, basis, center}.
static func solve(mouth: Vector3, target: Vector3, clearance: float) -> Dictionary:
	var end := target + Vector3.UP * clearance
	var delta := end - mouth
	var length := maxf(delta.length(), MIN_LENGTH)
	var dir := delta.normalized() if delta.length() > 0.001 else Vector3.FORWARD
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	return {
		origin = mouth, end = mouth + dir * length, direction = dir, length = length,
		basis = Basis.looking_at(dir, up), center = mouth + dir * length * 0.5,
	}


## Ground point that gets hit: Kaelen at `player_pos`, at a horizontal distance from the boss
## clamped to [min_range, max_range] (with no distance, it points forward).
static func clamp_target(boss_pos: Vector3, player_pos: Vector3, min_range: float, max_range: float) -> Vector3:
	var flat := Vector3(player_pos.x - boss_pos.x, 0.0, player_pos.z - boss_pos.z)
	var dist := flat.length()
	var dir := flat / dist if dist > 0.001 else Vector3.FORWARD
	var wanted := clampf(dist, min_range, max_range)
	return Vector3(boss_pos.x + dir.x * wanted, player_pos.y, boss_pos.z + dir.z * wanted)


## Ground line the impact travels: from `start_distance` m from the boss toward the fixed point
## `target` and `overshoot` m beyond. Returns {from, to, dir, length} (all at the height of `target`).
static func sweep_line(boss_pos: Vector3, target: Vector3, start_distance: float, overshoot: float) -> Dictionary:
	var flat := Vector3(target.x - boss_pos.x, 0.0, target.z - boss_pos.z)
	var dist := flat.length()
	var dir := flat / dist if dist > 0.001 else Vector3.FORWARD
	var from := Vector3(boss_pos.x, target.y, boss_pos.z) + dir * minf(start_distance, dist)
	var to := Vector3(boss_pos.x, target.y, boss_pos.z) + dir * (dist + overshoot)
	return {from = from, to = to, dir = dir, length = from.distance_to(to)}


## Ground point where the impact is at `t` (0-1) of the sweep.
static func sweep_point(line: Dictionary, t: float) -> Vector3:
	return (line.from as Vector3).lerp(line.to as Vector3, clampf(t, 0.0, 1.0))


func _ready() -> void:
	_boss = get_parent() as Node3D
	_hitbox = _boss.get_node_or_null(hitbox_path) as Node3D
	_visual = _boss.get_node_or_null(visual_path) as BeamVfx
	_telegraph = _boss.get_node_or_null(telegraph_path) as Node3D
	_hit_zone = _boss.get_node_or_null(hit_zone_path) as Node3D
	var skeletons := _boss.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_skeleton = skeletons.front() as Skeleton3D
		_head_idx = _skeleton.find_bone(head_bone)
	for a in _boss.get("attacks"):
		if a.id == attack_id:
			_attack = a
	if _hitbox:
		# The shape comes from a shared sub_resource: each boss uses its own copy.
		var shape_node := _hitbox.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
		if shape_node and shape_node.shape is BoxShape3D:
			var box := (shape_node.shape as BoxShape3D).duplicate() as BoxShape3D
			box.size = Vector3(thickness, hit_height, hit_length)
			shape_node.shape = box
	set_physics_process(_skeleton != null and _head_idx >= 0 and _attack != null)


## Mouth of the central head in global coordinates.
func mouth_position() -> Vector3:
	var bone := _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_idx)
	return bone.origin + bone.basis.z.normalized() * mouth_distance


func _physics_process(delta: float) -> void:
	var visual_on := _visual != null and _visual.visible
	var telegraph_on := _telegraph != null and _telegraph.visible
	if not telegraph_on and not visual_on:
		locked = false
		_telegraph_time = 0.0
		_sweep_time = 0.0
		progress = 0.0
		return
	var speed: float = 1.25 if _boss.get("phase") == 2 else 1.0
	if visual_on:
		locked = true
		_sweep_time += delta
		progress = clampf(_sweep_time / maxf(_attack.active_time / speed, 0.01), 0.0, 1.0)
	elif not locked:
		_telegraph_time += delta
		var telegraph_mult: float = _boss.get("telegraph_scale") if _boss.get("telegraph_scale") != null else 1.0
		var commit: float = _attack.telegraph_time * telegraph_mult / speed * Boss.TRACK_FRACTION
		_update_target()
		if _telegraph_time >= commit:
			locked = true
	apply_aim()


func _update_target() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	# If Kaelen runs, the boss gives the PREDICTED point (ahead of her escape): the strip cuts her off.
	# It is still fixed at 70 % of the telegraph and the beam takes ACTIVE to sweep it: still dodgeable.
	var aim := _player.global_position
	if _boss.has_method(&"aim_point_for"):
		aim = _boss.call(&"aim_point_for", attack_id, aim)
	target_ground = clamp_target(_boss.global_position, aim, _attack.min_range, _attack.max_range)


## Places the telegraph, damage zone and effect: the telegraph covers the whole line; the damage
## zone and the end of the beam are at the impact point the sweep has reached (`progress`).
func apply_aim() -> void:
	var line := sweep_line(_boss.global_position, target_ground, start_distance, overshoot)
	var impact := sweep_point(line, progress)
	var flat_basis := Basis.looking_at(line.dir, Vector3.UP)
	var beam := solve(mouth_position(), impact, ground_clearance)
	if _visual:
		_visual.global_transform = Transform3D(beam.basis, beam.origin)
		_visual.beam_length = beam.length
	if _hitbox:
		_hitbox.global_transform = Transform3D(flat_basis, impact + Vector3.UP * hit_height * 0.5)
	_aim_telegraph(line, flat_basis, impact)


## Telegraph: the ground strip the impact will pass over. While the beam sweeps, a darker
## stretch marks where it is hitting now.
func _aim_telegraph(line: Dictionary, flat_basis: Basis, impact: Vector3) -> void:
	if _telegraph == null or line.length < 0.01:
		return
	var floor_y := target_ground.y + 0.05
	var from: Vector3 = line.from
	var to: Vector3 = line.to
	from.y = floor_y
	to.y = floor_y
	# The mesh is 20 m long (z): it is scaled to cover exactly the strip.
	_telegraph.global_transform = Transform3D(flat_basis.scaled_local(Vector3(thickness / 1.5, 1.0, line.length / 20.0)), (from + to) * 0.5)
	if _hit_zone:
		_hit_zone.visible = _visual != null and _visual.visible
		var center := Vector3(impact.x, floor_y + 0.01, impact.z)
		_hit_zone.global_transform = Transform3D(flat_basis.scaled_local(Vector3(thickness / 1.5, 1.0, hit_length)), center)
