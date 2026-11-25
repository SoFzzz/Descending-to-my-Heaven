extends Node
## Each boss, forced into phase 2 in its own arena, chains at least one combo against a standing
## (invulnerable) Kaelen, and never in phase 1. Also the chase gap (AGENTS.md 18.3): a Kaelen that
## keeps circling the boss beyond its engage_range but inside the reach of one of its attacks, as fast
## as it walks, must be attacked instead of chased forever. And the phase-2 roar: short, invulnerable
## and with the repel shockwave that pushes a Kaelen standing next to the boss:
##  godot --headless --path . res://tests/flow/boss_combo_flow.tscn
## The Orchestrator is stopped so no minions get in the way. Exits with code 1 if anything fails.

const WATCH := 25.0
## Chase check: seconds the boss has to attack, and Kaelen's orbit radius per arena (beyond
## engage_range, inside the bite / tail of the Bone Dragon and the tail of Ghidorah).
const CHASE_WATCH := 3.0
const CHASE_RADIUS := {1: 4.0, 3: 6.5}

var _fails := 0


func _ready() -> void:
	_detach.call_deferred()


func _detach() -> void:
	var tree := get_tree()
	reparent(tree.root)
	var placeholder := Node.new()
	tree.root.add_child(placeholder)
	tree.current_scene = placeholder
	_run()


func _check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		_fails += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _run() -> void:
	for arena in [1, 2, 3]:
		for phase in [1, 2]:
			await _watch(arena, phase)
	for arena in CHASE_RADIUS:
		await _chase(arena, CHASE_RADIUS[arena])
	for arena in [1, 2, 3]:
		await _phase_roar(arena)
	print("FLOW: OK" if _fails == 0 else "FLOW: FAIL (%d)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _watch(arena: int, phase: int) -> void:
	var level := (load("res://scenes/levels/arena_%d_gameplay.tscn" % arena) as PackedScene).instantiate()
	get_tree().current_scene.add_child(level)
	await _wait(0.5)
	Orchestrator.end_arena()
	var player := get_tree().get_first_node_in_group("player") as Player
	player._god = true
	var boss := level.get_node("Boss") as Boss
	boss.phase = phase
	boss.repel_enabled = false   # the repel roar would interrupt the strings being measured
	# Kaelen 3 m in front of the boss, inside the melee attacks' range.
	var fwd := -boss.global_basis.z
	fwd.y = 0.0
	player.global_position = boss.global_position + fwd.normalized() * (boss.engage_range + 1.0)
	var started: Array[StringName] = []
	boss.attack_started.connect(func(a: BossAttack) -> void: started.append(a.id))
	# The warning aura rises progressively (never pops in) and fades after the blow.
	var first_tg := -1.0
	var first_aura := -1.0
	var peak := 0.0
	var fell := false
	var t := 0.0
	while t < WATCH and (phase == 1 or boss.combo_count == 0):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var a := AttackWarning.aura_of(boss._model)
		if boss.state == Boss.State.TELEGRAPH and first_tg < 0.0:
			first_tg = t
		if first_tg >= 0.0 and first_aura < 0.0 and t - first_tg >= 0.05:
			first_aura = a
		peak = maxf(peak, a)
		fell = fell or (peak > 0.9 and a < 0.1)
	var label := "%s phase %d" % [boss.display_name, phase]
	_check(started.size() > 0, "%s: attacks (%s)" % [label, ", ".join(started)])
	_check(first_aura >= 0.0 and first_aura < 0.5, "%s: the aura starts low (%.2f at 0.05 s)" % [label, first_aura])
	_check(peak > 0.9, "%s: the aura reaches full strength (%.2f)" % [label, peak])
	if phase == 1:
		_check(fell, "%s: the aura fades between attacks" % label)
		_check(boss.combo_count == 0, "%s: no combos in phase 1" % label)
	else:
		_check(boss.combo_count > 0, "%s: chains a combo (%.1f s)" % [label, t])
	level.queue_free()
	await _wait(0.3)


## Kaelen orbits the boss at `radius` m and boss.move_speed m/s (her lock-on step is 3.2 m/s), so the
## boss never reaches its engage_range although an attack reaches her.
func _chase(arena: int, radius: float) -> void:
	var level := (load("res://scenes/levels/arena_%d_gameplay.tscn" % arena) as PackedScene).instantiate()
	get_tree().current_scene.add_child(level)
	await _wait(0.5)
	Orchestrator.end_arena()
	var player := get_tree().get_first_node_in_group("player") as Player
	player._god = true
	var boss := level.get_node("Boss") as Boss
	var fwd := -boss.global_basis.z
	var angle := atan2(fwd.x, fwd.z)
	var height := player.global_position.y
	var t := 0.0
	var min_distance := INF
	while t < CHASE_WATCH and boss.attack_log.is_empty():
		angle += boss.move_speed / radius * get_physics_process_delta_time()
		var centre := boss.global_position
		player.global_position = Vector3(centre.x + sin(angle) * radius, height, centre.z + cos(angle) * radius)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		min_distance = minf(min_distance, boss._flat_distance())
	var label := "%s chase" % boss.display_name
	_check(min_distance > boss.engage_range, "%s: Kaelen stays beyond engage_range (%.2f > %.1f m)" % [label, min_distance, boss.engage_range])
	_check(not boss.attack_log.is_empty(), "%s: attacks a Kaelen circling %.1f m away within %.1f s (%s after %.2f s)" % [
		label, radius, CHASE_WATCH, ", ".join(boss.attack_log), t])
	level.queue_free()
	await _wait(0.3)


## Kaelen 1 m beyond engage_range; one hit takes the boss to 50 %: it roars for Boss.PHASE2_ROAR_TIME,
## a hit during the roar does nothing and the shockwave throws her out.
func _phase_roar(arena: int) -> void:
	var level := (load("res://scenes/levels/arena_%d_gameplay.tscn" % arena) as PackedScene).instantiate()
	get_tree().current_scene.add_child(level)
	await _wait(0.5)
	Orchestrator.end_arena()
	var player := get_tree().get_first_node_in_group("player") as Player
	player._god = true
	var boss := level.get_node("Boss") as Boss
	var fwd := -boss.global_basis.z
	fwd.y = 0.0
	player.global_position = boss.global_position + fwd.normalized() * (boss.engage_range + 1.0)
	await get_tree().physics_frame
	var start := boss._flat_distance()
	var source := Node.new()
	add_child(source)
	boss.health.reset(boss.max_health)
	boss.health.take_damage(boss.max_health - floori(boss.max_health * 0.5) - 1)   # one point above 50 %
	boss._on_hurt(1, source)   # crosses 50 %
	var roar_start := -1.0
	var roar_end := -1.0
	var hp_in_roar := -1
	var hittable_in_roar := -1
	var hittable_after := -1
	var pushed := false
	var farthest := start
	var t := 0.0
	while t < 4.0 and roar_end < 0.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if boss.state == Boss.State.ROAR and boss.phase_roaring and roar_start < 0.0:
			roar_start = t
		if roar_start >= 0.0 and boss.state == Boss.State.ROAR and hp_in_roar < 0 and t - roar_start > 0.5:
			hp_in_roar = boss.health.current
			hittable_in_roar = _hittable(boss)
			boss._on_hurt(40, source)
			hp_in_roar -= boss.health.current   # damage that got through
		pushed = pushed or player.state == Player.State.HURT
		farthest = maxf(farthest, boss._flat_distance())
		if roar_start >= 0.0 and boss.state != Boss.State.ROAR:
			roar_end = t
			hittable_after = _hittable(boss)
	var label := "%s phase roar" % boss.display_name
	var length := roar_end - roar_start
	_check(roar_start >= 0.0 and absf(length - Boss.PHASE2_ROAR_TIME) <= 0.05, "%s: lasts %.2f s (%.1f s wanted)" % [label, length, Boss.PHASE2_ROAR_TIME])
	_check(hp_in_roar == 0, "%s: invulnerable while roaring (%d damage got through)" % [label, hp_in_roar])
	_check(hittable_in_roar == 0 and hittable_after > 0, "%s: no hit feedback while roaring (%d hurtboxes take hits; %d after)" % [label, hittable_in_roar, hittable_after])
	_check(pushed and farthest >= start + 3.0, "%s: the shockwave pushes Kaelen (%.1f m -> %.1f m)" % [label, start, farthest])
	source.queue_free()
	level.queue_free()
	await _wait(0.3)


## Boss hurtboxes that would accept a sword hit now (Hurtbox.can_be_hit gates hit-stop, sound and flash).
func _hittable(boss: Boss) -> int:
	var n := 0
	for node in boss.find_children("*", "Hurtbox", true, false):
		if (node as Hurtbox).can_be_hit():
			n += 1
	return n
