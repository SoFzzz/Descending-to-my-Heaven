class_name Minion
extends CharacterBody3D
## Minion (Task 7): perception (radius + cone + raycast), navigation with avoidance and attacks
## coordinated by tokens (AttackTokens). MinionBrain decides the transitions.

const MinionState := MinionBrain.State

const TOKEN_RANGE := 4.0        # requests a token when entering this radius
const TOKEN_DROP_RANGE := 6.0   # drops the token if Kaelen moves away without being attacked
const TOKEN_COOLDOWN := 2.0     # after attacking or being stunned it does not request a token: it steps aside to orbit and lets another in
const ORBIT_RADIUS := 3.5
const ORBIT_LOOKAHEAD := 1.5    # m to the orbit point (> the agent's target_desired_distance)
const ORBIT_RADIAL_GAIN := 1.5  # how much it corrects toward the ring versus moving sideways
const ORBIT_SPEED_FACTOR := 0.6
const WINDUP_TIME := 0.5        # warning: turns toward Kaelen without moving
const ACTIVE_TIME := 0.3        # hitbox active
const RECOVER_TIME := 0.8
const STUN_TIME := 0.4
const FREE_DELAY := 1.0
const TURN_SPEED := 10.0
const EYE_HEIGHT := 1.5
const CHEST_HEIGHT := 1.2       # Kaelen's chest (1.70 m capsule)
const WORLD_MASK := 1

@export var cost := 1
@export var attack_range := 1.5
@export var move_speed := 3.5
@export var damage := 20

var state: MinionState = MinionState.IDLE
var brain := MinionBrain.new()

@onready var health: Health = $Health
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hitbox: Hitbox = $Hitbox
@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var _body_shape: CollisionShape3D = $CollisionShape3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _player: Node3D
var _state_time := 0.0
var _was_hit := false
var _safe_velocity := Vector3.ZERO
var _orbit_sign := 1.0
var _hitbox_on := false
var _token_cooldown := 0.0
var _holding_token := false   # result of the last request/release (AttackTokens' internal state is not read)


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("lockable")
	brain.attack_range = attack_range
	brain.circle_range = TOKEN_RANGE
	hitbox.damage = damage
	health.died.connect(_on_died)
	hurtbox.hurt.connect(_on_hurt)
	agent.velocity_computed.connect(_on_velocity_computed)
	# Fixed orbit direction per minion so they do not all pile up on the same side.
	_orbit_sign = 1.0 if get_instance_id() % 2 == 0 else -1.0


func _physics_process(delta: float) -> void:
	if state == MinionState.DEAD:
		return   # no collisions: if it moved it would fall through the floor
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_find_player()
	_state_time += delta
	_token_cooldown = maxf(0.0, _token_cooldown - delta)

	var distance := INF
	var sees := false
	if _player:
		distance = global_position.distance_to(_player.global_position)
		sees = _sees_player()
		_update_token(distance)
	var ctx := {
		distance = distance,
		sees_player = sees,
		has_token = _has_token(),
		attack_finished = state == MinionState.ATTACK and _state_time >= WINDUP_TIME + ACTIVE_TIME,
		recover_finished = state == MinionState.RECOVER and _state_time >= RECOVER_TIME,
		stun_finished = state == MinionState.STUNNED and _state_time >= STUN_TIME,
		was_hit = _was_hit,
		is_dead = health.is_dead(),
	}
	_was_hit = false
	var next := brain.next_state(state, ctx)
	if next != state or ctx.was_hit:
		_change_state(next)
	_run_state(delta)


func _run_state(delta: float) -> void:
	match state:
		MinionState.CHASE:
			if _player:
				_navigate_to(_player.global_position, move_speed)
				_face_direction(Vector3(velocity.x, 0.0, velocity.z), delta)
			else:
				_stop()
		MinionState.CIRCLE:
			if _player:
				_navigate_to(_orbit_point(), move_speed * ORBIT_SPEED_FACTOR)
				_face_direction(_player.global_position - global_position, delta)
			else:
				_stop()
		MinionState.ATTACK:
			_stop()
			if _state_time < WINDUP_TIME:
				if _player:
					_face_direction(_player.global_position - global_position, delta)
			elif _state_time < WINDUP_TIME + ACTIVE_TIME:
				_set_hitbox(true)
			else:
				_set_hitbox(false)
		_:
			_stop()
	move_and_slide()


func _change_state(next: MinionState) -> void:
	var prev := state
	state = next
	_state_time = 0.0
	if prev == MinionState.ATTACK:
		_set_hitbox(false)
		_release_token(true)
	match next:
		MinionState.STUNNED:
			_set_hitbox(false)
			_release_token(true)
		MinionState.DEAD:
			_die()


# --- Perception -------------------------------------------------------------------------------

func _find_player() -> void:
	if _player and is_instance_valid(_player) and _player.is_inside_tree():
		return
	_player = get_tree().get_first_node_in_group("player") as Node3D


func get_forward() -> Vector3:
	return -global_basis.z


func _sees_player() -> bool:
	var eye := global_position + Vector3.UP * EYE_HEIGHT
	var chest := _player.global_position + Vector3.UP * CHEST_HEIGHT
	if not MinionBrain.can_see(eye, get_forward(), chest):
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, chest, WORLD_MASK, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- Tokens -----------------------------------------------------------------------------------

func _tokens() -> Node:
	# By path: in tests run with -s there are no autoloads.
	return get_node_or_null(^"/root/AttackTokens")


func _update_token(distance: float) -> void:
	var tokens := _tokens()
	if tokens == null:
		return
	if state == MinionState.CHASE or state == MinionState.CIRCLE:
		if distance <= TOKEN_RANGE and _token_cooldown <= 0.0:
			_holding_token = tokens.request(self)   # returns true if it already holds one
		elif distance > TOKEN_DROP_RANGE and _holding_token:
			_release_token()


func _has_token() -> bool:
	return _holding_token


func _release_token(cooldown := false) -> void:
	if cooldown and _holding_token:
		_token_cooldown = TOKEN_COOLDOWN
	_holding_token = false
	var tokens := _tokens()
	if tokens:
		tokens.release(self)


# --- Movement ---------------------------------------------------------------------------------

func _navigate_to(target: Vector3, speed: float) -> void:
	agent.target_position = target
	var desired := Vector3.ZERO
	if not agent.is_navigation_finished():
		var next := agent.get_next_path_position()
		var dir := next - global_position
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			desired = dir.normalized() * speed
	if agent.avoidance_enabled:
		agent.velocity = desired   # the safe velocity arrives through velocity_computed
	else:
		_safe_velocity = desired
	velocity.x = _safe_velocity.x
	velocity.z = _safe_velocity.z


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	_safe_velocity = Vector3(safe_velocity.x, 0.0, safe_velocity.z)


func _stop() -> void:
	_safe_velocity = Vector3.ZERO
	velocity.x = 0.0
	velocity.z = 0.0
	if agent and agent.avoidance_enabled:
		agent.velocity = Vector3.ZERO


## Point ORBIT_LOOKAHEAD ahead: sideways around Kaelen, correcting toward the ring of
## ORBIT_RADIUS (if it is too close it opens out, if too far it closes in).
func _orbit_point() -> Vector3:
	var offset := global_position - _player.global_position
	offset.y = 0.0
	if offset.length_squared() < 0.01:
		offset = Vector3.BACK
	var radial := offset.normalized()
	var tangent := Vector3.UP.cross(radial) * _orbit_sign
	var error := clampf(ORBIT_RADIUS - offset.length(), -1.0, 1.0)
	var dir := (tangent + radial * error * ORBIT_RADIAL_GAIN).normalized()
	return global_position + dir * ORBIT_LOOKAHEAD


## Turns the body so its front (-Z) points toward `dir` (horizontal).
func _face_direction(dir: Vector3, delta: float) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, TURN_SPEED * delta))


# --- Combat -----------------------------------------------------------------------------------

func _set_hitbox(on: bool) -> void:
	if on == _hitbox_on:
		return
	_hitbox_on = on
	if on:
		hitbox.activate()
	else:
		hitbox.deactivate()


func _on_hurt(_amount: int, _source: Node) -> void:
	if not health.is_dead():
		_was_hit = true


func _on_died() -> void:
	if state != MinionState.DEAD:
		_change_state(MinionState.DEAD)


func _die() -> void:
	_set_hitbox(false)
	_release_token()
	_stop()
	remove_from_group("enemy")
	remove_from_group("lockable")
	# Deferred: death usually arrives inside a physics signal (area_entered).
	_body_shape.set_deferred(&"disabled", true)
	hurtbox.set_deferred(&"monitorable", false)
	set_deferred(&"collision_layer", 0)
	agent.avoidance_enabled = false
	var events := get_node_or_null(^"/root/Events")
	if events:
		events.enemy_died.emit(self, cost)
	get_tree().create_timer(FREE_DELAY).timeout.connect(queue_free)
