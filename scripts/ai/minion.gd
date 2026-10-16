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
const PSX := preload("res://scenes/levels/psx_test.gd")
const ANIM_BLEND := 0.15        # s of blend between clips
const MOVE_EPSILON := 0.1       # m/s below which a chasing minion plays idle instead of walk
const WALK_SCALE_MIN := 0.4
const WALK_SCALE_MAX := 1.5
const DEATH_FALL_TIME := 0.6    # fall tween when the model has no death clip
const DEATH_SINK := 0.15        # m the model sinks while falling
const KIND_IDLE := &"idle"
const KIND_WALK := &"walk"
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
@export var walk_anim_speed := 1.0              ## speed scale of the walk clip
@export var weapon_scene: PackedScene           ## optional, hung on weapon_bone
@export var weapon_bone: StringName = &"mixamorig:RightHand"
@export var weapon_transform := Transform3D.IDENTITY
@export var corpse_time := 2.0                  ## s from death to queue_free
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
	_setup_visuals()
	# Deferred: whoever spawns it sets the position right after add_child.
	_play_sfx.call_deferred(sfx_spawn)


func _physics_process(delta: float) -> void:
	if state == MinionState.DEAD:
		return   # no collisions: if it moved it would fall through the floor
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_find_player()
	_state_time += delta
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
	if MinionBrain.should_retreat(float(health.current) / maxf(1.0, float(health.max_value)), sfx_spawn != null, _retreated):
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
				_navigate_to(_player.global_position, move_speed)
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
		_set_hitbox(false)
		_release_token(true)
	match next:
		MinionState.STUNNED:
			_set_hitbox(false)
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
		elif distance <= TOKEN_RANGE and _token_cooldown <= 0.0:
			_holding_token = tokens.request(self)   # returns true if it already holds one
		elif distance > TOKEN_DROP_RANGE and _holding_token:
			_release_token()


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
		_play_sfx(sfx_hurt)


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
	_play_sfx(sfx_death)
	if is_inside_tree():
		ImpactFx.puff(get_tree(), global_position + Vector3.UP * 0.5)
	_play_death()
	get_tree().create_timer(corpse_time).timeout.connect(queue_free)


# --- Visuals ----------------------------------------------------------------------------------

## Static clip choice: which kind of clip the FSM state asks for (horizontal speed in m/s).
static func clip_kind(st: MinionState, horizontal_speed: float) -> StringName:
	match st:
		MinionState.DEAD:
			return KIND_DEATH
		MinionState.STUNNED:
			return KIND_HURT
		MinionState.ATTACK, MinionState.RECOVER:
			return KIND_ATTACK   # keeps playing through RECOVER so the swing ends naturally
		MinionState.CHASE, MinionState.CIRCLE:
			return KIND_WALK if horizontal_speed >= MOVE_EPSILON else KIND_IDLE
	return KIND_IDLE


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
		for clip in [anim_idle, anim_walk]:
			if _anim.has_animation(clip):
				_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		# One-shot clips must not loop (a looping death would get the corpse back up).
		for clip in [anim_attack, anim_hurt, anim_death]:
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
		KIND_ATTACK:
			return anim_attack
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
	var kind := clip_kind(state, speed)
	var clip := _clip_name(kind)
	if not _anim.has_animation(clip):
		return
	if kind == KIND_WALK:
		_anim.speed_scale = walk_speed_scale(speed, move_speed, walk_anim_speed)
	if not force and kind == _current_kind:
		return
	_current_kind = kind
	var length := _anim.get_animation(clip).length
	match kind:
		KIND_ATTACK:
			_anim.speed_scale = fit_speed(length, WINDUP_TIME + ACTIVE_TIME + RECOVER_TIME)
		KIND_HURT:
			_anim.speed_scale = fit_speed(length, STUN_TIME)
		KIND_WALK:
			pass   # already set above
		_:
			_anim.speed_scale = 1.0
	_anim.play(clip, ANIM_BLEND)


func _play_death() -> void:
	if _model_root == null:
		return   # placeholder: no animation, as before
	if _anim and _anim.is_inside_tree() and _anim.has_animation(anim_death):
		_current_kind = KIND_DEATH
		_anim.speed_scale = 1.0
		_anim.play(anim_death, ANIM_BLEND)
		return
	var holder := get_node_or_null(^"Model") as Node3D
	if holder == null or not is_inside_tree():
		return
	var tween := create_tween().set_parallel(true)
	tween.tween_property(holder, "rotation:x", PI * 0.5, DEATH_FALL_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(holder, "position:y", holder.position.y - DEATH_SINK, DEATH_FALL_TIME)


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
