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
##
## Approach vs attack: while CHASE, the boss asks BossBrain every frame (after the cooldown). Once
## it is within `engage_range` every attack valid at that distance competes; while it is still
## farther away only `BossAttack.opener` attacks (lunge, pounce, beam) can start, if the distance
## is inside their [min_range, max_range]. Otherwise it keeps walking (`walk_animation`).
## During ACTIVE an attack may move the boss (`advance_distance`), open extra hitboxes
## (`extra_hitbox_paths`), show a visual (`visual_path`) and expose gated hurtboxes.

signal state_changed(state: State)
signal attack_started(attack: BossAttack)

enum State { IDLE, CHASE, TELEGRAPH, ACTIVE, RECOVER, ROAR, DEAD }

const PHASE2_SPEED := 1.25
## Radio (m) del sello que aparece bajo el jefe al rugir al pasar a la fase 2.
const PHASE2_SEAL_RADIUS := 5.0
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
## Approaches until this distance (origin to origin); from there every attack may start. Attacks
## flagged `opener` may start earlier, from their own range.
@export var engage_range := 3.2
## Pause between the end of one recovery and the next decision.
@export var attack_cooldown := 0.25
@export var idle_animation: StringName = &"idle"
## The single locomotion clip of the scene (Blackhorn: "run"). Empty = glides with idle (Bone Dragon).
@export var walk_animation: StringName = &""
@export var roar_animation: StringName = &"roar"
@export var death_animation: StringName = &"death"
## Fixed seed for repeatable tests; 0 = random.
@export var rng_seed := 0
## Hurtboxes (relative to the boss) that only take hits during an attack with `exposes_hurtboxes`
## (+ `gated_grace` s): Ghidorah's heads while `bite` lasts.
@export var gated_hurtboxes: Array[NodePath] = []
@export var gated_grace := 0.2
## After dying, lowers the model until the body rests on the floor (Blackhorn's `death` ends in the air).
@export var settle_on_death := false
## Height of the lowest bone above the sole when settled.
@export var death_clearance := 0.07
@export var model_path := NodePath("Model")
@export_group("Repel")
## Repel reaction (BossRepel): when the boss takes `repel_threshold` of its max health within
## `repel_window` s, or `repel_burst_hits` hits within `repel_burst_window` s, or Kaelen stays within
## `repel_glue_radius` m for `repel_glue_time` s, it roars (roar_animation + sfx_phase2, no phase
## change) and is invulnerable while roaring. `repel_push_delay` s after the roar starts a shockwave
## pushes Kaelen away if she is within `repel_radius` m; a roll started so that its i-frames cover that
## instant dodges it. It can interrupt any state except the phase roar and death (also RECOVER).
@export var repel_enabled := true
@export_range(0.01, 1.0) var repel_threshold := 0.10
@export var repel_window := 4.0
@export var repel_cooldown := 7.0
@export var repel_burst_hits := 3
@export var repel_burst_window := 3.0
@export var repel_glue_time := 7.0
@export var repel_glue_radius := 3.2
@export var repel_radius := 7.0
## Initial outward speed (m/s) given to Kaelen; it fades to 0 over `repel_push_time` s, so she travels
## force * time / 2 = 4.5 m. `repel_lift` is a small upward hop (m/s) to make the shove readable.
@export var repel_force := 18.0
@export var repel_push_time := 0.5
@export var repel_lift := 3.0
## Seconds between the start of the roar (the warning) and the shockwave.
@export var repel_push_delay := 0.35
## The repel roar lasts at most this many seconds (the phase-2 roar plays its whole clip).
@export var repel_roar_max := 1.6
@export_group("Audio")
## Al recibir daño (suma de golpes de un mismo mandoble = un solo sonido).
@export var sfx_hurt: AudioStream
## Al entrar en la fase 2 (rugido).
@export var sfx_phase2: AudioStream
@export var sfx_death: AudioStream

var phase: int = 1
var state: State = State.IDLE
var brain := BossBrain.new()
var repel := BossRepel.new()
## True while the current ROAR is a repel reaction (not the phase-2 roar).
var repelling := false
## How many repel reactions happened (debug and tests).
var repel_count := 0
var current_attack: BossAttack
## Attack ids in the order they were used (debug and verification).
var attack_log: Array[StringName] = []
var gated_open := false
var settled_offset := 0.0

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
var _pending_repel := false
var _repel_push_left := 0.0
var _hitbox: Hitbox
var _telegraph: Node3D
var _spin_done := 0.0
var _was_rolling := false
var _defeated_emitted := false
var _clock := 0.0                 # game time, for SAME_SWING_WINDOW
var _swing_hits: Dictionary = {}  # source instance id → {time, amount}
var _advance_done := 0.0
var _advance_blocked := false
var _gate_grace := 0.0
var _extra_hitboxes: Array[Hitbox] = []
var _visual: Node3D
var _model: Node3D
var _skeleton: Skeleton3D


func _ready() -> void:
	add_to_group("boss")
	add_to_group("lockable")
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	repel.threshold_fraction = repel_threshold
	repel.window = repel_window
	repel.cooldown = repel_cooldown
	repel.burst_hits = repel_burst_hits
	repel.burst_window = repel_burst_window
	repel.glue_time = repel_glue_time
	repel.glue_radius = repel_glue_radius
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
			if attack.sfx_hit:
				hb.sfx_impact = attack.sfx_hit
		for path in attack.extra_hitbox_paths:
			var extra := get_node_or_null(path) as Hitbox
			if extra:
				extra.damage = attack.damage
				if attack.sfx_hit:
					extra.sfx_impact = attack.sfx_hit
		var visual := _visual_for(attack)
		if visual:
			visual.visible = false
		var tg := _telegraph_for(attack)
		if tg:
			tg.visible = false
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	_model = get_node_or_null(model_path) as Node3D
	if _model:
		var skeletons := _model.find_children("*", "Skeleton3D", true, false)
		_skeleton = skeletons.front() as Skeleton3D if not skeletons.is_empty() else null
	_set_gated(false)
	_warm_up()
	_play(idle_animation)


func _physics_process(delta: float) -> void:
	_clock += delta
	if state == State.DEAD:
		_settle(delta)
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	_find_player()
	_state_time += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	repel.tick(delta)
	var target_ok := _player_alive()
	if target_ok:
		_track_dodge()
		if repel_enabled and state != State.IDLE and state != State.DEAD 				and repel.register_proximity(delta, _flat_distance() <= repel.glue_radius, not can_repel()):
			_pending_repel = true
	if _pending_roar and state != State.ROAR:
		_pending_roar = false
		_cancel_attack()
		_play(roar_animation)
		_play_sfx(sfx_phase2)
		ImpactFx.seal(self, PHASE2_SEAL_RADIUS, 1.0, "blood")
		_set_state(State.ROAR)
	elif _pending_repel and can_repel():
		start_repel()
	elif not target_ok and state != State.IDLE and state != State.ROAR:
		_cancel_attack()   # Kaelen died: stop attacking
		_set_state(State.IDLE)
		_play(idle_animation)
	_run_state(delta, target_ok)
	_update_gate(delta)
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
			var approaching := distance > engage_range
			if _cooldown <= 0.0 and _try_start_attack(distance, approaching):
				_stop()
				return
			if approaching:
				_navigate_to(_player.global_position, move_speed * speed)
				_face(global_position + Vector3(velocity.x, 0.0, velocity.z), delta)
			else:
				_stop()
				_face(_player.global_position, delta)
			_play_locomotion(approaching and Vector2(velocity.x, velocity.z).length() > 0.3)
		State.TELEGRAPH:
			_stop()
			var telegraph := current_attack.telegraph_time / speed
			if _state_time < telegraph * TRACK_FRACTION:
				_face(_player.global_position, delta)
			if _state_time >= telegraph:
				_set_state(State.ACTIVE)
				_spin_done = 0.0
				_advance_done = 0.0
				_advance_blocked = false
				_begin_active()
		State.ACTIVE:
			_stop()
			var active := current_attack.active_time / speed
			var progress := minf(_state_time / active, 1.0)
			_apply_spin(progress)
			_apply_advance(progress)
			if _state_time >= active:
				_end_active()
				_set_state(State.RECOVER)
		State.RECOVER:
			_stop()
			if _state_time >= current_attack.recovery_time / speed:
				current_attack = null
				if _pending_repel or repel.is_due(health.max_value):
					_pending_repel = true   # deferred from the punish window: fires next frame
				_cooldown = attack_cooldown / speed
				_play(idle_animation)
				_set_state(State.CHASE)
		State.ROAR:
			_stop()
			if repelling and _repel_push_left > 0.0:
				_repel_push_left -= delta
				if _repel_push_left <= 0.0:
					_push_player()
			var roar_time := _anim_length(roar_animation, 2.0)
			if repelling:
				roar_time = minf(roar_time, repel_roar_max)   # the repel roar is cut short: it must not become a rest
			if _state_time >= roar_time / speed:
				repelling = false
				_play(idle_animation)
				_set_state(State.CHASE if target_ok else State.IDLE)


## Removes the first-use hitches (shaders of the attack effects and warnings, animation tracks): see
## ShaderWarmup. Without a window (tests) it does nothing.
func _warm_up() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _anim:
		for attack in attacks:
			if _anim.has_animation(attack.animation):
				_anim.play(attack.animation, 0.0)
				_anim.seek(0.0, true)
		if _anim.has_animation(idle_animation):
			_anim.play(idle_animation, 0.0)
			_anim.seek(0.0, true)
	ShaderWarmup.start(self)


# --- Attacks ----------------------------------------------------------------------------------

func _try_start_attack(distance: float, approaching := false) -> bool:
	var attack := brain.choose(attacks, distance, phase, _rng, approaching)
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


func _begin_active() -> void:
	var visual := _visual_for(current_attack)   # the beam fires from where its effect is (the mouth)
	_play_sfx(current_attack.sfx_active, visual.global_position if visual else global_position)
	if _hitbox:
		_hitbox.activate()
		if current_attack.id in ImpactFx.GROUND_ATTACKS and is_inside_tree():
			var spot := Vector3(_hitbox.global_position.x, global_position.y + 0.1, _hitbox.global_position.z)
			ImpactFx.dust(get_tree(), spot, 1.8)
	for path in current_attack.extra_hitbox_paths:
		var extra := get_node_or_null(path) as Hitbox
		if extra:
			extra.activate()
			_extra_hitboxes.append(extra)
	_visual = _visual_for(current_attack)
	if _visual:
		_visual.visible = true


func _end_active() -> void:
	if _hitbox:
		_hitbox.deactivate()
	for extra in _extra_hitboxes:
		if is_instance_valid(extra):
			extra.deactivate()
	_extra_hitboxes.clear()
	if _visual and is_instance_valid(_visual):
		_visual.visible = false
	_visual = null
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


## Moves the boss forward (its -Z) so that it has covered attack.advance_at(progress) metres;
## stops for good on the first collision (wall or Kaelen).
func _apply_advance(progress: float) -> void:
	if current_attack.advance_distance <= 0.0 or _advance_blocked:
		return
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	var step := current_attack.advance_at(progress) - _advance_done
	if step <= 0.0:
		return
	var hit := move_and_collide(forward.normalized() * step)
	if hit:
		_advance_blocked = true
		_advance_done += hit.get_travel().length()
	else:
		_advance_done += step


func _visual_for(attack: BossAttack) -> Node3D:
	if attack == null or attack.visual_path.is_empty():
		return null
	return get_node_or_null(attack.visual_path) as Node3D


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


## Plays the single locomotion clip while walking and idle otherwise (only if the scene has one).
func _play_locomotion(moving: bool) -> void:
	if _anim == null or walk_animation == &"":
		return
	var wanted := walk_animation if moving else idle_animation
	if _anim.current_animation != wanted and _anim.has_animation(wanted):
		_anim.play(wanted, ANIM_BLEND)


## True while the gated hurtboxes must take hits: attack in ACTIVE, or just finished.
static func gate_open(attacking: bool, grace_left: float) -> bool:
	return attacking or grace_left > 0.0


func _update_gate(delta: float) -> void:
	if gated_hurtboxes.is_empty():
		return
	var attacking := state == State.ACTIVE and current_attack != null and current_attack.exposes_hurtboxes
	_gate_grace = gated_grace if attacking else maxf(0.0, _gate_grace - delta)
	var open := gate_open(attacking, _gate_grace)
	if open != gated_open:
		_set_gated(open)


func _set_gated(open: bool) -> void:
	gated_open = open
	for path in gated_hurtboxes:
		var hurtbox := get_node_or_null(path) as Hurtbox
		if hurtbox:
			# Deferred: may run inside a physics signal.
			hurtbox.set_deferred(&"monitorable", open)


## After death: lowers the model (never raises it) until the lowest bone rests on the floor, smoothly.
func _settle(delta: float) -> void:
	if not settle_on_death or _model == null or _skeleton == null:
		return
	var lowest := INF
	for i in _skeleton.get_bone_count():
		lowest = minf(lowest, (_skeleton.global_transform * _skeleton.get_bone_global_pose(i)).origin.y)
	var at_zero_offset := lowest - global_position.y - _model.position.y
	var wanted := -maxf(0.0, at_zero_offset - death_clearance)
	settled_offset = move_toward(settled_offset, wanted, 1.5 * delta)
	_model.position.y = settled_offset


# --- Health, phase and death ------------------------------------------------------------------

## Damage from any hurtbox (already multiplied: head × 1.25). Hits from the same source within
## SAME_SWING_WINDOW are the same swing touching several hurtboxes: only the largest one counts.
func _on_hurt(amount: int, source: Node) -> void:
	if state == State.DEAD or repelling:
		return
	_aggro = true
	var key := source.get_instance_id() if source else 0
	var last: Dictionary = _swing_hits.get(key, {})
	if not last.is_empty() and _clock - float(last.time) <= SAME_SWING_WINDOW:
		var applied: int = last.amount
		if amount > applied:
			last.amount = amount
			health.take_damage(amount - applied)
			_register_repel_damage(amount - applied)
		return
	_swing_hits[key] = {time = _clock, amount = amount}
	health.take_damage(amount)
	_register_repel_damage(amount)
	if not health.is_dead():
		_play_sfx(sfx_hurt)


# --- Repel reaction ---------------------------------------------------------------------------

func _register_repel_damage(amount: int) -> void:
	if not repel_enabled or health.is_dead():
		return
	if repel.register_damage(amount, health.max_value, not can_repel()):
		_pending_repel = true   # handled in _physics_process (we may be inside a physics signal)


## The repel can start now: not dead, not roaring (phase roar or another repel), no phase roar
## pending (it may interrupt a recovery: the point is to stop Kaelen from chaining hits).
func can_repel() -> bool:
	return repel_enabled and state != State.DEAD and state != State.ROAR \
		and not _pending_roar and not repelling and not health.is_dead()


## Interrupts the current action, roars (phase-2 clip and sound, without phase effects), starts the
## cooldown and pushes Kaelen if she is close.
func start_repel() -> void:
	_pending_repel = false
	if not can_repel():
		return
	repel.trigger()
	repel_count += 1
	_cancel_attack()
	_stop()
	repelling = true
	_play(roar_animation)
	_play_sfx(sfx_phase2)
	ImpactFx.seal(self, repel_radius, repel_push_delay)   # el sello es el aviso: se cierra justo antes de la onda
	_set_state(State.ROAR)
	_repel_push_left = repel_push_delay


func _push_player() -> void:
	if not is_inside_tree():
		return
	_find_player()
	if not _player_alive():
		return
	RepelWave.spawn(self, repel_radius)
	var rig := _player.get_node_or_null(^"CameraRig")
	if rig and rig.has_method(&"shake"):
		rig.call(&"shake", 0.18, 0.45)
	var push := BossRepel.push_velocity(global_position, _player.global_position, repel_radius,
			repel_force, -global_basis.z)
	if push != Vector3.ZERO and _player.has_method(&"apply_shove"):
		_player.call(&"apply_shove", push, repel_push_time, repel_lift)


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
	_set_gated(false)
	_pending_roar = false
	_pending_repel = false
	_repel_push_left = 0.0
	repelling = false
	_play(death_animation)
	_play_sfx(sfx_death)
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


## Plays `stream` (if any) in 3D at the boss. By path: in tests run with -s there is no AudioManager.
func _play_sfx(stream: AudioStream, at := Vector3.INF) -> void:
	if stream == null or not is_inside_tree():
		return
	var audio := get_node_or_null(^"/root/AudioManager")
	if audio:
		audio.play_sfx_3d(stream, global_position if at == Vector3.INF else at, 0.1, 0.0, 16.0)


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
