class_name BossTactics
extends RefCounted
## Metas tácticas del jefe por utilidad (lógica pura). Una capa POR ENCIMA de BossBrain: BossBrain
## decide QUÉ ataque usar; aquí se decide QUÉ HACE el jefe mientras no está en mitad de un ataque:
##   ATTACK    acercarse y atacar (el comportamiento clásico)
##   CUT_OFF   cortar el paso: ir al punto previsto de Kaelen (o a lo que ella persigue) en vez de
##             seguirla por detrás
##   WAIT      dejar de atacar un momento: retroceder/rodearla a media distancia (respiro legible)
##   PINCER    pinza: el jefe se planta en su lado de Kaelen y los esbirros cierran por el contrario
## No es un planificador: cada meta tiene una puntuación (evalúa el contexto) y se elige la mejor
## con histéresis (la meta actual puntúa ×HYSTERESIS y debe mantenerse MIN_HOLD s) y tope de
## duración + enfriamiento por meta para que no se encadenen sin fin.
##
## ctx = {distance, fleeing, with_minions, glued, passive, distracted, health_ratio, phase,
##        minions_alive, recent_damage (fracción de la vida máxima perdida en los últimos 4 s),
##        since_repel (s desde la última repulsión), engage_range}. Las claves que falten valen 0/false.

enum Goal { ATTACK, CUT_OFF, WAIT, PINCER }

const GOAL_NAMES: Array[String] = ["ATACAR", "CORTAR PASO", "ESPERAR", "PINZA"]

const EVAL_INTERVAL := 0.5
const MIN_HOLD := 1.0
const HYSTERESIS := 1.3
## Duración máxima de cada meta (s) y enfriamiento (s) antes de poder repetirla. ATTACK no caduca.
const MAX_TIME: Dictionary = {Goal.CUT_OFF: 4.0, Goal.WAIT: 2.4, Goal.PINCER: 4.0}
const COOLDOWN: Dictionary = {Goal.CUT_OFF: 2.5, Goal.WAIT: 7.0, Goal.PINCER: 9.0}

const COMBO_DAMAGE := 0.16         # fracción de vida perdida en 4 s que cuenta como "combo largo"
const REPEL_RECOVERY := 3.0        # s tras la repulsión en los que prefiere esperar
const LOW_HEALTH := 0.3
const CUT_OFF_MIN_DISTANCE := 6.0
const WAIT_RING := 8.0             # distancia a Kaelen a la que espera
const AMBUSH_SPEED := 0.6          # factor de velocidad al acecharla distraída
const AMBUSH_TELEGRAPH := 1.3      # factor del aviso del ataque de la emboscada
const AMBUSH_MAX_DISTANCE := 14.0

var goal: Goal = Goal.ATTACK
var goal_time := 0.0
var last_scores: Dictionary = {}
## Segundos acumulados en cada meta y veces que se entró en ella (estadística para la simulación).
var time_in_goal: Dictionary = {Goal.ATTACK: 0.0, Goal.CUT_OFF: 0.0, Goal.WAIT: 0.0, Goal.PINCER: 0.0}
var entries: Dictionary = {Goal.ATTACK: 0, Goal.CUT_OFF: 0, Goal.WAIT: 0, Goal.PINCER: 0}

var _eval_timer := 0.0
var _cooldowns: Dictionary = {}


## Puntuación de cada meta para el contexto (sin histéresis ni enfriamientos).
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

	# ATACAR: la base; se devalúa cuando no hay nada que golpear (ella está lejos huyendo).
	var attack := 1.0 * aggressive
	if fleeing and distance > CUT_OFF_MIN_DISTANCE:
		attack = 0.45
	elif distance > 14.0:
		attack = 0.6

	# CORTAR PASO: solo si huye/se aleja, o está pasiva a lo lejos.
	var cut := 0.0
	if distance > CUT_OFF_MIN_DISTANCE:
		if fleeing:
			cut = 1.5 + 0.04 * minf(distance, 14.0)
		elif passive and distance > 10.0:
			cut = 0.9
	cut *= (1.15 if phase >= 2 else 1.0)

	# ESPERAR: respiros. Combo largo, repulsión reciente, vida baja o Kaelen pasiva.
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
	wait *= (0.6 if phase >= 2 else 1.0)   # la fase 2 es más agresiva

	# PINCER: Kaelen entre el jefe y los esbirros, o yendo a por ellos.
	var pincer := 0.0
	if minions >= 1 and with_minions and distance > 4.0 and distance < 18.0:
		pincer = 1.5 + (0.3 if minions >= 2 else 0.0)
		pincer *= (1.2 if phase >= 2 else 1.0)

	return {Goal.ATTACK: attack, Goal.CUT_OFF: cut, Goal.WAIT: wait, Goal.PINCER: pincer}


## Avanza los relojes `delta` s (el jefe lo llama TODOS los fotogramas, también en mitad de un ataque).
func advance(delta: float) -> void:
	goal_time += delta
	time_in_goal[goal] += delta
	for g in _cooldowns.keys():
		_cooldowns[g] = maxf(0.0, float(_cooldowns[g]) - delta)
	_eval_timer += delta


## Reevalúa la meta si pasaron EVAL_INTERVAL s desde la última vez (el jefe lo llama solo cuando NO
## está en mitad de un ataque). Devuelve true si la meta cambió.
func step(ctx: Dictionary) -> bool:
	if _eval_timer < EVAL_INTERVAL:
		return false
	_eval_timer = 0.0
	return reevaluate(ctx)


## advance + step (comodidad y pruebas).
func update(delta: float, ctx: Dictionary) -> bool:
	advance(delta)
	return step(ctx)


## Pide reevaluar en el próximo step (al salir de una recuperación o de un rugido: es el momento de decidir).
func request_eval() -> void:
	_eval_timer = EVAL_INTERVAL


## Reevalúa ya (sin esperar al intervalo). Devuelve true si cambió.
func reevaluate(ctx: Dictionary) -> bool:
	var scores := score_goals(ctx)
	for g in _cooldowns.keys():
		if float(_cooldowns[g]) > 0.0 and g != goal:
			scores[g] = 0.0
	last_scores = scores
	# Tope de duración: la meta caducó, se vuelve a ATACAR (con enfriamiento).
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
		# La meta actual ya no tiene sentido (puntúa 0 y no es ATTACK): abandona sin esperar.
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


# --- Geometría de las metas -----------------------------------------------------------------

## Emboscada: Kaelen distraída (con esbirros o de espaldas) y el jefe aún lejos pero no tanto.
static func is_ambush(distracted: bool, fleeing: bool, distance: float, engage_range: float) -> bool:
	return distracted and not fleeing and distance > engage_range and distance < AMBUSH_MAX_DISTANCE


## Punto al que va el jefe para cortar el paso: la posición prevista de Kaelen (la que da
## CombatMemory.predict a unos 1,5 s), que queda por delante de su huida, no detrás.
static func cut_off_point(predicted: Vector3, boss_pos: Vector3) -> Vector3:
	return Vector3(predicted.x, boss_pos.y, predicted.z)


## Punto hacia el que camina el jefe en ESPERAR: rodea a Kaelen a `ring` m (tangente + corrección
## radial, como la órbita de los esbirros). `side`: ±1, sentido del rodeo.
static func wait_point(boss_pos: Vector3, player_pos: Vector3, side: float, ring := WAIT_RING, lookahead := 3.0) -> Vector3:
	var offset := Vector3(boss_pos.x - player_pos.x, 0.0, boss_pos.z - player_pos.z)
	if offset.length_squared() < 0.01:
		offset = Vector3.BACK
	var radial := offset.normalized()
	var tangent := Vector3.UP.cross(radial) * side
	var error := clampf((ring - offset.length()) / 3.0, -1.0, 1.0)
	var dir := (tangent * 0.6 + radial * error * 1.2).normalized()
	return Vector3(boss_pos.x + dir.x * lookahead, boss_pos.y, boss_pos.z + dir.z * lookahead)
