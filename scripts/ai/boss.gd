class_name Boss
extends CharacterBody3D
## Boss (Task 9): IDLE → CHASE (NavigationAgent3D on the large layer) → picks an attack with
## BossBrain → TELEGRAPH (red warning on the floor, same size as the hitbox) → ACTIVE (hitbox on)
## → RECOVER → CHASE. Phase 2 at 50 % health: a short ROAR (PHASE2_ROAR_TIME, invulnerable) whose
## shockwave is the repel one (pushes Kaelen if she is within repel_radius), and then +25 % animation,
## attack and movement speed. On death: death animation,
## Events.boss_defeated once and deferred shutdown of collisions/hitboxes.
##
## Scene conventions (boss_base.tscn): children Health, CollisionShape3D, NavigationAgent3D,
## LockOnPoint, Telegraphs/<attack id> (hidden flat meshes) and an AnimationPlayer anywhere under
## Model. Hurtboxes anywhere below report to the boss, which applies the damage to Health.
##
## Approach vs attack: while CHASE, the boss asks BossBrain every frame (after the cooldown). Once
## it is within `engage_range` every attack valid at that distance competes; while it is still
## farther away only `BossAttack.opener` attacks (lunge, pounce, beam) can start, if the distance
## is inside their [min_range, max_range]. Otherwise it keeps walking (`walk_animation`), unless the
## chase stalls (Kaelen inside the reach of an attack backs off as fast as the boss walks): then every
## attack in range competes (BossBrain.track_chase).
## During ACTIVE an attack may move the boss (`advance_distance`), open extra hitboxes
## (`extra_hitbox_paths`), show a visual (`visual_path`) and expose gated hurtboxes.

signal state_changed(state: State)
signal attack_started(attack: BossAttack)
## The tactical goal changed (BossTactics.Goal): used by the F3 overlay and the simulations.
signal goal_changed(goal: BossTactics.Goal)

enum State { IDLE, CHASE, TELEGRAPH, ACTIVE, RECOVER, ROAR, DEAD }

const PHASE2_SPEED := 1.25
## The phase-2 roar lasts this many seconds (it used to play the whole clip: 3.7 s for the Bone
## Dragon, 2.3 s for Blackhorn and Ghidorah, with the boss open to hits). It is invulnerable and
## its shockwave is the repel one (repel_push_delay s after it starts, repel_radius m).
const PHASE2_ROAR_TIME := 1.5
const TURN_SPEED := 4.0            # rad/s-ish smoothing toward Kaelen
const TRACK_FRACTION := 0.7        # during the first 70 % of the warning it keeps turning; then it commits
const DODGE_RECORD_RANGE := 12.0   # only rolls this close count for the anticipation bonus
const ANIM_BLEND := 0.25
## Kaelen's sword is active ~0.2 s per slash and slashes are ≥ 0.4 s apart.
const SAME_SWING_WINDOW := 0.3
## Tactics (BossTactics): horizon of the predicted position when cutting off / intercepting (s),
## minimum speed of Kaelen to count as "moving", speed factors when waiting
## or pincering, and maximum duration of the gesture (roar / taunt) that announces an order.
const CUT_OFF_HORIZON := 1.5
const INTERCEPT_HORIZON := 1.0
const INTERCEPT_MIN_SPEED := 1.8
const WAIT_SPEED := 0.6
const PINCER_SPEED := 0.85
const GESTURE_MAX := 1.1
const GESTURE_VOLUME_DB := -3.0
const DAMAGE_WINDOW := 4.0
## Phase 2 combos (BossAttack.combo_next): the follow-up starts once this fraction of the recovery
## has passed and its warning lasts COMBO_TELEGRAPH of the normal one; the attack aura (AttackWarning)
## rises again from wherever its fade-out was. One follow-up per attack (no endless strings).
const COMBO_PHASE := 2
const COMBO_RECOVER_FRACTION := 0.35
const COMBO_TELEGRAPH := 0.85
const COMBO_RANGE_SLACK := 2.0
const COMBO_MAX_CHAIN := 1

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
@export_group("Tactics")
## Enables the tactical goals (cut off, wait, pincer, ambush). Off = the boss chases
## and attacks as before (useful for comparing in the simulations).
@export var tactics_enabled := true
## Attacks aimed at Kaelen's predicted point if she is moving (charge, pounce, beam).
@export var intercept_attacks: Array[StringName] = []
## Attack preferred (×circling_bonus) when Kaelen tries to circle the boss (Bone Dragon: tail swipe).
@export var circling_attack: StringName = &""
@export var circling_bonus := 2.2
## Taunt animation for the WAIT gesture (if the model has it; Blackhorn: "taunt").
@export var taunt_animation: StringName = &"taunt"
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
## On taking damage (hits of the same swing add up to a single sound).
@export var sfx_hurt: AudioStream
## On entering phase 2 (roar).
@export var sfx_phase2: AudioStream
@export var sfx_death: AudioStream

var phase: int = 1
var state: State = State.IDLE
var brain := BossBrain.new()
var repel := BossRepel.new()
## True while the current ROAR is a repel reaction (not the phase-2 roar).
var repelling := false
## True while the current ROAR is the phase-2 roar (invulnerable, with the repel shockwave).
var phase_roaring := false
## How many repel reactions happened (debug and tests).
var repel_count := 0
var current_attack: BossAttack
## Attack ids in the order they were used (debug and verification).
var attack_log: Array[StringName] = []
var gated_open := false
## Shared combat memory and tactical goals.
var memory := CombatMemory.new()
var tactics := BossTactics.new()
## Multiplies the warning of the current attack (ambush: longer, hence fairer).
var telegraph_scale := 1.0
## True while the ROAR is an announcement gesture (pincer / taunt) and not the phase roar or the repel.
var gesturing := false
## Tactics statistics (simulations and debugging).
var ambush_count := 0
## Follow-ups chained so far (phase 2 combos), for the debug overlay and the tests.
var combo_count := 0
var _combo_chain := 0              # follow-ups in the current string
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
var _gesture_len := 1.0
var _wait_side := 1.0
var _damage_log: Array = []        # [time, damage] of the last DAMAGE_WINDOW s
var _last_repel_clock := -99.0
var _threat_on := false
var _threat_near := false


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
		hurtbox.guard = self   # no hit feedback at all while the boss is invulnerable (roars)
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
			AttackWarning.make_ground(tg as MeshInstance3D, attack.warning, attack.telegraph_inner)
			for child in tg.get_children():   # the beam's "hitting now" stretch
				if AttackWarning.make_ground(child as MeshInstance3D, attack.warning):
					AttackWarning.set_progress(child as MeshInstance3D, 1.0)
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	_model = get_node_or_null(model_path) as Node3D
	if _model:
		var skeletons := _model.find_children("*", "Skeleton3D", true, false)
		_skeleton = skeletons.front() as Skeleton3D if not skeletons.is_empty() else null
	_set_gated(false)
	_warm_up()
	_play(idle_animation)


func _exit_tree() -> void:
	# A boss freed mid-attack (scene change) must not leave AttackTokens believing it still threatens.
	if _threat_on:
		_publish_threat(false, false)


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
		var sample_dt := memory.tick(delta)
		if sample_dt > 0.0:
			memory.observe(sample_dt, _memory_context())
		if tactics_enabled:
			tactics.advance(delta)
		if repel_enabled and state != State.IDLE and state != State.DEAD:
			var glued := repel.register_proximity(delta, _flat_distance() <= repel.glue_radius, not can_repel())
			if glued:
				_pending_repel = true
	if _pending_roar and state != State.ROAR:
		start_phase_roar()
	elif _pending_repel and can_repel():
		start_repel()
	elif not target_ok and state != State.IDLE and state != State.ROAR:
		_cancel_attack()   # Kaelen died: stop attacking
		_set_state(State.IDLE)
		_play(idle_animation)
	_run_state(delta, target_ok)
	_update_gate(delta)
	_update_threat()
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
			_run_chase(delta, speed)
		State.TELEGRAPH:
			_stop()
			var telegraph := current_attack.telegraph_time * telegraph_scale / speed
			if _state_time < telegraph * TRACK_FRACTION:
				_face(_aim_target(), delta)
			if _telegraph:
				AttackWarning.set_progress(_telegraph as GeometryInstance3D, _state_time / maxf(telegraph, 0.01))
			if _state_time >= telegraph:
				_set_state(State.ACTIVE)
				_spin_done = 0.0
				_advance_done = 0.0
				if _anim:
					_anim.speed_scale = speed   # the ambush's lengthened warning slows the animation only up to here
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
			if _try_combo(target_ok):
				return
			if _state_time >= current_attack.recovery_time / speed:
				current_attack = null
				telegraph_scale = 1.0
				_combo_chain = 0
				tactics.request_eval()   # end of the recovery: time to decide what to do
				if _pending_repel or repel.is_due(health.max_value):
					_pending_repel = true   # deferred from the punish window: fires next frame
				_cooldown = attack_cooldown / speed
				_play(idle_animation)
				_set_state(State.CHASE)
		State.ROAR:
			_stop()
			if (repelling or phase_roaring) and _repel_push_left > 0.0:
				_repel_push_left -= delta
				if _repel_push_left <= 0.0:
					_push_player()
			if _state_time >= _roar_duration(speed):
				repelling = false
				phase_roaring = false
				gesturing = false
				tactics.request_eval()
				_play(idle_animation)
				_set_state(State.CHASE if target_ok else State.IDLE)


# --- Tactics ---------------------------------------------------------------------------------

## CHASE with tactical goals (BossTactics): the goal decides where the boss goes and whether it may attack.
## ATTACK is the classic behaviour (follows Kaelen up to engage_range and attacks); CUT_OFF goes to the
## predicted point and only launches openers; WAIT backs off / circles without attacking; PINCER plants itself on its
## side of Kaelen while the Orchestrator closes in with the minions from the opposite one.
func _run_chase(delta: float, speed: float) -> void:
	var distance := _flat_distance()
	var goal := _tactics_step(distance)
	if state != State.CHASE:
		return   # the goal change started a gesture (ROAR): do not move or attack on top of it
	var approaching := distance > engage_range
	var target := _player.global_position
	var factor := 1.0
	var may_attack := true
	var strafing := false
	match goal:
		BossTactics.Goal.CUT_OFF:
			target = _clamp_nav(BossTactics.cut_off_point(memory.predict(CUT_OFF_HORIZON), global_position))
		BossTactics.Goal.WAIT:
			may_attack = false
			strafing = true
			factor = WAIT_SPEED
			target = _clamp_nav(BossTactics.wait_point(global_position, _player.global_position, _wait_side))
		BossTactics.Goal.PINCER:
			may_attack = not approaching   # does not open attacks from afar: its role is to close one side
			strafing = true
			factor = PINCER_SPEED
			target = _clamp_nav(SquadTactics.boss_pincer_point(_player.global_position, global_position))
		_:
			if tactics_enabled and BossTactics.is_ambush(memory.distracted, memory.fleeing, distance, engage_range):
				factor = BossTactics.AMBUSH_SPEED   # stalks: approaches more slowly while she is distracted
	# Chase gap: in ATTACK, a Kaelen inside the reach of an attack that the boss cannot catch up with
	# lets every attack in range start, not only the openers (BossBrain.track_chase).
	var stalled := false
	if goal == BossTactics.Goal.ATTACK and approaching:
		stalled = brain.track_chase(delta, distance, distance <= BossBrain.reach(attacks, phase))
	else:
		brain.reset_chase()
	if may_attack and _cooldown <= 0.0 and _try_start_attack(distance, approaching and not stalled):
		_stop()
		return
	var moving := approaching
	var to_target := target - global_position
	to_target.y = 0.0
	if goal == BossTactics.Goal.WAIT:
		moving = true
	elif goal == BossTactics.Goal.PINCER:
		moving = to_target.length() > 1.0
	elif goal == BossTactics.Goal.CUT_OFF:
		moving = approaching and to_target.length() > 1.0
	if moving:
		_navigate_to(target, move_speed * speed * factor)
		_face(_player.global_position if strafing else global_position + Vector3(velocity.x, 0.0, velocity.z), delta)
	else:
		_stop()
		_face(_player.global_position, delta)
	_play_locomotion(moving and Vector2(velocity.x, velocity.z).length() > 0.3)


## Re-evaluates the goal (every 0.5 s, only while not attacking) and returns the current one.
func _tactics_step(distance: float) -> BossTactics.Goal:
	if not tactics_enabled:
		return BossTactics.Goal.ATTACK
	if tactics.eval_due() and tactics.step(_tactics_context(distance)):
		_on_goal_changed()
	return tactics.goal


func _tactics_context(distance: float) -> Dictionary:
	return {
		distance = distance,
		fleeing = memory.fleeing,
		with_minions = memory.with_minions,
		glued = memory.glued,
		passive = memory.passive,
		distracted = memory.distracted,
		health_ratio = float(health.current) / maxf(1.0, float(health.max_value)),
		phase = phase,
		minions_alive = memory.minions_alive,
		recent_damage = _recent_damage(),
		since_repel = _clock - _last_repel_clock,
		engage_range = engage_range,
	}


func _on_goal_changed() -> void:
	_wait_side = 1.0 if _rng.randf() < 0.5 else -1.0
	match tactics.goal:
		BossTactics.Goal.PINCER:
			_start_gesture(roar_animation, true)   # "announces" the order to the minions: readable
		BossTactics.Goal.WAIT:
			if _anim and _anim.has_animation(taunt_animation):
				_start_gesture(taunt_animation, false)
	goal_changed.emit(tactics.goal)


## Short gesture (roar or taunt) reusing the ROAR state: it deals no damage and the boss is NOT invulnerable.
func _start_gesture(anim_name: StringName, with_sound: bool) -> void:
	if state != State.CHASE:
		return
	_stop()
	gesturing = true
	_gesture_len = minf(_anim_length(anim_name, 1.0), GESTURE_MAX)
	_play(anim_name)
	if with_sound:
		_play_sfx(sfx_phase2, Vector3.INF, GESTURE_VOLUME_DB)
	_set_state(State.ROAR)


## Data for the combat memory: Kaelen, the boss and the live minions.
func _memory_context() -> Dictionary:
	var minion_positions: Array[Vector3] = []
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(&"enemy"):
			var minion := node as Node3D
			if minion and minion != self and minion.is_inside_tree():
				minion_positions.append(minion.global_position)
	var ctx := {
		player_pos = _player.global_position,
		boss_pos = global_position,
		boss_forward = -global_basis.z,
		minions = minion_positions,
		dodge_bias = brain.dodge_bias,
	}
	var player := _player as Player
	if player:
		ctx.player_attacking = player.state == Player.State.ATTACK
		ctx.player_facing = player.get_facing()
		var locked := player.get_lock_target()
		ctx.locked_minion = locked != null and locked.is_in_group(&"enemy")
	return ctx


## Point the current attack aims at: Kaelen's predicted position if it is an intercept attack
## (charge, pounce, beam) and she is moving; otherwise, her.
func _aim_target() -> Vector3:
	return aim_point_for(current_attack.id if current_attack else &"", _player.global_position)


## Also used by GhidorahBeamAim to fix the beam's strip.
func aim_point_for(attack_id: StringName, fallback: Vector3) -> Vector3:
	if tactics_enabled and attack_id in intercept_attacks and memory.samples > 2 and memory.speed > INTERCEPT_MIN_SPEED:
		return _clamp_nav(memory.predict(INTERCEPT_HORIZON))
	return fallback


## Clamps a point to the navigation mesh (the arena). Without a synced mesh (tests, simulation) it changes nothing.
func _clamp_nav(p: Vector3) -> Vector3:
	if agent == null or not is_inside_tree():
		return p
	var map := agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return p
	var q := NavigationServer3D.map_get_closest_point(map, p)
	return Vector3(q.x, p.y, q.z)


func _attack_multipliers() -> Dictionary:
	if tactics_enabled and memory.circling and circling_attack != &"":
		return {circling_attack: circling_bonus}
	return {}


## Fraction of max health lost in the last DAMAGE_WINDOW s.
func _recent_damage() -> float:
	var total := 0
	var kept: Array = []
	for entry: Array in _damage_log:
		if _clock - float(entry[0]) <= DAMAGE_WINDOW:
			kept.append(entry)
			total += int(entry[1])
	_damage_log = kept
	return float(total) / maxf(1.0, float(max_health))


## Shared threat: while the boss warns or attacks, AttackTokens hands no new tokens to the
## minions if Kaelen is near (SquadTactics.token_slots).
func _update_threat() -> void:
	var threatening := state == State.TELEGRAPH or state == State.ACTIVE
	var near := threatening and _player != null and is_instance_valid(_player) \
			and _flat_distance() <= SquadTactics.THREAT_RADIUS
	if threatening == _threat_on and near == _threat_near:
		return
	_publish_threat(threatening, near)


func _publish_threat(threatening: bool, near: bool) -> void:
	_threat_on = threatening
	_threat_near = near
	var tokens := get_node_or_null(^"/root/AttackTokens") if is_inside_tree() else null
	if tokens:
		tokens.call(&"set_boss_threat", threatening, near)


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
	var attack := brain.choose(attacks, distance, phase, _rng, approaching, _attack_multipliers())
	if attack == null:
		return false
	# Ambush: Kaelen distracted (with minions or turned away) → the warning lasts a bit longer.
	var warn_scale := 1.0
	if tactics_enabled and tactics.goal == BossTactics.Goal.ATTACK and memory.distracted and not memory.fleeing:
		warn_scale = BossTactics.AMBUSH_TELEGRAPH
		ambush_count += 1
	_combo_chain = 0
	_start_attack(attack, warn_scale)
	return true


## The follow-up of a phase 2 combo, decided in RECOVER (see combo_follow_up).
func _try_combo(target_ok: bool) -> bool:
	if not target_ok or _pending_repel or _pending_roar or current_attack == null:
		return false
	if repel_enabled and repel.is_due(health.max_value):
		return false   # a due repel wins: it fires at the end of this recovery, as without combos
	if _state_time < current_attack.recovery_time / _speed() * COMBO_RECOVER_FRACTION:
		return false
	var next := combo_follow_up(current_attack, attacks, phase, _flat_distance(), _combo_chain)
	if next == null:
		return false
	_combo_chain += 1
	combo_count += 1
	_cancel_attack()
	_start_attack(next, COMBO_TELEGRAPH)
	return true


## Pure rule of the phase 2 combos: the attack chained after `attack`, or null. Needs phase ≥
## COMBO_PHASE, a free slot in the string, the follow-up in the list (and allowed in this phase)
## and Kaelen within its range ± COMBO_RANGE_SLACK.
static func combo_follow_up(attack: BossAttack, list: Array[BossAttack], phase_now: int, distance: float, chain: int) -> BossAttack:
	if attack == null or attack.combo_next == &"" or phase_now < COMBO_PHASE or chain >= COMBO_MAX_CHAIN:
		return null
	for candidate in list:
		if candidate.id != attack.combo_next:
			continue
		if phase_now < candidate.phase_min:
			return null
		if distance < candidate.min_range - COMBO_RANGE_SLACK or distance > candidate.max_range + COMBO_RANGE_SLACK:
			return null
		return candidate
	return null


func _start_attack(attack: BossAttack, warn_scale: float) -> void:
	brain.reset_chase()
	telegraph_scale = warn_scale
	current_attack = attack
	brain.last_attack_id = attack.id
	attack_log.append(attack.id)
	_hitbox = _hitbox_for(attack)
	_telegraph = _telegraph_for(attack)
	if _telegraph:
		AttackWarning.set_progress(_telegraph as GeometryInstance3D, 0.0)
		_telegraph.visible = true
	if attack.warning != AttackWarning.Level.NONE:
		var warn_time := attack.telegraph_time * telegraph_scale / _speed()
		AttackWarning.aura_to(_model, AttackWarning.color_for(attack.warning), 1.0, AttackWarning.rise_time(warn_time))
	_play(attack.animation)
	if _anim and telegraph_scale != 1.0:
		_anim.speed_scale = _speed() / telegraph_scale
	_set_state(State.TELEGRAPH)
	attack_started.emit(attack)


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
	if current_attack and current_attack.warning != AttackWarning.Level.NONE:
		AttackWarning.aura_to(_model, AttackWarning.color_for(current_attack.warning), 0.0, AttackWarning.AURA_FADE)


## Stops the current attack wherever it is (Kaelen died, phase change or death).
func _cancel_attack() -> void:
	if current_attack == null:
		return
	_end_active()
	current_attack = null
	_hitbox = null
	_telegraph = null
	telegraph_scale = 1.0
	if _anim:
		_anim.speed_scale = _speed()


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
	if state == State.DEAD or is_invulnerable():
		return
	_aggro = true
	var key := source.get_instance_id() if source else 0
	var last: Dictionary = _swing_hits.get(key, {})
	if not last.is_empty() and _clock - float(last.time) <= SAME_SWING_WINDOW:
		var applied: int = last.amount
		if amount > applied:
			last.amount = amount
			_damage_log.append([_clock, amount - applied])
			health.take_damage(amount - applied)
			_register_repel_damage(amount - applied)
		return
	_swing_hits[key] = {time = _clock, amount = amount}
	_damage_log.append([_clock, amount])
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
	_last_repel_clock = _clock
	_cancel_attack()
	_stop()
	repelling = true
	_play(roar_animation)
	_play_sfx(sfx_phase2)
	ImpactFx.seal(self, repel_radius, repel_push_delay)   # the seal is the warning: it closes right before the shockwave
	_set_state(State.ROAR)
	_repel_push_left = repel_push_delay


## Starts the phase-2 roar: interrupts the current action, roars (invulnerable) for PHASE2_ROAR_TIME
## s and fires the repel shockwave after repel_push_delay s. It counts as a repel for the anti-burst
## window (clears it and starts its cooldown, so no second roar follows right after), but not for
## the tactics (no WAIT afterwards: phase 2 is the aggressive one) nor for repel_count.
func start_phase_roar() -> void:
	_pending_roar = false
	_pending_repel = false
	_cancel_attack()
	_stop()
	repel.trigger()
	phase_roaring = true
	_play(roar_animation)
	_play_sfx(sfx_phase2)
	ImpactFx.seal(self, repel_radius, repel_push_delay, "blood")   # same warning as the repel, phase colour
	_set_state(State.ROAR)
	_repel_push_left = repel_push_delay


## True while no damage gets through: repel roar and phase-2 roar.
func is_invulnerable() -> bool:
	return repelling or phase_roaring


## Seconds (game time) the current ROAR lasts: the gesture, the phase roar, the repel roar (clip cut
## to repel_roar_max) or the whole clip, the last two at the phase speed.
func _roar_duration(speed: float) -> float:
	if gesturing:
		return _gesture_len / speed
	if phase_roaring:
		return PHASE2_ROAR_TIME
	var roar_time := _anim_length(roar_animation, 2.0)
	if repelling:
		roar_time = minf(roar_time, repel_roar_max)   # the repel roar is cut short: it must not become a rest
	return roar_time / speed


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
	phase_roaring = false
	gesturing = false
	_play(death_animation)
	_play_sfx(sfx_death)
	_set_state(State.DEAD)
	_stop()
	_update_threat()
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
func _play_sfx(stream: AudioStream, at := Vector3.INF, volume_db := 0.0) -> void:
	if stream == null or not is_inside_tree():
		return
	var audio := get_node_or_null(^"/root/AudioManager")
	if audio:
		audio.play_sfx_3d(stream, global_position if at == Vector3.INF else at, 0.1, volume_db, 16.0)


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
