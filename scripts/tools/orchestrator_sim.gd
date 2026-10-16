extends SceneTree
## Windowless simulation of the Orchestrator intensity (real OrchestratorModel, at 10 Hz) in the
## three arenas with the current wave rule: groups of 2-3 minions with 1 elite, never more than 3
## alive, boss window between waves. Usage:
##   godot --headless --path . -s res://scripts/tools/orchestrator_sim.gd
## Simulated Kaelen: kills the minions one at a time (3 s arrival + random kill time), nearby
## minions attack (at most 2 at once) every ~3.6 s, the boss every 4 s; the hit probability depends
## on the Kaelen profile (skilled / average / weak);
## the boss enters phase 2 at 70 s. On death the arena restarts (full health, model reset).
## Output per arena: min/max/mean, % of time saturated (>= 80) or at the floor (< 5), PEAK entries
## per minute, mean period between peaks, relax duration and waves per minute.

const CONFIGS := [
	"res://resources/arenas/arena_1_config.tres",
	"res://resources/arenas/arena_2_config.tres",
	"res://resources/arenas/arena_3_config.tres",
]
const HP := [100, 70, 40]
const DT := 0.1
const RUN_TIME := 180.0
const RUNS := 30
const ARRIVE := 3.0
const NEAR_ATTACK_EVERY := 3.6   # 0.5 telegraph + 0.3 active + 0.8 recovery + 2 s token wait
const MAX_ATTACKERS := 2         # simultaneous attack tokens
const BOSS_EVERY := 4.0
## Kaelen profiles: probability that a minion / boss attack reaches her.
const PROFILES := {
	"skilled": [0.12, 0.08],
	"average": [0.22, 0.14],
	"weak": [0.38, 0.25],
}
const BOSS_DAMAGE := 25
const PHASE2_AT := 70.0
const MINION_DAMAGE := 20
const ELITE_DAMAGE := 30

var _rng := RandomNumberGenerator.new()
var _hit := 0.2
var _boss_hit := 0.12
var _max_hp := 100


func _initialize() -> void:
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _main() -> void:
	_rng.seed = 18
	print("Orchestrator intensity: %d runs of %d s per arena (sampled at %.0f Hz)" % [RUNS, int(RUN_TIME), 1.0 / DT])
	for profile in PROFILES:
		_hit = PROFILES[profile][0]
		_boss_hit = PROFILES[profile][1]
		print("--- Kaelen %s (minion hit %.0f %%, boss %.0f %%)" % [profile, _hit * 100.0, _boss_hit * 100.0])
		for i in CONFIGS.size():
			_report(i)
	quit()


func _report(index: int) -> void:
	var cfg := load(CONFIGS[index]) as ArenaConfig
	var samples := PackedFloat32Array()
	var peaks := 0
	var peak_gaps: Array[float] = []
	var relax_lengths: Array[float] = []
	var waves := 0
	var deaths := 0
	var swing: Array[float] = []   # amplitude of each oscillation (maximum - previous minimum)
	var total_time := 0.0
	var trace := ""
	for run in RUNS:
		var res := _run(cfg, HP[index])
		if run == 0:
			for k in range(0, mini(res.samples.size(), int(90.0 / DT)), int(3.0 / DT)):
				trace += str(mini(9, int(res.samples[k] / 10.0)))
		samples.append_array(res.samples)
		peaks += res.peaks
		peak_gaps.append_array(res.peak_gaps)
		relax_lengths.append_array(res.relax)
		waves += res.waves
		deaths += res.deaths
		swing.append_array(res.swing)
		total_time += res.time
	var mn := 100.0
	var mx := 0.0
	var sum := 0.0
	var sat := 0
	var low := 0
	for v in samples:
		mn = minf(mn, v)
		mx = maxf(mx, v)
		sum += v
		if v >= OrchestratorModel.PEAK_THRESHOLD:
			sat += 1
		if v < 5.0:
			low += 1
	var n := float(samples.size())
	var mean := sum / n
	var variance := 0.0
	for v in samples:
		variance += (v - mean) * (v - mean)
	var minutes := total_time / 60.0
	print("Arena %d (base %.0f, HP %d): intensity min %.1f / max %.1f / mean %.1f / dev. %.1f" % [index + 1, cfg.base_budget, HP[index], mn, mx, mean, sqrt(variance / n)])
	print("   saturated (>=80): %.1f %% of the time | at the floor (<5): %.1f %%" % [100.0 * sat / n, 100.0 * low / n])
	print("   curve (1st run, 1 digit every 3 s = intensity/10): %s" % trace)
	print("   PEAK entries: %.2f/min | period between peaks: %.1f s | mean relax: %.1f s | waves: %.1f/min | deaths: %.2f/run | mean swing: %.1f" % [peaks / minutes, _mean(peak_gaps), _mean(relax_lengths), waves / minutes, float(deaths) / RUNS, _mean(swing)])


static func _mean(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()


func _run(cfg: ArenaConfig, max_hp: int) -> Dictionary:
	var m := OrchestratorModel.new()
	m.base_budget = cfg.base_budget
	m.max_alive = cfg.max_alive
	m.wave_size_min = cfg.wave_size_min
	m.wave_size_max = cfg.wave_size_max
	m.clear_delay = cfg.clear_delay
	m.first_wave_delay = cfg.first_wave_delay
	m.reset()
	var hp := max_hp
	_max_hp = max_hp
	var minions: Array[Dictionary] = []   # {age, work, elite, next_attack}
	var since_hit := 0.0
	var boss_next := BOSS_EVERY
	var t := 0.0
	var out := {samples = PackedFloat32Array(), peaks = 0, peak_gaps = [] as Array[float], relax = [] as Array[float], waves = 0, deaths = 0, swing = [] as Array[float], time = 0.0}
	var last_phase := m.phase
	var last_peak_t := -1.0
	var relax_start := 0.0
	var trough := 0.0
	var crest := 0.0
	var rising := true
	while t < RUN_TIME:
		t += DT
		since_hit += DT
		# Kaelen kills the first one in the queue when it is its turn (only once it has arrived).
		if not minions.is_empty():
			var first: Dictionary = minions[0]
			if first.age >= ARRIVE:
				first.work -= DT
				if first.work <= 0.0:
					minions.pop_front()
		var near := 0
		var attackers := 0
		for mi in minions:
			mi.age += DT
			if mi.age >= ARRIVE:
				near += 1
				mi.next_attack -= DT
				if mi.next_attack <= 0.0 and attackers < MAX_ATTACKERS:
					attackers += 1
					mi.next_attack = NEAR_ATTACK_EVERY * _rng.randf_range(0.8, 1.3)
					if _rng.randf() < _hit:
						hp = _hurt(m, hp, ELITE_DAMAGE if mi.elite else MINION_DAMAGE)
						since_hit = 0.0
		boss_next -= DT
		if boss_next <= 0.0:
			boss_next = BOSS_EVERY * _rng.randf_range(0.8, 1.3)
			if _rng.randf() < _boss_hit:
				hp = _hurt(m, hp, BOSS_DAMAGE)
				since_hit = 0.0
		if hp <= 0:
			out.deaths += 1
			hp = max_hp
			m.reset()
			minions.clear()
			since_hit = 0.0
			last_phase = m.phase
			continue
		var ctx := {
			hp_ratio = float(hp) / float(max_hp),
			enemies_near = near,
			enemies_alive = minions.size(),
			time_since_hit = since_hit,
			boss_phase = 2 if t >= PHASE2_AT else 1,
			boss_special = false,
		}
		var budget := m.update(DT, ctx)
		if budget > 0:
			out.waves += 1
			for k in budget:
				var elite := k == 0
				minions.append({age = 0.0, elite = elite, work = _rng.randf_range(10.0, 16.0) if elite else _rng.randf_range(4.0, 8.0), next_attack = _rng.randf_range(0.5, NEAR_ATTACK_EVERY)})
		out.samples.append(m.intensity)
		# Phases and oscillation.
		if m.phase != last_phase:
			if m.phase == OrchestratorModel.Phase.PEAK:
				out.peaks += 1
				if last_peak_t >= 0.0:
					out.peak_gaps.append(t - last_peak_t)
				last_peak_t = t
			if last_phase == OrchestratorModel.Phase.RELAX:
				out.relax.append(t - relax_start)
			if m.phase == OrchestratorModel.Phase.RELAX:
				relax_start = t
			last_phase = m.phase
		if rising:
			if m.intensity > crest:
				crest = m.intensity
			elif crest - m.intensity > 10.0:
				out.swing.append(crest - trough)
				rising = false
				trough = m.intensity
		else:
			if m.intensity < trough:
				trough = m.intensity
			elif m.intensity - trough > 10.0:
				rising = true
				crest = m.intensity
	out.time = t
	return out


func _hurt(m: OrchestratorModel, hp: int, amount: int) -> int:
	m.on_player_damaged(roundi(amount * OrchestratorModel.hp_damage_scale(_max_hp)))
	return hp - amount
