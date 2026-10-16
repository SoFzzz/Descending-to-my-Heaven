class_name MinionBrain
extends RefCounted
## Minion state machine (spec §8.1), pure logic without nodes: minion.gd builds the context
## every frame and applies the state returned by next_state.
##
## ctx = {distance, sees_player, has_token, attack_finished, recover_finished, stun_finished,
##        was_hit, is_dead}. `stun_finished` was added to the plan's contract: it signals that the
## 0.4 s of STUNNED have passed. Missing keys default to 0 / false.
##
## Rules:
## - is_dead → DEAD from any state; DEAD is never left.
## - was_hit → STUNNED (interrupts everything, also restarts a STUNNED in progress).
## - STUNNED → CHASE when finished (it already knows where Kaelen is); ATTACK → RECOVER → CHASE.
## - IDLE → CHASE only if it sees the player (radius + cone + line of sight).
## - CHASE/CIRCLE: with a token and at ≤ attack_range → ATTACK; without a token at ≤ circle_range → CIRCLE;
##   CIRCLE returns to CHASE if Kaelen moves beyond circle_exit_range or if the token is granted
##   outside the attack range. Losing line of sight is not enough to forget her (a pillar can block it):
##   it returns to IDLE only if it is also farther than lose_radius.

enum State { IDLE, CHASE, CIRCLE, ATTACK, RECOVER, STUNNED, DEAD }

const DETECT_RADIUS := 12.0
const FOV_DEG := 110.0

## Tactical retreat (stop attacking): a NORMAL minion with health below RETREAT_HEALTH
## backs off for RETREAT_TIME s to ~RETREAT_DISTANCE m from Kaelen and comes back (once per life).
const RETREAT_HEALTH := 0.3
const RETREAT_TIME := 3.5
const RETREAT_DISTANCE := 9.0

var attack_range := 1.5
var circle_range := 4.0
var circle_exit_range := 5.0   # hysteresis so CHASE/CIRCLE does not flicker at the border
var lose_radius := DETECT_RADIUS


func next_state(state: State, ctx: Dictionary) -> State:
	if state == State.DEAD or ctx.get("is_dead", false):
		return State.DEAD
	if ctx.get("was_hit", false):
		return State.STUNNED
	var distance: float = ctx.get("distance", INF)
	var sees: bool = ctx.get("sees_player", false)
	var token: bool = ctx.get("has_token", false)
	match state:
		State.IDLE:
			return State.CHASE if sees else State.IDLE
		State.STUNNED:
			return State.CHASE if ctx.get("stun_finished", false) else State.STUNNED
		State.ATTACK:
			return State.RECOVER if ctx.get("attack_finished", false) else State.ATTACK
		State.RECOVER:
			return State.CHASE if ctx.get("recover_finished", false) else State.RECOVER
		State.CHASE, State.CIRCLE:
			if not sees and distance > lose_radius:
				return State.IDLE
			if token and distance <= attack_range:
				return State.ATTACK
			if token:
				return State.CHASE
			if distance <= circle_range:
				return State.CIRCLE
			if state == State.CIRCLE and distance <= circle_exit_range:
				return State.CIRCLE
			return State.CHASE
	return state


## Should it retreat now? Only normal minions (not elites), once, with health below the threshold.
static func should_retreat(hp_ratio: float, is_elite: bool, already_retreated: bool) -> bool:
	return not is_elite and not already_retreated and hp_ratio > 0.0 and hp_ratio < RETREAT_HEALTH


## Point it flees to: away from Kaelen, along the line joining them, `lookahead` m from its position.
static func retreat_point(from: Vector3, player_pos: Vector3, lookahead := 6.0) -> Vector3:
	var away := Vector3(from.x - player_pos.x, 0.0, from.z - player_pos.z)
	if away.length_squared() < 0.0001:
		away = Vector3.BACK
	return from + away.normalized() * lookahead


## Radius + horizontal cone (no raycast: minion.gd checks the line of sight).
static func can_see(from: Vector3, forward: Vector3, to: Vector3, radius := DETECT_RADIUS, fov_deg := FOV_DEG) -> bool:
	var offset := to - from
	if offset.length() > radius:
		return false
	var flat := Vector3(offset.x, 0.0, offset.z)
	var fwd := Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() < 0.0001:
		return true   # directly above / below: counts as seen
	if fwd.length_squared() < 0.0001:
		return false
	return rad_to_deg(fwd.angle_to(flat)) <= fov_deg * 0.5
