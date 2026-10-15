class_name BossRepel
extends RefCounted
## "Repel" reaction of the bosses, pure logic without nodes (boss.gd owns one per boss).
##
## The boss adds up the damage it takes inside a sliding window of `window` seconds. When that sum
## reaches `threshold_fraction` of its max health and the cooldown is over, the reaction is due: the
## boss roars (same clip and sound as the phase-2 roar, without changing phase) and pushes Kaelen
## away. It keeps her from chaining a long string of hits on the boss.

## Fraction of the max health that, taken within `window` seconds, triggers the reaction.
var threshold_fraction := 0.15
## Length (s) of the sliding window where the damage is added up.
var window := 4.0
## Seconds after a reaction during which it cannot happen again (the damage is not counted either).
var cooldown := 9.0

var _hits: Array[Vector2] = []   # (time, amount)
var _cooldown_left := 0.0
var _clock := 0.0


## Advances time: expires old hits and counts down the cooldown.
func tick(delta: float) -> void:
	_clock += delta
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	while not _hits.is_empty() and _clock - _hits[0].x > window:
		_hits.pop_front()


## Damage inside the current window.
func recent_damage() -> int:
	var total := 0.0
	for h in _hits:
		total += h.y
	return int(total)


func on_cooldown() -> bool:
	return _cooldown_left > 0.0


## Records `amount` of damage and returns true if the reaction must fire now. `blocked`: the boss
## cannot react (phase roar, death, already repelling): the damage is still counted.
func register_damage(amount: int, max_health: int, blocked := false) -> bool:
	if amount <= 0 or on_cooldown():
		return false
	_hits.append(Vector2(_clock, amount))
	return not blocked and is_due(max_health)


## True if the accumulated damage reached the threshold and the cooldown is over.
func is_due(max_health: int) -> bool:
	return not on_cooldown() and max_health > 0 \
		and recent_damage() >= ceili(threshold_fraction * max_health)


## The reaction fired: clears the window and starts the cooldown.
func trigger() -> void:
	_hits.clear()
	_cooldown_left = cooldown


## Horizontal push velocity for a target at `target` from a boss at `origin`: `force` m/s outward,
## or ZERO if it is farther than `radius`. If both overlap, it pushes along `fallback`.
static func push_velocity(origin: Vector3, target: Vector3, radius: float, force: float, fallback := Vector3.BACK) -> Vector3:
	var d := target - origin
	d.y = 0.0
	if d.length() > radius:
		return Vector3.ZERO
	if d.length_squared() < 0.0001:
		d = Vector3(fallback.x, 0.0, fallback.z)
		if d.length_squared() < 0.0001:
			d = Vector3.BACK
	return d.normalized() * force
