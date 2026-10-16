class_name Player
extends CharacterBody3D
## Kaelen. States: MOVE (walk relative to the camera, gravity, smooth turning), ROLL (roll with
## i-frames and stamina cost), ATTACK (3-hit combo with the greatsword; hyper armor: a hit does not
## interrupt it and does less damage), HURT (stunned when taking damage) and DEAD (no control;
## respawn is handled by GameState, Task 10). Every hit taken grants HURT_IFRAMES of invulnerability.

enum State { MOVE, ROLL, ATTACK, HURT, DEAD }

const WALK_SPEED := 5.0          # m/s (Task 3)
const ACCELERATION := 30.0       # m/s² when starting to move
const DECELERATION := 40.0       # m/s² when slowing down
const TURN_SPEED := 12.0         # turning speed toward the direction of movement
const MAX_STEP := 0.35           # highest step she climbs by herself (map steps are 0.25 m)
const STEP_PROBE := 0.2          # how far ahead it looks for the step's footprint
const ROLL_DURATION := 0.6
const ROLL_IFRAME_START := 0.05
const ROLL_IFRAME_END := 0.40
const ROLL_COST := 25.0
const ROLL_SPEED := 7.0          # constant m/s during the whole roll

# --- Combo (spec §4) ---
const COMBO_DAMAGE: Array[int] = [20, 20, 36]
const ATTACK_COST := 20.0
## When each hit's damage window closes, there are COMBO_WINDOW s to chain the next one;
## after that window the hit ends and it returns to MOVE (the tail of the clip is cut).
const COMBO_WINDOW := 0.4
## Clip of each hit. attack_2 is a long Mixamo combo (3.3 s, three slashes): only its first
## upward slash is used and the hit is cut when the combo window closes (≈ 1.32 s of the clip),
## before the second slash begins (≈ 1.38 s).
const ATTACK_ANIMS: Array[StringName] = [&"attack_1", &"attack_2", &"attack_3"]
## Each hit starts its clip at ATTACK_CLIP_START (clip seconds, start_offset of the AnimationTree
## node) and plays it at ATTACK_ANIM_SPEED, so game time = (clip time − start) / speed. The slow
## anticipation of attack_1 (guard pose, clip 0–0.35 s) and the loop of attack_3 around Kaelen's
## back (clip 0–0.70 s) are skipped instead of speeding the clips up a lot: hitting that early
## without skipping would need ×2.3 and ×2.75, and the slashes would look absurd.
const ATTACK_CLIP_START: Array[float] = [0.35, 0.0, 0.70]
const ATTACK_ANIM_SPEED: Array[float] = [1.4, 1.45, 1.2]
## Damage windows in CLIP seconds, measured by sweeping the sword hitbox against a dummy 1.5 m away
## (Hurtbox capsule r 0.4) at every angle around Kaelen (model space, + = +X):
## - attack_1: horizontal slash, +120° → −25° (clip 0.80–1.03 s).
## - attack_2: first upward slash in front of Kaelen, −120° → +25° (clip 0.53–0.74 s).
## - attack_3: final downward strike, −35° → +65° (clip 1.10–1.27 s).
const CLIP_HIT_START: Array[float] = [0.80, 0.53, 1.10]
const CLIP_HIT_END: Array[float] = [1.03, 0.74, 1.27]
## The same windows in game seconds from the start of each hit (by time, not by animation markers):
## ≈ 0.32–0.49, 0.37–0.51 and 0.33–0.48 s.
const HIT_START: Array[float] = [
	(CLIP_HIT_START[0] - ATTACK_CLIP_START[0]) / ATTACK_ANIM_SPEED[0],
	(CLIP_HIT_START[1] - ATTACK_CLIP_START[1]) / ATTACK_ANIM_SPEED[1],
	(CLIP_HIT_START[2] - ATTACK_CLIP_START[2]) / ATTACK_ANIM_SPEED[2],
]
const HIT_END: Array[float] = [
	(CLIP_HIT_END[0] - ATTACK_CLIP_START[0]) / ATTACK_ANIM_SPEED[0],
	(CLIP_HIT_END[1] - ATTACK_CLIP_START[1]) / ATTACK_ANIM_SPEED[1],
	(CLIP_HIT_END[2] - ATTACK_CLIP_START[2]) / ATTACK_ANIM_SPEED[2],
]
## The slashes do not pass exactly through the front (see the sweeps above). When turning toward the
## target this offset is added so the target is hit in the middle of the sweep (the target ends up
## at +30°, −35° and +5° of the model).
const ATTACK_AIM_OFFSET: Array[float] = [deg_to_rad(-30.0), deg_to_rad(35.0), deg_to_rad(-5.0)]

const HURT_DURATION := 0.4
## After any hit that does not kill her (also in ATTACK) she is invulnerable for this long, counted
## from the hit; HURT ends earlier (HURT_DURATION) and she can act while still invulnerable.
const HURT_IFRAMES := 1.0
## Meanwhile the model blinks: it toggles its visibility every HURT_BLINK_INTERVAL s.
const HURT_BLINK_INTERVAL := 0.08
## Hyper armor: in ATTACK a hit does not interrupt the slash (no HURT) and only this fraction of its
## damage is taken (multiplier of Kaelen's Hurtbox while attacking).
const ATTACK_DAMAGE_TAKEN_MULT := 0.5
## Orders (roll, attack) pressed while they cannot be executed are kept for this long.
const BUFFER_TIME := 0.2

# --- Audio ---
## Metros recorridos entre dos pasos (la muestra de carrera dura 0,5 s: a 5 m/s suena cada ~0,4 s).
const FOOTSTEP_STRIDE := 2.0
## Por debajo de esta velocidad horizontal (m/s) no hay pasos.
const FOOTSTEP_MIN_SPEED := 0.5
const FOOTSTEP_VOLUME_DB := -4.0

# Ground speed at which each clip looks right without sliding (measured by eye with captures; see
# docs/asset-status.md). Above RUN_ANIM_SPEED the `run` clip is sped up.
const WALK_ANIM_SPEED := 1.4
const RUN_ANIM_SPEED := 4.2

# Action states of the AnimationTree (besides "locomotion").
const ACTION_STATES: Array[StringName] = [&"roll", &"attack_1", &"attack_2", &"attack_3", &"hurt", &"death"]
# States whose clip is adjusted with a TimeScale (parameters/<state>/speed/scale).
const SCALED_STATES: Array[StringName] = [&"roll", &"attack_1", &"attack_2", &"attack_3", &"hurt"]

## Sonido del golpe de espada al empezar cada ataque (assign a randomizer to vary it).
@export var sfx_swing: AudioStream
## Sonido de los pasos al correr; lo asigna el nivel (level_gameplay.gd: piedra en arenas, tierra fuera).
@export var footstep_stream: AudioStream
## Sonidos de Kaelen: rodar, recibir un golpe, morir (cae al suelo) y quedarse sin estamina.
@export var sfx_roll: AudioStream
@export var sfx_hurt: AudioStream
@export var sfx_death: AudioStream
@export var sfx_tired: AudioStream

var state: State = State.MOVE
## If nobody assigned them before, they are looked up in _ready (children "Health", "Stamina" and "Hurtbox"). Tests
## assign them by hand without putting Kaelen in the tree and call _connect_components().
var health: Health
var stamina: Stamina
var hurtbox: Hurtbox
## Current combo hit (0, 1, 2, 3…; damage and clip use index % 3).
var combo_index := 0
## How many times she died (Events.player_died is emitted only the first time).
var death_count := 0

@onready var _model: Node3D = $Model
@onready var _camera_rig: CameraRig = $CameraRig
@onready var _lock_on: LockOn = get_node_or_null(^"LockOn") as LockOn
@onready var _sword_hitbox: Hitbox = get_node_or_null(^"SwordHitbox") as Hitbox
@onready var _sword_marker: Node3D = get_node_or_null(^"Model/Armature/Skeleton3D/RightHand/SwordGrip/SwordHitboxMarker") as Node3D
var _anim_tree: AnimationTree
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _roll_time := 0.0
var _roll_dir := Vector3.ZERO
# Sources of invulnerability: they combine and none of them turns off the others (Review focus 4).
var _iframes := false   # roll window
var _hurt_iframes_left := 0.0   # after taking a hit (HURT_IFRAMES)
var _victory := false   # after Events.boss_defeated
var _god := false       # debug (action "debug_god", F6)
var _cutscene := false  # scripted sequence (set_cutscene): no control, invulnerable
# Hyper armor: the Hurtbox's multiplier is scaled while attacking and restored afterwards.
var _armor_on := false
var _base_damage_multiplier := 1.0

var _footstep_distance := 0.0
var _attack_time := 0.0
var _hitbox_on := false
var _hurt_time := 0.0
var _last_hp := -1
var _last_stamina := 0.0
var _attack_pressed := false   # from _unhandled_input: the click that recaptures the mouse does not attack
var _buffered_action: StringName = &""
# Shove (Boss repel): outward velocity that fades linearly to 0 over _shove_total s, inside HURT.
var _shove_velocity := Vector3.ZERO
var _shove_total := 0.0
var _shove_left := 0.0
var _buffer_left := 0.0


func _ready() -> void:
	add_to_group("player")
	if health == null:
		health = get_node_or_null(^"Health") as Health
	if stamina == null:
		stamina = get_node_or_null(^"Stamina") as Stamina
	if hurtbox == null:
		hurtbox = get_node_or_null(^"Hurtbox") as Hurtbox
	# Maximum health according to the level (GameState may not exist in tests run with -s).
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state and health:
		health.reset(game_state.get_player_max_hp())
	_connect_components()
	# Events may not exist (tests run with -s), so it is looked up by path.
	var events := _events()
	if events:
		events.boss_defeated.connect(_on_boss_defeated)
	_build_animation_tree()


## Connects the Health signals. Separate from _ready so tests can call it without a tree.
func _connect_components() -> void:
	if health == null:
		return
	_last_hp = health.current
	if not health.changed.is_connected(_on_health_changed):
		health.changed.connect(_on_health_changed)
	if not health.died.is_connected(_on_died):
		health.died.connect(_on_died)
	if stamina and not stamina.changed.is_connected(_on_stamina_changed):
		_last_stamina = stamina.current
		stamina.changed.connect(_on_stamina_changed)


func _events() -> Node:
	return get_node_or_null(^"/root/Events") if is_inside_tree() else null


# The attack is read as an event and not with Input.is_action_just_pressed: CameraRig (a child, receives the
# event first) marks as handled the click that recaptures the mouse, so it does not count as a hit.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		_attack_pressed = true


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if Input.is_action_just_pressed("debug_god"):
		_god = not _god
		print("debug_god: ", _god)

	if _cutscene:
		_attack_pressed = false
		_stand_still()
		_tick_hurt_iframes(delta)
		_update_invulnerability()
		_follow_sword()
		_update_animation(0.0)
		return

	var want_roll := false
	var want_attack := false
	if state != State.DEAD:
		if Input.is_action_just_pressed("lock_on") and _lock_on:
			_lock_on.toggle()
		want_roll = Input.is_action_just_pressed("roll")
		want_attack = _attack_pressed
	_attack_pressed = false

	match state:
		State.MOVE:
			_tick_buffer(delta)
			if want_roll and try_roll():
				_roll_step(delta)
			elif want_attack and try_attack():
				_stand_still()
			else:
				_move_step(delta)
		State.ROLL:
			_tick_buffer(delta)
			_buffer_input(want_roll, want_attack)
			_roll_step(delta)
		State.ATTACK:
			# Attacking inside the combo window chains; otherwise it is stored in the buffer.
			if want_attack and not try_attack():
				buffer_action(&"attack")
			if want_roll:
				buffer_action(&"roll")
			_stand_still()
			if state == State.ATTACK:
				_advance_attack(delta)   # also counts down the buffer
		State.HURT:
			_tick_buffer(delta)
			_buffer_input(want_roll, want_attack)
			_shove_step(delta)
			_advance_hurt(delta)
		State.DEAD:
			_stand_still()
	_tick_hurt_iframes(delta)
	_update_invulnerability()
	_follow_sword()
	var ground_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	_tick_footsteps(delta, ground_speed)
	_update_animation(ground_speed)


# --- Audio ---

## Distancia acumulada tras avanzar `delta` s a `speed` m/s. Por debajo de FOOTSTEP_MIN_SPEED o si
## no `walking` (rodando, atacando, en el aire, cinemática) se reinicia.
static func footstep_progress(accumulated: float, speed: float, delta: float, walking: bool) -> float:
	if not walking or speed < FOOTSTEP_MIN_SPEED:
		return 0.0
	return accumulated + speed * delta


## true si la distancia acumulada completa una zancada.
static func footstep_due(accumulated: float) -> bool:
	return accumulated >= FOOTSTEP_STRIDE


## Pasos sincronizados con la velocidad real; solo en MOVE y con los pies en el suelo.
func _tick_footsteps(delta: float, ground_speed: float) -> void:
	var walking := state == State.MOVE and is_on_floor() and not _cutscene
	_footstep_distance = footstep_progress(_footstep_distance, ground_speed, delta, walking)
	if footstep_due(_footstep_distance):
		_footstep_distance -= FOOTSTEP_STRIDE
		_play_sfx(footstep_stream, FOOTSTEP_VOLUME_DB)


## 3D sound at Kaelen. By path: tests run with -s, without autoloads.
func _play_sfx(stream: AudioStream, volume_db := 0.0) -> void:
	if stream == null or not is_inside_tree():
		return
	var audio := get_node_or_null(^"/root/AudioManager")
	if audio:
		audio.play_sfx_3d(stream, global_position, 0.1, volume_db)


func _buffer_input(want_roll: bool, want_attack: bool) -> void:
	if want_roll:
		buffer_action(&"roll")
	elif want_attack:
		buffer_action(&"attack")


func _stand_still() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()


# The greatsword hitbox is a direct child of Kaelen (under the SwordGrip scaled ×577 the collision shape
# would be distorted): every frame it copies the position and rotation, without scale, of the blade marker.
func _follow_sword() -> void:
	if _sword_hitbox and _sword_marker:
		_sword_hitbox.global_transform = Transform3D(_sword_marker.global_basis.orthonormalized(), _sword_marker.global_position)


## Input direction relative to the camera (length ≤ 1; zero without input).
func _input_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input == Vector2.ZERO:
		return Vector3.ZERO
	# Relative to the camera: only its horizontal rotation matters.
	var yaw := _camera_rig.yaw if _camera_rig else 0.0
	var dir := Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)
	return dir.normalized() * minf(input.length(), 1.0)


func _move_step(delta: float) -> void:
	var dir := _input_direction()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var goal := dir * WALK_SPEED
	var rate := ACCELERATION if goal.length() > horizontal.length() else DECELERATION
	horizontal = horizontal.move_toward(goal, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	var was_on_floor := is_on_floor()
	move_and_slide()
	if was_on_floor and is_on_wall() and dir != Vector3.ZERO:
		_try_step_up(dir * WALK_SPEED * delta)

	if dir != Vector3.ZERO:
		# The Mixamo model faces +Z: it is rotated so its front points toward `dir`.
		var target_yaw := atan2(dir.x, dir.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, minf(1.0, TURN_SPEED * delta))


# CharacterBody3D does not climb steps by itself: if it hits something up to MAX_STEP high, it tries to
# raise itself, move forward a little and drop down until it touches the step; if there is support, it rises to that height and
# the next move_and_slide makes it advance.
func _try_step_up(motion: Vector3) -> void:
	var probe := motion.normalized() * STEP_PROBE
	var from := global_transform
	if test_move(from, Vector3.UP * MAX_STEP):
		return   # ceiling above
	var raised := from.translated(Vector3.UP * MAX_STEP)
	if test_move(raised, probe):
		return   # still a wall: it is not a step
	var col := KinematicCollision3D.new()
	if not test_move(raised.translated(probe), Vector3.DOWN * MAX_STEP, col):
		return   # no floor to stand on
	var rise := MAX_STEP + col.get_travel().y
	if rise <= 0.01:
		return
	global_position.y += rise
	velocity.y = 0.0


# --- Roll -------------------------------------------------------------------------------------

## Roll invulnerability window: [ROLL_IFRAME_START, ROLL_IFRAME_END) seconds.
static func iframes_active_at(t: float) -> bool:
	return t >= ROLL_IFRAME_START and t < ROLL_IFRAME_END


## Starts a roll if she is in MOVE and has stamina. Direction: the input relative to the
## camera or, without input, the model's facing.
func try_roll() -> bool:
	if state != State.MOVE or stamina == null or not stamina.try_spend(ROLL_COST):
		return false
	var dir := _input_direction()
	if dir == Vector3.ZERO:
		dir = get_facing()
	dir.y = 0.0
	_roll_dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.BACK
	_roll_time = 0.0
	state = State.ROLL
	if _model:
		_model.rotation.y = atan2(_roll_dir.x, _roll_dir.z)
	_play_action(&"roll")
	_play_sfx(sfx_roll)
	if is_inside_tree():
		ImpactFx.dust(get_tree(), global_position + Vector3.UP * 0.1, 0.5)
	return true


func _roll_step(delta: float) -> void:
	var motion := _roll_dir * ROLL_SPEED
	velocity.x = motion.x
	velocity.z = motion.z
	var was_on_floor := is_on_floor()
	move_and_slide()
	if was_on_floor and is_on_wall():
		_try_step_up(motion * delta)
	_advance_roll(delta)


## Advances the roll clock; when ROLL_DURATION is reached it returns to MOVE, stopped dead, and runs
## the stored order, if there is one.
func _advance_roll(delta: float) -> void:
	_roll_time += delta
	_iframes = iframes_active_at(_roll_time)
	if _roll_time >= ROLL_DURATION - 0.0001:
		state = State.MOVE
		_iframes = false
		_roll_time = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		_update_invulnerability()
		_consume_buffer()
		return
	_update_invulnerability()


# --- Combo attack -----------------------------------------------------------------------------

static func combo_damage(i: int) -> int:
	return COMBO_DAMAGE[posmod(i, COMBO_DAMAGE.size())]


func _in_combo_window() -> bool:
	return state == State.ATTACK and _attack_time >= HIT_END[combo_index % 3]


## Starts a hit from MOVE, or chains the next one inside the window after the previous one.
## Spends ATTACK_COST of stamina.
func try_attack() -> bool:
	var chaining := _in_combo_window()
	if not (state == State.MOVE or chaining):
		return false
	if stamina == null or not stamina.try_spend(ATTACK_COST):
		return false
	combo_index = combo_index + 1 if chaining else 0
	_set_hitbox_active(false)
	_attack_time = 0.0
	state = State.ATTACK
	_set_armor(true)
	_face_attack_direction()
	var hit := combo_index % 3
	if _anim_tree:
		_anim_tree.set(StringName("parameters/%s/speed/scale" % ATTACK_ANIMS[hit]), ATTACK_ANIM_SPEED[hit])
	_play_action(ATTACK_ANIMS[hit])
	_play_sfx(sfx_swing)
	return true


## At the start of each hit Kaelen turns toward the locked target; without a target, toward the input (with the
## slash offset). Without a target or input she keeps her facing.
func _face_attack_direction() -> void:
	if _model == null or not is_inside_tree():
		return
	var dir := Vector3.ZERO
	if _lock_on and is_instance_valid(_lock_on.target):
		dir = _lock_on.target.global_position - global_position
	else:
		dir = _input_direction()
	dir.y = 0.0
	if dir.length_squared() > 0.0001:
		_model.rotation.y = atan2(dir.x, dir.z) + ATTACK_AIM_OFFSET[combo_index % 3]


## Advances the hit clock: activates the hitbox only inside its damage window, chains a buffered
## attack when the combo window opens and returns to MOVE when that window closes.
func _advance_attack(delta: float) -> void:
	_attack_time += delta
	_tick_buffer(delta)
	var hit := combo_index % 3
	_set_hitbox_active(_attack_time >= HIT_START[hit] and _attack_time < HIT_END[hit])
	if _attack_time >= HIT_END[hit] and _buffered_action == &"attack":
		_clear_buffer()
		if try_attack():
			return
	if _attack_time >= HIT_END[hit] + COMBO_WINDOW:
		_end_attack()
		_play_action(&"locomotion")
		_consume_buffer()


func _end_attack() -> void:
	_set_hitbox_active(false)
	_set_armor(false)
	_attack_time = 0.0
	combo_index = 0
	if state == State.ATTACK:
		state = State.MOVE


## Hyper armor: scales the damage that reaches Health through the Hurtbox while attacking
## (scripts/combat is not touched: only its damage_multiplier is changed at runtime).
func _set_armor(on: bool) -> void:
	if on == _armor_on:
		return
	_armor_on = on
	if hurtbox == null:
		return
	if on:
		_base_damage_multiplier = hurtbox.damage_multiplier
		hurtbox.damage_multiplier = _base_damage_multiplier * ATTACK_DAMAGE_TAKEN_MULT
	else:
		hurtbox.damage_multiplier = _base_damage_multiplier


func _set_hitbox_active(on: bool) -> void:
	if on == _hitbox_on:
		return
	_hitbox_on = on
	if _sword_hitbox == null:
		return
	if on:
		_sword_hitbox.damage = combo_damage(combo_index)
		_sword_hitbox.activate()
	else:
		_sword_hitbox.deactivate()


# --- Input buffer -----------------------------------------------------------------------------

## Stores an order (&"roll" or &"attack") for BUFFER_TIME; the latest one replaces the previous one.
func buffer_action(action: StringName) -> void:
	_buffered_action = action
	_buffer_left = BUFFER_TIME


func _tick_buffer(delta: float) -> void:
	if _buffered_action == &"":
		return
	_buffer_left -= delta
	if _buffer_left <= 0.0:
		_clear_buffer()


func _clear_buffer() -> void:
	_buffered_action = &""
	_buffer_left = 0.0


## Runs the stored order if it is still valid (called when returning to MOVE).
func _consume_buffer() -> bool:
	var action := _buffered_action
	_clear_buffer()
	match action:
		&"roll":
			return try_roll()
		&"attack":
			return try_attack()
	return false


# --- Damage and death -------------------------------------------------------------------------

# Health.changed is used (not Hurtbox.hurt, which is emitted even when the hit does no damage).
func _on_health_changed(current: int, max_value: int) -> void:
	var previous := _last_hp
	_last_hp = current
	if previous < 0 or current >= previous:
		return   # healing or reset
	var events := _events()
	if events:
		events.player_damaged.emit(previous - current, current, max_value)
	if current <= 0 or state == State.DEAD:
		return
	_play_sfx(sfx_hurt)
	_start_hurt_iframes()
	if state != State.ATTACK:   # hyper armor: the slash goes on, without the hurt animation
		_enter_hurt()


## True when the stamina has just run out (it was above 0 and is now 0).
static func stamina_ran_out(previous: float, current: float) -> bool:
	return previous > 0.0 and current <= 0.0


func _on_stamina_changed(current: float, _max_value: float) -> void:
	var previous := _last_stamina
	_last_stamina = current
	if stamina_ran_out(previous, current) and state != State.DEAD:
		_play_sfx(sfx_tired)


## HURT interrupts the roll (an attack is not interrupted by damage: hyper armor).
func _enter_hurt() -> void:
	_end_attack()
	_shove_left = 0.0
	_roll_time = 0.0
	_iframes = false
	_hurt_time = 0.0
	state = State.HURT
	_update_invulnerability()
	_play_action(&"hurt")


func _advance_hurt(delta: float) -> void:
	_hurt_time += delta
	if _hurt_time >= HURT_DURATION - 0.0001:
		_hurt_time = 0.0
		state = State.MOVE
		_consume_buffer()


# --- Shove (boss repel) ------------------------------------------------------------------------

## Pushes Kaelen with horizontal `push` (m/s) fading to 0 over `duration` s, without damage. She
## stays in HURT (no control) until the push ends (at least HURT_DURATION). Interrupts attacks too
## (hyper armor stops damage, not a shove). The roll's i-frames dodge it, as do death, cutscenes and
## victory. `lift` (m/s) adds an upward hop. Returns true if it was applied.
func apply_shove(push: Vector3, duration: float, lift := 0.0) -> bool:
	if state == State.DEAD or _iframes or _cutscene or _victory or duration <= 0.0:
		return false
	push.y = 0.0
	if push.length_squared() < 0.0001:
		return false
	_enter_hurt()
	_hurt_time = minf(0.0, HURT_DURATION - duration)   # HURT lasts as long as the push
	_shove_velocity = push
	_shove_total = duration
	_shove_left = duration
	velocity.x = push.x
	velocity.z = push.z
	if lift > 0.0:
		velocity.y = lift   # small hop: the shove reads as an impact
	return true


## Shove speed with `left` of `total` seconds remaining: linear fade from `initial` to 0.
static func shove_velocity_at(initial: Vector3, total: float, left: float) -> Vector3:
	if total <= 0.0 or left <= 0.0:
		return Vector3.ZERO
	return initial * clampf(left / total, 0.0, 1.0)


func _shove_step(delta: float) -> void:
	if _shove_left <= 0.0:
		_stand_still()
		return
	var v := shove_velocity_at(_shove_velocity, _shove_total, _shove_left)
	velocity.x = v.x
	velocity.z = v.z
	_shove_left = maxf(0.0, _shove_left - delta)
	move_and_slide()


func _start_hurt_iframes() -> void:
	_hurt_iframes_left = HURT_IFRAMES
	_update_invulnerability()
	_update_blink()


## Counts down the post-hit invulnerability (every frame, in any state) and makes the model blink.
func _tick_hurt_iframes(delta: float) -> void:
	if _hurt_iframes_left <= 0.0:
		return
	_hurt_iframes_left = maxf(0.0, _hurt_iframes_left - delta)
	_update_invulnerability()
	_update_blink()


## Hidden during the odd HURT_BLINK_INTERVAL slices of the i-frames; visible otherwise.
func _update_blink() -> void:
	if _model == null:
		return
	if _hurt_iframes_left <= 0.0:
		_model.visible = true
		return
	var elapsed := HURT_IFRAMES - _hurt_iframes_left
	_model.visible = int(elapsed / HURT_BLINK_INTERVAL) % 2 == 1


func _on_died() -> void:
	if state == State.DEAD:
		return
	_end_attack()
	_clear_buffer()
	_iframes = false
	_hurt_iframes_left = 0.0
	_update_blink()
	state = State.DEAD
	_update_invulnerability()
	death_count += 1
	if _lock_on:
		_lock_on.target = null
	_play_action(&"death")
	_play_sfx(sfx_death)
	if death_count == 1:
		var events := _events()
		if events:
			events.player_died.emit()


func _on_boss_defeated(_boss: Node3D) -> void:
	_victory = true
	_update_invulnerability()


func is_invulnerable() -> bool:
	return _iframes or _hurt_iframes_left > 0.0 or _victory or _god or _cutscene


## Hands Kaelen over to a scripted sequence (the ending) or gives control back. While on: movement,
## roll, attack and lock-on are ignored, she stands in idle and cannot be hurt. Turning it on cancels
## any roll / attack / hurt in progress and the target lock.
func set_cutscene(on: bool) -> void:
	if on == _cutscene:
		return
	_cutscene = on
	if on:
		if state != State.DEAD:
			_end_attack()
			_roll_time = 0.0
			_hurt_time = 0.0
			state = State.MOVE
		_clear_buffer()
		_iframes = false
		_hurt_iframes_left = 0.0
		_update_blink()
		velocity.x = 0.0
		velocity.z = 0.0
		if _lock_on and _lock_on.target != null:
			_lock_on.toggle()   # with a target, toggle() releases it
		if state != State.DEAD:
			_play_action(&"locomotion")
	_update_invulnerability()


func is_cutscene() -> bool:
	return _cutscene


## Turns the model toward a world point (horizontal only). The Mixamo model faces +Z.
func face_point(point: Vector3) -> void:
	if _model == null:
		return
	var dir := point - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.0001:
		_model.rotation.y = atan2(dir.x, dir.z)


func _update_invulnerability() -> void:
	if health:
		health.invulnerable = is_invulnerable()


func get_facing() -> Vector3:
	if _model == null:
		return basis.z   # outside the tree (tests)
	return _model.global_basis.z


## Current locked target (or null). Used by the camera and the HUD.
func get_lock_target() -> Node3D:
	if _lock_on and is_instance_valid(_lock_on.target):
		return _lock_on.target
	return null


## Places Kaelen at a point (Marker3D) in the level and lines the camera up behind her.
func spawn_at(marker: Node3D) -> void:
	global_position = marker.global_position
	velocity = Vector3.ZERO
	var forward := -marker.global_basis.z   # Marker3D nodes face -Z
	_model.rotation.y = atan2(forward.x, forward.z)
	_camera_rig.yaw = atan2(-forward.x, -forward.z)
	_camera_rig.rotate_view(0.0, 0.0)
	_camera_rig.global_position = global_position + Vector3.UP * _camera_rig.pivot_height


# --- Animation --------------------------------------------------------------------------------
# Root: AnimationNodeStateMachine.
# - "locomotion": BlendTree with a BlendSpace1D idle/walk/run based on speed and a TimeScale
#   that speeds up the clip when moving faster than it shows (prevents the feet from sliding).
# - roll, attack_1..3, hurt: BlendTree with the clip and a TimeScale ("speed"). roll and hurt are fitted
#   to ROLL_DURATION / HURT_DURATION; each hit uses ATTACK_ANIM_SPEED and starts its clip at
#   ATTACK_CLIP_START.
# - death: the clip only, no return.
# Transitions: locomotion → action and action → action are immediate (travel is used so there is a crossfade);
# roll and hurt return on their own when finished; hits return when the code asks for it,
# because they are cut when the combo window closes, before the end of the clip.

func _build_animation_tree() -> void:
	var player := _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var sm := AnimationNodeStateMachine.new()
	sm.add_node(&"locomotion", _build_locomotion(), Vector2(0, 0))
	for i in ACTION_STATES.size():
		var state_name := ACTION_STATES[i]
		var node: AnimationRootNode
		if state_name in ATTACK_ANIMS:
			var hit := ATTACK_ANIMS.find(state_name)
			node = _build_time_scaled_clip(state_name, ATTACK_CLIP_START[hit], _clip_length(player, state_name, 2.0))
		elif state_name in SCALED_STATES:
			node = _build_time_scaled_clip(state_name)
		else:
			var clip := AnimationNodeAnimation.new()
			clip.animation = state_name
			node = clip
		sm.add_node(state_name, node, Vector2(300, (i - 2) * 80))
		var go := AnimationNodeStateMachineTransition.new()
		go.xfade_time = 0.08
		sm.add_transition(&"locomotion", state_name, go)
		if state_name == &"death":
			continue
		var back := AnimationNodeStateMachineTransition.new()
		back.xfade_time = 0.15
		if state_name in ATTACK_ANIMS:
			back.xfade_time = 0.2   # requested with travel when the combo window closes
		else:
			back.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
			back.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
		sm.add_transition(state_name, &"locomotion", back)
	# Action → action (chaining hits, stored roll, interruption by damage or death).
	for from_name in ACTION_STATES:
		if from_name == &"death":
			continue
		for to_name in ACTION_STATES:
			if to_name == from_name:
				continue
			var t := AnimationNodeStateMachineTransition.new()
			t.xfade_time = 0.08
			sm.add_transition(from_name, to_name, t)
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition(&"Start", &"locomotion", start)

	_anim_tree = AnimationTree.new()
	_anim_tree.name = "AnimationTree"
	_anim_tree.tree_root = sm
	add_child(_anim_tree)
	_anim_tree.anim_player = _anim_tree.get_path_to(player)
	# The roll (~2.4 s) and hurt (~0.7 s) clips must fit their duration: factor based on their real length.
	_anim_tree.set(&"parameters/roll/speed/scale", _clip_length(player, &"roll", ROLL_DURATION) / ROLL_DURATION)
	_anim_tree.set(&"parameters/hurt/speed/scale", _clip_length(player, &"hurt", HURT_DURATION) / HURT_DURATION)
	for i in ATTACK_ANIMS.size():
		_anim_tree.set(StringName("parameters/%s/speed/scale" % ATTACK_ANIMS[i]), ATTACK_ANIM_SPEED[i])
	_anim_tree.active = true


func _clip_length(player: AnimationPlayer, clip: StringName, fallback: float) -> float:
	if player.has_animation(clip):
		return player.get_animation(clip).length
	push_warning("Kaelen: falta el clip '%s'" % clip)
	return fallback


## Switches to the action state with a crossfade; if it is already in it (e.g. another hit during HURT), it restarts it.
func _play_action(state_name: StringName) -> void:
	if _anim_tree == null:
		return
	var playback := _anim_tree.get(&"parameters/playback") as AnimationNodeStateMachinePlayback
	if playback.get_current_node() == state_name:
		playback.start(state_name)
	else:
		playback.travel(state_name)


func _build_locomotion() -> AnimationNodeBlendTree:
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	space.max_space = WALK_SPEED
	for p in [["idle", 0.0], ["walk", WALK_ANIM_SPEED], ["run", RUN_ANIM_SPEED]]:
		var clip := AnimationNodeAnimation.new()
		clip.animation = p[0]
		space.add_blend_point(clip, p[1], -1, p[0])
	var tree := AnimationNodeBlendTree.new()
	tree.add_node(&"locomotion", space)
	tree.add_node(&"speed", AnimationNodeTimeScale.new())
	tree.connect_node(&"speed", 0, &"locomotion")
	tree.connect_node(&"output", 0, &"speed")
	return tree


## BlendTree clip → TimeScale ("speed") → output; the factor is set in parameters/<state>/speed/scale.
## With start_offset > 0 the clip starts at that clip second (custom timeline of the node, up to
## the end of the clip without stretching it).
func _build_time_scaled_clip(clip_name: StringName, start_offset := 0.0, clip_length := 0.0) -> AnimationNodeBlendTree:
	var clip := AnimationNodeAnimation.new()
	clip.animation = clip_name
	if start_offset > 0.0:
		clip.use_custom_timeline = true
		clip.stretch_time_scale = false
		clip.start_offset = start_offset
		clip.timeline_length = clip_length - start_offset
	var tree := AnimationNodeBlendTree.new()
	tree.add_node(&"clip", clip)
	tree.add_node(&"speed", AnimationNodeTimeScale.new())
	tree.connect_node(&"speed", 0, &"clip")
	tree.connect_node(&"output", 0, &"speed")
	return tree


func _update_animation(speed: float) -> void:
	_anim_tree.set(&"parameters/locomotion/locomotion/blend_position", speed)
	var anim_scale := 1.0
	if speed > RUN_ANIM_SPEED:
		anim_scale = speed / RUN_ANIM_SPEED
	elif speed > 0.05 and speed < WALK_ANIM_SPEED:
		anim_scale = maxf(0.6, speed / WALK_ANIM_SPEED)
	_anim_tree.set(&"parameters/locomotion/speed/scale", anim_scale)
