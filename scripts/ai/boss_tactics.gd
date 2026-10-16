class_name BossTactics
extends RefCounted
## Utility-based tactical goals of the boss (pure logic). A layer ABOVE BossBrain: BossBrain decides
## WHICH attack to use; this decides WHAT THE BOSS DOES while it is not in the middle of an attack:
##   ATTACK    close in and attack (the classic behaviour)
##   CUT_OFF   cut her off: go to Kaelen's predicted point (or to what she is chasing) instead of
##             following her from behind
##   WAIT      stop attacking for a moment: back off / circle her at mid distance (a readable breather)
##   PINCER    pincer: the boss plants itself on its side of Kaelen and the minions close in on the other
## It is not a planner: each goal has a score (it evaluates the context) and the best one is picked
## with hysteresis (the current goal scores x HYSTERESIS and must be kept for MIN_HOLD s), a maximum
## duration and a per-goal cooldown so they cannot chain forever.
##
## ctx = {distance, fleeing, with_minions, glued, passive, distracted, health_ratio, phase,
##        minions_alive, recent_damage (fraction of max health lost in the last 4 s),
##        since_repel (s since the last repel), engage_range}. Missing keys default to 0 / false.

enum Goal { ATTACK, CUT_OFF, WAIT, PINCER }

const GOAL_NAMES: Array[String] = ["ATTACK", "CUT OFF", "WAIT", "PINCER"]

const EVAL_INTERVAL := 0.5
const MIN_HOLD := 1.0
const HYSTERESIS := 1.3
## Maximum duration of each goal (s) and cooldown (s) before it can be repeated. ATTACK never expires.
const MAX_TIME: Dictionary = {Goal.CUT_OFF: 4.0, Goal.WAIT: 2.4, Goal.PINCER: 4.0}
const COOLDOWN: Dictionary = {Goal.CUT_OFF: 2.5, Goal.WAIT: 7.0, Goal.PINCER: 9.0}

const COMBO_DAMAGE := 0.16         # fraction of health lost in 4 s that counts as a "long combo"
const REPEL_RECOVERY := 3.0        # s after a repel during which it prefers to wait
const LOW_HEALTH := 0.3
const CUT_OFF_MIN_DISTANCE := 6.0
const WAIT_RING := 8.0             # distance to Kaelen at which it waits
const AMBUSH_SPEED := 0.6          # speed factor when stalking a distracted Kaelen
const AMBUSH_TELEGRAPH := 1.3      # warning factor of the ambush attack
const AMBUSH_MAX_DISTANCE := 14.0

var goal: Goal = Goal.ATTACK
var goal_time := 0.0
var last_scores: Dictionary = {}
## Seconds accumulated in each goal and times it was entered (statistics for the simulation).
var time_in_goal: Dictionary = {Goal.ATTACK: 0.0, Goal.CUT_OFF: 0.0, Goal.WAIT: 0.0, Goal.PINCER: 0.0}
var entries: Dictionary = {Goal.ATTACK: 0, Goal.CUT_OFF: 0, Goal.WAIT: 0, Goal.PINCER: 0}

var _eval_timer := 0.0
var _cooldowns: Dictionary = {}


## Score of each goal for the context (without hysteresis or cooldowns).
static func score_goals(ctx: Dictionary) -> Dictionary:
	var distance: float = ctx.get("distance", 0.0)
	var fleeing: bool = ctx.get("fleeing", false)
	var with_minions: bool = ctx.get("with_minions", false)
	var passive: bool = ctx.get("passive", false)
	var health: float = ctx.get("health_ratio", 1.0)
	var phase: int = ctx.get("phase", 1)
	var minions: int = ctx.get("minions_alive", 0)
	var recent: float = ctx.get("recent_damage", 0.0)
	var since_repel: float = ctx.get("since_repel", 99.0)
	var aggressive := 1.25 if phase >= 2 else 1.0

	# ATTACK: the baseline; devalued when there is nothing to hit (she is far away, fleeing).
	var attack := 1.0 * aggressive
	if fleeing and distance > CUT_OFF_MIN_DISTANCE:
		attack = 0.45
	elif distance > 14.0:
		attack = 0.6

	# CUT_OFF: only if she flees / moves away, or is passive at a distance.
	var cut := 0.0
	if distance > CUT_OFF_MIN_DISTANCE:
		if fleeing:
			cut = 1.5 + 0.04 * minf(distance, 14.0)
		elif passive and distance > 10.0:
			cut = 0.9
	cut *= (1.15 if phase >= 2 else 1.0)

	# WAIT: breathers. Long combo, recent repel, low health or a passive Kaelen.
	var wait := 0.0
	if recent >= COMBO_DAMAGE:
		wait += 1.4
	if since_repel < REPEL_RECOVERY:
		wait += 1.5
	if health < LOW_HEALTH and not fleeing:
		wait += 0.5
	if passive and distance < 16.0:
		wait += 1.1
	if fleeing:
		wait *= 0.3
	wait *= (0.6 if phase >= 2 else 1.0)   # phase 2 is more aggressive

	# PINCER: Kaelen between the boss and the minions, or heading for them.
	var pincer := 0.0
	if minions >= 1 and with_minions and distance > 4.0 and distance < 18.0:
		pincer = 1.5 + (0.3 if minions >= 2 else 0.0)
		pincer *= (1.2 if phase >= 2 else 1.0)

	return {Goal.ATTACK: attack, Goal.CUT_OFF: cut, Goal.WAIT: wait, Goal.PINCER: pincer}


## Advances the clocks by `delta` s (the boss calls it EVERY frame, also in the middle of an attack).
func advance(delta: float) -> void:
	goal_time += delta
	time_in_goal[goal] += delta
	for g in _cooldowns.keys():
		_cooldowns[g] = maxf(0.0, float(_cooldowns[g]) - delta)
	_eval_timer += delta


## Re-evaluates the goal if EVAL_INTERVAL s have passed since the last time (the boss calls it only when it is NOT
## in the middle of an attack). Returns true if the goal changed.
func step(ctx: Dictionary) -> bool:
	if _eval_timer < EVAL_INTERVAL:
		return false
	_eval_timer = 0.0
	return reevaluate(ctx)


## True when the next step() will re-evaluate (lets the caller skip building the context otherwise).
func eval_due() -> bool:
	return _eval_timer >= EVAL_INTERVAL


## advance + step (convenience and tests).
func update(delta: float, ctx: Dictionary) -> bool:
	advance(delta)
	return step(ctx)


## Asks to re-evaluate on the next step (when leaving a recovery or a roar: time to decide).
func request_eval() -> void:
	_eval_timer = EVAL_INTERVAL


## Re-evaluates right now (without waiting for the interval). Returns true if the goal changed.
func reevaluate(ctx: Dictionary) -> bool:
	var scores := score_goals(ctx)
	for g in _cooldowns.keys():
		if float(_cooldowns[g]) > 0.0 and g != goal:
			scores[g] = 0.0
	last_scores = scores
	# Duration cap: the goal expired, go back to ATTACK (with a cooldown).
	if goal != Goal.ATTACK and goal_time >= float(MAX_TIME[goal]):
		_enter(Goal.ATTACK, true)
		return true
	var current: float = scores[goal] * HYSTERESIS
	var best := goal
	var best_score := current
	for g in scores.keys():
		if g != goal and float(scores[g]) > best_score:
			best = g
			best_score = float(scores[g])
	if best == goal:
		# The current goal no longer makes sense (scores 0 and is not ATTACK): drop it without waiting.
		if goal != Goal.ATTACK and float(scores[goal]) <= 0.0 and goal_time >= MIN_HOLD * 0.5:
			_enter(Goal.ATTACK, true)
			return true
		return false
	if goal_time < MIN_HOLD:
		return false
	_enter(best, goal != Goal.ATTACK)
	return true


func goal_name() -> String:
	return GOAL_NAMES[int(goal)]


func _enter(next: Goal, start_cooldown: bool) -> void:
	if start_cooldown and goal != Goal.ATTACK:
		_cooldowns[goal] = float(COOLDOWN[goal])
	goal = next
	goal_time = 0.0
	entries[next] = int(entries[next]) + 1


# --- Goal geometry -------------------------------------------------------------------------

## Ambush: Kaelen distracted (with minions or turned away) and the boss still far, but not too far.
static func is_ambush(distracted: bool, fleeing: bool, distance: float, engage_range: float) -> bool:
	return distracted and not fleeing and distance > engage_range and distance < AMBUSH_MAX_DISTANCE


## Point the boss goes to cut her off: Kaelen's predicted position (the one CombatMemory.predict
## gives at about 1.5 s), which lies ahead of her escape, not behind it.
static func cut_off_point(predicted: Vector3, boss_pos: Vector3) -> Vector3:
	return Vector3(predicted.x, boss_pos.y, predicted.z)


## Point the boss walks toward while WAITing: circles Kaelen at `ring` m (tangent + radial correction,
## like the minions' orbit). `side`: ±1, direction of the circling.
static func wait_point(boss_pos: Vector3, player_pos: Vector3, side: float, ring := WAIT_RING, lookahead := 3.0) -> Vector3:
	var offset := Vector3(boss_pos.x - player_pos.x, 0.0, boss_pos.z - player_pos.z)
	if offset.length_squared() < 0.01:
		offset = Vector3.BACK
	var radial := offset.normalized()
	var tangent := Vector3.UP.cross(radial) * side
	var error := clampf((ring - offset.length()) / 3.0, -1.0, 1.0)
	var dir := (tangent * 0.6 + radial * error * 1.2).normalized()
	return Vector3(boss_pos.x + dir.x * lookahead, boss_pos.y, boss_pos.z + dir.z * lookahead)
