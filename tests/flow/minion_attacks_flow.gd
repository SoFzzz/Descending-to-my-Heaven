extends Node
## Every attack of every minion lands on a standing Kaelen, in its arena, with the real tree:
##  godot --headless --path . res://tests/flow/minion_attacks_flow.tscn
## Each attack is tested alone (the minion gets a one-attack list) from inside its range.
## The boss is switched off and the Orchestrator stopped, so only the tested minion acts.
## Exits with code 1 if anything fails.

const TIMEOUT := 8.0

## arena -> minion scenes of that arena.
const CASES := {
	1: ["res://scenes/enemies/minion_skeleton.tscn", "res://scenes/enemies/minion_knight_elite.tscn"],
	2: ["res://scenes/enemies/minion_plague.tscn", "res://scenes/enemies/minion_plague_elite.tscn"],
	3: ["res://scenes/enemies/minion_wrapper.tscn", "res://scenes/enemies/minion_reaper_elite.tscn"],
}

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
	for arena in CASES:
		var level := (load("res://scenes/levels/arena_%d_gameplay.tscn" % arena) as PackedScene).instantiate()
		get_tree().current_scene.add_child(level)
		await _wait(0.5)
		Orchestrator.end_arena()
		var boss := level.get_node_or_null(^"Boss") as Node3D
		if boss:
			boss.process_mode = Node.PROCESS_MODE_DISABLED
			boss.global_position += Vector3.DOWN * 200.0
		var player := get_tree().get_first_node_in_group("player") as Node3D
		var health: Health = player.get(&"health")
		for path in CASES[arena]:
			var scene := load(path) as PackedScene
			var probe := scene.instantiate() as Minion
			var attacks := probe.attacks.duplicate()
			probe.free()
			for atk: MinionAttack in attacks:
				await _try_attack(level, player, health, scene, atk, path.get_file().get_basename())
		await _clip_deaths(level, player, CASES[arena].filter(func(p: String) -> bool: return not p.ends_with("minion_wrapper.tscn")))
		if arena == 1:
			await _knockback(level, player as Player)
		if arena == 2:
			await _spell_visuals(level, player, health)
			await _taunt_on_death(level, player as Player)
		if arena == 3:
			await _wrapper_collapse(level, player)
			await _runner(level, player, health)
		level.queue_free()
		await _wait(0.3)
	print("FLOW: OK" if _fails == 0 else "FLOW: FAIL (%d)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


## Kaelen's hits push minions back: a little on a normal slash, a lot on the combo's 3rd hit (and a
## longer stun), half as much on an elite; the heavy attack stuns HEAVY_STUN s.
func _knockback(level: Node, player: Player) -> void:
	player._god = true
	var cases := [["normal", 0, false], ["finisher", 2, false], ["elite finisher", 2, true], ["heavy", -1, false]]
	var moved := {}
	for c in cases:
		var path := "res://scenes/enemies/minion_knight_elite.tscn" if c[2] else "res://scenes/enemies/minion_skeleton.tscn"
		var minion := (load(path) as PackedScene).instantiate() as Minion
		level.add_child(minion)
		var fwd := player.get_facing()
		fwd.y = 0.0
		minion.global_position = player.global_position + fwd.normalized() * 1.6
		await _wait(0.2)
		player.stamina.current = player.stamina.max_value
		if c[1] < 0:
			player.try_heavy_attack()
		else:
			player.try_attack()
			player.combo_index = c[1]
		var start := minion.global_position
		minion.hurtbox.receive_hit(1, player)
		await _wait(0.5)
		var d := Vector2(minion.global_position.x - start.x, minion.global_position.z - start.z).length()
		moved[c[0]] = d
		if c[0] == "heavy":
			_check(minion.state == MinionBrain.State.STUNNED, "heavy: still stunned after 0.5 s")
			await _wait(Minion.HEAVY_STUN - 0.4)
			_check(minion.state != MinionBrain.State.STUNNED, "heavy: the stun ends after %.1f s" % Minion.HEAVY_STUN)
		player._end_attack()
		minion.queue_free()
		await _wait(0.6)
	_check(moved["normal"] > 0.2 and moved["normal"] < 0.7, "normal hit pushes back a little (%.2f m)" % moved["normal"])
	_check(moved["finisher"] > 0.9, "3rd hit pushes back a lot (%.2f m)" % moved["finisher"])
	_check(moved["elite finisher"] < moved["finisher"] * 0.75, "an elite is pushed less (%.2f m)" % moved["elite finisher"])
	player._god = false


## The Plague Arcanist's cast: a magic circle on Kaelen's spot, an orb that flies onto it, the
## yellow aura on the caster during the windup.
func _spell_visuals(level: Node, player: Node3D, health: Health) -> void:
	health.reset(health.max_value)
	await _wait(1.2)
	var minion := (load("res://scenes/enemies/minion_plague.tscn") as PackedScene).instantiate() as Minion
	var cast: Array[MinionAttack] = [load("res://resources/attacks/minions/plague_cast.tres")]
	minion.attacks = cast
	level.add_child(minion)
	var dir := -player.global_basis.z
	dir.y = 0.0
	minion.global_position = player.global_position + dir.normalized() * 5.0
	minion.alert()
	var circle := false
	var orb := false
	var aura := 0.0
	var t := 0.0
	while t < 6.0 and not (circle and orb):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		circle = circle or (minion._spell_circle != null and is_instance_valid(minion._spell_circle))
		orb = orb or level.find_child("SpellOrb", true, false) != null
		aura = maxf(aura, AttackWarning.aura_of(minion._model_root))
	_check(circle, "cast: magic circle on Kaelen's spot")
	_check(orb, "cast: the orb flies to the circle")
	_check(aura > 0.3, "cast: yellow aura on the caster (%.2f)" % aura)
	await _wait(2.0)
	_check(AttackWarning.aura_of(minion._model_root) < 0.05, "cast: the aura fades after the blow")
	minion.release_token()
	minion.queue_free()
	await _wait(0.3)


## Kaelen dies: the minions stay and mock her instead of vanishing.
func _taunt_on_death(level: Node, player: Player) -> void:
	Orchestrator.end_arena()
	var gameplay := level as Node
	Orchestrator.begin_arena(gameplay.get(&"config"), gameplay, null)
	Orchestrator.spawn_wave(2)
	await _wait(0.5)
	var minions := get_tree().get_nodes_in_group(&"enemy").filter(func(n: Node) -> bool: return n is Minion)
	_check(minions.size() >= 1, "death: a wave is out (%d)" % minions.size())
	Orchestrator._on_player_died()   # (the global signal would also open the death screen and pause)
	await _wait(1.5)
	var alive := minions.filter(func(n: Node) -> bool: return is_instance_valid(n))
	_check(alive.size() == minions.size(), "death: the minions stay (%d / %d)" % [alive.size(), minions.size()])
	_check(alive.all(func(m: Minion) -> bool: return m.is_taunting()), "death: they mock Kaelen")
	for m in alive:
		m.queue_free()
	await _wait(0.3)


## Arena 3 threat: TheWrapper sprints with its run clip while far and walks once it is close.
func _runner(level: Node, player: Node3D, health: Health) -> void:
	health.reset(health.max_value)
	var minion := (load("res://scenes/enemies/minion_wrapper.tscn") as PackedScene).instantiate() as Minion
	level.add_child(minion)
	var dir := -player.global_basis.z
	dir.y = 0.0
	minion.global_position = player.global_position + dir.normalized() * 14.0
	minion.alert()
	var top := 0.0
	var ran := false
	var t := 0.0
	while t < 3.0 and minion.global_position.distance_to(player.global_position) > minion.run_distance + 1.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		top = maxf(top, Vector2(minion.velocity.x, minion.velocity.z).length())
		if minion._anim.current_animation == minion.anim_run:
			ran = true
	_check(top > minion.move_speed + 1.0, "wrapper: sprints while far (%.1f m/s)" % top)
	_check(ran, "wrapper: plays its run clip while sprinting")
	while t < 6.0 and minion.global_position.distance_to(player.global_position) > minion.run_distance - 1.5:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var near_speed := Vector2(minion.velocity.x, minion.velocity.z).length()
	_check(near_speed <= minion.move_speed + 0.2, "wrapper: walks once close (%.1f m/s)" % near_speed)
	minion.release_token()
	minion.queue_free()
	await get_tree().physics_frame


## TheWrapper has no death clip: it collapses with the tween (stagger clip, buckle, fall, dust).
func _wrapper_collapse(level: Node, player: Node3D) -> void:
	var minion := (load("res://scenes/enemies/minion_wrapper.tscn") as PackedScene).instantiate() as Minion
	level.add_child(minion)
	minion.global_position = player.global_position + Vector3(6, 0, 6)
	await _wait(0.3)
	minion.health.take_damage(9999)
	await _wait(0.15)
	_check(minion._anim.current_animation == minion.death_stagger_clip, "wrapper: stagger clip while collapsing")
	var holder := minion.get_node(^"Model") as Node3D
	_check(holder.rotation.x < 0.0, "wrapper: buckles forward first (%.2f)" % holder.rotation.x)
	await _wait(1.1)
	_check(is_instance_valid(minion) and absf(holder.rotation.x - PI * 0.5) < 0.05, "wrapper: lies on the floor")
	_check(minion._anim.speed_scale == 0.0, "wrapper: pose frozen on landing")
	await _wait(minion.death_landing - 1.25)   # _check_corpse counts from the landing
	await _check_corpse(minion, minion.death_landing, "wrapper")


## Every minion with a death clip falls within death_fall_time (it no longer vanishes mid-stagger).
func _clip_deaths(level: Node, player: Node3D, paths: Array) -> void:
	for path in paths:
		var minion := (load(path) as PackedScene).instantiate() as Minion
		level.add_child(minion)
		minion.global_position = player.global_position + Vector3(-6, 0, 6)
		await _wait(0.3)
		minion.health.take_damage(9999)
		var label: String = path.get_file().get_basename()
		var anim := minion._anim
		var land: float = minion.death_land_at if minion.death_land_at > 0.0 else anim.get_animation(minion.anim_death).length
		_check(minion.death_landing <= minion.death_fall_time + 0.01, "%s: falls in %.2f s (<= %.1f)" % [
				label, minion.death_landing, minion.death_fall_time])
		await _wait(minion.death_landing + 0.1)
		_check(is_instance_valid(minion) and anim.assigned_animation == minion.anim_death \
				and anim.current_animation_position >= land - 0.05, "%s: on the floor (clip at %.2f / %.2f)" % [
				label, anim.current_animation_position, land])
		await _check_corpse(minion, minion.death_landing + 0.1, label)


## The corpse stays corpse_time s on the floor, then sinks and is freed.
func _check_corpse(minion: Minion, elapsed: float, label: String) -> void:
	await _wait(minion.corpse_time - 0.5)
	_check(is_instance_valid(minion), "%s: the corpse lies on the floor (%.1f s after dying)" % [label, elapsed + minion.corpse_time - 0.5])
	var holder := minion.get_node(^"Model") as Node3D
	var y0 := holder.position.y
	await _wait(1.0)
	_check(is_instance_valid(minion) and holder.position.y < y0 - 0.1, "%s: it sinks into the floor" % label)
	await _wait(Minion.CORPSE_SINK_TIME)
	_check(not is_instance_valid(minion), "%s: corpse freed after sinking" % label)


func _try_attack(level: Node, player: Node3D, health: Health, scene: PackedScene, atk: MinionAttack, label: String) -> void:
	health.reset(health.max_value)
	await _wait(1.2)   # Kaelen's hurt i-frames from the previous case
	var minion := scene.instantiate() as Minion
	var list: Array[MinionAttack] = [atk]
	minion.attacks = list
	var dist := clampf(lerpf(atk.min_range, atk.max_range, 0.6), 1.0, 6.0)
	var dir := -player.global_basis.z
	dir.y = 0.0
	level.add_child(minion)
	minion.global_position = player.global_position + dir.normalized() * dist
	minion.look_at(player.global_position, Vector3.UP)
	minion.alert()
	var before := health.current
	var t := 0.0
	var attacked := false
	while t < TIMEOUT and health.current == before:
		if minion.state == MinionBrain.State.ATTACK:
			attacked = true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var dealt := before - health.current
	_check(attacked, "%s/%s: started its attack" % [label, atk.id])
	_check(dealt > 0, "%s/%s: hit Kaelen (%d damage, %.1f s)" % [label, atk.id, dealt, t])
	var expected := roundi(minion.damage * atk.damage_mult)
	_check(dealt == expected, "%s/%s: exactly one blow of %d" % [label, atk.id, expected])
	minion.release_token()
	minion.queue_free()
	await get_tree().physics_frame
