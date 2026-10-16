extends SceneTree
## Simulación sin ventana de ráfagas reales de Kaelen contra cada jefe (boss.gd real, avanzado a mano
## a 60 Hz). Mide cuántas veces se activa la repulsión en 30 s de presión y el tiempo estimado para
## matar (TTK). Uso:
##   godot --headless --path . -s res://scripts/tools/boss_pressure_sim.gd
## Perfiles de Kaelen: "constante" (encadena el mandoble sin parar, limitada por aguante, rueda el 70 %
## de los ataques) y "oportunista" (solo golpea mientras el jefe se recupera, 2 golpes por ventana).

const BOSSES := {
	"Bone Dragon": "res://scenes/bosses/boss_bonedragon.tscn",
	"Blackhorn": "res://scenes/bosses/boss_blackhorn.tscn",
	"Ghidorah": "res://scenes/bosses/boss_ghidorah.tscn",
}
const DT := 1.0 / 60.0
const REACH := 2.5          # distancia a la que Kaelen golpea (m)
const WALK := 5.0
const RUNS := 12
const MAX_TIME := 240.0


class Dummy extends Node3D:
	var shoves := 0
	var disp := Vector3.ZERO
	var vel := Vector3.ZERO
	var shove_left := 0.0
	var total := 0.0
	var home := Vector3(0.0, 0.0, -REACH)

	func apply_shove(push: Vector3, duration: float, _lift := 0.0) -> bool:
		shoves += 1
		vel = push
		total = duration
		shove_left = duration
		return true

	func step(dt: float) -> void:
		if shove_left > 0.0:
			var k := clampf(shove_left / total, 0.0, 1.0)
			global_position += vel * k * dt
			shove_left = maxf(0.0, shove_left - dt)
		else:
			var to := home - global_position
			to.y = 0.0
			if to.length() > 0.05:
				global_position += to.normalized() * minf(WALK * dt, to.length())


var _rng := RandomNumberGenerator.new()
var _lags: Array[float] = []   # segundos entre alcanzar el umbral y empezar el rugido


func _initialize() -> void:
	process_frame.connect(_main, CONNECT_ONE_SHOT)   # el árbol solo está listo tras el primer fotograma


func _main() -> void:
	var profiles := ["constante", "oportunista"]
	print("Presión simulada (%d ejecuciones por celda; ventana de 30 s, TTK hasta %d s)" % [RUNS, int(MAX_TIME)])
	for boss_name in BOSSES:
		for profile in profiles:
			var repels := 0.0
			var dmg := 0.0
			var ttk := 0.0
			var ttk_n := 0
			_lags.clear()
			for r in RUNS:
				var res := _run(BOSSES[boss_name], profile, MAX_TIME, 1000 + r)
				repels += res.repels30
				dmg += res.damage30
				if res.dead:
					ttk += res.time
					ttk_n += 1
			print("%-12s %-12s repulsiones/30s=%.2f  daño/30s=%.0f  TTK=%.1fs (%d/%d mueren)  retraso umbral-rugido=%.2fs" % [
				boss_name, profile, repels / RUNS, dmg / RUNS, ttk / maxf(1, ttk_n), ttk_n, RUNS, _mean(_lags)])
	quit()


func _run(path: String, profile: String, duration: float, seed_value: int) -> Dictionary:
	_rng.seed = seed_value
	var boss := (load(path) as PackedScene).instantiate() as Boss
	boss.rng_seed = seed_value
	var player := Dummy.new()
	player.add_to_group("player")
	root.add_child(boss)
	root.add_child(player)
	player.global_position = player.home
	boss.set_physics_process(false)
	boss.set(&"_gravity", 0.0)   # sin suelo en la simulación
	var sword := Node.new()
	root.add_child(sword)
	var stamina := 100.0
	var since_spend := 9.0
	var t := 0.0
	var busy_until := 0.0       # Kaelen no puede iniciar otro golpe hasta aquí
	var hits: Array = []        # [tiempo, daño]
	var combo := 0
	var roll_until := -1.0
	var decided_roll := false
	var punish_hits := 0
	var snap := {}
	var pend_t := -1.0
	var seen_repels := 0
	while t < duration and boss.state != Boss.State.DEAD:
		t += DT
		var prev_state := boss.state
		player.step(DT)
		boss._physics_process(DT)
		if boss.state != prev_state:
			decided_roll = false
			punish_hits = 0
		since_spend += DT
		if since_spend > 0.6:
			stamina = minf(100.0, stamina + 30.0 * DT)
		# Rodar un ataque: se decide al empezar el aviso, se rueda 0.3 s antes de que acabe.
		if boss.state == Boss.State.TELEGRAPH and not decided_roll:
			decided_roll = true
			if _rng.randf() < 0.7 and boss.current_attack:
				roll_until = t + boss.current_attack.telegraph_time / (1.25 if boss.phase == 2 else 1.0) - 0.3 + 0.6
				stamina -= 25.0
				since_spend = 0.0
		var rolling := t < roll_until and t > roll_until - 0.6
		var shoved: bool = player.shove_left > 0.0
		var near: bool = (player.global_position - boss.global_position).length() <= REACH + 0.4
		var can_swing := (not rolling and not shoved and near and t >= busy_until and stamina >= 20.0)
		if can_swing and profile == "oportunista":
			can_swing = boss.state == Boss.State.RECOVER and punish_hits < 2
		if can_swing and _rng.randf() < 0.85:
			var k := combo % 3
			busy_until = t + Player.HIT_END[k]
			stamina -= 20.0
			since_spend = 0.0
			hits.append([t + Player.HIT_START[k], Player.combo_damage(combo)])
			combo += 1
			punish_hits += 1
		elif can_swing:
			busy_until = t + 0.3
			combo = 0
		while not hits.is_empty() and hits[0][0] <= t:
			var h: Array = hits.pop_front()
			if near and not shoved:
				boss._on_hurt(h[1], sword)
		if pend_t < 0.0 and boss.repel.is_due(boss.health.max_value):
			pend_t = t
		elif pend_t >= 0.0 and not boss.repel.is_due(boss.health.max_value) and boss.repel_count == seen_repels:
			pend_t = -1.0   # la ventana lo olvidó antes de reaccionar
		if boss.repel_count > seen_repels:
			seen_repels = boss.repel_count
			if pend_t >= 0.0:
				_lags.append(t - pend_t)
			pend_t = -1.0
		if snap.is_empty() and t >= 30.0:
			snap = {repels = boss.repel_count, damage = boss.max_health - boss.health.current}
	if snap.is_empty():
		snap = {repels = boss.repel_count, damage = boss.max_health - boss.health.current}
	if OS.get_cmdline_user_args().has("debug"):
		print("  dbg estado=%d dist=%.2f hp=%d attacks=%d" % [boss.state, (player.global_position - boss.global_position).length(), boss.health.current, boss.attack_log.size()])
	var out := {repels30 = snap.repels, damage30 = snap.damage,
			dead = boss.state == Boss.State.DEAD, time = t}
	boss.free()
	player.free()
	sword.free()
	return out


func _mean(values: Array[float]) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / maxf(1.0, values.size())
