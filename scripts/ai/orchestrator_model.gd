class_name OrchestratorModel
extends RefCounted
## Pure model of the Orchestrator (spec 8.3): intensity, phase state machine and wave budget.
## No nodes: the Orchestrator autoload passes it the context every tick and spends the budget.
##
## Wave pacing with a boss window: a group of wave_size_min or wave_size_max minions (2 or 3;
## never more than max_alive = 3 alive; the Orchestrator replaces one with the elite) -> all of them
## are killed -> boss window of `clear_delay` s (scaled +-30 % by the intensity) without
## spawns -> next wave. A wave never starts while any minion is alive. The phase
## (RELAX / hp_ratio < 0.25 / boss_special) still vetoes waves.
##
## ctx = {hp_ratio: float, enemies_near: int, enemies_alive: int, time_since_hit: float,
##        boss_phase: int, boss_special: bool}

enum Phase { BUILD_UP, PEAK, RELAX }
## Cycle state (for debugging): waiting for the first wave, wave in progress (minions alive)
## or boss window (0 alive, countdown to the next wave).
enum Cycle { FIRST_WAIT, WAVE, WINDOW }

const LOW_HP_RISE := 5.0          # +/s with hp_ratio < LOW_HP_RATIO
const LOW_HP_RATIO := 0.3
const NEAR_ENEMY_RISE := 2.0      # +/s per enemy within 5 m
const DECAY := 8.0                # -/s natural
const DECAY_NO_ENEMIES := 15.0    # -/s if no enemies are near (replaces DECAY)
const DAMAGE_FACTOR := 1.5
const PEAK_THRESHOLD := 80.0
const PEAK_DURATION := 5.0
const RELAX_MIN := 10.0
const RELAX_MAX := 20.0
const RELAX_EXIT_INTENSITY := 30.0
const FORCE_RELAX_HP := 0.25
const PERF_MIN := 0.6
const PERF_MAX := 1.4
## Seconds without taking damage after which the player is considered to be "dominating".
const PERF_CALM_TIME := 20.0
const PHASE2_MULTIPLIER := 1.5
## The boss window scales with the intensity once 0 are alive: x0.9 at intensity 0
## up to x1.3 at intensity 100 (more pressure suffered -> longer pause to attack the boss).
const WINDOW_SCALE_MIN := 0.9
const WINDOW_SCALE_MAX := 1.3
const RETRY_DELAY := 1.0
## Spawn points: never within SPAWN_MIN_DISTANCE of Kaelen; the visible ones (camera cone)
## only count if they are farther than SPAWN_FAR_DISTANCE, or as a last resort (SpawnTier.FALLBACK).
const SPAWN_MIN_DISTANCE := 8.0
const SPAWN_FAR_DISTANCE := 14.0

## Spawn preference (lower number = better): see select_spawn_points().
enum SpawnTier { NONE, HIDDEN, FAR, FALLBACK }

var intensity := 0.0
var phase: Phase = Phase.BUILD_UP
## Pressure threshold of the level (ArenaConfig.base_budget): with base x performance x phase >= base the
## group is wave_size_max; below it, wave_size_min. Set by the Orchestrator.
var base_budget := 4.0
## Maximum number of minions alive at once (elite included).
var max_alive := 3
## Group size (minions, elite included): 2 if the player is doing badly, 3 if well; set by ArenaConfig.
var wave_size_min := 2
var wave_size_max := 3
## Seconds of boss window after the wave is cleared (no spawns).
var clear_delay := 12.0
## Seconds until the first wave after entering the arena.
var first_wave_delay := 3.0
var phase_time := 0.0             # seconds in the current phase
var relax_duration := RELAX_MIN
## Countdown to the next wave (first delay or boss window).
var wave_timer := 3.0
var cycle: Cycle = Cycle.FIRST_WAIT
var _wave_out := false            # a wave was launched and its window has not been counted yet


## Resets phase, intensity and cycle; keeps the parameters (base_budget, sizes, delays).
func reset() -> void:
	intensity = 0.0
	phase = Phase.BUILD_UP
	phase_time = 0.0
	relax_duration = RELAX_MIN
	wave_timer = first_wave_delay
	cycle = Cycle.FIRST_WAIT
	_wave_out = false


## Kaelen loses max health after each boss (100 / 70 / 40): the same hit weighs more in arena 3 and
## the intensity never reached PEAK. The damage is scaled halfway toward a health of 100 (x1.0 / x1.2 /
## x1.8), so a hit counts as a similar slice of health in the three arenas without fully equalising it.
static func hp_damage_scale(max_hp: int) -> float:
	if max_hp <= 0:
		return 1.0
	return clampf(lerpf(1.0, 100.0 / float(max_hp), 0.5), 1.0, 2.0)


func on_player_damaged(amount: int) -> void:
	intensity = clampf(intensity + amount * DAMAGE_FACTOR, 0.0, 100.0)


## Advances the model `delta` s. Returns the budget to spend now (0 if nothing is spawned).
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
			# With low health the breather is not left.
			if not low_hp and phase_time >= relax_duration and intensity < RELAX_EXIT_INTENSITY:
				_enter(Phase.BUILD_UP)

	# Cycle: with any minion alive there is never a wave; the window starts when 0 are left.
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


## Chooses where the minions spawn (pure logic). `points`: positions; `in_view[i]`: is point i
## visible (camera cone)? (missing ones count as visible). Distances are flat.
## Intent: Kaelen must not see enemies appear out of nowhere nor spawn on top of her.
##   1 HIDDEN:   outside the cone and farther than 8 m (all that qualify).
##   2 FAR:      if none, those farther than 14 m even if visible.
##   3 FALLBACK: if none either and `allow_visible_fallback` (the retry), ONLY the farthest one beyond 8 m.
##   NONE:       none -> the Orchestrator delays the wave (retry_wave_soon).
## Returns {tier: SpawnTier, indices: Array[int]} (indices into `points`, in input order).
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


## Boss window duration at the current intensity: clear_delay x [0.9, 1.3].
func window_duration() -> float:
	return clear_delay * lerpf(WINDOW_SCALE_MIN, WINDOW_SCALE_MAX, intensity / 100.0)


## Called if the Orchestrator could not place anything (no valid points): retries soon.
func retry_wave_soon() -> void:
	_wave_out = false
	wave_timer = RETRY_DELAY


## Group size: pressure = base x performance x (1.5 in boss phase 2). With pressure >= base
## (the player is doing well or the boss is in phase 2) wave_size_max minions come out; with less,
## wave_size_min. Never more than the free slots (max_alive - alive).
func wave_size_for(ctx: Dictionary, base: float) -> int:
	var raw := base * performance_factor(ctx)
	if int(ctx.get("boss_phase", 1)) == 2:
		raw *= PHASE2_MULTIPLIER
	var size := wave_size_max if raw >= base else wave_size_min
	var free_slots := max_alive - int(ctx.get("enemies_alive", 0))
	return clampi(size, 0, maxi(0, free_slots))


## Performance factor (0.6-1.4), deterministic: mean of the current health (hp_ratio, 0-1) and of the
## time without taking damage (time_since_hit / 20 s, saturated at 1), mapped linearly to
## [0.6, 1.4]. Full health and 20 s without damage -> 1.4 (doing well: more pressure); health 0 and just
## hit -> 0.6 (doing badly: less).
func performance_factor(ctx: Dictionary) -> float:
	var hp := clampf(float(ctx.get("hp_ratio", 1.0)), 0.0, 1.0)
	var calm := clampf(float(ctx.get("time_since_hit", 0.0)) / PERF_CALM_TIME, 0.0, 1.0)
	return lerpf(PERF_MIN, PERF_MAX, 0.5 * hp + 0.5 * calm)


func _enter(next: Phase) -> void:
	phase = next
	phase_time = 0.0


## The breather duration scales with the intensity on entry (more pressure -> longer pause):
## 10 s at intensity 0 up to 20 s at intensity 100. Deterministic.
func _enter_relax() -> void:
	relax_duration = lerpf(RELAX_MIN, RELAX_MAX, intensity / 100.0)
	_enter(Phase.RELAX)
