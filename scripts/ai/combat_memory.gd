class_name CombatMemory
extends RefCounted
## Memoria de combate compartida (inspirada en la "working memory" de F.E.A.R.): lógica pura, sin
## nodos. El jefe la alimenta ~10 veces por segundo con lo que ve (Kaelen, sí misma, los esbirros) y
## el resto de la IA (BossTactics, el Orquestador, el overlay F3) lee de aquí en vez de volver a
## calcular. Guarda la posición y velocidad SUAVIZADAS de Kaelen, una posición prevista a ~1 s y un
## comportamiento detectado:
##   HUYENDO        la distancia al jefe crece de forma sostenida
##   CON_ESBIRROS   su objetivo fijado / el que golpea es un esbirro, el más cercano está mucho más
##                  cerca que el jefe, o va decidida hacia uno
##   PEGADA         lleva un rato junto al jefe
##   PASIVA         lejos del jefe, sin atacar y sin huir
## Además mantiene marcas independientes (`fleeing`, `with_minions`, `distracted`, `circling`...)
## porque pueden darse a la vez (huye hacia los esbirros); `behavior` es la principal.

enum Behavior { NEUTRAL, FLEEING, WITH_MINIONS, GLUED, PASSIVE }

const BEHAVIOR_NAMES: Array[String] = ["NEUTRAL", "HUYENDO", "CON ESBIRROS", "PEGADA", "PASIVA"]

const SAMPLE_DT := 0.1             # periodo de muestreo (s)
const VEL_SMOOTH := 0.35           # peso de la muestra nueva en la media móvil de la velocidad
const RATE_SMOOTH := 0.3           # idem para la variación de la distancia al jefe
const HORIZON := 1.0               # s de la posición prevista por defecto
const MAX_LEAD_SPEED := 7.0        # m/s: la velocidad usada para predecir se limita (rodada)
const FLEE_RATE := 1.0             # m/s de aumento de distancia que cuenta como alejarse
const FLEE_MIN_SPEED := 2.2        # m/s mínimos de Kaelen para considerarla huyendo
const FLEE_TIME := 0.8             # s sostenidos para declarar HUYENDO
const FLEE_MIN_DISTANCE := 4.5
const FLEE_FORGET := 1.2           # s de calma para dejar de considerarla huyendo (histéresis)
const GLUE_RADIUS := 3.8
const GLUE_TIME := 2.0
const PASSIVE_DISTANCE := 7.0
const PASSIVE_TIME := 3.0
const MINION_NEAR := 3.0           # esbirro a menos de esto mientras ella ataca = su objetivo
const MINION_HEADING_DISTANCE := 9.0
const HEADING_DOT := 0.75          # cos del ángulo entre su velocidad y la dirección al esbirro
const HEADING_MIN_SPEED := 2.0
const AWAY_DOT := -0.3             # de espaldas al jefe: su frente · dirección al jefe < esto
const CIRCLE_DISTANCE := 7.0
const CIRCLE_SPEED := 2.2          # m/s tangenciales al jefe
const CIRCLE_TIME := 0.5

# Lo que se sabe de Kaelen (todo plano en XZ salvo `position.y`).
var position := Vector3.ZERO
var velocity := Vector3.ZERO       # suavizada
var speed := 0.0
var distance := 0.0                # al jefe
var distance_rate := 0.0           # m/s, suavizada (> 0: se aleja)
var minions_alive := 0
var nearest_minion_distance := INF # de Kaelen al esbirro más cercano
var nearest_minion_position := Vector3.ZERO
var dodge_side := 0.0              # sesgo de rodada (BossBrain.dodge_bias): −1 izquierda … +1 derecha

# Comportamiento detectado.
var behavior: Behavior = Behavior.NEUTRAL
var fleeing := false
var with_minions := false
var glued := false
var passive := false
var distracted := false
var circling := false
var attacking := false             # Kaelen está atacando ahora mismo
var samples := 0

var _acc := 0.0
var _has_last := false
var _last_pos := Vector3.ZERO
var _flee_time := 0.0
var _calm_time := 0.0
var _glue_time := 0.0
var _passive_time := 0.0
var _circle_time := 0.0


## Vacía todo lo aprendido (nueva arena / Kaelen murió).
func reset() -> void:
	var fresh := CombatMemory.new()
	for prop in ["position", "velocity", "speed", "distance", "distance_rate", "minions_alive",
			"nearest_minion_distance", "nearest_minion_position", "dodge_side", "behavior", "fleeing",
			"with_minions", "glued", "passive", "distracted", "circling", "attacking", "samples",
			"_acc", "_has_last", "_last_pos", "_flee_time", "_calm_time", "_glue_time",
			"_passive_time", "_circle_time"]:
		set(prop, fresh.get(prop))


## Acumula tiempo; devuelve los segundos acumulados cuando toca muestrear (cada SAMPLE_DT) y 0 si no.
## Así quien la alimenta solo arma el contexto (consulta de grupos, etc.) cuando hace falta.
func tick(delta: float) -> float:
	_acc += delta
	if _acc < SAMPLE_DT - 0.0001:
		return 0.0
	var dt := _acc
	_acc = 0.0
	return dt


## tick + observe en una llamada (pruebas). Devuelve true si muestreó.
func feed(delta: float, ctx: Dictionary) -> bool:
	var dt := tick(delta)
	if dt <= 0.0:
		return false
	observe(dt, ctx)
	return true


## Una muestra de `dt` s. ctx:
##   player_pos, boss_pos, boss_forward (Vector3, plano), player_facing (Vector3, opcional),
##   player_attacking (bool), locked_minion (bool: su objetivo fijado es un esbirro),
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

	# --- Posición, velocidad y distancia suavizadas ---
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

	# --- Esbirros ---
	minions_alive = minions.size()
	nearest_minion_distance = INF
	for m: Vector3 in minions:
		var d := _flat(m - player_pos).length()
		if d < nearest_minion_distance:
			nearest_minion_distance = d
			nearest_minion_position = m

	# --- Huir: aumento sostenido de distancia a buena velocidad ---
	var running_away := distance_rate > FLEE_RATE and speed > FLEE_MIN_SPEED
	if running_away:
		_flee_time += dt
		_calm_time = 0.0
	else:
		_calm_time += dt
		if _calm_time >= FLEE_FORGET:
			_flee_time = 0.0
	fleeing = _flee_time >= FLEE_TIME and distance >= FLEE_MIN_DISTANCE

	# --- Con esbirros ---
	var heading_to_minion := false
	if minions_alive > 0 and speed > HEADING_MIN_SPEED and nearest_minion_distance < MINION_HEADING_DISTANCE:
		var to_minion := _flat(nearest_minion_position - player_pos)
		if to_minion.length() > 0.1:
			heading_to_minion = _flat(velocity).normalized().dot(to_minion.normalized()) > HEADING_DOT
	var target_is_minion: bool = ctx.get("locked_minion", false) and minions_alive > 0
	var striking_minion := attacking and nearest_minion_distance < MINION_NEAR
	var minion_closer := minions_alive > 0 and distance > 5.0 and nearest_minion_distance < distance * 0.5
	with_minions = target_is_minion or striking_minion or heading_to_minion or minion_closer

	# --- Pegada / pasiva ---
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

	# --- Rodeando al jefe (velocidad tangencial alta y cerca) ---
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

	# --- Distraída: esbirros, o de espaldas al jefe ---
	var turned_away := false
	if facing.length_squared() > 0.01 and distance > 3.0:
		var to_boss := _flat(boss_pos - player_pos).normalized()
		turned_away = _flat(facing).normalized().dot(to_boss) < AWAY_DOT
	distracted = (with_minions and not fleeing) or (turned_away and not fleeing)
	if boss_forward.length_squared() < 0.0001:
		circling = false

	# --- Comportamiento principal (prioridad) ---
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


## Posición prevista de Kaelen a `horizon` s (velocidad suavizada y limitada). Si se da `bounds`
## (Callable Vector3 → Vector3, p. ej. el punto más cercano del navmesh) el resultado se limita con él.
func predict(horizon := HORIZON, bounds := Callable()) -> Vector3:
	var v := Vector3(velocity.x, 0.0, velocity.z)
	if v.length() > MAX_LEAD_SPEED:
		v = v.normalized() * MAX_LEAD_SPEED
	var p := position + v * horizon
	if bounds.is_valid():
		p = bounds.call(p)
	return p


## Dirección plana de la marcha de Kaelen (cero si está quieta).
func heading() -> Vector3:
	var v := Vector3(velocity.x, 0.0, velocity.z)
	return v.normalized() if v.length() > 0.2 else Vector3.ZERO


func behavior_name() -> String:
	return BEHAVIOR_NAMES[clampi(int(behavior), 0, BEHAVIOR_NAMES.size() - 1)]


## Limita `p` a un disco (centro y radio en XZ): la versión pura de "dentro de la arena".
static func clamp_to_disc(p: Vector3, center: Vector3, radius: float) -> Vector3:
	var offset := Vector3(p.x - center.x, 0.0, p.z - center.z)
	if offset.length() <= radius or radius <= 0.0:
		return p
	var limited := offset.normalized() * radius
	return Vector3(center.x + limited.x, p.y, center.z + limited.z)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
