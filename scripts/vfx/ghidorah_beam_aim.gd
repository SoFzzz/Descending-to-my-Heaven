class_name GhidorahBeamAim
extends Node
## Apunta el rayo de Mecha King Ghidorah: sale de la boca de la cabeza central y baja en diagonal
## hasta el suelo donde estaba Kaelen. El punto de impacto se fija al final del aviso (a los
## TRACK_FRACTION del aviso, como el giro del jefe) y ya no persigue a Kaelen: se puede esquivar.
## Efecto (`BeamVfx`), zona de daño (`Hitbox`) y aviso en el suelo se colocan con la MISMA recta
## boca -> impacto, así que lo que se ve es lo que golpea. Hijo directo del jefe y último hermano
## (se procesa después de él). Solo mueve nodos; no toca `boss.gd` ni `boss_attack.gd`.

const KAELEN_HEIGHT := 1.7
const KAELEN_RADIUS := 0.3
const MIN_LENGTH := 1.0

@export var attack_id: StringName = &"beam"
@export var hitbox_path := NodePath("BeamHitbox")
@export var visual_path := NodePath("BeamVisual")
@export var telegraph_path := NodePath("Telegraphs/beam")
@export var hit_zone_path := NodePath("Telegraphs/beam/HitZone")
## Hueso de la cabeza central y distancia (m) de ese hueso a la boca, a lo largo de su eje +Z.
@export var head_bone: StringName = &"頭"
@export var mouth_distance := 0.9
## Grosor de la zona de daño (m) y altura sobre el suelo a la que termina el eje del rayo.
@export var thickness := 1.5
@export var ground_clearance := 0.35

var target_ground := Vector3.ZERO   # punto del suelo al que apunta (se fija al final del aviso)
var locked := false

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


## Recta del rayo: de `mouth` al punto del suelo `target` (el eje termina `clearance` m sobre él).
## Devuelve {origin, end, direction, length, basis, center}.
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


## Punto del suelo que se golpea: Kaelen a `player_pos`, a una distancia horizontal del jefe
## limitada a [min_range, max_range] (sin jugador, `fallback_dir` a max_range).
static func clamp_target(boss_pos: Vector3, player_pos: Vector3, min_range: float, max_range: float) -> Vector3:
	var flat := Vector3(player_pos.x - boss_pos.x, 0.0, player_pos.z - boss_pos.z)
	var dist := flat.length()
	var dir := flat / dist if dist > 0.001 else Vector3.FORWARD
	var wanted := clampf(dist, min_range, max_range)
	return Vector3(boss_pos.x + dir.x * wanted, player_pos.y, boss_pos.z + dir.z * wanted)


## Metros (en horizontal, hacia atrás desde el impacto) donde el rayo todavía alcanza a una
## Kaelen de pie: el eje está a menos de su altura + el semigrosor del rayo sobre el suelo.
static func danger_run(slope_angle: float, half_thickness: float, clearance: float) -> float:
	var reach := KAELEN_HEIGHT + half_thickness / maxf(cos(slope_angle), 0.05) - clearance
	return maxf(reach, 0.0) / maxf(tan(slope_angle), 0.05)


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
		# La forma viene de un sub_resource compartido: cada jefe usa la suya.
		var shape_node := _hitbox.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
		if shape_node and shape_node.shape is BoxShape3D:
			shape_node.shape = (shape_node.shape as BoxShape3D).duplicate()
	set_physics_process(_skeleton != null and _head_idx >= 0 and _attack != null)


## Boca de la cabeza central en coordenadas globales.
func mouth_position() -> Vector3:
	var bone := _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_idx)
	return bone.origin + bone.basis.z.normalized() * mouth_distance


func _physics_process(delta: float) -> void:
	var visual_on := _visual != null and _visual.visible
	var telegraph_on := _telegraph != null and _telegraph.visible
	if not telegraph_on and not visual_on:
		locked = false
		_telegraph_time = 0.0
		return
	if visual_on:
		locked = true
	elif not locked:
		_telegraph_time += delta
		var speed: float = 1.25 if _boss.get("phase") == 2 else 1.0
		var commit: float = _attack.telegraph_time / speed * Boss.TRACK_FRACTION
		_update_target()
		if _telegraph_time >= commit:
			locked = true
	apply_aim()


func _update_target() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	target_ground = clamp_target(_boss.global_position, _player.global_position, _attack.min_range, _attack.max_range)


## Coloca efecto, zona de daño y aviso sobre la recta boca -> `target_ground`.
func apply_aim() -> void:
	var beam := solve(mouth_position(), target_ground, ground_clearance)
	var basis: Basis = beam.basis
	if _visual:
		_visual.global_transform = Transform3D(basis, beam.origin)
		_visual.beam_length = beam.length
	if _hitbox:
		_hitbox.global_transform = Transform3D(basis, beam.center)
		var shape_node := _hitbox.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
		if shape_node and shape_node.shape is BoxShape3D:
			(shape_node.shape as BoxShape3D).size = Vector3(thickness, thickness, beam.length)
	_aim_telegraph(beam)


## Aviso: la proyección del rayo en el suelo (tira del grosor del rayo) y, más oscuro, el tramo
## donde el rayo todavía alcanza a Kaelen de pie.
func _aim_telegraph(beam: Dictionary) -> void:
	if _telegraph == null:
		return
	var floor_y := target_ground.y + 0.05
	var from := Vector3(beam.origin.x, floor_y, beam.origin.z)
	var to := Vector3(beam.end.x, floor_y, beam.end.z)
	var run := from.distance_to(to)
	if run < 0.01:
		return
	var flat_dir := (to - from) / run
	var flat_basis := Basis.looking_at(flat_dir, Vector3.UP)
	# El mesh mide 20 m de largo (z): se escala para cubrir exactamente la proyección.
	_telegraph.global_transform = Transform3D(flat_basis.scaled_local(Vector3(thickness / 1.5, 1.0, run / 20.0)), (from + to) * 0.5)
	if _hit_zone:
		var slope := asin(clampf(-(beam.direction as Vector3).y, 0.0, 1.0))
		var zone := minf(danger_run(slope, thickness * 0.5, ground_clearance), run)
		var zone_center := to - flat_dir * zone * 0.5
		zone_center.y = floor_y + 0.01
		_hit_zone.global_transform = Transform3D(flat_basis.scaled_local(Vector3(thickness / 1.5, 1.0, zone)), zone_center)
