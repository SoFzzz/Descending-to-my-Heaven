class_name AttackDriver
extends Node
## Complemento de los jefes grandes (Tarea 13). Hijo directo de un Boss; NO modifica boss.gd: usa sus
## señales y variables públicas. Cubre lo que Boss todavía no sabe hacer:
##  1. Embestida/salto: durante ACTIVE de ciertos ataques mueve al jefe hacia delante (`lunges`,
##     metros en total); Boss pone la velocidad a 0 en ACTIVE y su `engage_range` es fijo.
##  2. Aproximación: Boss solo ataca a menos de `engage_range`, así que un ataque de largo alcance
##     (embestida 8–16 m, rayo 8–20 m) nunca se elegiría. Este nodo sube `engage_range` hasta la
##     distancia actual cuando hay un ataque válido que NO sea el último usado y que esté más allá
##     de `base_engage_range`; si no, vuelve a `base_engage_range` y el jefe se acerca.
##  3. Locomoción: Boss no usa `walk_animation`; aquí se reproduce `walk` / `run` (fase 2) al avanzar.
##  4. Hitboxes extra que se activan con un ataque (p. ej. garras con el zarpazo).
##  5. Hurtboxes que solo se pueden golpear en la ventana de un ataque (cabezas de Ghidorah en `bite`).
##  6. Un efecto visual (el rayo) visible solo mientras el ataque está ACTIVE.
##  7. Al morir, baja el modelo hasta apoyar el cuerpo en el suelo (la `death` de Blackhorn termina
##     con el cuerpo 0.83 m en el aire).

## Distancia a la que el jefe se detiene para atacar si no hay ataque de largo alcance disponible.
@export var base_engage_range := 3.0
## Animaciones de caminar y de correr en fase 2 (vacío = no se tocan; el jefe desliza con idle).
@export var walk_animation: StringName = &""
@export var run_animation: StringName = &""
## id de ataque → metros que avanza durante ACTIVE.
@export var lunges: Dictionary = {}
## id de ataque → Array[NodePath] de Hitbox (relativos al jefe) que se activan junto al ataque.
@export var extra_hitboxes: Dictionary = {}
## Hurtboxes (relativos al jefe) que solo reciben golpes durante `exposed_attack` (+ `exposed_grace`).
@export var exposed_hurtboxes: Array[NodePath] = []
@export var exposed_attack: StringName = &""
@export var exposed_grace := 0.2
## id de ataque → NodePath (relativo al jefe) de un Node3D visible solo durante ACTIVE.
@export var visuals: Dictionary = {}
## Tras morir, apoya el modelo en el suelo. `death_clearance` = altura del hueso más bajo sobre la suela.
@export var settle_on_death := false
@export var death_clearance := 0.07
@export var model_path := NodePath("Model")

var exposed_open := false
var settled_offset := 0.0

var _boss: Boss
var _anim: AnimationPlayer
var _player: Node3D
var _lunge_left := 0.0
var _lunge_speed := 0.0
var _grace_left := 0.0
var _active_extras: Array[Hitbox] = []
var _active_visual: Node3D
var _dead := false
var _model: Node3D
var _skeleton: Skeleton3D


## ¿La ventana de exposición está abierta? (ataque en ACTIVE, o recién terminado).
static func window_open(active_with_attack: bool, grace_left: float) -> bool:
	return active_with_attack or grace_left > 0.0


## ¿Algún ataque válido a esa distancia justifica detenerse más lejos que `base`?
static func opener_distance(attacks: Array[BossAttack], distance: float, base: float, phase: int, last_id: StringName) -> bool:
	if distance <= base:
		return false
	for attack in attacks:
		if attack.phase_min <= phase and attack.id != last_id \
				and distance >= attack.min_range and distance <= attack.max_range:
			return true
	return false


## Metros por segundo para recorrer `meters` en `active_time` segundos (ya dividido por la fase).
static func lunge_speed_for(meters: float, active_time: float) -> float:
	return meters / maxf(active_time, 0.01)


func _ready() -> void:
	_boss = get_parent() as Boss
	if _boss == null:
		set_physics_process(false)
		return
	_boss.engage_range = base_engage_range
	if not _boss.is_node_ready():
		await _boss.ready
	_anim = _boss.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_model = _boss.get_node_or_null(model_path) as Node3D
	if _model:
		var skeletons := _model.find_children("*", "Skeleton3D", true, false)
		_skeleton = skeletons.front() as Skeleton3D if not skeletons.is_empty() else null
	_boss.state_changed.connect(_on_state_changed)
	_boss.health.died.connect(_on_died)
	for path in visuals.values():
		var node := _boss.get_node_or_null(path as NodePath) as Node3D
		if node:
			node.visible = false
	_apply_exposed(false)


func _physics_process(delta: float) -> void:
	if _boss == null or _boss.health == null:
		return
	if _dead:
		_settle(delta)
		return
	_find_player()
	_update_engage()
	_update_locomotion()
	_update_lunge(delta)
	_update_exposure(delta)


# --- Aproximación y locomoción ----------------------------------------------------------------

func _find_player() -> void:
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = get_tree().get_first_node_in_group("player") as Node3D


func _flat_distance() -> float:
	if _player == null:
		return INF
	var d := _player.global_position - _boss.global_position
	d.y = 0.0
	return d.length()


func _update_engage() -> void:
	if _boss.state != Boss.State.CHASE:
		return
	var d := _flat_distance()
	if opener_distance(_boss.attacks, d, base_engage_range, _boss.phase, _boss.brain.last_attack_id):
		_boss.engage_range = d + 0.3
	else:
		_boss.engage_range = base_engage_range


func _update_locomotion() -> void:
	if _anim == null or walk_animation == &"" or _boss.state != Boss.State.CHASE:
		return
	var moving := Vector2(_boss.velocity.x, _boss.velocity.z).length() > 0.3
	var wanted: StringName = _boss.idle_animation
	if moving:
		wanted = run_animation if (_boss.phase == 2 and run_animation != &"") else walk_animation
	if _anim.current_animation != wanted and _anim.has_animation(wanted):
		_anim.play(wanted, Boss.ANIM_BLEND)


# --- Ataques ----------------------------------------------------------------------------------

func _on_state_changed(state: Boss.State) -> void:
	if state == Boss.State.ACTIVE and _boss.current_attack != null:
		_begin_active(_boss.current_attack)
	else:
		_end_active()


func _begin_active(attack: BossAttack) -> void:
	var speed := Boss.PHASE2_SPEED if _boss.phase == 2 else 1.0
	if lunges.has(attack.id):
		_lunge_left = float(lunges[attack.id])
		_lunge_speed = lunge_speed_for(_lunge_left, attack.active_time / speed)
	if extra_hitboxes.has(attack.id):
		for path in extra_hitboxes[attack.id]:
			var hb := _boss.get_node_or_null(path as NodePath) as Hitbox
			if hb:
				hb.damage = attack.damage
				hb.activate()
				_active_extras.append(hb)
	if visuals.has(attack.id):
		_active_visual = _boss.get_node_or_null(visuals[attack.id] as NodePath) as Node3D
		if _active_visual:
			_active_visual.visible = true


func _end_active() -> void:
	_lunge_left = 0.0
	for hb in _active_extras:
		if is_instance_valid(hb):
			hb.deactivate()
	_active_extras.clear()
	if _active_visual and is_instance_valid(_active_visual):
		_active_visual.visible = false
	_active_visual = null


func _update_lunge(delta: float) -> void:
	if _lunge_left <= 0.0 or _boss.state != Boss.State.ACTIVE:
		return
	var forward := -_boss.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	var step := minf(_lunge_left, _lunge_speed * delta)
	var hit := _boss.move_and_collide(forward.normalized() * step)
	_lunge_left = 0.0 if hit else _lunge_left - step


# --- Hurtboxes expuestas ----------------------------------------------------------------------

func _update_exposure(delta: float) -> void:
	if exposed_hurtboxes.is_empty():
		return
	var attacking := _boss.state == Boss.State.ACTIVE and _boss.current_attack != null \
			and _boss.current_attack.id == exposed_attack
	if attacking:
		_grace_left = exposed_grace
	else:
		_grace_left = maxf(0.0, _grace_left - delta)
	var open := window_open(attacking, _grace_left)
	if open != exposed_open:
		_apply_exposed(open)


func _apply_exposed(open: bool) -> void:
	exposed_open = open
	for path in exposed_hurtboxes:
		var hurtbox := _boss.get_node_or_null(path) as Hurtbox
		if hurtbox:
			# Diferido: puede llamarse dentro de una señal de física.
			hurtbox.set_deferred(&"monitorable", open)


# --- Muerte -----------------------------------------------------------------------------------

func _on_died() -> void:
	_dead = true
	_end_active()
	_apply_exposed(false)


## Apoya el cuerpo en el suelo: baja el modelo (nunca lo sube) lo que haga falta, con suavidad.
func _settle(delta: float) -> void:
	if not settle_on_death or _model == null or _skeleton == null:
		return
	var floor_y := _boss.global_position.y
	var lowest := INF
	for i in _skeleton.get_bone_count():
		lowest = minf(lowest, (_skeleton.global_transform * _skeleton.get_bone_global_pose(i)).origin.y)
	var at_zero_offset := lowest - floor_y - _model.position.y
	var wanted := -maxf(0.0, at_zero_offset - death_clearance)
	settled_offset = move_toward(settled_offset, wanted, 1.5 * delta)
	_model.position.y = settled_offset
