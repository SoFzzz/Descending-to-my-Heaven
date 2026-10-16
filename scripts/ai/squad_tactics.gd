class_name SquadTactics
extends RefCounted
## Coordinación jefe + esbirros (lógica pura): puntos de cerco para la pinza y reparto de amenazas
## simultáneas. El Orquestador aplica las órdenes y AttackTokens aplica el límite de amenazas.

## Distancia al jefe (m) a partir de la cual su ataque cuenta como amenaza "cercana" para Kaelen.
const THREAT_RADIUS := 10.0
## Radio (m) alrededor de Kaelen en el que se colocan los esbirros de la pinza (< TOKEN_RANGE de
## los esbirros: al llegar quedan en CIRCLE y pueden pedir ficha).
const PINCER_RADIUS := 3.6
## Separación angular (grados) entre esbirros vecinos del cerco.
const PINCER_SPREAD_DEG := 55.0
## Distancia a Kaelen a la que el jefe se planta en su lado de la pinza.
const BOSS_PINCER_DISTANCE := 6.0


## Puntos de cerco de `count` esbirros alrededor de Kaelen, en el lado OPUESTO al jefe: el centro
## del abanico queda exactamente a 180° del jefe visto desde Kaelen. Todos a `radius` de ella.
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


## Dónde se planta el jefe: en su lado actual de Kaelen, a `distance` de ella (la pinza es jefe de
## un lado, esbirros del otro).
static func boss_pincer_point(player_pos: Vector3, boss_pos: Vector3, distance := BOSS_PINCER_DISTANCE) -> Vector3:
	var away := Vector3(boss_pos.x - player_pos.x, 0.0, boss_pos.z - player_pos.z)
	if away.length_squared() < 0.0001:
		away = Vector3.BACK
	var p := player_pos + away.normalized() * distance
	p.y = boss_pos.y
	return p


## Reparto voraz de puntos a esbirros (el más cercano primero): devuelve, por esbirro, el índice
## del punto asignado. Con más esbirros que puntos, el sobrante recibe -1.
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


## Fichas de ataque disponibles para esbirros mientras el jefe amenaza. Si no amenaza: `max_tokens`.
## Si amenaza cerca de Kaelen: 0 (ningún esbirro inicia ataque). Si amenaza lejos (el rayo): una
## ficha menos (como máximo max_tokens - 1 amenazas de esbirros más la del jefe).
static func token_slots(boss_threat: bool, boss_near: bool, max_tokens: int) -> int:
	if not boss_threat:
		return max_tokens
	if boss_near:
		return 0
	return maxi(0, max_tokens - 1)


## ¿El esbirro puede empezar un ataque ahora? (ficha + límite de amenazas simultáneas).
static func may_start_attack(holds_token: bool, boss_threat: bool, boss_near: bool) -> bool:
	return holds_token and not (boss_threat and boss_near)
