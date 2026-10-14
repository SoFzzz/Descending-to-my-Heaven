class_name Player
extends CharacterBody3D
## Kaelen. States: MOVE (walk relative to the camera, gravity, smooth turning), ROLL (roll with
## i-frames and stamina cost), ATTACK (3-hit combo with the greatsword), HURT (stunned when taking
## damage) and DEAD (no control; respawn is handled by GameState, Task 10).

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
const COMBO_DAMAGE: Array[int] = [10, 10, 18]
const ATTACK_COST := 20.0
## When each hit's damage window closes, there are COMBO_WINDOW s to chain the next one;
## after that window the hit ends and it returns to MOVE (the tail of the clip is cut).
const COMBO_WINDOW := 0.4
## Clip and playback speed of each hit. attack_2 is a long Mixamo combo (3.3 s,
## three slashes): only its first upward slash is used and the hit is cut when the combo
## window closes (≈ 1.36 s of the clip), before the second slash begins.
const ATTACK_ANIMS: Array[StringName] = [&"attack_1", &"attack_2", &"attack_3"]
const ATTACK_ANIM_SPEED: Array[float] = [1.3, 1.2, 1.2]
## Damage windows in game seconds from the start of each hit (by time, not by animation
## markers). Measured by following the greatsword tip in each clip; the clip time
## (= game time × speed) is in parentheses:
## - attack_1: horizontal slash from right to left (clip 0.75–1.00 s).
## - attack_2: first upward slash in front of Kaelen (clip 0.60–0.88 s).
## - attack_3: final downward strike (clip 1.00–1.25 s).
const HIT_START: Array[float] = [0.58, 0.50, 0.83]
const HIT_END: Array[float] = [0.77, 0.73, 1.04]
## Mixamo's slashes do not pass exactly through the front: within its window attack_1 sweeps from −20° to
## +60°, attack_2 from −60° to 0° and attack_3 from −60° to −5° (angle in the model's space, + = +X,
## measured with a target 1.5 m away). When turning toward the target this offset is added so the
## target ends up in the center of the sweep.
const ATTACK_AIM_OFFSET: Array[float] = [deg_to_rad(-15.0), deg_to_rad(25.0), deg_to_rad(25.0)]

const HURT_DURATION := 0.4
## Orders (roll, attack) pressed while they cannot be executed are kept for this long.
const BUFFER_TIME := 0.2

# Ground speed at which each clip looks right without sliding (measured by eye with captures; see
# docs/asset-status.md). Above RUN_ANIM_SPEED the `run` clip is sped up.
const WALK_ANIM_SPEED := 1.4
const RUN_ANIM_SPEED := 4.2

# Action states of the AnimationTree (besides "locomotion").
const ACTION_STATES: Array[StringName] = [&"roll", &"attack_1", &"attack_2", &"attack_3", &"hurt", &"death"]
# States whose clip is adjusted with a TimeScale (parameters/<state>/speed/scale).
const SCALED_STATES: Array[StringName] = [&"roll", &"attack_1", &"attack_2", &"attack_3", &"hurt"]

var state: State = State.MOVE
## If nobody assigned them before, they are looked up in _ready (children "Health" and "Stamina"). Tests
## assign them by hand without putting Kaelen in the tree and call _connect_components().
var health: Health
var stamina: Stamina
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
var _victory := false   # after Events.boss_defeated
var _god := false       # debug (action "debug_god", F6)

var _attack_time := 0.0
var _hitbox_on := false
var _hurt_time := 0.0
var _last_hp := -1
var _attack_pressed := false   # from _unhandled_input: the click that recaptures the mouse does not attack
var _buffered_action: StringName = &""
var _buffer_left := 0.0


func _ready() -> void:
	add_to_group("player")
	if health == null:
		health = get_node_or_null(^"Health") as Health
	if stamina == null:
		stamina = get_node_or_null(^"Stamina") as Stamina
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
			_stand_still()
			_advance_hurt(delta)
		State.DEAD:
			_stand_still()
	_update_invulnerability()
	_follow_sword()
	_update_animation(Vector3(velocity.x, 0.0, velocity.z).length())


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
	_face_attack_direction()
	var hit := combo_index % 3
	if _anim_tree:
		_anim_tree.set(StringName("parameters/%s/speed/scale" % ATTACK_ANIMS[hit]), ATTACK_ANIM_SPEED[hit])
	_play_action(ATTACK_ANIMS[hit])
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
	_attack_time = 0.0
	combo_index = 0
	if state == State.ATTACK:
		state = State.MOVE


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
	if current > 0 and state != State.DEAD:
		_enter_hurt()


## HURT interrupts the attack (and turns off the hitbox) or the roll.
func _enter_hurt() -> void:
	_end_attack()
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


func _on_died() -> void:
	if state == State.DEAD:
		return
	_end_attack()
	_clear_buffer()
	_iframes = false
	state = State.DEAD
	_update_invulnerability()
	death_count += 1
	if _lock_on:
		_lock_on.target = null
	_play_action(&"death")
	if death_count == 1:
		var events := _events()
		if events:
			events.player_died.emit()


func _on_boss_defeated(_boss: Node3D) -> void:
	_victory = true
	_update_invulnerability()


func is_invulnerable() -> bool:
	return _iframes or _victory or _god


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
#   to ROLL_DURATION / HURT_DURATION; each hit uses ATTACK_ANIM_SPEED.
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
		if state_name in SCALED_STATES:
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
func _build_time_scaled_clip(clip_name: StringName) -> AnimationNodeBlendTree:
	var clip := AnimationNodeAnimation.new()
	clip.animation = clip_name
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
