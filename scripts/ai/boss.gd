class_name Boss
extends CharacterBody3D
## Boss (Task 9): IDLE → CHASE (NavigationAgent3D on the large layer) → picks an attack with
## BossBrain → TELEGRAPH (red warning on the floor, same size as the hitbox) → ACTIVE (hitbox on)
## → RECOVER → CHASE. Phase 2 at 50 % health: ROAR (no damage, NOT invulnerable: punishing it is a
## reward) and then +25 % animation, attack and movement speed. On death: death animation,
## Events.boss_defeated once and deferred shutdown of collisions/hitboxes.
##
## Scene conventions (boss_base.tscn): children Health, CollisionShape3D, NavigationAgent3D,
## LockOnPoint, Telegraphs/<attack id> (hidden flat meshes) and an AnimationPlayer anywhere under
## Model. Hurtboxes anywhere below report to the boss, which applies the damage to Health.

signal state_changed(state: State)
signal attack_started(attack: BossAttack)

enum State { IDLE, CHASE, TELEGRAPH, ACTIVE, RECOVER, ROAR, DEAD }

const PHASE2_SPEED := 1.25
const TURN_SPEED := 4.0            # rad/s-ish smoothing toward Kaelen
const TRACK_FRACTION := 0.7        # during the first 70 % of the warning it keeps turning; then it commits
const DODGE_RECORD_RANGE := 12.0   # only rolls this close count for the anticipation bonus
const ANIM_BLEND := 0.25
## Kaelen's sword is active ~0.2 s per slash and slashes are ≥ 0.4 s apart.
const SAME_SWING_WINDOW := 0.3

@export var display_name: String = "Boss"
@export var attacks: Array[BossAttack] = []
@export var max_health: int = 400
@export var move_speed := 3.0
@export var detect_radius := 20.0
## Approaches until this distance (origin to origin); then it may attack.
@export var engage_range := 3.2
## Pause between the end of one recovery and the next decision.
@export var attack_cooldown := 0.4
@export var idle_animation: StringName = &"idle"
@export var walk_animation: StringName = &""   # Bone Dragon has no walk clip: it glides with idle
@export var roar_animation: StringName = &"roar"
@export var death_animation: StringName = &"death"
## Fixed seed for repeatable tests; 0 = random.
@export var rng_seed := 0

var phase: int = 1
var state: State = State.IDLE
var brain := BossBrain.new()
var current_attack: BossAttack
## Attack ids in the order they were used (debug and verification).
var attack_log: Array[StringName] = []

@onready var health: Health = $Health
@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var _body_shape: CollisionShape3D = $CollisionShape3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _rng := RandomNumberGenerator.new()
var _anim: AnimationPlayer
var _player: Node3D
var _player_health: Health
var _aggro := false
var _state_time := 0.0
var _cooldown := 0.0
var _pending_roar := false
var _hitbox: Hitbox
var _telegraph: Node3D
var _spin_done := 0.0
var _was_rolling := false
var _defeated_emitted := false
var _clock := 0.0                 # game time, for SAME_SWING_WINDOW
var _swing_hits: Dictionary = {}  # source instance id → {time, amount}


func _ready() -> void:
	add_to_group("boss")
	add_to_group("lockable")
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	if max_health > 0:
		health.reset(max_health)
	health.changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	for node in find_children("*", "Hurtbox", true, false):
		# The boss applies the damage itself (_on_hurt) so one swing touching several hurtboxes
		# counts once; that is why its hurtboxes have no Health.
		var hurtbox := node as Hurtbox
		hurtbox.health = null
		hurtbox.hurt.connect(_on_hurt)
	for attack in attacks:
		var hb := _hitbox_for(attack)
		if hb:
			hb.damage = attack.damage
		var tg := _telegraph_for(attack)
		if tg:
			tg.visible = false
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	_play(idle_animation)


func _physics_process(delta: float) -> void:
	_clock += delta
	if state == State.DEAD:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	_find_player()
	_state_time += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	var target_ok := _player_alive()
	if target_ok:
		_track_dodge()
	if _pending_roar and state != State.ROAR:
		_pending_roar = false
		_cancel_attack()
		_play(roar_animation)
		_set_state(State.ROAR)
	elif not target_ok and state != State.IDLE and state != State.ROAR:
		_cancel_attack()   # Kaelen died: stop attacking
		_set_state(State.IDLE)
		_play(idle_animation)
	_run_state(delta, target_ok)
	move_and_slide()


func _run_state(delta: float, target_ok: bool) -> void:
	var speed := _speed()
	match state:
		State.IDLE:
			_stop()
			if target_ok and (_aggro or _flat_distance() <= detect_radius):
				_aggro = true
				_set_state(State.CHASE)
		State.CHASE:
			var distance := _flat_distance()
			if distance <= engage_range:
				_stop()
				_face(_player.global_position, delta)
				if _cooldown <= 0.0 and _try_start_attack(distance):
					return
			else:
				_navigate_to(_player.global_position, move_speed * speed)
				_face(global_position + Vector3(velocity.x, 0.0, velocity.z), delta)
		State.TELEGRAPH:
			_stop()
			var telegraph := current_attack.telegraph_time / speed
			if _state_time < telegraph * TRACK_FRACTION:
				_face(_player.global_position, delta)
			if _state_time >= telegraph:
				_set_state(State.ACTIVE)
				_spin_done = 0.0
				if _hitbox:
					_hitbox.activate()
		State.ACTIVE:
			_stop()
			var active := current_attack.active_time / speed
			_apply_spin(minf(_state_time / active, 1.0))
			if _state_time >= active:
				_end_active()
				_set_state(State.RECOVER)
		State.RECOVER:
			_stop()
			if _state_time >= current_attack.recovery_time / speed:
				current_attack = null
				_cooldown = attack_cooldown / speed
				_play(idle_animation)
				_set_state(State.CHASE)
		State.ROAR:
			_stop()
			if _state_time >= _anim_length(roar_animation, 2.0) / speed:
				_play(idle_animation)
				_set_state(State.CHASE if target_ok else State.IDLE)


# --- Attacks ----------------------------------------------------------------------------------

func _try_start_attack(distance: float) -> bool:
	var attack := brain.choose(attacks, distance, phase, _rng)
	if attack == null:
		return false
	current_attack = attack
	brain.last_attack_id = attack.id
	attack_log.append(attack.id)
	_hitbox = _hitbox_for(attack)
	_telegraph = _telegraph_for(attack)
	if _telegraph:
		_telegraph.visible = true
	_play(attack.animation)
	_set_state(State.TELEGRAPH)
	attack_started.emit(attack)
	return true


func _end_active() -> void:
	if _hitbox:
		_hitbox.deactivate()
	if _telegraph:
		_telegraph.visible = false


## Stops the current attack wherever it is (Kaelen died, phase change or death).
func _cancel_attack() -> void:
	if current_attack == null:
		return
	_end_active()
	current_attack = null
	_hitbox = null
	_telegraph = null


func _apply_spin(progress: float) -> void:
	if current_attack.spin_degrees == 0.0:
		return
	var target := deg_to_rad(current_attack.spin_degrees) * progress
	rotation.y += target - _spin_done
	_spin_done = target


func _hitbox_for(attack: BossAttack) -> Hitbox:
	if attack == null or attack.hitbox_path.is_empty():
		return null
	return get_node_or_null(attack.hitbox_path) as Hitbox


func _telegraph_for(attack: BossAttack) -> Node3D:
	return get_node_or_null(NodePath("Telegraphs/" + String(attack.id))) as Node3D


func _speed() -> float:
	return PHASE2_SPEED if phase == 2 else 1.0


# --- Kaelen -----------------------------------------------------------------------------------

func _find_player() -> void:
	if _player and is_instance_valid(_player) and _player.is_inside_tree():
		return
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_player_health = _player.get_node_or_null(^"Health") as Health if _player else null


func _player_alive() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	return _player_health == null or not _player_health.is_dead()


func _flat_distance() -> float:
	var d := _player.global_position - global_position
	d.y = 0.0
	return d.length()


## Records Kaelen's rolls (start of each roll) as −1 / +1 relative to the boss's left / right.
func _track_dodge() -> void:
	var player := _player as Player
	if player == null:
		return
	var rolling := player.state == Player.State.ROLL
	if rolling and not _was_rolling and _flat_distance() <= DODGE_RECORD_RANGE:
		var side := global_basis.x.dot(player.velocity)
		if absf(side) > 0.5:
			brain.record_dodge(1 if side > 0.0 else -1)
	_was_rolling = rolling


# --- Movement ---------------------------------------------------------------------------------

func _navigate_to(target: Vector3, speed: float) -> void:
	agent.target_position = target
	var dir := Vector3.ZERO
	if not agent.is_navigation_finished():
		dir = agent.get_next_path_position() - global_position
		dir.y = 0.0
	if dir.length_squared() < 0.0001:
		# Off the mesh or path finished: straight at her (the stop distance keeps it from overlapping).
		dir = target - global_position
		dir.y = 0.0
	if dir.length_squared() > 0.0001:
		dir = dir.normalized() * speed
	velocity.x = dir.x
	velocity.z = dir.z


func _stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


## Turns the body so its front (-Z) points toward `point` (horizontal).
func _face(point: Vector3, delta: float) -> void:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, TURN_SPEED * _speed() * delta))


## Places the boss on a marker looking toward `look_at_point` (if given) or along the marker's -Z.
func spawn_at(marker: Node3D, look_at_point = null) -> void:
	global_position = marker.global_position
	var forward := -marker.global_basis.z
	if look_at_point is Vector3:
		forward = (look_at_point as Vector3) - global_position
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		rotation.y = atan2(-forward.x, -forward.z)


# --- Health, phase and death ------------------------------------------------------------------

## Damage from any hurtbox (already multiplied: head × 1.25). Hits from the same source within
## SAME_SWING_WINDOW are the same swing touching several hurtboxes: only the largest one counts.
func _on_hurt(amount: int, source: Node) -> void:
	if state == State.DEAD:
		return
	_aggro = true
	var key := source.get_instance_id() if source else 0
	var last: Dictionary = _swing_hits.get(key, {})
	if not last.is_empty() and _clock - float(last.time) <= SAME_SWING_WINDOW:
		var applied: int = last.amount
		if amount > applied:
			last.amount = amount
			health.take_damage(amount - applied)
		return
	_swing_hits[key] = {time = _clock, amount = amount}
	health.take_damage(amount)


func _on_health_changed(current: int, max_value: int) -> void:
	if BossBrain.should_enter_phase2(current, max_value, phase):
		phase = 2
		if _anim:
			_anim.speed_scale = PHASE2_SPEED
		_pending_roar = true   # handled in _physics_process (we may be inside a physics signal)
		var events := _events()
		if events:
			events.boss_phase_changed.emit(self, phase)


func _on_died() -> void:
	if state == State.DEAD:
		return
	_cancel_attack()
	_pending_roar = false
	_play(death_animation)
	_set_state(State.DEAD)
	_stop()
	remove_from_group("lockable")
	# Deferred: death arrives inside a physics signal (the sword's area_entered).
	_body_shape.set_deferred(&"disabled", true)
	set_deferred(&"collision_layer", 0)
	for node in find_children("*", "Hurtbox", true, false):
		node.set_deferred(&"monitorable", false)
	for node in find_children("*", "Hitbox", true, false):
		(node as Hitbox).deactivate()
	if not _defeated_emitted:
		_defeated_emitted = true
		var events := _events()
		if events:
			events.boss_defeated.emit(self)


func _events() -> Node:
	# By path: in tests run with -s there are no autoloads.
	return get_node_or_null(^"/root/Events") if is_inside_tree() else null


# --- Animation --------------------------------------------------------------------------------

func _play(anim_name: StringName) -> void:
	if _anim == null or anim_name == &"" or not _anim.has_animation(anim_name):
		return
	_anim.play(anim_name, ANIM_BLEND)


func _anim_length(anim_name: StringName, fallback: float) -> float:
	if _anim and _anim.has_animation(anim_name):
		return _anim.get_animation(anim_name).length
	return fallback


func _set_state(next: State) -> void:
	state = next
	_state_time = 0.0
	state_changed.emit(next)
