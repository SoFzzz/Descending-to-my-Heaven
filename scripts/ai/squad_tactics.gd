class_name SquadTactics
extends RefCounted
## Boss + minion coordination (pure logic): encirclement points for the pincer and sharing of
## simultaneous threats. The Orchestrator applies the orders and AttackTokens applies the threat limit.

## Distance to the boss (m) within which its attack counts as a "near" threat to Kaelen.
const THREAT_RADIUS := 10.0
## Radius (m) around Kaelen at which the pincer minions are placed (< the minions' TOKEN_RANGE:
## on arrival they are in CIRCLE and can ask for a token).
const PINCER_RADIUS := 3.6
## Angular separation (degrees) between neighbouring minions of the encirclement.
const PINCER_SPREAD_DEG := 55.0
## Distance to Kaelen at which the boss plants itself on its side of the pincer.
const BOSS_PINCER_DISTANCE := 6.0


## Encirclement points of `count` minions around Kaelen, on the side OPPOSITE the boss: the centre
## of the fan is exactly 180° from the boss as seen from Kaelen. All at `radius` from her.
static func pincer_points(player_pos: Vector3, boss_pos: Vector3, count: int, radius := PINCER_RADIUS, spread_deg := PINCER_SPREAD_DEG) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if count <= 0:
		return points
	var to_boss := Vector3(boss_pos.x - player_pos.x, 0.0, boss_pos.z - player_pos.z)
	var base := atan2(to_boss.z, to_boss.x) + PI if to_boss.length_squared() > 0.0001 else PI
	for i in count:
		var offset := (float(i) - (count - 1) * 0.5) * deg_to_rad(spread_deg)
		var angle := base + offset
		points.append(Vector3(player_pos.x + cos(angle) * radius, player_pos.y, player_pos.z + sin(angle) * radius))
	return points


## Where the boss plants itself: on its current side of Kaelen, `distance` away from her (the pincer is
## boss on one side, minions on the other).
static func boss_pincer_point(player_pos: Vector3, boss_pos: Vector3, distance := BOSS_PINCER_DISTANCE) -> Vector3:
	var away := Vector3(boss_pos.x - player_pos.x, 0.0, boss_pos.z - player_pos.z)
	if away.length_squared() < 0.0001:
		away = Vector3.BACK
	var p := player_pos + away.normalized() * distance
	p.y = boss_pos.y
	return p


## Greedy assignment of points to minions (closest pair first): returns, per minion, the index
## of its assigned point. With more minions than points, the surplus gets -1.
static func assign_points(from: Array[Vector3], to: Array[Vector3]) -> Array[int]:
	var result: Array[int] = []
	result.resize(from.size())
	result.fill(-1)
	var taken: Array[bool] = []
	taken.resize(to.size())
	taken.fill(false)
	var pairs: Array = []
	for i in from.size():
		for j in to.size():
			pairs.append([from[i].distance_squared_to(to[j]), i, j])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for pair: Array in pairs:
		var i: int = pair[1]
		var j: int = pair[2]
		if result[i] == -1 and not taken[j]:
			result[i] = j
			taken[j] = true
	return result


## Attack tokens available to minions while the boss threatens. If it does not: `max_tokens`.
## If it threatens near Kaelen: 0 (no minion starts an attack). If it threatens from afar (the beam): one
## token fewer (at most max_tokens - 1 minion threats plus the boss's).
static func token_slots(boss_threat: bool, boss_near: bool, max_tokens: int) -> int:
	if not boss_threat:
		return max_tokens
	if boss_near:
		return 0
	return maxi(0, max_tokens - 1)


## Can the minion start an attack now? (token + limit of simultaneous threats).
static func may_start_attack(holds_token: bool, boss_threat: bool, boss_near: bool) -> bool:
	return holds_token and not (boss_threat and boss_near)
