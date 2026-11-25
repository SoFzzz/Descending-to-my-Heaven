class_name BossBrain
extends RefCounted
## Boss attack selection by utility (spec §8.2), pure logic without nodes: boss.gd asks for an
## attack with choose() and records what Kaelen does (record_dodge, last_attack_id).
##
## score = base_weight × distance_fit (1 inside [min_range, max_range], 0 outside)
##         × (0.3 if id == last_attack_id, otherwise 1)
##         × (1 + 0.5 × |dodge_bias| if the attack is lateral)
##         × (1.25 if phase == 2)
##         × multipliers[id] (optional: tactical preferences, e.g. tail swipe when Kaelen circles the boss)
## Attacks with phase_min > phase score 0. choose() draws weighted between the 2 best scores.
##
## Chase without progress (track_chase): while the boss is still approaching only `opener` attacks may
## start. A Kaelen that backs off or circles as fast as the boss walks, inside the reach of a normal
## attack, used to be chased forever without a single attack (the Bone Dragon has no openers). When
## the boss has not closed CHASE_PROGRESS m in CHASE_PATIENCE s while she is in reach, the chase is
## "stalled" and the caller lets every attack in range compete.

const REPEAT_PENALTY := 0.3
const PHASE2_MULTIPLIER := 1.25
const LATERAL_BONUS := 0.5
const DODGE_HISTORY := 6
## A still Kaelen is closed at the boss's full speed (≥ 3 m/s: 0.5 m in ≤ 0.17 s), so a stall of
## 0.6 s means the boss gains less than 0.83 m/s on her.
const CHASE_PATIENCE := 0.6
const CHASE_PROGRESS := 0.5

## Id of the last attack used; boss.gd sets it after choose() (choose does not change state).
var last_attack_id: StringName = &""
## Average of the last DODGE_HISTORY dodges: −1 always to the left, +1 always to the right.
var dodge_bias: float = 0.0

var _dodges: Array[int] = []
var _chase_ref := INF       # distance at the last CHASE_PROGRESS m of progress of the current approach
var _chase_stall := 0.0     # seconds without closing CHASE_PROGRESS m


static func score(attack: BossAttack, distance: float, last_attack_id: StringName, dodge_bias: float, phase: int, multipliers := {}) -> float:
	if attack == null or attack.phase_min > phase:
		return 0.0
	if distance < attack.min_range or distance > attack.max_range:
		return 0.0
	var s := attack.base_weight
	if attack.id == last_attack_id:
		s *= REPEAT_PENALTY
	if attack.lateral:
		s *= 1.0 + LATERAL_BONUS * absf(dodge_bias)
	if phase == 2:
		s *= PHASE2_MULTIPLIER
	# Tactical preferences (BossTactics / boss specialisation): id → factor.
	s *= float(multipliers.get(attack.id, 1.0))
	return s


## Weighted draw between the two attacks with the highest score (> 0). Null if none can be used.
## `approaching`: the boss has not reached its engage_range yet, so only `opener` attacks (long
## range) are candidates and the last one used is never repeated (otherwise it would keep
## launching the same far attack instead of closing in).
func choose(attacks: Array[BossAttack], distance: float, phase: int, rng: RandomNumberGenerator, approaching := false, multipliers := {}) -> BossAttack:
	var best: BossAttack = null
	var best_score := 0.0
	var second: BossAttack = null
	var second_score := 0.0
	for attack in attacks:
		if approaching and (not attack.opener or attack.id == last_attack_id):
			continue
		var s := score(attack, distance, last_attack_id, dodge_bias, phase, multipliers)
		if s <= 0.0:
			continue
		if s > best_score:
			second = best
			second_score = best_score
			best = attack
			best_score = s
		elif s > second_score:
			second = attack
			second_score = s
	if second == null:
		return best
	return best if rng.randf() * (best_score + second_score) < best_score else second


## Longest max_range of the attacks usable in `phase` (how far the boss can hit at all).
static func reach(attacks: Array[BossAttack], phase: int) -> float:
	var best := 0.0
	for attack in attacks:
		if attack.phase_min <= phase:
			best = maxf(best, attack.max_range)
	return best


## Call every frame of the approach with Kaelen `in_reach` of some attack. Returns true once the boss
## has gone CHASE_PATIENCE s without getting CHASE_PROGRESS m closer (see the header).
func track_chase(delta: float, distance: float, in_reach: bool) -> bool:
	if not in_reach:
		reset_chase()
		return false
	if distance <= _chase_ref - CHASE_PROGRESS:   # also the first frame (_chase_ref = INF)
		_chase_ref = distance
		_chase_stall = 0.0
		return false
	_chase_stall += delta
	return _chase_stall >= CHASE_PATIENCE


## The approach ended (attack started, engage_range reached, other goal, Kaelen out of reach).
func reset_chase() -> void:
	_chase_ref = INF
	_chase_stall = 0.0


## Seconds the current approach has gone without progress (tests and debug).
func chase_stall_seconds() -> float:
	return _chase_stall


## side: −1 Kaelen rolled to the boss's left, +1 to its right. Keeps the last DODGE_HISTORY.
func record_dodge(side: int) -> void:
	if side == 0:
		return
	_dodges.append(signi(side))
	while _dodges.size() > DODGE_HISTORY:
		_dodges.pop_front()
	var total := 0
	for d in _dodges:
		total += d
	dodge_bias = float(total) / _dodges.size()


## True only when the boss is still in phase 1, alive, and its health reached 50 % or less.
static func should_enter_phase2(current: int, max_value: int, phase: int) -> bool:
	return phase == 1 and current > 0 and current * 2 <= max_value
