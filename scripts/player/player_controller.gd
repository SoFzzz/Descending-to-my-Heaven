class_name Player
extends CharacterBody3D
## Kaelen. States: MOVE (walk relative to the camera, gravity, smooth turning), ROLL (roll with
## i-frames and stamina cost), ATTACK (3-hit combo with the greatsword; hyper armor: a hit does not
## interrupt it and does less damage, except in the follow-through of a finisher), HURT (stunned when
## taking damage) and DEAD (no control; respawn is handled by GameState, Task 10). Every hit taken
## grants HURT_IFRAMES of invulnerability. Two sub-states of MOVE: healing (see try_heal, a flask with
## HEAL_CHARGES uses per level) and the roll's recovery (see is_roll_recovering).

enum State { MOVE, ROLL, ATTACK, HURT, DEAD }

## Emitted when the number of flask uses changes (the HUD shows it).
signal heal_charges_changed(current: int, max_value: int)
## A scripted walk (scripted_walk) reached its last point.
signal scripted_walk_finished

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
## The roll plays roll_to_run (kaelen.glb, 1.43 s): a dive, a roll on the ground and a get-up into a
## run. Sampled pose by pose (Hips height): the head is lowest at clip 0.7 s, the hips at 0.9-1.0 s,
## and from 1.0 s she rises (hips 0.20 -> 0.82 m at 1.4 s). The clip is fitted so the travel
## (ROLL_DURATION) ends at ROLL_CLIP_RISE and the get-up is the recovery.
const ROLL_CLIP := &"roll_to_run"
const ROLL_CLIP_LENGTH := 1.4333   # checked against the real clip by test_player_roll
const ROLL_CLIP_RISE := 1.0
## Recovery after the travel (MOVE sub-state, ≈ 0.26 s: the get-up at the clip's speed). She can steer
## and attack (a roll attack), but another roll waits in the buffer until it ends (no roll spam).
const ROLL_RECOVERY := ROLL_DURATION * (ROLL_CLIP_LENGTH - ROLL_CLIP_RISE) / ROLL_CLIP_RISE

# --- Healing flask ---
## Uses per level (refilled on entering an arena and on retrying: the player scene is rebuilt).
const HEAL_CHARGES := 10
## Fraction of the level's max HP restored by one use (38 / 27 / 15 HP at 100 / 70 / 40 max HP).
const HEAL_RATIO := 0.38
## Seconds from pressing the button until the HP is restored (the use is spent only then).
const HEAL_DURATION := 0.9
## Walk speed multiplier while drinking.
const HEAL_MOVE_MULT := 0.35
const HEAL_GLOW_COLOR := Color(0.55, 1.0, 0.55)
const HEAL_GLOW_PEAK := 0.4
const HEAL_SFX_VOLUME_DB := -3.0

# --- Combo (spec §4) ---
const COMBO_DAMAGE: Array[int] = [20, 20, 36]
const ATTACK_COST := 20.0
## The 3rd hit (the finisher) closes the combo: nothing chains from it.
const COMBO_LENGTH := 3
## When the damage window of hits 1 and 2 closes, there are COMBO_WINDOW s to chain the next one (or
## the heavy attack as finisher); after that window the hit ends and it returns to MOVE (the tail of the
## clip is cut).
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
## The finisher plays its follow-through to the end of attack_3 (1.90 s in kaelen.glb, checked by
## test_player_combo): ≈ 0.53 s after its damage window, without hyper armor and without chaining.
const FINISHER_CLIP_END := 1.90
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
## Game second at which the finisher ends and returns to MOVE (1.0 s).
const FINISHER_END := (FINISHER_CLIP_END - ATTACK_CLIP_START[2]) / ATTACK_ANIM_SPEED[2]
## The slashes do not pass exactly through the front (see the sweeps above). When turning toward the
## target this offset is added so the target is hit in the middle of the sweep (the target ends up
## at +30°, −35° and +5° of the model).
const ATTACK_AIM_OFFSET: Array[float] = [deg_to_rad(-30.0), deg_to_rad(35.0), deg_to_rad(-5.0)]
## With a locked target each hit steps toward it for ATTACK_STEP_TIME s (at most ≈ 0.75 m), unless it
## is already within ATTACK_STEP_MIN m: strafing out of reach does not make the slash whiff.
const ATTACK_STEP_SPEED := 3.0
const ATTACK_STEP_TIME := 0.25
const ATTACK_STEP_MIN := 1.8

# --- Heavy attack (jump_attack clip): a leap forward that lands with a downward slam ---
const HEAVY_ANIM := &"jump_attack"
const HEAVY_DAMAGE := 45
const HEAVY_COST := 35.0
const HEAVY_ANIM_SPEED := 1.25
## Clip seconds (jump_attack, 2.2 s): the hips peak at ≈ 0.8 s; the blade stays behind her head until
## ≈ 1.25 s and slams down in front at ≈ 1.27-1.40 s (traced frame by frame in kaelen_moves_flow).
const HEAVY_CLIP_LEAP_START := 0.40
const HEAVY_CLIP_LEAP_END := 1.00
const HEAVY_CLIP_HIT_START := 1.15
const HEAVY_CLIP_HIT_END := 1.50
const HEAVY_CLIP_IMPACT := 1.28   # dust and camera shake
const HEAVY_CLIP_END := 1.85      # back to MOVE (the recovery crouch is cut)
const HEAVY_LEAP_SPEED := 4.2     # m/s while airborne: ≈ 2 m forward
const HEAVY_LEAP_STOP := 1.6      # m to a locked target at which the leap stops pushing
## The slam's arc enters from her right, crosses the front and ends low on her LEFT (traced: the blade
## bottoms out about 77 deg left of her facing). The model turns this much to her right at the start so
## the arc is centred on the target (re-traced at -55 deg: it crosses the target line at full reach and
## bottoms out about 25 deg left); the leap still goes straight at the target (_heavy_dir).
const HEAVY_AIM_OFFSET := deg_to_rad(-55.0)
## Hit-stop of Kaelen's blows: light on a normal slash, a bit more on the combo's 3rd hit and the slam.
const HIT_STOP_LIGHT := 0.035
const HIT_STOP_STRONG := 0.07
## The same marks in game seconds from the start of the heavy attack.
const HEAVY_LEAP_START := HEAVY_CLIP_LEAP_START / HEAVY_ANIM_SPEED
const HEAVY_LEAP_END := HEAVY_CLIP_LEAP_END / HEAVY_ANIM_SPEED
const HEAVY_HIT_START := HEAVY_CLIP_HIT_START / HEAVY_ANIM_SPEED
const HEAVY_HIT_END := HEAVY_CLIP_HIT_END / HEAVY_ANIM_SPEED
const HEAVY_IMPACT := HEAVY_CLIP_IMPACT / HEAVY_ANIM_SPEED
const HEAVY_END := HEAVY_CLIP_END / HEAVY_ANIM_SPEED

# --- Lock-on strafe ---
## With a locked target Kaelen keeps facing it and walks around it (strafe clips) at this speed.
const LOCK_MOVE_SPEED := 3.2
## Ground speed at which the strafe / walk_back clips look right (by eye; see AGENTS.md section 6).
const STRAFE_ANIM_SPEED := 2.0
## How fast the locomotion crossfades between free running and strafing (blend units per s).
const LOCK_BLEND_RATE := 6.0

const HURT_DURATION := 0.4
## After any hit that does not kill her (also in ATTACK) she is invulnerable for this long, counted
## from the hit; HURT ends earlier (HURT_DURATION) and she can act while still invulnerable.
const HURT_IFRAMES := 1.0
## Damage (as a fraction of max HP) from which a hit also shakes the camera.
const HEAVY_HIT_RATIO := 0.15
## Meanwhile the model blinks: it toggles its visibility every HURT_BLINK_INTERVAL s.
const HURT_BLINK_INTERVAL := 0.08
## Hyper armor: in ATTACK a hit does not interrupt the slash (no HURT) and only this fraction of its
## damage is taken (multiplier of Kaelen's Hurtbox while attacking). It drops when the damage window of
## a finisher (3rd hit, heavy attack) closes: trading blows is not free during its follow-through.
const ATTACK_DAMAGE_TAKEN_MULT := 0.5
## Orders (roll, attack) pressed while they cannot be executed are kept for this long.
const BUFFER_TIME := 0.2

# --- Audio ---
## Meters traveled between two footsteps (the run sample lasts 0.5 s: at 5 m/s it plays every ~0.4 s).
const FOOTSTEP_STRIDE := 2.0
## Below this horizontal speed (m/s) there are no footsteps.
const FOOTSTEP_MIN_SPEED := 0.5
const FOOTSTEP_VOLUME_DB := -4.0

# Ground speed at which each clip looks right without sliding (measured by eye with captures; see
# AGENTS.md, section 15). Above RUN_ANIM_SPEED the `run` clip is sped up.
const WALK_ANIM_SPEED := 1.4
const RUN_ANIM_SPEED := 4.2

# Action states of the AnimationTree (besides "locomotion").
const ACTION_STATES: Array[StringName] = [&"roll", &"attack_1", &"attack_2", &"attack_3", HEAVY_ANIM, &"hurt", &"death"]
# States whose clip is adjusted with a TimeScale (parameters/<state>/speed/scale).
const SCALED_STATES: Array[StringName] = [&"roll", &"attack_1", &"attack_2", &"attack_3", HEAVY_ANIM, &"hurt"]

## Sword swing sound when each attack starts (assign a randomizer to vary it).
@export var sfx_swing: AudioStream
## Footstep sound while running; assigned by the level (level_gameplay.gd: stone in arenas, dirt outside).
@export var footstep_stream: AudioStream
## Kaelen's sounds: rolling, taking a hit, dying (falling to the ground) and running out of stamina.
@export var sfx_roll: AudioStream
@export var sfx_hurt: AudioStream
@export var sfx_death: AudioStream
@export var sfx_tired: AudioStream
## Sound of drinking the flask (starts with the use; the HP arrives HEAL_DURATION later).
@export var sfx_heal: AudioStream

var state: State = State.MOVE
## If nobody assigned them before, they are looked up in _ready (children "Health", "Stamina" and "Hurtbox"). Tests
## assign them by hand without putting Kaelen in the tree and call _connect_components().
var health: Health
var stamina: Stamina
var hurtbox: Hurtbox
## Current combo hit (0, 1 or 2; 2 is the finisher).
var combo_index := 0
## How many times she died (Events.player_died is emitted only the first time).
var death_count := 0
## Flask uses left in this level.
var heal_charges := HEAL_CHARGES

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
## Speed of the standing idle clip (1 = normal). The ending slows it so Kaelen stands almost still.
var idle_anim_scale := 1.0
var _cutscene := false  # scripted sequence (set_cutscene): no control, invulnerable
# Hyper armor: the Hurtbox's multiplier is scaled while attacking and restored afterwards.
var _armor_on := false
var _base_damage_multiplier := 1.0

var _footstep_distance := 0.0
var _attack_time := 0.0
var _hitbox_on := false
var _hurt_time := 0.0
var _roll_recovery_left := 0.0   # > 0: getting up after a roll (MOVE sub-state)
var _last_hp := -1
var _last_stamina := 0.0
var _attack_pressed := false   # from _unhandled_input: the click that recaptures the mouse does not attack
var _buffered_action: StringName = &""
# Shove (Boss repel): outward velocity that fades linearly to 0 over _shove_total s, inside HURT.
var _shove_velocity := Vector3.ZERO
var _shove_total := 0.0
var _shove_left := 0.0
var _buffer_left := 0.0
var _heal_time := -1.0   # < 0: not drinking; otherwise seconds since the use started
var _heavy := false      # the ATTACK in progress is the heavy attack (jump_attack)
var _heavy_pressed := false
var _heavy_axis_down := false   # the heavy attack's trigger is past its deadzone
var _heavy_dir := Vector3.ZERO  # where the heavy attack leaps (the target, the input or her facing)
var _lock_blend := 0.0   # 0 = free locomotion, 1 = strafing around the locked target
var _walk_points: Array[Vector3] = []   # scripted walk in progress (cutscene)
var _walk_speed := 0.0
const WALK_ARRIVE := 0.25              # m to a point at which the scripted walk takes the next one


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
		if not events.boss_defeated.is_connected(_on_boss_defeated):
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
	elif event is InputEventJoypadMotion and InputMap.event_is_action(event, &"heavy_attack"):
		# A trigger (RT) sends a stream of motion events while it travels: only the press edge counts.
		var down := event.is_action_pressed(&"heavy_attack")
		if down and not _heavy_axis_down:
			_heavy_pressed = true
		_heavy_axis_down = down
	elif event.is_action_pressed("heavy_attack"):
		_heavy_pressed = true


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if Input.is_action_just_pressed("debug_god"):
		toggle_debug_god()

	if _cutscene:
		_attack_pressed = false
		_heavy_pressed = false
		if _walk_points.is_empty():
			_stand_still()
		else:
			_scripted_step(delta)
		_tick_hurt_iframes(delta)
		_update_invulnerability()
		_follow_sword()
		_update_animation(Vector3(velocity.x, 0.0, velocity.z).length())
		return

	var want_roll := false
	var want_attack := false
	var want_heal := false
	var want_heavy := false
	if state != State.DEAD:
		if Input.is_action_just_pressed("lock_on") and _lock_on:
			_lock_on.toggle()
		want_roll = Input.is_action_just_pressed("roll")
		want_attack = _attack_pressed
		want_heavy = _heavy_pressed
		want_heal = Input.is_action_just_pressed("heal")
	_attack_pressed = false
	_heavy_pressed = false

	match state:
		State.MOVE:
			_tick_buffer(delta)
			if is_roll_recovering():
				_recover_step(delta, want_roll, want_attack, want_heavy)
			elif want_roll and try_roll():
				_roll_step(delta)
			elif want_attack and try_attack():
				_stand_still()
			elif want_heavy and try_heavy_attack():
				_stand_still()
			else:
				if want_heal:
					try_heal()
				_move_step(delta)
				_advance_heal(delta)
		State.ROLL:
			_tick_buffer(delta)
			_buffer_input(want_roll, want_attack, want_heavy)
			_roll_step(delta)
		State.ATTACK:
			# Attacking inside the combo window chains; otherwise it is stored in the buffer.
			if want_attack and not try_attack():
				buffer_action(&"attack")
			if want_heavy and not try_heavy_attack():
				buffer_action(&"heavy")
			if want_roll:
				buffer_action(&"roll")
			_attack_motion()
			if state == State.ATTACK:
				_advance_attack(delta)   # also counts down the buffer
		State.HURT:
			_tick_buffer(delta)
			_buffer_input(want_roll, want_attack, want_heavy)
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

## Accumulated distance after advancing `delta` s at `speed` m/s. Below FOOTSTEP_MIN_SPEED or if
## not `walking` (rolling, attacking, airborne, cutscene) it resets.
static func footstep_progress(accumulated: float, speed: float, delta: float, walking: bool) -> float:
	if not walking or speed < FOOTSTEP_MIN_SPEED:
		return 0.0
	return accumulated + speed * delta


## true if the accumulated distance completes a stride.
static func footstep_due(accumulated: float) -> bool:
	return accumulated >= FOOTSTEP_STRIDE


## Footsteps synchronized with the real speed; only in MOVE and with the feet on the ground.
func _tick_footsteps(delta: float, ground_speed: float) -> void:
	var walking := state == State.MOVE and is_on_floor() and not _cutscene and not is_roll_recovering()
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


func _buffer_input(want_roll: bool, want_attack: bool, want_heavy := false) -> void:
	if want_roll:
		buffer_action(&"roll")
	elif want_attack:
		buffer_action(&"attack")
	elif want_heavy:
		buffer_action(&"heavy")


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
	var target := strafe_target()
	var top_speed := LOCK_MOVE_SPEED if target else WALK_SPEED
	var goal := dir * top_speed * (HEAL_MOVE_MULT if is_healing() else 1.0)
	var rate := ACCELERATION if goal.length() > horizontal.length() else DECELERATION
	horizontal = horizontal.move_toward(goal, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	var was_on_floor := is_on_floor()
	move_and_slide()
	if was_on_floor and is_on_wall() and dir != Vector3.ZERO:
		_try_step_up(dir * WALK_SPEED * delta)

	var face := dir
	if target:
		face = target.global_position - global_position   # strafe: keep facing the target
		face.y = 0.0
	if face.length_squared() > 0.0001:
		# The Mixamo model faces +Z: it is rotated so its front points toward `face`.
		var target_yaw := atan2(face.x, face.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, minf(1.0, TURN_SPEED * delta))


## Locked target Kaelen strafes around (only walking in MOVE, outside cutscenes), or null.
func strafe_target() -> Node3D:
	if state != State.MOVE or _cutscene:
		return null
	return get_lock_target()


## Velocity in the model's frame: x = to her right, y = forward (the model faces +Z, its right is −X).
func local_ground_velocity() -> Vector2:
	if _model == null:
		return Vector2.ZERO
	var b := _model.global_basis.orthonormalized()
	var v := Vector3(velocity.x, 0.0, velocity.z)
	return Vector2(-v.dot(b.x), v.dot(b.z))


## TimeScale of the strafe blend at local velocity `v` (see local_ground_velocity): forward uses the
## walk / run speeds; sideways and backwards, STRAFE_ANIM_SPEED. Only speeds up past each clip.
static func strafe_anim_scale(v: Vector2) -> float:
	var speed := v.length()
	if speed <= 0.05:
		return 1.0
	if v.y >= absf(v.x):
		return free_anim_scale(speed)
	return maxf(0.6, speed / STRAFE_ANIM_SPEED)


## TimeScale of the free locomotion at ground `speed` (prevents the feet from sliding).
static func free_anim_scale(speed: float) -> float:
	if speed > RUN_ANIM_SPEED:
		return speed / RUN_ANIM_SPEED
	if speed > 0.05 and speed < WALK_ANIM_SPEED:
		return maxf(0.6, speed / WALK_ANIM_SPEED)
	return 1.0


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


## Starts a roll if she is in MOVE (not getting up from the previous one) and has stamina.
## Direction: the input relative to the camera or, without input, the model's facing.
func try_roll() -> bool:
	if state != State.MOVE or is_roll_recovering() or stamina == null or not stamina.try_spend(ROLL_COST):
		return false
	var dir := _input_direction()
	if dir == Vector3.ZERO:
		dir = get_facing()
	dir.y = 0.0
	_roll_dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.BACK
	cancel_heal()
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


## Advances the roll clock; when ROLL_DURATION is reached it returns to MOVE, stopped dead, and the
## recovery (ROLL_RECOVERY) starts. A stored attack runs at once (the roll attack); a stored roll stays
## in the buffer until the recovery ends.
func _advance_roll(delta: float) -> void:
	_roll_time += delta
	_iframes = iframes_active_at(_roll_time)
	if _roll_time >= ROLL_DURATION - 0.0001:
		state = State.MOVE
		_iframes = false
		_roll_time = 0.0
		_roll_recovery_left = ROLL_RECOVERY
		velocity.x = 0.0
		velocity.z = 0.0
		_update_invulnerability()
		if _buffered_action != &"roll":
			_consume_buffer()
		return
	_update_invulnerability()


## True while she gets up after a roll (no i-frames; she can walk and attack, not roll).
func is_roll_recovering() -> bool:
	return _roll_recovery_left > 0.0


## Counts down the recovery; when it ends a stored order (a spammed roll) runs. Returns true then.
func _tick_roll_recovery(delta: float) -> bool:
	if _roll_recovery_left <= 0.0:
		return false
	_roll_recovery_left -= delta
	if _roll_recovery_left > 0.0001:
		return false
	_roll_recovery_left = 0.0
	_consume_buffer()
	return true


## One frame of the recovery: an attack cuts it (roll attack), a roll is stored, and she walks.
func _recover_step(delta: float, want_roll: bool, want_attack: bool, want_heavy: bool) -> void:
	if want_attack and try_attack():
		_stand_still()
		return
	if want_heavy and try_heavy_attack():
		_stand_still()
		return
	if want_roll:
		buffer_action(&"roll")
	_move_step(delta)
	_tick_roll_recovery(delta)


# --- Healing flask ----------------------------------------------------------------------------
# Sub-state of MOVE: she keeps walking at HEAL_MOVE_MULT of her speed for HEAL_DURATION s and the HP
# arrives at the end, when the use is spent. A hit (HURT), a roll, an attack, death or a cutscene
# cancels it and the use is NOT spent (the cost of being hit is the lost time, not the flask).

## HP restored by one use at `max_hp` max HP.
static func heal_amount(max_hp: int) -> int:
	return maxi(1, roundi(float(max_hp) * HEAL_RATIO))


func is_healing() -> bool:
	return _heal_time >= 0.0


## Why a use cannot start now ("" if it can): state, scene, pause, empty flask or full health.
func heal_blocked_reason() -> String:
	if state != State.MOVE:
		return "state"
	if _cutscene or _victory:
		return "cutscene"
	if is_inside_tree():
		if get_tree().paused:
			return "paused"
		var game_state := get_node_or_null(^"/root/GameState")
		if game_state and game_state.cutscene_active:
			return "cutscene"
	if _heal_time >= 0.0 or is_roll_recovering():
		return "busy"
	if heal_charges <= 0:
		return "empty"
	if health == null or health.is_dead() or health.current >= health.max_value:
		return "full"
	return ""


## Starts drinking. Returns false (and spends nothing) in a blocked state or with full health.
func try_heal() -> bool:
	if heal_blocked_reason() != "":
		return false
	_heal_time = 0.0
	_play_sfx(sfx_heal, HEAL_SFX_VOLUME_DB)
	if _model:
		HitFlash.glow(_model, HEAL_GLOW_COLOR, HEAL_GLOW_PEAK, HEAL_DURATION)
	return true


## Advances the drinking clock; at HEAL_DURATION spends the use and heals.
func _advance_heal(delta: float) -> void:
	if _heal_time < 0.0:
		return
	_heal_time += delta
	if _heal_time < HEAL_DURATION - 0.0001:
		return
	_heal_time = -1.0
	if health == null or health.is_dead():
		return
	if health.heal(heal_amount(health.max_value)) > 0:
		heal_charges -= 1
		heal_charges_changed.emit(heal_charges, HEAL_CHARGES)
		if is_inside_tree():
			ImpactFx.heal(get_tree(), global_position)
		if _model:
			HitFlash.flash(_model, HEAL_GLOW_COLOR, 0.25)


## Aborts the drinking (without spending the use) and clears its glow.
func cancel_heal(clear_glow := true) -> void:
	if _heal_time < 0.0:
		return
	_heal_time = -1.0
	if clear_glow and _model:
		HitFlash.clear(_model)


## Gives the flask its full uses back (entering a level, retrying).
func refill_heals() -> void:
	heal_charges = HEAL_CHARGES
	heal_charges_changed.emit(heal_charges, HEAL_CHARGES)


# --- Combo attack -----------------------------------------------------------------------------

## Damage of hit `i` of the combo. Kaelen's combo_index stays in 0..2; the wrap-around is kept for
## boss_pressure_sim.gd, whose simulated Kaelen counts her hits without a limit.
static func combo_damage(i: int) -> int:
	return COMBO_DAMAGE[posmod(i, COMBO_DAMAGE.size())]


## True if the hit in progress is the combo's finisher (its 3rd hit), which closes the combo.
func is_finisher() -> bool:
	return state == State.ATTACK and not _heavy and combo_index >= COMBO_LENGTH - 1


## Inside the chaining window of hits 1 and 2 (never after the finisher or the heavy attack).
func _in_combo_window() -> bool:
	return state == State.ATTACK and not _heavy and not is_finisher() and _attack_time >= HIT_END[combo_index]


## Starts a hit from MOVE (also during the roll's recovery: the roll attack), or chains the next one
## inside the window after hits 1 and 2. Spends ATTACK_COST of stamina.
func try_attack() -> bool:
	var chaining := _in_combo_window()
	if not (state == State.MOVE or chaining):
		return false
	if stamina == null or not stamina.try_spend(ATTACK_COST):
		return false
	combo_index = combo_index + 1 if chaining else 0
	_roll_recovery_left = 0.0
	cancel_heal()
	_set_hitbox_active(false)
	_attack_time = 0.0
	_heavy = false
	state = State.ATTACK
	_set_armor(true)
	_face_attack_direction()
	var hit := combo_index
	if _anim_tree:
		_anim_tree.set(StringName("parameters/%s/speed/scale" % ATTACK_ANIMS[hit]), ATTACK_ANIM_SPEED[hit])
	_play_action(ATTACK_ANIMS[hit])
	_play_sfx(sfx_swing)
	return true


## Heavy attack: a leap that lands with a slam (HEAVY_DAMAGE). From MOVE (also after a roll) or as
## the finisher inside the window of hits 1 and 2. Spends HEAVY_COST of stamina; it has the same hyper
## armor as the combo until its damage window closes.
func try_heavy_attack() -> bool:
	var chaining := _in_combo_window()
	if not (state == State.MOVE or chaining):
		return false
	if stamina == null or not stamina.try_spend(HEAVY_COST):
		return false
	_roll_recovery_left = 0.0
	cancel_heal()
	_set_hitbox_active(false)
	_attack_time = 0.0
	combo_index = 0
	_heavy = true
	state = State.ATTACK
	_set_armor(true)
	_heavy_dir = get_facing()
	_heavy_dir.y = 0.0
	_heavy_dir = _heavy_dir.normalized()
	_face_attack_direction()
	_play_action(HEAVY_ANIM)
	_play_sfx(sfx_swing)
	return true


func is_heavy_attacking() -> bool:
	return state == State.ATTACK and _heavy


## Hit-stop for the blow Kaelen is landing now (Hitbox asks it): stronger on the finisher and the slam.
func hit_stop_time() -> float:
	if _heavy or is_finisher():
		return HIT_STOP_STRONG
	return HIT_STOP_LIGHT


## At the start of each hit Kaelen turns toward the locked target; without a target, toward the input (with the
## slash offset; the heavy slam goes straight). Without a target or input she keeps her facing.
func _face_attack_direction() -> void:
	if _model == null or not is_inside_tree():
		return
	var dir := Vector3.ZERO
	if _lock_on and is_instance_valid(_lock_on.target):
		dir = _lock_on.target.global_position - global_position
	else:
		dir = _input_direction()
	dir.y = 0.0
	if dir.length_squared() <= 0.0001 and _heavy:
		dir = _heavy_dir   # no target or input: the slam still centres on where she was facing
	if dir.length_squared() > 0.0001:
		var offset := HEAVY_AIM_OFFSET if _heavy else ATTACK_AIM_OFFSET[combo_index]
		_model.rotation.y = atan2(dir.x, dir.z) + offset
		if _heavy:
			_heavy_dir = dir.normalized()


## Horizontal motion during ATTACK: the heavy attack leaps forward while airborne; a combo hit steps
## toward the locked target at its start (it stops short of it, and walls stop both).
func _attack_motion() -> void:
	var v := Vector3.ZERO
	var target := get_lock_target()
	var to_target := Vector3.INF
	if target:
		to_target = target.global_position - global_position
		to_target.y = 0.0
	if _heavy:
		var airborne := _attack_time >= HEAVY_LEAP_START and _attack_time < HEAVY_LEAP_END
		if airborne and (target == null or to_target.length() > HEAVY_LEAP_STOP):
			v = _heavy_dir * HEAVY_LEAP_SPEED
	elif target and _attack_time < ATTACK_STEP_TIME and to_target.length() > ATTACK_STEP_MIN:
		v = to_target.normalized() * ATTACK_STEP_SPEED
	velocity.x = v.x
	velocity.z = v.z
	move_and_slide()


## Advances the hit clock: activates the hitbox only inside its damage window, chains a buffered
## attack when the combo window opens and returns to MOVE when that window closes. The finisher does
## not chain: it loses the hyper armor when its window closes and returns to MOVE at FINISHER_END,
## where a buffered order starts again from the first hit.
func _advance_attack(delta: float) -> void:
	_attack_time += delta
	_tick_buffer(delta)
	if _heavy:
		_advance_heavy(delta)
		return
	var hit := combo_index
	_set_hitbox_active(_attack_time >= HIT_START[hit] and _attack_time < HIT_END[hit])
	if is_finisher():
		if _attack_time >= HIT_END[hit]:
			_set_armor(false)
		if _attack_time >= FINISHER_END - 0.0001:
			_end_attack()
			_play_action(&"locomotion")
			_consume_buffer()
		return
	if _attack_time >= HIT_END[hit] and _buffered_action == &"heavy":
		_clear_buffer()
		if try_heavy_attack():
			return
	if _attack_time >= HIT_END[hit] and _buffered_action == &"attack":
		_clear_buffer()
		if try_attack():
			return
	if _attack_time >= HIT_END[hit] + COMBO_WINDOW:
		_end_attack()
		_play_action(&"locomotion")
		_consume_buffer()


## Heavy attack clock: the blade is live in [HEAVY_HIT_START, HEAVY_HIT_END), the slam raises dust
## and shakes the camera at HEAVY_IMPACT, and it returns to MOVE at HEAVY_END (a buffered order runs then).
func _advance_heavy(delta: float) -> void:
	var was_before := _attack_time - delta < HEAVY_IMPACT
	_set_hitbox_active(_attack_time >= HEAVY_HIT_START and _attack_time < HEAVY_HIT_END)
	if _attack_time >= HEAVY_HIT_END:
		_set_armor(false)   # the landing crouch can be punished
	if was_before and _attack_time >= HEAVY_IMPACT and is_inside_tree():
		var spot := _sword_hitbox.global_position if _sword_hitbox else global_position + _heavy_dir * 1.6
		ImpactFx.dust(get_tree(), Vector3(spot.x, global_position.y + 0.1, spot.z), 1.2)
		if _camera_rig:
			_camera_rig.shake(0.05, 0.18)
	if _attack_time >= HEAVY_END:
		_end_attack()
		_play_action(&"locomotion")
		_consume_buffer()


func _end_attack() -> void:
	_set_hitbox_active(false)
	_set_armor(false)
	_attack_time = 0.0
	_heavy = false
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
		_sword_hitbox.damage = HEAVY_DAMAGE if _heavy else combo_damage(combo_index)
		_sword_hitbox.activate()
	else:
		_sword_hitbox.deactivate()


# --- Input buffer -----------------------------------------------------------------------------

## Stores an order (&"roll" or &"attack") for BUFFER_TIME; the latest one replaces the previous one.
func buffer_action(action: StringName) -> void:
	_buffered_action = action
	_buffer_left = BUFFER_TIME


## Counts the stored order down. It does not expire during the roll's get-up: a roll pressed late in
## the travel or while getting up cannot run yet, so it waits for the end of the recovery (at most
## BUFFER_TIME + ROLL_RECOVERY ≈ 0.46 s after the press). An attack never waits there (it cuts it).
func _tick_buffer(delta: float) -> void:
	if _buffered_action == &"" or is_roll_recovering():
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
		&"heavy":
			return try_heavy_attack()
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
	_hurt_feedback(previous - current, max_value)
	_start_hurt_iframes()
	if not (state == State.ATTACK and _armor_on):   # hyper armor: the slash goes on, without the hurt animation
		_enter_hurt()


## Hit feedback: a short hit-stop and, for a strong hit (>= HEAVY_HIT_RATIO of max HP), a small camera shake.
func _hurt_feedback(amount: int, max_value: int) -> void:
	if not is_inside_tree():
		return
	HitStop.request(get_tree(), HitStop.HURT_DURATION)
	if float(amount) / maxf(1.0, float(max_value)) >= HEAVY_HIT_RATIO:
		var rig := get_node_or_null(^"CameraRig") as CameraRig
		if rig:
			rig.shake(0.07, 0.22)


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
	cancel_heal(false)   # the hit's own flash replaces the glow
	_end_attack()
	_shove_left = 0.0
	_roll_time = 0.0
	_roll_recovery_left = 0.0
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
	cancel_heal(false)
	_end_attack()
	_clear_buffer()
	_roll_recovery_left = 0.0
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


## F6 (action "debug_god"): toggles invulnerability, only in debug builds; an exported release build
## ignores it. Returns true if it toggled.
func toggle_debug_god(debug_build := OS.is_debug_build()) -> bool:
	if not debug_build:
		return false
	_god = not _god
	_update_invulnerability()
	print("debug_god: ", _god)
	return true


## Hands Kaelen over to a scripted sequence (the ending) or gives control back. While on: movement,
## roll, attack and lock-on are ignored, she stands in idle and cannot be hurt. Turning it on cancels
## any roll / attack / hurt in progress and the target lock.
func set_cutscene(on: bool) -> void:
	if on == _cutscene:
		return
	_cutscene = on
	if not on and not _walk_points.is_empty():
		_end_scripted_walk()
	if on:
		cancel_heal()
		if state != State.DEAD:
			_end_attack()
			_roll_time = 0.0
			_hurt_time = 0.0
			state = State.MOVE
		_roll_recovery_left = 0.0
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


## Directed walk (stairs between floors, entering the temple): Kaelen, already in cutscene mode,
## walks through `points` (only x/z matter; ramps and gravity do the height) at `speed` with her
## walk/run clip, facing where she goes, and the camera eases in behind her. Emits
## scripted_walk_finished at the last point; set_cutscene(false) gives control back.
func scripted_walk(points: Array[Vector3], speed := 2.6) -> void:
	_walk_points = points.duplicate()
	_walk_speed = speed
	if _walk_points.is_empty():
		_end_scripted_walk()


func is_scripted_walking() -> bool:
	return not _walk_points.is_empty()


func _scripted_step(delta: float) -> void:
	var to := _walk_points[0] - global_position
	to.y = 0.0
	while to.length() <= WALK_ARRIVE:
		_walk_points.pop_front()
		if _walk_points.is_empty():
			_end_scripted_walk()
			return
		to = _walk_points[0] - global_position
		to.y = 0.0
	var dir := to.normalized()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(dir * _walk_speed, ACCELERATION * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var was_on_floor := is_on_floor()
	move_and_slide()
	if was_on_floor and is_on_wall():
		_try_step_up(dir * _walk_speed * delta)
	_model.rotation.y = lerp_angle(_model.rotation.y, atan2(dir.x, dir.z), minf(1.0, TURN_SPEED * delta))
	if _camera_rig:
		_camera_rig.guide_yaw = atan2(-dir.x, -dir.z)


func _end_scripted_walk() -> void:
	_walk_points.clear()
	velocity.x = 0.0
	velocity.z = 0.0
	if _camera_rig:
		_camera_rig.guide_yaw = NAN
	scripted_walk_finished.emit()


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
# - roll, attack_1..3, hurt: BlendTree with the clip and a TimeScale ("speed"). The roll state plays
#   ROLL_CLIP fitted to ROLL_DURATION + ROLL_RECOVERY, hurt is fitted to HURT_DURATION; each hit uses
#   ATTACK_ANIM_SPEED and starts its clip at ATTACK_CLIP_START.
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
		elif state_name == &"roll":
			node = _build_time_scaled_clip(ROLL_CLIP)
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
		if state_name in ATTACK_ANIMS or state_name == HEAVY_ANIM:
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
	# Posed on physics frames: the sword hitbox follows a bone of the hand (_follow_sword) and its
	# damage windows are counted in physics time. Posed on idle frames, a slow frame (measured in
	# kaelen_moves_flow: one idle frame per 3-6 physics frames) froze the blade for several physics
	# steps and a slash at full reach could pass through a target without touching it.
	_anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	add_child(_anim_tree)
	_anim_tree.anim_player = _anim_tree.get_path_to(player)
	# The roll (roll_to_run, ~1.43 s) and hurt (~0.7 s) clips must fit their duration: factor based on
	# their real length. The roll's clip covers the travel and the recovery.
	_anim_tree.set(&"parameters/roll/speed/scale", roll_anim_scale(_clip_length(player, ROLL_CLIP, ROLL_CLIP_LENGTH)))
	_anim_tree.set(&"parameters/hurt/speed/scale", _clip_length(player, &"hurt", HURT_DURATION) / HURT_DURATION)
	for i in ATTACK_ANIMS.size():
		_anim_tree.set(StringName("parameters/%s/speed/scale" % ATTACK_ANIMS[i]), ATTACK_ANIM_SPEED[i])
	_anim_tree.set(StringName("parameters/%s/speed/scale" % HEAVY_ANIM), HEAVY_ANIM_SPEED)
	_anim_tree.active = true


## TimeScale of the roll state for a roll clip of `clip_length` s: the whole clip spans the travel and
## the recovery, so ROLL_CLIP_RISE lands at the end of the travel.
static func roll_anim_scale(clip_length: float) -> float:
	return clip_length / (ROLL_DURATION + ROLL_RECOVERY)


func _clip_length(player: AnimationPlayer, clip: StringName, fallback: float) -> float:
	if player.has_animation(clip):
		return player.get_animation(clip).length
	push_warning("Kaelen: missing clip '%s'" % clip)
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
	# Strafe (locked target): x = speed to her right, y = forward speed, in the model's frame.
	var strafe := AnimationNodeBlendSpace2D.new()
	strafe.min_space = Vector2(-WALK_SPEED, -WALK_SPEED)
	strafe.max_space = Vector2(WALK_SPEED, WALK_SPEED)
	for p in [["idle", Vector2.ZERO], ["walk", Vector2(0, WALK_ANIM_SPEED)], ["run", Vector2(0, RUN_ANIM_SPEED)],
			["walk_back", Vector2(0, -STRAFE_ANIM_SPEED)], ["strafe_right", Vector2(STRAFE_ANIM_SPEED, 0)],
			["strafe_left", Vector2(-STRAFE_ANIM_SPEED, 0)]]:
		var clip := AnimationNodeAnimation.new()
		clip.animation = p[0]
		strafe.add_blend_point(clip, p[1], -1, p[0])
	var tree := AnimationNodeBlendTree.new()
	tree.add_node(&"locomotion", space)
	tree.add_node(&"strafe", strafe)
	tree.add_node(&"lock", AnimationNodeBlend2.new())
	tree.add_node(&"speed", AnimationNodeTimeScale.new())
	tree.connect_node(&"lock", 0, &"locomotion")
	tree.connect_node(&"lock", 1, &"strafe")
	tree.connect_node(&"speed", 0, &"lock")
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
	var strafing := strafe_target() != null
	_lock_blend = move_toward(_lock_blend, 1.0 if strafing else 0.0, LOCK_BLEND_RATE * get_physics_process_delta_time())
	var local := local_ground_velocity()
	_anim_tree.set(&"parameters/locomotion/locomotion/blend_position", speed)
	_anim_tree.set(&"parameters/locomotion/strafe/blend_position", local)
	_anim_tree.set(&"parameters/locomotion/lock/blend_amount", _lock_blend)
	var anim_scale := lerpf(free_anim_scale(speed), strafe_anim_scale(local), _lock_blend)
	if speed < 0.05:
		anim_scale *= idle_anim_scale
	_anim_tree.set(&"parameters/locomotion/speed/scale", anim_scale)
