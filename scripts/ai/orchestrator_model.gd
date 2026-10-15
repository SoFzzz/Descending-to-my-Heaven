class_name OrchestratorModel
extends RefCounted
## Modelo puro del Orquestador (spec §8.3): intensidad, máquina de fases y presupuesto de oleada.
## Sin nodos: el autoload Orchestrator le pasa el contexto cada tick y gasta el presupuesto.
##
## Ritmo por oleadas con ventana del jefe: grupo de wave_size_min o wave_size_max esbirros (2 o 3;
## nunca más de max_alive = 3 vivos; el Orquestador reemplaza a uno por la élite) -> se
## eliminan todos -> ventana del jefe de `clear_delay` s (escalada +-30 % por la intensidad) sin
## apariciones -> siguiente oleada. Nunca hay una oleada con algún esbirro vivo. La fase
## (RELAX / hp_ratio < 0.25 / boss_special) sigue vetando oleadas.
##
## ctx = {hp_ratio: float, enemies_near: int, enemies_alive: int, time_since_hit: float,
##        boss_phase: int, boss_special: bool}

enum Phase { BUILD_UP, PEAK, RELAX }
## Estado del ciclo (para depuración): espera de la primera oleada, oleada en curso (hay vivos)
## o ventana del jefe (0 vivos, cuenta atrás hasta la siguiente oleada).
enum Cycle { FIRST_WAIT, WAVE, WINDOW }

const LOW_HP_RISE := 5.0          # +/s con hp_ratio < LOW_HP_RATIO
const LOW_HP_RATIO := 0.3
const NEAR_ENEMY_RISE := 2.0      # +/s por enemigo a < 5 m
const DECAY := 8.0                # -/s natural
const DECAY_NO_ENEMIES := 15.0    # -/s si no hay enemigos cerca (sustituye a DECAY)
const DAMAGE_FACTOR := 1.5
const PEAK_THRESHOLD := 80.0
const PEAK_DURATION := 5.0
const RELAX_MIN := 10.0
const RELAX_MAX := 20.0
const RELAX_EXIT_INTENSITY := 30.0
const FORCE_RELAX_HP := 0.25
const PERF_MIN := 0.6
const PERF_MAX := 1.4
## Segundos sin recibir daño a partir de los cuales el jugador se considera "dominando".
const PERF_CALM_TIME := 20.0
const PHASE2_MULTIPLIER := 1.5
## La ventana del jefe se escala con la intensidad al quedar a 0 vivos: x0.9 con intensidad 0
## hasta x1.3 con intensidad 100 (más presión sufrida -> más pausa para atacar al jefe).
const WINDOW_SCALE_MIN := 0.9
const WINDOW_SCALE_MAX := 1.3
const RETRY_DELAY := 1.0
## Puntos de aparición: nunca a <= SPAWN_MIN_DISTANCE de Kaelen; los que se ven (cono de la
## cámara) solo valen si están a > SPAWN_FAR_DISTANCE, o como último recurso (SpawnTier.FALLBACK).
const SPAWN_MIN_DISTANCE := 8.0
const SPAWN_FAR_DISTANCE := 14.0

## Preferencia de aparición (menor número = mejor): ver select_spawn_points().
enum SpawnTier { NONE, HIDDEN, FAR, FALLBACK }

var intensity := 0.0
var phase: Phase = Phase.BUILD_UP
## Umbral de presión del nivel (ArenaConfig.base_budget): con base x desempeño x fase >= base el
## grupo es de wave_size_max; por debajo, de wave_size_min. Lo fija el Orquestador.
var base_budget := 4.0
## Máximo de esbirros vivos a la vez (élite incluida).
var max_alive := 3
## Tamaño del grupo (esbirros, élite incluida): 2 si el jugador va mal, 3 si va bien; ArenaConfig los fija.
var wave_size_min := 2
var wave_size_max := 3
## Segundos de ventana del jefe tras eliminar la oleada (sin apariciones).
var clear_delay := 12.0
## Segundos hasta la primera oleada tras entrar a la arena.
var first_wave_delay := 3.0
var phase_time := 0.0             # segundos en la fase actual
var relax_duration := RELAX_MIN
## Cuenta atrás hasta la siguiente oleada (primer retardo o ventana del jefe).
var wave_timer := 3.0
var cycle: Cycle = Cycle.FIRST_WAIT
var _wave_out := false            # se lanzó una oleada y aún no se ha contado su ventana


## Reinicia fase, intensidad y ciclo; conserva los parámetros (base_budget, tamaños, retardos).
func reset() -> void:
	intensity = 0.0
	phase = Phase.BUILD_UP
	phase_time = 0.0
	relax_duration = RELAX_MIN
	wave_timer = first_wave_delay
	cycle = Cycle.FIRST_WAIT
	_wave_out = false


func on_player_damaged(amount: int) -> void:
	intensity = clampf(intensity + amount * DAMAGE_FACTOR, 0.0, 100.0)


## Avanza el modelo `delta` s. Devuelve el presupuesto a gastar ahora (0 si no se genera).
func update(delta: float, ctx: Dictionary) -> int:
	var hp: float = ctx.get("hp_ratio", 1.0)
	var near: int = ctx.get("enemies_near", 0)
	var alive: int = ctx.get("enemies_alive", 0)

	var rate := -(DECAY if near > 0 else DECAY_NO_ENEMIES)
	if hp < LOW_HP_RATIO:
		rate += LOW_HP_RISE
	rate += NEAR_ENEMY_RISE * near
	intensity = clampf(intensity + rate * delta, 0.0, 100.0)

	phase_time += delta
	wave_timer = maxf(0.0, wave_timer - delta)
	var low_hp := hp < FORCE_RELAX_HP
	match phase:
		Phase.BUILD_UP:
			if low_hp:
				_enter_relax()
			elif intensity >= PEAK_THRESHOLD:
				_enter(Phase.PEAK)
		Phase.PEAK:
			if low_hp or phase_time >= PEAK_DURATION:
				_enter_relax()
		Phase.RELAX:
			# Con la vida baja no se sale del respiro.
			if not low_hp and phase_time >= relax_duration and intensity < RELAX_EXIT_INTENSITY:
				_enter(Phase.BUILD_UP)

	# Ciclo: con algún esbirro vivo nunca hay oleada; la ventana empieza al quedar a 0.
	if alive > 0:
		cycle = Cycle.WAVE
		return 0
	if _wave_out:
		_wave_out = false
		wave_timer = window_duration()
	if cycle == Cycle.WAVE:
		cycle = Cycle.WINDOW
	if phase != Phase.BUILD_UP or ctx.get("boss_special", false):
		return 0
	if wave_timer > 0.0:
		return 0
	var size := wave_size_for(ctx, base_budget)
	if size <= 0:
		return 0
	_wave_out = true
	cycle = Cycle.WAVE
	return size


## Elige dónde aparecen los esbirros (lógica pura). `points`: posiciones; `in_view[i]`: ¿el punto i
## se ve (cono de la cámara)? (los que falten cuentan como visibles). Distancias en planta.
## Intención: que Kaelen no vea aparecer enemigos de la nada ni nazcan encima de ella.
##   1 HIDDEN:   fuera del cono y a > 8 m (todos los que cumplan).
##   2 FAR:      si no hay, los que estén a > 14 m aunque se vean.
##   3 FALLBACK: si tampoco y `allow_visible_fallback` (el reintento), SOLO el más lejano que esté a > 8 m.
##   NONE:       ninguno -> el Orquestador retrasa la oleada (retry_wave_soon).
## Devuelve {tier: SpawnTier, indices: Array[int]} (índices de `points`, en orden de entrada).
static func select_spawn_points(points: Array[Vector3], player_pos: Vector3, in_view: Array[bool], allow_visible_fallback: bool) -> Dictionary:
	var hidden: Array[int] = []
	var far: Array[int] = []
	var farthest := -1
	var farthest_d := SPAWN_MIN_DISTANCE
	for i in points.size():
		var flat := points[i] - player_pos
		flat.y = 0.0
		var d := flat.length()
		if d <= SPAWN_MIN_DISTANCE:
			continue
		var visible := i >= in_view.size() or in_view[i]
		if not visible:
			hidden.append(i)
		if d > SPAWN_FAR_DISTANCE:
			far.append(i)
		if d > farthest_d:
			farthest_d = d
			farthest = i
	if not hidden.is_empty():
		return {tier = SpawnTier.HIDDEN, indices = hidden}
	if not far.is_empty():
		return {tier = SpawnTier.FAR, indices = far}
	if allow_visible_fallback and farthest >= 0:
		var only: Array[int] = [farthest]
		return {tier = SpawnTier.FALLBACK, indices = only}
	return {tier = SpawnTier.NONE, indices = [] as Array[int]}


## Duración de la ventana del jefe con la intensidad actual: clear_delay x [0.9, 1.3].
func window_duration() -> float:
	return clear_delay * lerpf(WINDOW_SCALE_MIN, WINDOW_SCALE_MAX, intensity / 100.0)


## Se llama si el Orquestador no pudo colocar nada (sin puntos válidos): reintenta pronto.
func retry_wave_soon() -> void:
	_wave_out = false
	wave_timer = RETRY_DELAY


## Tamaño del grupo: presión = base x desempeño x (1.5 en fase 2 del jefe). Con presión >= base
## (el jugador va bien o el jefe está en fase 2) salen wave_size_max esbirros; con menos,
## wave_size_min. Nunca más que los huecos libres (max_alive - vivos).
func wave_size_for(ctx: Dictionary, base: float) -> int:
	var raw := base * performance_factor(ctx)
	if int(ctx.get("boss_phase", 1)) == 2:
		raw *= PHASE2_MULTIPLIER
	var size := wave_size_max if raw >= base else wave_size_min
	var free_slots := max_alive - int(ctx.get("enemies_alive", 0))
	return clampi(size, 0, maxi(0, free_slots))


## Factor de desempeño (0.6–1.4), determinista: media de la vida actual (hp_ratio, 0–1) y del
## tiempo sin recibir daño (time_since_hit / 20 s, saturado a 1), mapeada linealmente a
## [0.6, 1.4]. Vida llena y 20 s sin daño -> 1.4 (va bien: más presión); vida 0 y recién
## golpeada -> 0.6 (va mal: menos).
func performance_factor(ctx: Dictionary) -> float:
	var hp := clampf(float(ctx.get("hp_ratio", 1.0)), 0.0, 1.0)
	var calm := clampf(float(ctx.get("time_since_hit", 0.0)) / PERF_CALM_TIME, 0.0, 1.0)
	return lerpf(PERF_MIN, PERF_MAX, 0.5 * hp + 0.5 * calm)


func _enter(next: Phase) -> void:
	phase = next
	phase_time = 0.0


## La duración del respiro se escala con la intensidad al entrar (más presión -> más pausa):
## 10 s con intensidad 0 hasta 20 s con intensidad 100. Determinista.
func _enter_relax() -> void:
	relax_duration = lerpf(RELAX_MIN, RELAX_MAX, intensity / 100.0)
	_enter(Phase.RELAX)
