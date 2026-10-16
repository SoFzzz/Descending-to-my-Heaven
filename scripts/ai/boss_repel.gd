class_name BossRepel
extends RefCounted
## "Repel" reaction of the bosses, pure logic without nodes (boss.gd owns one per boss).
##
## The reaction is due (once the cooldown is over) when ANY of these happens:
##  - the boss took `threshold_fraction` of its max health within `window` seconds (burst damage);
##  - it took `burst_hits` hits within `burst_window` seconds (fast chaining, whatever the damage);
##  - Kaelen stayed within `glue_radius` of it for `glue_time` seconds (see register_proximity).
## The boss then roars (same clip and sound as the phase-2 roar, without changing phase) and pushes
## Kaelen away. It keeps her from chaining a long string of hits or hiding under its belly.

## Fraction of the max health that, taken within `window` seconds, triggers the reaction.
var threshold_fraction := 0.10
## Length (s) of the sliding window where the damage is added up.
var window := 4.0
## Seconds after a reaction during which it cannot happen again (the damage is not counted either).
var cooldown := 7.0
## Number of hits inside `burst_window` s that also triggers it.
var burst_hits := 3
var burst_window := 3.0
## Seconds that Kaelen may stay within `glue_radius` m of the boss before it reacts. Time away from
## the boss drains the counter twice as fast.
var glue_time := 7.0
var glue_radius := 3.2

var _hits: Array[Vector2] = []   # (time, amount)
var _cooldown_left := 0.0
var _clock := 0.0
var _glue := 0.0


## Advances time: expires old hits and counts down the cooldown.
func tick(delta: float) -> void:
	_clock += delta
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	while not _hits.is_empty() and _clock - _hits[0].x > maxf(window, burst_window):
		_hits.pop_front()


## Hits inside the burst window.
func recent_hits() -> int:
	var n := 0
	for h in _hits:
		if _clock - h.x <= burst_window:
			n += 1
	return n


## Seconds Kaelen has been stuck to the boss (for tests and debug).
func glue_seconds() -> float:
	return _glue


## Counts how long Kaelen stays close: `close` is true while she is within `glue_radius` of the
## boss. Returns true when that time reaches `glue_time` (and the cooldown is over).
func register_proximity(delta: float, close: bool, blocked := false) -> bool:
	if on_cooldown():
		_glue = 0.0
		return false
	if close:
		_glue += delta
	else:
		_glue = maxf(0.0, _glue - 2.0 * delta)
	return not blocked and _glue >= glue_time


## Damage inside the current window.
func recent_damage() -> int:
	var total := 0.0
	for h in _hits:
		if _clock - h.x <= window:
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


## True if any of the three conditions is met and the cooldown is over.
func is_due(max_health: int) -> bool:
	if on_cooldown() or max_health <= 0:
		return false
	return recent_damage() >= ceili(threshold_fraction * max_health) \
		or recent_hits() >= burst_hits or _glue >= glue_time


## The reaction fired: clears the window and starts the cooldown.
func trigger() -> void:
	_hits.clear()
	_glue = 0.0
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
