class_name CombatMemory
extends RefCounted
## Shared combat memory (inspired by F.E.A.R.'s "working memory"): pure logic, no nodes. The boss
## feeds it ~10 times per second with what it sees (Kaelen, itself, the minions) and the rest of the
## AI (BossTactics, the Orchestrator, the F3 overlay) reads from here instead of recomputing. It keeps
## Kaelen's SMOOTHED position and velocity, a predicted position ~1 s ahead and a detected behaviour:
##   FLEEING        the distance to the boss keeps growing
##   WITH_MINIONS   her locked target / the one she strikes is a minion, the nearest one is much
##                  closer than the boss, or she heads for one with determination
##   GLUED          has been next to the boss for a while
##   PASSIVE        far from the boss, not attacking and not fleeing
## It also keeps independent flags (`fleeing`, `with_minions`, `distracted`, `circling`...) because
## they can hold at once (fleeing toward the minions); `behavior` is the main one.

enum Behavior { NEUTRAL, FLEEING, WITH_MINIONS, GLUED, PASSIVE }

const BEHAVIOR_NAMES: Array[String] = ["NEUTRAL", "FLEEING", "WITH MINIONS", "GLUED", "PASSIVE"]

const SAMPLE_DT := 0.1             # sampling period (s)
const VEL_SMOOTH := 0.35           # weight of the new sample in the velocity moving average
const RATE_SMOOTH := 0.3           # same for the rate of change of the distance to the boss
const HORIZON := 1.0               # s of the default predicted position
const MAX_LEAD_SPEED := 7.0        # m/s: the speed used to predict is capped (roll)
const FLEE_RATE := 1.0             # m/s of distance increase that counts as moving away
const FLEE_MIN_SPEED := 2.2        # minimum m/s of Kaelen to consider her fleeing
const FLEE_TIME := 0.8             # sustained s to declare FLEEING
const FLEE_MIN_DISTANCE := 4.5
const FLEE_FORGET := 1.2           # s of calm before she stops being considered fleeing (hysteresis)
const GLUE_RADIUS := 3.8
const GLUE_TIME := 2.0
const PASSIVE_DISTANCE := 7.0
const PASSIVE_TIME := 3.0
const MINION_NEAR := 3.0           # minion closer than this while she attacks = her target
const MINION_HEADING_DISTANCE := 9.0
const HEADING_DOT := 0.75          # cos of the angle between her velocity and the direction to the minion
const HEADING_MIN_SPEED := 2.0
const AWAY_DOT := -0.3             # back to the boss: her facing · direction to the boss is below this
const CIRCLE_DISTANCE := 7.0
const CIRCLE_SPEED := 2.2          # tangential m/s around the boss
const CIRCLE_TIME := 0.5

# What is known about Kaelen (everything flat in XZ except `position.y`).
var position := Vector3.ZERO
var velocity := Vector3.ZERO       # smoothed
var speed := 0.0
var distance := 0.0                # to the boss
var distance_rate := 0.0           # m/s, smoothed (> 0: moving away)
var minions_alive := 0
var nearest_minion_distance := INF # from Kaelen to the nearest minion
var nearest_minion_position := Vector3.ZERO
var dodge_side := 0.0              # roll bias (BossBrain.dodge_bias): -1 left ... +1 right

# Detected behaviour.
var behavior: Behavior = Behavior.NEUTRAL
var fleeing := false
var with_minions := false
var glued := false
var passive := false
var distracted := false
var circling := false
var attacking := false             # Kaelen is attacking right now
var samples := 0

var _acc := 0.0
var _has_last := false
var _last_pos := Vector3.ZERO
var _flee_time := 0.0
var _calm_time := 0.0
var _glue_time := 0.0
var _passive_time := 0.0
var _circle_time := 0.0


## Forgets everything learned (new arena / Kaelen died).
func reset() -> void:
	var fresh := CombatMemory.new()
	for prop in ["position", "velocity", "speed", "distance", "distance_rate", "minions_alive",
			"nearest_minion_distance", "nearest_minion_position", "dodge_side", "behavior", "fleeing",
			"with_minions", "glued", "passive", "distracted", "circling", "attacking", "samples",
			"_acc", "_has_last", "_last_pos", "_flee_time", "_calm_time", "_glue_time",
			"_passive_time", "_circle_time"]:
		set(prop, fresh.get(prop))


## Accumulates time; returns the accumulated seconds when it is time to sample (every SAMPLE_DT), else 0.
## That way the feeder only builds the context (group queries, etc.) when needed.
func tick(delta: float) -> float:
	_acc += delta
	if _acc < SAMPLE_DT - 0.0001:
		return 0.0
	var dt := _acc
	_acc = 0.0
	return dt


## tick + observe in one call (tests). Returns true if it sampled.
func feed(delta: float, ctx: Dictionary) -> bool:
	var dt := tick(delta)
	if dt <= 0.0:
		return false
	observe(dt, ctx)
	return true


## One sample of `dt` s. ctx:
##   player_pos, boss_pos, boss_forward (Vector3, flat), player_facing (Vector3, optional),
##   player_attacking (bool), locked_minion (bool: her locked target is a minion),
##   minions (Array[Vector3]), dodge_bias (float)
func observe(dt: float, ctx: Dictionary) -> void:
	dt = maxf(dt, 0.001)
	var player_pos: Vector3 = ctx.get("player_pos", position)
	var boss_pos: Vector3 = ctx.get("boss_pos", Vector3.ZERO)
	var boss_forward: Vector3 = ctx.get("boss_forward", Vector3.FORWARD)
	var facing: Vector3 = ctx.get("player_facing", Vector3.ZERO)
	attacking = ctx.get("player_attacking", false)
	dodge_side = ctx.get("dodge_bias", dodge_side)
	var minions: Array = ctx.get("minions", [])
	var prev_distance := distance

	# --- Smoothed position, velocity and distance ---
	if _has_last:
		var raw := (player_pos - _last_pos) / dt
		raw.y = 0.0
		velocity = velocity.lerp(raw, VEL_SMOOTH)
	_last_pos = player_pos
	_has_last = true
	position = player_pos
	speed = Vector2(velocity.x, velocity.z).length()
	distance = _flat(player_pos - boss_pos).length()
	if samples > 0:
		distance_rate = lerpf(distance_rate, (distance - prev_distance) / dt, RATE_SMOOTH)
	samples += 1

	# --- Minions ---
	minions_alive = minions.size()
	nearest_minion_distance = INF
	for m: Vector3 in minions:
		var d := _flat(m - player_pos).length()
		if d < nearest_minion_distance:
			nearest_minion_distance = d
			nearest_minion_position = m

	# --- Fleeing: sustained distance increase at good speed ---
	var running_away := distance_rate > FLEE_RATE and speed > FLEE_MIN_SPEED
	if running_away:
		_flee_time += dt
		_calm_time = 0.0
	else:
		_calm_time += dt
		if _calm_time >= FLEE_FORGET:
			_flee_time = 0.0
	fleeing = _flee_time >= FLEE_TIME and distance >= FLEE_MIN_DISTANCE

	# --- With minions ---
	var heading_to_minion := false
	if minions_alive > 0 and speed > HEADING_MIN_SPEED and nearest_minion_distance < MINION_HEADING_DISTANCE:
		var to_minion := _flat(nearest_minion_position - player_pos)
		if to_minion.length() > 0.1:
			heading_to_minion = _flat(velocity).normalized().dot(to_minion.normalized()) > HEADING_DOT
	var target_is_minion: bool = ctx.get("locked_minion", false) and minions_alive > 0
	var striking_minion := attacking and nearest_minion_distance < MINION_NEAR
	var minion_closer := minions_alive > 0 and distance > 5.0 and nearest_minion_distance < distance * 0.5
	with_minions = target_is_minion or striking_minion or heading_to_minion or minion_closer

	# --- Glued / passive ---
	if distance <= GLUE_RADIUS:
		_glue_time += dt
	else:
		_glue_time = maxf(0.0, _glue_time - dt * 2.0)
	glued = _glue_time >= GLUE_TIME
	if distance >= PASSIVE_DISTANCE and not attacking and not fleeing and not with_minions:
		_passive_time += dt
	else:
		_passive_time = 0.0
	passive = _passive_time >= PASSIVE_TIME

	# --- Circling the boss (high tangential speed, close) ---
	var radial := _flat(player_pos - boss_pos)
	var tangential := 0.0
	if radial.length() > 0.1:
		var r := radial.normalized()
		tangential = absf(velocity.x * -r.z + velocity.z * r.x)
	if distance < CIRCLE_DISTANCE and tangential > CIRCLE_SPEED:
		_circle_time += dt
	else:
		_circle_time = maxf(0.0, _circle_time - dt)
	circling = _circle_time >= CIRCLE_TIME

	# --- Distracted: minions, or back to the boss ---
	var turned_away := false
	if facing.length_squared() > 0.01 and distance > 3.0:
		var to_boss := _flat(boss_pos - player_pos).normalized()
		turned_away = _flat(facing).normalized().dot(to_boss) < AWAY_DOT
	distracted = (with_minions and not fleeing) or (turned_away and not fleeing)
	if boss_forward.length_squared() < 0.0001:
		circling = false

	# --- Main behaviour (priority order) ---
	if glued:
		behavior = Behavior.GLUED
	elif fleeing:
		behavior = Behavior.FLEEING
	elif with_minions:
		behavior = Behavior.WITH_MINIONS
	elif passive:
		behavior = Behavior.PASSIVE
	else:
		behavior = Behavior.NEUTRAL


## Predicted position of Kaelen at `horizon` s (smoothed, capped velocity). If `bounds` is given
## (a Callable Vector3 → Vector3, e.g. the closest navmesh point) the result is limited with it.
func predict(horizon := HORIZON, bounds := Callable()) -> Vector3:
	var v := Vector3(velocity.x, 0.0, velocity.z)
	if v.length() > MAX_LEAD_SPEED:
		v = v.normalized() * MAX_LEAD_SPEED
	var p := position + v * horizon
	if bounds.is_valid():
		p = bounds.call(p)
	return p


## Flat direction of Kaelen's movement (zero if she is still).
func heading() -> Vector3:
	var v := Vector3(velocity.x, 0.0, velocity.z)
	return v.normalized() if v.length() > 0.2 else Vector3.ZERO


func behavior_name() -> String:
	return BEHAVIOR_NAMES[clampi(int(behavior), 0, BEHAVIOR_NAMES.size() - 1)]


## Limits `p` to a disc (centre and radius in XZ): the pure version of "inside the arena".
static func clamp_to_disc(p: Vector3, center: Vector3, radius: float) -> Vector3:
	var offset := Vector3(p.x - center.x, 0.0, p.z - center.z)
	if offset.length() <= radius or radius <= 0.0:
		return p
	var limited := offset.normalized() * radius
	return Vector3(center.x + limited.x, p.y, center.z + limited.z)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
