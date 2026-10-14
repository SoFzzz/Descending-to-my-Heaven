class_name OrchestratorModel
extends RefCounted
## Modelo puro del Orquestador (spec §8.3): intensidad, máquina de fases y presupuesto de oleada.
## Sin nodos: el autoload Orchestrator le pasa el contexto cada tick y gasta el presupuesto.
##
## Ritmo por oleadas con ventana del jefe: oleada de wave_size_min..wave_size_max esbirros -> se
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
const MINION_COST := 1
const ELITE_COST := 3

var intensity := 0.0
var phase: Phase = Phase.BUILD_UP
## Presupuesto base del nivel (ArenaConfig.base_budget); lo fija el Orquestador.
var base_budget := 4.0
var max_alive := 6
## Tamaño de oleada (en coste: esbirro 1, élite 3), entre min y max; ArenaConfig los fija.
var wave_size_min := 3
var wave_size_max := 4
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
	var budget := budget_for(ctx, base_budget)
	if budget <= 0:
		return 0
	# Una oleada nunca es un goteo: al menos wave_size_min (si caben) y como mucho wave_size_max.
	budget = clampi(budget, mini(wave_size_min, max_alive), maxi(wave_size_max, 1))
	_wave_out = true
	cycle = Cycle.WAVE
	return budget


## Duración de la ventana del jefe con la intensidad actual: clear_delay x [0.9, 1.3].
func window_duration() -> float:
	return clear_delay * lerpf(WINDOW_SCALE_MIN, WINDOW_SCALE_MAX, intensity / 100.0)


## Se llama si el Orquestador no pudo colocar nada (sin puntos válidos): reintenta pronto.
func retry_wave_soon() -> void:
	_wave_out = false
	wave_timer = RETRY_DELAY


## Presupuesto = base × desempeño × (1.5 en fase 2 del jefe), redondeado, sin pasar de los
## huecos libres (max_alive - vivos): con 5 vivos como mucho 1.
func budget_for(ctx: Dictionary, base: float) -> int:
	var raw := base * performance_factor(ctx)
	if int(ctx.get("boss_phase", 1)) == 2:
		raw *= PHASE2_MULTIPLIER
	var free_slots := max_alive - int(ctx.get("enemies_alive", 0))
	return clampi(roundi(raw), 0, maxi(0, free_slots))


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
