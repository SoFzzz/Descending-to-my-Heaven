class_name MinionAttack
extends Resource
## One minion attack. A minion with an empty `attacks` list keeps the single classic swing
## (Minion.WINDUP_TIME / ACTIVE_TIME / RECOVER_TIME with `anim_attack`). Ranges are horizontal,
## from the minion's origin to Kaelen's origin.
##
## Timeline: windup → hits × active, with hit_gap between them → recover.

@export var id: StringName
@export var clip: StringName = &"attack"
## Seconds skipped at the start of the clip (long clips with a slow wind-up of their own).
@export var clip_start := 0.0
@export var min_range := 0.0
@export var max_range := 1.5
@export var weight := 1.0
@export var windup := 0.5
@export var active := 0.3
@export var hits := 1
@export var hit_gap := 0.3
@export var recover := 0.8
@export var damage_mult := 1.0
## m/s forward during the active windows (a leap or a lunge). 0 = stays put.
@export var lunge_speed := 0.0
## > 0: the blow is a circle of this radius on the floor instead of the weapon hitbox.
## `zone_at_target` puts it where Kaelen stood when the windup began (a cast); otherwise it
## is centred on the minion (a scream).
@export var zone_radius := 0.0
@export var zone_at_target := false
## Yellow warning aura on the minion during the windup (AttackWarning): its special attacks (leap,
## cast, combos, heavy blows). 0 = none.
@export_range(0, 2) var warning := 0
## Seconds before this attack can be chosen again (the cast: so it mixes in the melee).
@export var cooldown := 0.0

const REPEAT_FACTOR := 0.35   # the same attack twice in a row is less likely


## Time from the start of ATTACK until the last active window ends.
func strike_time() -> float:
	var n := maxi(1, hits)
	return windup + active * n + hit_gap * (n - 1)


func total_time() -> float:
	return strike_time() + recover


## Is a hit window active `t` s after the start of ATTACK?
func is_active_at(t: float) -> bool:
	if t < windup or t >= strike_time():
		return false
	var local := fmod(t - windup, active + hit_gap)
	return local < active


## Index of the hit window at `t` (-1 outside them): a new index means a fresh activation.
func hit_index_at(t: float) -> int:
	if not is_active_at(t):
		return -1
	return int((t - windup) / (active + hit_gap))


func in_range(distance: float) -> bool:
	return distance >= min_range and distance <= max_range


## Weighted pick among the attacks in range; `last_id` is penalised so it does not repeat.
## With nothing in range it returns the one with the smallest min_range (the melee fallback).
## -1 only for an empty list.
static func choose(attacks: Array, distance: float, last_id: StringName, roll: float) -> int:
	if attacks.is_empty():
		return -1
	var weights: Array[float] = []
	var total := 0.0
	for a in attacks:
		var attack := a as MinionAttack
		var w := 0.0
		if attack.in_range(distance):
			w = maxf(0.0, attack.weight)
			if attack.id == last_id and attacks.size() > 1:
				w *= REPEAT_FACTOR
		weights.append(w)
		total += w
	if total <= 0.0:
		var best := 0
		for i in attacks.size():
			if (attacks[i] as MinionAttack).min_range < (attacks[best] as MinionAttack).min_range:
				best = i
		return best
	var pick := clampf(roll, 0.0, 0.999999) * total
	for i in weights.size():
		pick -= weights[i]
		if pick < 0.0:
			return i
	return weights.size() - 1


## Longest reach of the list (the brain starts an attack within it).
static func reach(attacks: Array, fallback: float) -> float:
	var r := 0.0
	for a in attacks:
		r = maxf(r, (a as MinionAttack).max_range)
	return r if r > 0.0 else fallback
