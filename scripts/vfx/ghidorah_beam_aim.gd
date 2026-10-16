class_name GhidorahBeamAim
extends Node
## Rayo de Mecha King Ghidorah: sale de la boca de la cabeza central y su punto de impacto RECORRE
## el suelo, de cerca de Ghidorah hasta donde estaba Kaelen (y un poco mas alla). La recta del aviso
## (la linea roja del suelo) se fija a los TRACK_FRACTION del aviso, como el giro del jefe, y ya no
## persigue a Kaelen. Al disparar, el impacto avanza por esa recta durante ACTIVE y la zona de dano
## (`Hitbox`, una caja corta) viaja con el: solo golpea donde esta pasando el rayo, una vez por
## disparo (el Hitbox ya golpea cada hurtbox una sola vez por activacion). El efecto (`BeamVfx`)
## sigue saliendo de la boca y su extremo sigue al impacto. Hijo directo del jefe y ultimo hermano
## (se procesa despues de el). Solo mueve nodos; no toca `boss.gd` ni `boss_attack.gd`.

const MIN_LENGTH := 1.0

@export var attack_id: StringName = &"beam"
@export var hitbox_path := NodePath("BeamHitbox")
@export var visual_path := NodePath("BeamVisual")
@export var telegraph_path := NodePath("Telegraphs/beam")
@export var hit_zone_path := NodePath("Telegraphs/beam/HitZone")
## Hueso de la cabeza central y distancia (m) de ese hueso a la boca, a lo largo de su eje +Z.
@export var head_bone: StringName = &"頭"
@export var mouth_distance := 0.9
## Ancho del rayo / de su zona de daño (m) y altura sobre el suelo a la que termina el eje del rayo.
@export var thickness := 1.5
@export var ground_clearance := 0.35
## El impacto empieza a `start_distance` m del jefe, termina `overshoot` m despues del punto
## fijado de Kaelen, y la zona de dano que lo acompana mide hit_height (alto) x hit_length (largo
## a lo largo de la recta).
@export var start_distance := 2.5
@export var overshoot := 2.0
@export var hit_height := 2.4
@export var hit_length := 2.0

var target_ground := Vector3.ZERO   # punto del suelo donde estaba Kaelen (se fija al final del aviso)
var locked := false
var progress := 0.0                 # 0-1: cuanto del recorrido lleva el impacto

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


## Recta del suelo que recorre el impacto: de `start_distance` m del jefe hacia el punto fijado
## `target` y `overshoot` m mas alla. Devuelve {from, to, dir, length} (todo a la altura de `target`).
static func sweep_line(boss_pos: Vector3, target: Vector3, start_distance: float, overshoot: float) -> Dictionary:
	var flat := Vector3(target.x - boss_pos.x, 0.0, target.z - boss_pos.z)
	var dist := flat.length()
	var dir := flat / dist if dist > 0.001 else Vector3.FORWARD
	var from := Vector3(boss_pos.x, target.y, boss_pos.z) + dir * minf(start_distance, dist)
	var to := Vector3(boss_pos.x, target.y, boss_pos.z) + dir * (dist + overshoot)
	return {from = from, to = to, dir = dir, length = from.distance_to(to)}


## Punto del suelo donde esta el impacto al `t` (0-1) del recorrido.
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
		# La forma viene de un sub_resource compartido: cada jefe usa la suya.
		var shape_node := _hitbox.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
		if shape_node and shape_node.shape is BoxShape3D:
			var box := (shape_node.shape as BoxShape3D).duplicate() as BoxShape3D
			box.size = Vector3(thickness, hit_height, hit_length)
			shape_node.shape = box
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
		var scale: float = _boss.get("telegraph_scale") if _boss.get("telegraph_scale") != null else 1.0
		var commit: float = _attack.telegraph_time * scale / speed * Boss.TRACK_FRACTION
		_update_target()
		if _telegraph_time >= commit:
			locked = true
	apply_aim()


func _update_target() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	# Si Kaelen corre, el jefe da el punto PREVISTO (delante de su huida): la franja corta el paso.
	# Se fija igualmente al 70 % del aviso y el rayo tarda ACTIVE en recorrerla: sigue siendo esquivable.
	var aim := _player.global_position
	if _boss.has_method(&"aim_point_for"):
		aim = _boss.call(&"aim_point_for", attack_id, aim)
	target_ground = clamp_target(_boss.global_position, aim, _attack.min_range, _attack.max_range)


## Coloca aviso, zona de dano y efecto: el aviso cubre toda la recta; la zona de dano y el extremo
## del rayo estan en el punto de impacto que lleva el recorrido (`progress`).
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


## Aviso: la franja del suelo por la que va a pasar el impacto. Mientras el rayo recorre, un tramo
## mas oscuro marca donde esta pegando ahora.
func _aim_telegraph(line: Dictionary, flat_basis: Basis, impact: Vector3) -> void:
	if _telegraph == null or line.length < 0.01:
		return
	var floor_y := target_ground.y + 0.05
	var from: Vector3 = line.from
	var to: Vector3 = line.to
	from.y = floor_y
	to.y = floor_y
	# El mesh mide 20 m de largo (z): se escala para cubrir exactamente la franja.
	_telegraph.global_transform = Transform3D(flat_basis.scaled_local(Vector3(thickness / 1.5, 1.0, line.length / 20.0)), (from + to) * 0.5)
	if _hit_zone:
		_hit_zone.visible = _visual != null and _visual.visible
		var center := Vector3(impact.x, floor_y + 0.01, impact.z)
		_hit_zone.global_transform = Transform3D(flat_basis.scaled_local(Vector3(thickness / 1.5, 1.0, hit_length)), center)
