extends SceneTree
## Simulación sin ventana de las tácticas del jefe (CombatMemory + BossTactics + pinza). Usa el
## `Boss` real y el código real del Orquestador para la pinza (`_update_squad`), avanzados a mano a
## 60 Hz, con una Kaelen simulada y esbirros simples. Compara "antes" (tactics_enabled = false, el
## jefe persigue y ataca como antes) con "después". Uso:
##   godot --headless --path . -s res://scripts/tools/boss_tactics_sim.gd [-- boss=Ghidorah runs=4 secs=120]
## Perfiles de Kaelen:
##   agresiva  pegada al jefe, encadena el mandoble y rueda ~50 % de los avisos.
##   huidiza   kitea: se mantiene a 9-13 m rodeando la arena, va a matar al esbirro más cercano y
##             solo entra a golpear cuando el jefe se recupera (2 golpes por ventana).
## Daño recibido: modelo geométrico simple (volumen del ataque en ACTIVE; rodar da invulnerabilidad),
## suficiente para comparar antes/después, no para cifras absolutas.

const BOSSES := {
	"Bone Dragon": "res://scenes/bosses/boss_bonedragon.tscn",
	"Blackhorn": "res://scenes/bosses/boss_blackhorn.tscn",
	"Ghidorah": "res://scenes/bosses/boss_ghidorah.tscn",
}
const OrchScript := preload("res://scripts/ai/orchestrator.gd")
const DT := 1.0 / 60.0
const ARENA := 20.0
const REACH := 2.4
const RUN := 5.5
const MINION_SPEED := 3.5
const MINION_DAMAGE := 8
const WAVE_DELAY := 8.0

var _rng := RandomNumberGenerator.new()
var _args := {}


class SimMinion extends Node3D:
	var state := 1                  # MinionBrain.State: 1 CHASE, 2 CIRCLE, 3 ATTACK
	var hp := 3
	var order_point := Vector3.ZERO
	var order_left := 0.0
	var attack_t := -1.0
	var cooldown := 0.0
	var damage_done := false

	func order_to(point: Vector3, duration := 1.2) -> void:
		order_point = point
		order_left = duration

	func clear_order() -> void:
		order_left = 0.0

	func is_retreating() -> bool:
		return false


class Dummy extends Node3D:
	var shoves := 0
	var vel := Vector3.ZERO
	var shove_left := 0.0
	var total := 0.0

	func apply_shove(push: Vector3, duration: float, _lift := 0.0) -> bool:
		shoves += 1
		vel = push
		total = duration
		shove_left = duration
		return true

	func step_shove(dt: float) -> void:
		if shove_left > 0.0:
			global_position += vel * clampf(shove_left / total, 0.0, 1.0) * dt
			shove_left = maxf(0.0, shove_left - dt)


func _initialize() -> void:
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _main() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := String(arg).split("=")
		if parts.size() == 2:
			_args[parts[0]] = parts[1]
	var runs := int(_args.get("runs", 6))
	var secs := float(_args.get("secs", 120.0))
	print("Tácticas del jefe: %d ejecuciones por celda de %d s (Kaelen simulada; 'antes' = tactics_enabled=false)" % [runs, int(secs)])
	print("%-12s %-9s %-7s %9s | %5s %5s %5s %6s | %7s %7s %6s %6s | %s" % [
		"jefe", "perfil", "modo", "daño/min", "%ATK", "%CUT", "%WAIT", "%PINZA", "cortes/m", "pinzas/m", "espe/m", "embos/m", "TTK jefe"])
	for boss_name in BOSSES:
		if _args.has("boss") and _args["boss"] != boss_name:
			continue
		for profile in ["agresiva", "huidiza"]:
			for tactics in [false, true]:
				var acc := {dmg = 0.0, atk = 0.0, cut = 0.0, wait = 0.0, pin = 0.0, cuts = 0.0, pins = 0.0, waits = 0.0, amb = 0.0,
						ttk = 0.0, ttk_n = 0, secs = 0.0}
				for r in runs:
					var res := _run(BOSSES[boss_name], profile, tactics, secs, 2000 + r)
					for k in ["dmg", "atk", "cut", "wait", "pin", "cuts", "pins", "waits", "amb", "secs"]:
						acc[k] += res[k]
					if res.dead:
						acc.ttk += res.secs
						acc.ttk_n += 1
				var minutes: float = acc.secs / 60.0
				var frames: float = maxf(1.0, acc.atk + acc.cut + acc.wait + acc.pin)
				print("%-12s %-9s %-7s %9.0f | %5.1f %5.1f %5.1f %6.1f | %7.2f %7.2f %6.2f %6.2f | %s" % [
					boss_name, profile, "después" if tactics else "antes", acc.dmg / minutes,
					100.0 * acc.atk / frames, 100.0 * acc.cut / frames, 100.0 * acc.wait / frames, 100.0 * acc.pin / frames,
					acc.cuts / minutes, acc.pins / minutes, acc.waits / minutes, acc.amb / minutes,
					("%.0f s (%d/%d)" % [acc.ttk / acc.ttk_n, acc.ttk_n, runs]) if acc.ttk_n > 0 else "- (0/%d)" % runs])
	quit()


func _run(path: String, profile: String, tactics: bool, duration: float, seed_value: int) -> Dictionary:
	_rng.seed = seed_value
	var boss := (load(path) as PackedScene).instantiate() as Boss
	boss.rng_seed = seed_value
	boss.tactics_enabled = tactics
	var player := Dummy.new()
	player.add_to_group("player")
	root.add_child(boss)
	root.add_child(player)
	boss.global_position = Vector3.ZERO
	player.global_position = Vector3(0.0, 0.0, 9.0)
	boss.set_physics_process(false)
	boss.set(&"_gravity", 0.0)
	boss._aggro = true
	var sword := Node.new()
	root.add_child(sword)
	var orch: Node = OrchScript.new()
	orch.set(&"_boss", boss)
	orch.set(&"_player", player)
	root.add_child(orch)
	var minions: Array = []
	orch.set(&"_minions", minions)
	var t := 0.0
	var damage_taken := 0.0
	var invuln_until := -1.0
	var busy_until := 0.0
	var combo := 0
	var hits: Array = []
	var punish := 0
	var stamina := 100.0
	var since_spend := 9.0
	var prev_state := boss.state
	var decided := false
	var wave_timer := WAVE_DELAY
	var squad_timer := 0.0
	var goal_frames := [0, 0, 0, 0]
	var attack_hit_done := false
	var beam_line := {}
	var minion_attacking := 0
	while t < duration and boss.state != Boss.State.DEAD:
		t += DT
		player.step_shove(DT)
		boss._physics_process(DT)
		# El jefe no sale de la arena (en el juego lo limita el navmesh).
		var bp := boss.global_position
		if Vector2(bp.x, bp.z).length() > ARENA + 2.0:
			var cl := Vector2(bp.x, bp.z).normalized() * (ARENA + 2.0)
			boss.global_position = Vector3(cl.x, bp.y, cl.y)
		goal_frames[int(boss.tactics.goal) if tactics else 0] += 1
		if _args.has("debug") and int(t * 60.0) % 300 == 0:
			print("  t=%.0f estado=%d meta=%s kaelen=%s dist=%.1f vel=%.1f rate=%.2f minions=%d" % [t, boss.state, boss.tactics.goal_name(),
					boss.memory.behavior_name(), boss.memory.distance, boss.memory.speed, boss.memory.distance_rate, boss.memory.minions_alive])

		# --- inicio de un ataque del jefe: ¿ruedo? ---
		if boss.state != prev_state:
			decided = false
			punish = 0
			attack_hit_done = false
			beam_line = {}
		prev_state = boss.state
		since_spend += DT
		if since_spend > 0.6:
			stamina = minf(100.0, stamina + 30.0 * DT)
		var pdist := _flat(player.global_position - boss.global_position).length()
		if boss.state == Boss.State.TELEGRAPH and not decided:
			decided = true
			if boss.current_attack and pdist < boss.current_attack.max_range + 4.0 and _rng.randf() < (0.5 if profile == "agresiva" else 0.4):
				var end := boss.current_attack.telegraph_time * boss.telegraph_scale / boss._speed()
				invuln_until = t + end - 0.05 + 0.25
				stamina -= 25.0
				since_spend = 0.0
		var rolling := t < invuln_until
		# --- daño del jefe a Kaelen (una vez por ataque) ---
		if boss.state == Boss.State.ACTIVE and not attack_hit_done and boss.current_attack:
			if _boss_hits(boss, player, beam_line):
				attack_hit_done = true
				if not rolling:
					damage_taken += boss.current_attack.damage
		if boss.state == Boss.State.TELEGRAPH and boss.current_attack and boss.current_attack.id == &"beam" and beam_line.is_empty() \
				and boss._state_time >= boss.current_attack.telegraph_time * boss.telegraph_scale / boss._speed() * Boss.TRACK_FRACTION:
			var aim: Vector3 = boss.aim_point_for(&"beam", player.global_position)
			var tg := GhidorahBeamAim.clamp_target(boss.global_position, aim, boss.current_attack.min_range, boss.current_attack.max_range)
			beam_line = GhidorahBeamAim.sweep_line(boss.global_position, tg, 2.5, 2.0)
		if boss.state == Boss.State.ACTIVE and boss.current_attack and boss.current_attack.id == &"beam" and not beam_line.is_empty():
			var progress := clampf(boss._state_time / (boss.current_attack.active_time / boss._speed()), 0.0, 1.0)
			beam_line["progress"] = progress

		# --- esbirros ---
		wave_timer -= DT
		if minions.is_empty() and wave_timer <= 0.0:
			for i in 3:
				var m := SimMinion.new()
				m.add_to_group("enemy")
				root.add_child(m)
				var ang := _rng.randf() * TAU
				m.global_position = Vector3(cos(ang), 0.0, sin(ang)) * (ARENA - 3.0)
				minions.append(m)
			wave_timer = WAVE_DELAY
		var slots := SquadTactics.token_slots(boss._threat_on, boss._threat_near, 2)
		minion_attacking = 0
		for m: SimMinion in minions:
			if m.state == 3:
				minion_attacking += 1
		for m: SimMinion in minions:
			var dealt := _step_minion(m, player, DT, slots - minion_attacking)
			if dealt > 0 and not rolling:
				damage_taken += dealt
			if m.state == 3 and m.attack_t < 0.0:
				pass
		squad_timer += DT
		if squad_timer >= 0.35:
			orch.call(&"_update_squad", 0.35)
			squad_timer = 0.0

		# --- Kaelen ---
		var swing := _step_player(profile, player, boss, minions, t, DT)
		if swing and t >= busy_until and not rolling and stamina >= 20.0:
			var near_boss := pdist <= REACH + 0.4
			if profile == "agresiva" or boss.state == Boss.State.RECOVER or boss.state == Boss.State.ROAR:
				if near_boss and (profile == "agresiva" or punish < 2):
					var k := combo % 3
					busy_until = t + Player.HIT_END[k]
					stamina -= 20.0
					since_spend = 0.0
					hits.append([t + Player.HIT_START[k], Player.combo_damage(combo)])
					combo += 1
					punish += 1
		while not hits.is_empty() and hits[0][0] <= t:
			var h: Array = hits.pop_front()
			if _flat(player.global_position - boss.global_position).length() <= REACH + 0.6 and player.shove_left <= 0.0:
				boss._on_hurt(h[1], sword)
		# Cada mandoble también corta esbirros cercanos (1 de vida por golpe).
		if swing and t >= busy_until - 0.01 and not minions.is_empty() and profile == "huidiza":
			for m: SimMinion in minions.duplicate():
				if _flat(m.global_position - player.global_position).length() < 2.2 and _rng.randf() < DT * 3.0:
					m.hp -= 1
					if m.hp <= 0:
						minions.erase(m)
						m.remove_from_group("enemy")
						m.free()
	var out := {
		dmg = damage_taken, secs = t, dead = boss.state == Boss.State.DEAD,
		atk = goal_frames[0], cut = goal_frames[1], wait = goal_frames[2], pin = goal_frames[3],
		cuts = boss.tactics.entries[BossTactics.Goal.CUT_OFF], pins = boss.tactics.entries[BossTactics.Goal.PINCER],
		waits = boss.tactics.entries[BossTactics.Goal.WAIT], amb = boss.ambush_count,
	}
	for m: SimMinion in minions:
		m.free()
	orch.free()
	boss.free()
	player.free()
	sword.free()
	return out


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## ¿El ataque en curso alcanza a Kaelen ahora? Volúmenes simples según el tipo de ataque.
func _boss_hits(boss: Boss, player: Node3D, beam_line: Dictionary) -> bool:
	var a := boss.current_attack
	var to := _flat(player.global_position - boss.global_position)
	var dist := to.length()
	if a.id == &"beam":
		if beam_line.is_empty() or not beam_line.has("progress"):
			return false
		var impact := GhidorahBeamAim.sweep_point(beam_line, float(beam_line.progress))
		return _flat(player.global_position - impact).length() <= 1.7
	if a.spin_degrees > 0.0 or a.id == &"stomp":
		return dist <= a.max_range
	var forward := _flat(-boss.global_basis.z).normalized()
	var reach := a.max_range
	if a.id == &"charge":
		reach = 3.4   # embiste: el jefe avanza, la caja de daño va pegada a él
	elif a.id == &"pounce":
		reach = 4.5
	if dist > reach + 0.4:
		return false
	return dist < 1.2 or forward.dot(to.normalized()) >= 0.5


## Mueve a Kaelen; devuelve true si puede intentar un mandoble.
func _step_player(profile: String, player: Dummy, boss: Boss, minions: Array, t: float, dt: float) -> bool:
	var pos := player.global_position
	if player.shove_left > 0.0:
		return false
	var to_boss := _flat(boss.global_position - pos)
	var dist := to_boss.length()
	var move := Vector3.ZERO
	var speed := RUN
	var swing := false
	if profile == "agresiva":
		var home := boss.global_position - to_boss.normalized() * REACH if dist > 0.01 else pos
		move = _flat(home - pos)
		speed = 5.0
		swing = true
	else:
		var minion: SimMinion = null
		var best := INF
		for m: SimMinion in minions:
			var d := _flat(m.global_position - pos).length()
			if d < best:
				best = d
				minion = m
		if boss.state == Boss.State.RECOVER and dist < 5.0:
			move = to_boss - to_boss.normalized() * REACH   # entra a castigar
			swing = true
		elif minion != null and dist > 4.0:
			var to_m := _flat(minion.global_position - pos)
			move = to_m if to_m.length() > 1.6 else Vector3.ZERO
			swing = true
		elif dist < 9.0:
			move = -to_boss.normalized() + Vector3.UP.cross(to_boss.normalized()) * 0.5   # se aleja rodeando
		elif dist <= 13.0:
			move = Vector3.UP.cross(to_boss.normalized()) * 0.8
			speed = 3.5
		else:
			move = Vector3.ZERO
	if move.length() > 0.05:
		var step := minf(speed * dt, move.length()) if profile == "agresiva" else speed * dt
		pos += move.normalized() * step
	# Dentro de la arena.
	if Vector2(pos.x, pos.z).length() > ARENA:
		var c := Vector2(pos.x, pos.z).normalized() * ARENA
		pos = Vector3(c.x, pos.y, c.y)
	player.global_position = pos
	return swing


## Esbirro simple: persigue/ocupa su punto de cerco y ataca si hay "ficha" libre (amenazas compartidas).
func _step_minion(m: SimMinion, player: Node3D, dt: float, free_slots: int) -> int:
	m.order_left = maxf(0.0, m.order_left - dt)
	m.cooldown = maxf(0.0, m.cooldown - dt)
	var to_player := _flat(player.global_position - m.global_position)
	var dealt := 0
	if m.attack_t >= 0.0:
		m.attack_t += dt
		if m.attack_t >= 0.5 and not m.damage_done:
			m.damage_done = true
			if to_player.length() <= 1.9:
				dealt = MINION_DAMAGE
		if m.attack_t >= 1.6:
			m.attack_t = -1.0
			m.state = 1
			m.cooldown = 2.0
		return dealt
	var target := player.global_position
	var stop_at := 1.4
	if m.order_left > 0.0:
		target = m.order_point
		stop_at = 0.8
		m.state = 2
	else:
		m.state = 1
	var to_target := _flat(target - m.global_position)
	if to_target.length() > stop_at:
		m.global_position += to_target.normalized() * MINION_SPEED * dt
	if to_player.length() <= 1.6 and m.cooldown <= 0.0 and free_slots > 0:
		m.attack_t = 0.0
		m.damage_done = false
		m.state = 3
	return dealt
