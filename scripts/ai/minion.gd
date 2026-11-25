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
## Any hit from Kaelen (normal slash, combo finisher or heavy attack alike) stuns a minion for this
## long: STUN_NORMAL for a normal minion, STUN_ELITE for an elite, which recovers faster and is never
## stun-locked by the combo. Bosses are never stunned (Boss has no STUNNED state).
const STUN_NORMAL := 0.6
const STUN_ELITE := 0.35
const PSX := preload("res://scenes/levels/psx_test.gd")
const ANIM_BLEND := 0.15        # s of blend between clips
const MOVE_EPSILON := 0.1       # m/s below which a chasing minion plays idle instead of walk
const WALK_SCALE_MIN := 0.4
const WALK_SCALE_MAX := 1.5
const DEATH_FALL_TIME := 0.55   # fall tween when the model has no death clip
const DEATH_SINK := 0.15        # m the model sinks while falling
const DEATH_BUCKLE := 0.3       # rad it doubles forward before toppling
const DEATH_BUCKLE_TIME := 0.3
const DEATH_TWIST := 0.5        # rad it turns while buckling (side given by the orbit sign)
const DEATH_BOUNCE := 0.12      # rad it rebounds after hitting the floor
const DEATH_BOUNCE_TIME := 0.12
const DEATH_STAGGER_SPEED := 1.6
const DEATH_DUST_OFFSET := 1.0  # m behind its feet, where the torso lands
const DEATH_DUST_SIZE := 1.2
const CORPSE_SINK_DEPTH := 0.9  # m the corpse sinks into the floor before it is freed
const CORPSE_SINK_TIME := 1.0
const CORPSE_DUST_SIZE := 1.0
const KIND_IDLE := &"idle"
const KIND_WALK := &"walk"
const KIND_RUN := &"run"
const KIND_ATTACK := &"attack"
const KIND_HURT := &"hurt"
const KIND_DEATH := &"death"
const TURN_SPEED := 10.0
const EYE_HEIGHT := 1.5
const CHEST_HEIGHT := 1.2       # Kaelen's chest (1.70 m capsule)
const WORLD_MASK := 1
const ORDER_ARRIVE := 0.8       # m to the order point within which it stands still

@export var cost := 1
@export var attack_range := 1.5
@export var move_speed := 3.5
@export var damage := 20
## Attack repertoire. Empty = the classic single swing (WINDUP/ACTIVE/RECOVER_TIME, anim_attack).
@export var attacks: Array[MinionAttack] = []

@export_group("Visuals")
@export var model_scene: PackedScene            ## null = the placeholder (Body/Visor) stays unchanged
@export var model_scale := 1.0
@export var model_yaw_offset := PI              ## models facing +Z inside a minion that faces -Z
@export var tint := Color(1, 1, 1, 1)           ## multiplies the model color (elites)
@export var anim_idle: StringName = &"idle"
@export var anim_walk: StringName = &"walk"
@export var anim_attack: StringName = &"attack"
@export var anim_hurt: StringName = &"hurt"
@export var anim_death: StringName = &"death"   ## empty or missing -> fall tween
## Played in a loop over Kaelen's body when she dies (empty or missing = idle).
@export var anim_taunt: StringName = &""
## Without a death clip: clip played while the body collapses (e.g. "hurt"). Empty = none.
@export var death_stagger_clip: StringName = &""
@export var walk_anim_speed := 1.0              ## speed scale of the walk clip
## Runners (arena 3): while chasing a Kaelen farther than run_distance they sprint at run_speed with
## anim_run. Empty anim_run or run_speed <= move_speed = it always walks.
@export var anim_run: StringName = &""
@export var run_speed := 0.0
@export var run_distance := 6.0
@export var run_anim_speed := 1.0
@export var weapon_scene: PackedScene           ## optional, hung on weapon_bone
@export var weapon_bone: StringName = &"mixamorig:RightHand"
@export var weapon_transform := Transform3D.IDENTITY
@export var corpse_time := 2.5                  ## s the body lies on the floor before sinking away
## Death clip: clip seconds skipped at the start (a slow stagger before the fall), clip second at
## which the body hits the floor (< 0 = the clip's end) and the game seconds that fall may take (the
## clip is sped up to fit, never slowed down).
@export var death_clip_start := 0.0
@export var death_land_at := -1.0
@export var death_fall_time := 1.5
@export_group("Audio")
@export var sfx_spawn: AudioStream              ## elites: sound when they appear
@export var sfx_attack: AudioStream
@export var sfx_hurt: AudioStream
@export var sfx_death: AudioStream
## Footsteps of a normal minion: a long track of several steps that loops while it walks.
## Elites (those with `sfx_spawn`) use neither it nor the normal minions' attack sound.
@export var sfx_step: AudioStream

## Footsteps: only those of minions within STEP_HEARING_DISTANCE m of Kaelen are heard, and never more than
## STEP_MAX_VOICES at once in the whole scene (each one is a looping 3D player).
const STEP_HEARING_DISTANCE := 14.0
const STEP_MAX_VOICES := 3
const STEP_VOLUME_DB := -6.0
const STEP_MIN_SPEED := 0.4
static var _step_voices_in_use := 0

var state: MinionState = MinionState.IDLE
var brain := MinionBrain.new()
var _step_player: AudioStreamPlayer3D

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
var _model_root: Node3D       # instanced model (null = placeholder)
var _anim: AnimationPlayer
var _current_kind: StringName = &""
var _order_point := Vector3.ZERO   # encirclement point given by the Orchestrator (pincer)
var _order_left := 0.0
var _retreat_left := 0.0           # s of retreat left (low health)
var _retreated := false
var current_attack: MinionAttack
## Seconds from death until the body is on the floor (set when it dies).
var death_landing := 0.0
var _default_attack: MinionAttack   # built from the constants when `attacks` is empty
var _last_attack_id: StringName = &""
var _hit_index := -1                # hit window in progress (-1 = none)
var _rng := RandomNumberGenerator.new()
var _zone_hitbox: Hitbox            # floor circle of zone attacks (cast, scream), created on demand
var _zone_telegraph: MeshInstance3D
var _zone_point := Vector3.ZERO

var _stun_for := STUN_NORMAL        # length of the current STUNNED (set on each hit, see stun_time)
var _knock := Vector3.ZERO          # knockback velocity at the start of the push (fades to 0)
var _knock_total := 0.0
var _knock_left := 0.0
var _flinch: Tween
var _spell_circle: MagicArea        # magic circle of a cast in progress
var _orb_sent := false
var _orb: Node3D                    # the cast's orb while it flies
var _ready_at := {}                 # attack id -> game time from which it can be chosen again
var _clock := 0.0
var _taunting := false              # Kaelen died: it stops and mocks her

## Being hit pushes the minion back: a normal hit KNOCK_SPEED m/s fading over KNOCK_TIME (about 0.35 m),
## the combo's 3rd hit and the heavy attack FINISHER_KNOCK_* (about 1.3 m). The kind of hit changes
## only the push and the flinch, not the stun (see STUN_NORMAL). Elites, heavier, take
## ELITE_KNOCK_MULT of the push. The body also flinches back.
const KNOCK_SPEED := 3.2
const KNOCK_TIME := 0.22
const FINISHER_KNOCK_SPEED := 7.0
const FINISHER_KNOCK_TIME := 0.36
const ELITE_KNOCK_MULT := 0.5
const FLINCH_ANGLE := 0.16          # rad the body leans back on a hit (twice on a finisher)
const FLINCH_TIME := 0.09
const SPELL_COLOR := Color(0.6, 1.0, 0.3)
const SPELL_EDGE := Color(0.15, 0.55, 0.08)
const ZONE_TRACK_FRACTION := 0.6    # a cast follows Kaelen for the first 60 % of its windup
const LUNGE_STOP := 0.9             # m to Kaelen at which a lunge stops pushing
const ZONE_HEIGHT := 2.0


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("lockable")
	_rng.randomize()
	brain.attack_range = MinionAttack.reach(attacks, attack_range)
	brain.circle_range = TOKEN_RANGE
	hitbox.damage = damage
	health.died.connect(_on_died)
	hurtbox.hurt.connect(_on_hurt)
	agent.velocity_computed.connect(_on_velocity_computed)
	# Avoidance clamps the safe velocity to max_speed: a runner needs room for its sprint.
	agent.max_speed = maxf(agent.max_speed, maxf(move_speed, run_speed))
	# Fixed orbit direction per minion so they do not all pile up on the same side.
	_orbit_sign = 1.0 if get_instance_id() % 2 == 0 else -1.0
	_setup_visuals()
	# Deferred: whoever spawns it sets the position right after add_child.
	_play_sfx.call_deferred(sfx_spawn)


func _physics_process(delta: float) -> void:
	if state == MinionState.DEAD:
		return   # no collisions: if it moved it would fall through the floor
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_find_player()
	_clock += delta
	if _taunting:
		_run_taunt(delta)
		return
	_state_time += delta
	brain.attack_range = MinionAttack.reach(_ready_attacks(), attack_range)
	_token_cooldown = maxf(0.0, _token_cooldown - delta)
	_order_left = maxf(0.0, _order_left - delta)
	_retreat_left = maxf(0.0, _retreat_left - delta)
	_check_retreat()

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
		attack_finished = state == MinionState.ATTACK and _state_time >= get_attack().strike_time(),
		recover_finished = state == MinionState.RECOVER and _state_time >= get_attack().recover,
		stun_finished = state == MinionState.STUNNED and _state_time >= _stun_for,
		was_hit = _was_hit,
		is_dead = health.is_dead(),
	}
	_was_hit = false
	var next := brain.next_state(state, ctx)
	if next != state or ctx.was_hit:
		_change_state(next)
	_run_state(delta)
	_update_steps()
	_update_animation()


## Position order from the Orchestrator (pincer): go to the point and stay in CIRCLE there for `duration` s.
func order_to(point: Vector3, duration := 1.2) -> void:
	if state == MinionState.DEAD:
		return   # a corpse takes no orders (it could arrive late, from a squad built before it died)
	_order_point = point
	_order_left = duration


func clear_order() -> void:
	_order_left = 0.0


func has_order() -> bool:
	return _order_left > 0.0


func is_retreating() -> bool:
	return _retreat_left > 0.0


## Stop attacking: with low health a normal minion backs away for a few seconds and comes back.
func _check_retreat() -> void:
	if state == MinionState.DEAD or state == MinionState.ATTACK or _retreat_left > 0.0:
		return
	if MinionBrain.should_retreat(float(health.current) / maxf(1.0, float(health.max_value)), is_elite(), _retreated):
		_retreated = true
		_retreat_left = MinionBrain.RETREAT_TIME
		_order_left = 0.0
		_release_token()


## Puts it in pursuit with no lose radius: used by the Orchestrator for the waves, which spawn
## farther than 8 m (normally outside the detection radius) and, without this, would stay IDLE.
func alert() -> void:
	if state == MinionState.DEAD:
		return
	brain.lose_radius = INF
	state = MinionState.CHASE
	_state_time = 0.0


func _run_state(delta: float) -> void:
	match state:
		MinionState.CHASE:
			if _player and _retreat_left > 0.0:
				_navigate_to(MinionBrain.retreat_point(global_position, _player.global_position), move_speed)
				_face_direction(Vector3(velocity.x, 0.0, velocity.z), delta)
			elif _player and _order_left > 0.0:
				_go_to_order(delta, move_speed)
			elif _player:
				var to_player := global_position.distance_to(_player.global_position)
				_navigate_to(_player.global_position, chase_speed(move_speed, run_speed, to_player, run_distance))
				_face_direction(Vector3(velocity.x, 0.0, velocity.z), delta)
			else:
				_stop()
		MinionState.CIRCLE:
			if _player and _retreat_left > 0.0:
				_navigate_to(MinionBrain.retreat_point(global_position, _player.global_position), move_speed)
				_face_direction(Vector3(velocity.x, 0.0, velocity.z), delta)
			elif _player and _order_left > 0.0:
				_go_to_order(delta, move_speed * 0.85)
			elif _player:
				_navigate_to(_orbit_point(), move_speed * ORBIT_SPEED_FACTOR)
				_face_direction(_player.global_position - global_position, delta)
			else:
				_stop()
		MinionState.ATTACK:
			_run_attack(delta)
		MinionState.STUNNED:
			_run_knockback(delta)
		_:
			_stop()
	move_and_slide()


## Pushed back by a hit: the push fades linearly; walls stop it (move_and_slide).
func _run_knockback(delta: float) -> void:
	_stop()
	if _knock_left <= 0.0:
		return
	var v := _knock * clampf(_knock_left / _knock_total, 0.0, 1.0)
	velocity.x = v.x
	velocity.z = v.z
	_knock_left = maxf(0.0, _knock_left - delta)


## Goes to the encirclement point and, on arrival, stands looking at Kaelen.
func _go_to_order(delta: float, speed: float) -> void:
	var to_point := _order_point - global_position
	to_point.y = 0.0
	if to_point.length() <= ORDER_ARRIVE:
		_stop()
		_face_direction(_player.global_position - global_position, delta)
	else:
		_navigate_to(_order_point, speed)
		_face_direction(Vector3(velocity.x, 0.0, velocity.z), delta)


func _change_state(next: MinionState) -> void:
	var prev := state
	state = next
	_state_time = 0.0
	if prev == MinionState.ATTACK:
		_end_strike()
		_release_token(true)
	match next:
		MinionState.ATTACK:
			_begin_attack()
		MinionState.STUNNED:
			_end_strike()
			_release_token(true)
		MinionState.DEAD:
			_stop_steps()
			_die()
	if next == MinionState.ATTACK and sfx_spawn == null:   # elites have their own sounds
		_play_sfx(sfx_attack)
	# Attack and hurt always restart their clip (a new hit while stunned too).
	_update_animation(next == MinionState.ATTACK or next == MinionState.STUNNED)


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
		# Shared threat: if the boss is warning / attacking near Kaelen, it does not start an attack.
		if _holding_token and tokens.get(&"boss_threat_near") == true:
			_release_token()
		elif _retreat_left > 0.0:
			pass
		elif distance <= token_range() and _token_cooldown <= 0.0:
			_holding_token = tokens.request(self)   # returns true if it already holds one
		elif distance > token_range() + (TOKEN_DROP_RANGE - TOKEN_RANGE) and _holding_token:
			_release_token()


## Radius at which it asks for a token: TOKEN_RANGE, or more for a minion with a ranged attack.
func token_range() -> float:
	return maxf(TOKEN_RANGE, brain.attack_range + 0.5)


## Asks AttackTokens (the source of truth): if it was reset with this minion alive,
## it stops believing it holds a token. Without the autoload (tests with -s) it uses its local copy.
func _has_token() -> bool:
	var tokens := _tokens()
	if tokens and _holding_token:
		_holding_token = tokens.is_holder(self)
	return _holding_token


## Gives the token back (used by the Orchestrator when the arena ends).
func release_token() -> void:
	_release_token()


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

## The attack in use (or about to be used): the chosen one, else the classic single swing.
func get_attack() -> MinionAttack:
	if current_attack:
		return current_attack
	if not attacks.is_empty():
		return attacks[0]
	if _default_attack == null:
		_default_attack = MinionAttack.new()
		_default_attack.id = &"swing"
		_default_attack.clip = anim_attack
		_default_attack.max_range = attack_range
		_default_attack.windup = WINDUP_TIME
		_default_attack.active = ACTIVE_TIME
		_default_attack.recover = RECOVER_TIME
	return _default_attack


## Attacks that can be chosen now (off cooldown); all of them if every one is cooling down.
func _ready_attacks() -> Array:
	var out: Array = []
	for a in attacks:
		if _clock >= float(_ready_at.get(a.id, 0.0)):
			out.append(a)
	return out if not out.is_empty() else attacks


func _begin_attack() -> void:
	current_attack = null
	if not attacks.is_empty():
		var pool := _ready_attacks()
		var distance := global_position.distance_to(_player.global_position) if _player else 0.0
		var i := MinionAttack.choose(pool, distance, _last_attack_id, _rng.randf())
		current_attack = pool[i]
	var atk := get_attack()
	_last_attack_id = atk.id
	if atk.cooldown > 0.0:
		_ready_at[atk.id] = _clock + atk.cooldown
	_hit_index = -1
	_orb_sent = false
	hitbox.damage = roundi(damage * atk.damage_mult)
	if atk.warning != AttackWarning.Level.NONE:
		AttackWarning.aura_to(_model_root, AttackWarning.color_for(atk.warning), 1.0, AttackWarning.rise_time(atk.windup))
	if atk.zone_radius > 0.0:
		_zone_point = _zone_center(atk)
		_show_zone(atk)


func _run_attack(delta: float) -> void:
	var atk := get_attack()
	_stop()
	if _state_time < atk.windup:
		if _player:
			_face_direction(_player.global_position - global_position, delta)
			if atk.zone_radius > 0.0 and _state_time < atk.windup * ZONE_TRACK_FRACTION:
				_zone_point = _zone_center(atk)
				_place_zone()
		if atk.zone_radius > 0.0:
			if _zone_telegraph:
				AttackWarning.set_progress(_zone_telegraph, _state_time / atk.windup)
			if atk.zone_at_target and not _orb_sent and _state_time >= atk.windup * ZONE_TRACK_FRACTION:
				_orb_sent = true   # the spot is fixed now: the orb flies onto it and lands with the blow
				_orb = SpellFx.orb(get_parent(), _hand_position(), _zone_point + Vector3.UP * 0.3,
						atk.windup - _state_time, SPELL_COLOR, SPELL_EDGE)
		return
	var idx := atk.hit_index_at(_state_time)
	if idx != _hit_index:
		_set_strike(false)
		if idx >= 0:
			_set_strike(true)
			if atk.zone_at_target and idx == 0:
				SpellFx.burst(get_parent(), _zone_point, atk.zone_radius, SPELL_COLOR, SPELL_EDGE)
		_hit_index = idx
	if idx >= 0 and atk.lunge_speed > 0.0:
		var close := _player != null and global_position.distance_to(_player.global_position) <= LUNGE_STOP
		if not close:
			var fwd := get_forward() * atk.lunge_speed
			velocity.x = fwd.x
			velocity.z = fwd.z


## Where a spell leaves the caster: in front of its chest, at hand height.
func _hand_position() -> Vector3:
	return global_position + Vector3.UP * 1.5 + get_forward() * 0.6


## Where a zone attack lands: Kaelen's feet (cast) or the minion's own (scream).
func _zone_center(atk: MinionAttack) -> Vector3:
	if atk.zone_at_target and _player:
		return _player.global_position
	return global_position


func _set_strike(on: bool) -> void:
	if get_attack().zone_radius > 0.0:
		if _zone_hitbox:
			if on:
				_zone_hitbox.damage = hitbox.damage
				_zone_hitbox.activate()
			else:
				_zone_hitbox.deactivate()
	else:
		_set_hitbox(on)


## Leaves ATTACK: weapon and zone off, warning hidden.
func _end_strike() -> void:
	_set_hitbox(false)
	if _zone_hitbox:
		_zone_hitbox.deactivate()
	if _zone_telegraph:
		_zone_telegraph.visible = false
	SpellFx.stop_circle(_spell_circle)
	_spell_circle = null
	if _orb and is_instance_valid(_orb) and _hit_index < 0:
		SpellFx.fizzle(_orb)   # interrupted before it landed: it must not fall harmlessly
	_orb = null
	if current_attack and current_attack.warning != AttackWarning.Level.NONE:
		AttackWarning.aura_to(_model_root, AttackWarning.color_for(current_attack.warning), 0.0, AttackWarning.AURA_FADE)
	_hit_index = -1


## Shows the zone's warning: a spell's magic circle (cast) or the yellow ground warning (scream).
func _show_zone(atk: MinionAttack) -> void:
	if _zone_hitbox == null:
		_build_zone()
	((_zone_hitbox.get_child(0) as CollisionShape3D).shape as CylinderShape3D).radius = atk.zone_radius
	if atk.zone_at_target:
		_spell_circle = SpellFx.circle(get_parent(), _zone_point, atk.zone_radius, atk.windup)
	else:
		AttackWarning.set_radius(_zone_telegraph, atk.zone_radius)
		AttackWarning.set_progress(_zone_telegraph, 0.0)
		_zone_telegraph.visible = true
	_place_zone()


func _place_zone() -> void:
	if _zone_hitbox == null:
		return
	_zone_hitbox.global_position = _zone_point
	_zone_telegraph.global_position = _zone_point + Vector3.UP * 0.05
	if _spell_circle and is_instance_valid(_spell_circle):
		_spell_circle.global_position = _zone_point + Vector3.UP * 0.06


## Floor circle (hitbox + warning) shared by every zone attack of this minion. top_level: it stays
## where it landed even if the minion turns or moves.
func _build_zone() -> void:
	_zone_hitbox = Hitbox.new()
	_zone_hitbox.name = "ZoneHitbox"
	_zone_hitbox.top_level = true
	_zone_hitbox.collision_layer = hitbox.collision_layer
	_zone_hitbox.collision_mask = hitbox.collision_mask
	_zone_hitbox.monitorable = false
	_zone_hitbox.sfx_impact = hitbox.sfx_impact
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.height = ZONE_HEIGHT
	shape.shape = cyl
	shape.position.y = ZONE_HEIGHT * 0.5
	_zone_hitbox.add_child(shape)
	add_child(_zone_hitbox)
	_zone_telegraph = AttackWarning.ground_disc(1.0, AttackWarning.Level.DODGE)   # same look as the bosses'
	_zone_telegraph.name = "ZoneTelegraph"
	_zone_telegraph.top_level = true
	_zone_telegraph.visible = false
	add_child(_zone_telegraph)


func _set_hitbox(on: bool) -> void:
	if on == _hitbox_on:
		return
	_hitbox_on = on
	if on:
		hitbox.activate()
	else:
		hitbox.deactivate()


func _on_hurt(_amount: int, source: Node) -> void:
	if health.is_dead():
		return
	_was_hit = true
	_play_sfx(sfx_hurt)
	var kind := hit_kind(source)
	_stun_for = stun_time(is_elite())
	var strong := kind != &"normal"
	var away := -get_forward()
	if source is Node3D:
		away = global_position - (source as Node3D).global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = -get_forward()
	var mult := ELITE_KNOCK_MULT if is_elite() else 1.0
	_knock = away.normalized() * (FINISHER_KNOCK_SPEED if strong else KNOCK_SPEED) * mult
	_knock_total = FINISHER_KNOCK_TIME if strong else KNOCK_TIME
	_knock_left = _knock_total
	_flinch_back(2.0 if strong else 1.0)


## Elites are the minions with their own spawn sound (one per group, cost 3; see AGENTS.md 7.2).
func is_elite() -> bool:
	return sfx_spawn != null


## Seconds a hit stuns a normal minion or an elite.
static func stun_time(elite: bool) -> float:
	return STUN_ELITE if elite else STUN_NORMAL


## How hard a hit was: &"heavy" (Kaelen's heavy attack), &"finisher" (3rd hit of her combo) or &"normal".
static func hit_kind(source: Node) -> StringName:
	var player := source as Player
	if player == null:
		return &"normal"
	if player.is_heavy_attacking():
		return &"heavy"
	if player.is_finisher():
		return &"finisher"
	return &"normal"


## The body leans back for an instant (procedural, on the model holder) and straightens.
func _flinch_back(scale_by: float) -> void:
	var holder := get_node_or_null(^"Model") as Node3D
	if holder == null or not is_inside_tree():
		return
	if _flinch and _flinch.is_valid():
		_flinch.kill()
	_flinch = create_tween()
	_flinch.tween_property(holder, "rotation:x", -FLINCH_ANGLE * scale_by, FLINCH_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_flinch.tween_property(holder, "rotation:x", 0.0, FLINCH_TIME * 3.0 * scale_by) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Kaelen died: stop attacking and mock her over her body until the arena reloads.
func celebrate() -> void:
	if state == MinionState.DEAD or _taunting:
		return
	_taunting = true
	_end_strike()
	_release_token()
	_stop()
	_stop_steps()
	if _anim and _anim.is_inside_tree():
		var clip := anim_taunt if _anim.has_animation(anim_taunt) else anim_idle
		if _anim.has_animation(clip):
			_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			_anim.speed_scale = 1.0
			_anim.play(clip, ANIM_BLEND * 2.0)
			_current_kind = KIND_IDLE


func is_taunting() -> bool:
	return _taunting


func _run_taunt(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_stop()
	if _player:
		_face_direction(_player.global_position - global_position, delta)
	move_and_slide()


func _on_died() -> void:
	if state != MinionState.DEAD:
		_change_state(MinionState.DEAD)


func _die() -> void:
	if _flinch and _flinch.is_valid():
		_flinch.kill()
	_end_strike()
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
	_play_sfx(sfx_death)
	if is_inside_tree():
		ImpactFx.puff(get_tree(), global_position + Vector3.UP * 0.5)
	death_landing = _play_death()
	# The body lies on the floor corpse_time s after landing, then sinks away (paused with the game).
	get_tree().create_timer(death_landing + corpse_time, false).timeout.connect(_despawn)


## The corpse sinks into the floor in a puff of dust and is freed.
func _despawn() -> void:
	if not is_inside_tree():
		return
	ImpactFx.dust(get_tree(), global_position + Vector3.UP * 0.1, CORPSE_DUST_SIZE)
	var holder := get_node_or_null(^"Model") as Node3D
	if holder == null:
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(holder, "position:y", holder.position.y - CORPSE_SINK_DEPTH, CORPSE_SINK_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


# --- Visuals ----------------------------------------------------------------------------------

## Static clip choice: which kind of clip the FSM state asks for (horizontal speed in m/s).
## `run_from`: speed from which a runner shows its run clip (INF = it never runs).
static func clip_kind(st: MinionState, horizontal_speed: float, run_from := INF) -> StringName:
	match st:
		MinionState.DEAD:
			return KIND_DEATH
		MinionState.STUNNED:
			return KIND_HURT
		MinionState.ATTACK, MinionState.RECOVER:
			return KIND_ATTACK   # keeps playing through RECOVER so the swing ends naturally
		MinionState.CHASE, MinionState.CIRCLE:
			if horizontal_speed >= run_from:
				return KIND_RUN
			return KIND_WALK if horizontal_speed >= MOVE_EPSILON else KIND_IDLE
	return KIND_IDLE


## Chase speed: a runner sprints while Kaelen is farther than run_distance, otherwise it walks.
static func chase_speed(walk: float, run: float, distance: float, run_from_distance: float) -> float:
	return run if run > walk and distance > run_from_distance else walk


## Speed from which the run clip shows (half-way between walking and running), INF without one.
func _run_threshold() -> float:
	if anim_run == &"" or run_speed <= move_speed:
		return INF
	return (move_speed + run_speed) * 0.5


## Walk clip speed proportional to the real speed (relative to max_speed).
static func walk_speed_scale(horizontal_speed: float, max_speed: float, walk_anim: float) -> float:
	if max_speed <= 0.0:
		return walk_anim
	return clampf(horizontal_speed / max_speed, WALK_SCALE_MIN, WALK_SCALE_MAX) * walk_anim


## Speed that makes a clip of `length` s fit in `window` s (only speeds up, never slows down).
static func fit_speed(length: float, window: float) -> float:
	if length <= 0.0 or window <= 0.0:
		return 1.0
	return maxf(1.0, length / window)


func _setup_visuals() -> void:
	if model_scene == null:
		return
	var inst := model_scene.instantiate() as Node3D
	if inst == null:
		push_warning("Minion: model_scene is not a Node3D scene.")
		return
	if not _attach_model(inst):
		inst.free()


## Hangs `inst` under Model, hides the placeholder, applies PSX + tint and finds the AnimationPlayer.
func _attach_model(inst: Node3D) -> bool:
	var holder := get_node_or_null(^"Model") as Node3D
	if holder == null:
		push_warning("Minion: no Model node to hang the model on.")
		return false
	for placeholder in [^"Body", ^"Visor"]:
		var node := holder.get_node_or_null(placeholder) as Node3D
		if node:
			node.visible = false
	inst.scale = Vector3.ONE * model_scale
	inst.rotation.y = model_yaw_offset
	holder.add_child(inst)
	_model_root = inst
	PSX.apply_psx(inst)
	_apply_tint(inst, tint)
	_anim = _find_animation_player(inst)
	if _anim == null:
		push_warning("Minion: the model has no AnimationPlayer.")
	else:
		for clip in [anim_idle, anim_walk, anim_run]:
			if _anim.has_animation(clip):
				_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		# One-shot clips must not loop (a looping death would get the corpse back up).
		var one_shots: Array[StringName] = [anim_attack, anim_hurt, anim_death]
		for atk in attacks:
			one_shots.append(atk.clip)
		for clip in one_shots:
			if _anim.has_animation(clip):
				_anim.get_animation(clip).loop_mode = Animation.LOOP_NONE
	if weapon_scene:
		var weapon := weapon_scene.instantiate() as Node3D
		if weapon == null:
			push_warning("Minion: weapon_scene is not a Node3D scene.")
		elif _attach_weapon(inst, weapon) == null:
			weapon.free()
	if is_inside_tree():
		_update_animation(true)
	return true


## The weapon hangs from a "WeaponGrip" node under the BoneAttachment3D. Mixamo bones carry a large
## scale (Kaelen needed a ×577 grip by hand), so once in the tree the grip cancels the bone's world
## scale: `weapon_transform` is then in meters relative to the hand, times model_scale.
func _attach_weapon(root: Node, weapon: Node3D) -> BoneAttachment3D:
	var skeleton := _find_skeleton(root)
	var bone := _resolve_bone_name(skeleton, String(weapon_bone)) if skeleton else ""
	if bone.is_empty():
		push_warning("Minion: no Skeleton3D with bone '%s' for the weapon." % weapon_bone)
		return null
	var attachment := BoneAttachment3D.new()
	attachment.name = "WeaponAttachment"
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	var grip := Node3D.new()
	grip.name = "WeaponGrip"
	attachment.add_child(grip)
	grip.add_child(weapon)
	weapon.transform = weapon_transform
	PSX.apply_psx(weapon)
	_apply_tint(weapon, tint)
	if is_inside_tree():
		_fit_weapon_grip.call_deferred(grip)
	return attachment


## glTF import turns "mixamorig:RightHand" into "mixamorig_RightHand": accept either spelling.
static func _resolve_bone_name(skeleton: Skeleton3D, wanted: String) -> String:
	for candidate in [wanted, wanted.replace(":", "_"), wanted.replace("_", ":")]:
		if skeleton.find_bone(candidate) >= 0:
			return candidate
	return ""


## Waits for the BoneAttachment3D to follow its bone, then cancels the bone's world scale.
func _fit_weapon_grip(grip: Node3D) -> void:
	await get_tree().process_frame
	if not is_instance_valid(grip) or not grip.is_inside_tree():
		return
	var parent := grip.get_parent() as Node3D
	var bone_scale := parent.global_basis.get_scale()
	# Mixamo bones can be really small in world space (the knight's hand is ~7.5e-5): only zero is invalid.
	if is_zero_approx(bone_scale.x) or is_zero_approx(bone_scale.y) or is_zero_approx(bone_scale.z):
		return
	var root_scale := global_basis.get_scale()   # the minion root, normally 1
	grip.scale = Vector3(root_scale.x / bone_scale.x, root_scale.y / bone_scale.y, root_scale.z / bone_scale.z) * model_scale


static func _find_animation_player(root: Node) -> AnimationPlayer:
	var found := root.find_children("*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if not found.is_empty() else null


static func _find_skeleton(root: Node) -> Skeleton3D:
	var found := root.find_children("*", "Skeleton3D", true, false)
	return found[0] as Skeleton3D if not found.is_empty() else null


## Multiplies the PSX materials' modulate_color by `color` (call after apply_psx).
static func _apply_tint(node: Node, color: Color) -> void:
	if color.is_equal_approx(Color.WHITE):
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_surface_override_material(i) as ShaderMaterial
				if mat == null:
					continue
				var current: Variant = mat.get_shader_parameter("modulate_color")
				var base: Color = current if current is Color else Color.WHITE
				mat.set_shader_parameter("modulate_color", base * color)
	for child in node.get_children():
		_apply_tint(child, color)


func _clip_name(kind: StringName) -> StringName:
	match kind:
		KIND_WALK:
			return anim_walk
		KIND_RUN:
			return anim_run
		KIND_ATTACK:
			return get_attack().clip
		KIND_HURT:
			return anim_hurt
		KIND_DEATH:
			return anim_death
	return anim_idle


## Plays the clip that matches the state; only switches when the kind changes (or `force`).
func _update_animation(force := false) -> void:
	if _anim == null or not _anim.is_inside_tree():
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var kind := clip_kind(state, speed, _run_threshold())
	var clip := _clip_name(kind)
	if not _anim.has_animation(clip):
		return
	if kind == KIND_WALK:
		_anim.speed_scale = walk_speed_scale(speed, move_speed, walk_anim_speed)
	elif kind == KIND_RUN:
		_anim.speed_scale = walk_speed_scale(speed, run_speed, run_anim_speed)
	if not force and kind == _current_kind:
		return
	_current_kind = kind
	var length := _anim.get_animation(clip).length
	var start := 0.0
	match kind:
		KIND_ATTACK:
			var atk := get_attack()
			start = clampf(atk.clip_start, 0.0, maxf(0.0, length - 0.1))
			_anim.speed_scale = fit_speed(length - start, atk.total_time())
		KIND_HURT:
			_anim.speed_scale = fit_speed(length, _stun_for)
		KIND_WALK, KIND_RUN:
			pass   # already set above
		_:
			_anim.speed_scale = 1.0
	_anim.play(clip, ANIM_BLEND)
	if start > 0.0:
		_anim.seek(start, true)


## Plays the death and returns the seconds until the body is on the floor.
func _play_death() -> float:
	if _model_root == null:
		return 0.0   # placeholder: no animation, as before
	if _anim and _anim.is_inside_tree() and _anim.has_animation(anim_death):
		var length := _anim.get_animation(anim_death).length
		var start := clampf(death_clip_start, 0.0, maxf(0.0, length - 0.05))
		var land := death_land_at if death_land_at > start and death_land_at <= length else length
		var speed := fit_speed(land - start, death_fall_time)
		_current_kind = KIND_DEATH
		_anim.speed_scale = speed
		_anim.play(anim_death, ANIM_BLEND)
		if start > 0.0:
			_anim.seek(start, true)
		var land_in := (land - start) / speed
		if is_inside_tree():
			get_tree().create_timer(land_in, false).timeout.connect(_on_clip_landed)
		return land_in
	var holder := get_node_or_null(^"Model") as Node3D
	if holder == null or not is_inside_tree():
		return 0.0
	# No death clip: a staged collapse. The stagger clip (if any) bends the body while the holder
	# buckles forward and twists, then it topples backwards, bounces once and raises dust.
	if _anim and _anim.is_inside_tree() and _anim.has_animation(death_stagger_clip):
		_current_kind = KIND_DEATH
		_anim.speed_scale = DEATH_STAGGER_SPEED
		_anim.play(death_stagger_clip, ANIM_BLEND)
	var twist := DEATH_TWIST * _orbit_sign
	var y0 := holder.position.y
	var tween := create_tween()
	tween.tween_property(holder, "rotation", Vector3(-DEATH_BUCKLE, holder.rotation.y + twist, 0.0), DEATH_BUCKLE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(holder, "rotation:x", PI * 0.5, DEATH_FALL_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(holder, "position:y", y0 - DEATH_SINK, DEATH_FALL_TIME)
	tween.tween_callback(_on_death_landed)
	tween.tween_property(holder, "rotation:x", PI * 0.5 - DEATH_BOUNCE, DEATH_BOUNCE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(holder, "rotation:x", PI * 0.5, DEATH_BOUNCE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	return DEATH_BUCKLE_TIME + DEATH_FALL_TIME


## A death clip reached death_land_at: dust under the body (the clip keeps settling on its own).
func _on_clip_landed() -> void:
	if is_inside_tree():
		ImpactFx.dust(get_tree(), global_position + Vector3.UP * 0.1, DEATH_DUST_SIZE)


## The body hits the floor: dust where the torso lands and the pose freezes.
func _on_death_landed() -> void:
	if not is_inside_tree():
		return
	if _anim and _anim.is_inside_tree():
		_anim.speed_scale = 0.0
	var back := global_basis.z * DEATH_DUST_OFFSET   # it falls backwards (+Z)
	ImpactFx.dust(get_tree(), global_position + back, DEATH_DUST_SIZE)


## Can the footstep loop play? `has_voice`: this minion already owns one of the players.
static func step_voice_allowed(walking: bool, distance: float, voices_in_use: int, has_voice: bool) -> bool:
	if not walking or distance > STEP_HEARING_DISTANCE:
		return false
	return has_voice or voices_in_use < STEP_MAX_VOICES


func _update_steps() -> void:
	if sfx_step == null or sfx_spawn != null or not is_inside_tree():
		return
	var walking := (state == MinionState.CHASE or state == MinionState.CIRCLE) and is_on_floor() \
			and Vector2(velocity.x, velocity.z).length() > STEP_MIN_SPEED
	var distance := global_position.distance_to(_player.global_position) if _player else INF
	if step_voice_allowed(walking, distance, _step_voices_in_use, _step_player != null):
		if _step_player == null:
			_step_voices_in_use += 1
			_step_player = AudioStreamPlayer3D.new()
			_step_player.name = "StepSound"
			_step_player.stream = sfx_step
			_step_player.bus = &"SFX"
			_step_player.max_distance = STEP_HEARING_DISTANCE
			_step_player.unit_size = 4.0
			_step_player.volume_db = STEP_VOLUME_DB
			add_child(_step_player)
			_step_player.play(randf() * maxf(sfx_step.get_length() - 0.1, 0.0))   # out of phase with the others
		elif not _step_player.playing:
			_step_player.play()
	else:
		_stop_steps()


func _stop_steps() -> void:
	if _step_player == null:
		return
	_step_voices_in_use = maxi(0, _step_voices_in_use - 1)
	_step_player.queue_free()
	_step_player = null


func _exit_tree() -> void:
	_stop_steps()


func _play_sfx(stream: AudioStream) -> void:
	if stream == null or not is_inside_tree():
		return
	# By path: tests run without autoloads.
	var audio := get_node_or_null(^"/root/AudioManager")
	if audio and audio.has_method(&"play_sfx_3d"):
		audio.play_sfx_3d(stream, global_position)
