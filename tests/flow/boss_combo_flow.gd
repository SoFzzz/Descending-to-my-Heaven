extends Node
## Each boss, forced into phase 2 in its own arena, chains at least one combo against a standing
## (invulnerable) Kaelen, and never in phase 1:
##  godot --headless --path . res://tests/flow/boss_combo_flow.tscn
## The Orchestrator is stopped so no minions get in the way. Exits with code 1 if anything fails.

const WATCH := 25.0

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
