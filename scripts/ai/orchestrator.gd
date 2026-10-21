extends Node
## Autoload "Orchestrator": combat pacing (spec 8.3). Wraps OrchestratorModel (pure,
## tested logic) and handles what needs the tree: reading Kaelen and the minions,
## choosing spawn points and spawning / freeing minions.
##
## Lifecycle: the arena gameplay explicitly calls `begin_arena(config, self, boss)`
## at the end of its _ready (after emitting Events.arena_entered). This is preferred over reacting
## to `arena_entered` because that signal only carries the id and the Orchestrator needs the ArenaConfig,
## the arena root (to filter the spawn_points) and the boss. The arena also ends by itself: on
## Events.boss_defeated the live minions die (they fall like any other) and on Events.player_died
## they stop and mock Kaelen over her body (Minion.celebrate) instead of vanishing; GameState calls
## `end_arena()` when changing scene, which frees whatever is left.
##
## Autoloads are looked up by path (get_node_or_null) because they do not exist under `-s`.

const NEAR_RANGE := 5.0           # an enemy is "near" Kaelen for the intensity
const SPAWN_SEPARATION := 1.3     # minimum distance between freshly spawned minions
const SQUAD_INTERVAL := 0.35      # how often the pincer orders are handed out
const ORDER_DURATION := 0.9       # s each position order lasts (renewed while the pincer goes on)
const CHEST_OFFSET := Vector3(0.0, 1.0, 0.0)   # the point is checked at minion mid height

var model := OrchestratorModel.new()

var _config: ArenaConfig
var _arena_root: Node3D
var _boss: Boss
var _active := false
var _minions: Array = []
var _time_since_hit := 10.0       # starts "calm" so the first wave is a normal one
var _boss_phase := 1
var _last_budget := 0             # budget of the last wave spawned (for debugging)
var _spawn_count := 0             # rotating spawn point index
var _failed_waves := 0            # consecutive attempts without valid points: from the 2nd on the fallback is allowed
var last_spawn_tier := OrchestratorModel.SpawnTier.NONE   # tier of the last selection (debugging)
var _total_spawned := 0           # to name the minions without repeats
var _player: Node3D
var _player_health: Health
var _squad_timer := 0.0
var _pincer_active := false
## Pincer orders handed out in this arena (debugging and simulation).
var pincer_orders := 0


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_prune_minions()
	_time_since_hit += delta
	if not _find_player():
		return
	_update_squad(delta)
	var ctx := build_context()
	var budget := model.update(delta, ctx)
	if budget > 0:
		_last_budget = budget
		if spawn_wave(budget) == 0:
			_failed_waves += 1
			model.retry_wave_soon()
		else:
			_failed_waves = 0


## `arena_root`: node under which the spawn_points live and where the minions are instanced
## (the current scene by default). `boss`: to read its phase and special attacks.
func begin_arena(config: ArenaConfig, arena_root: Node3D = null, boss: Boss = null) -> void:
	if _active:
		end_arena()
	_config = config
	_arena_root = arena_root if arena_root else get_tree().current_scene as Node3D
	_boss = boss
	_boss_phase = 1
	_time_since_hit = 10.0
	_last_budget = 0
	_spawn_count = 0
	_failed_waves = 0
	last_spawn_tier = OrchestratorModel.SpawnTier.NONE
	_total_spawned = 0
	_squad_timer = 0.0
	_pincer_active = false
	pincer_orders = 0
	if config:
		model.base_budget = config.base_budget
		model.max_alive = config.max_alive
		model.wave_size_min = config.wave_size_min
		model.wave_size_max = config.wave_size_max
		model.clear_delay = config.clear_delay
		model.first_wave_delay = config.first_wave_delay
	model.reset()
	_connect_events(true)
	_active = config != null and config.minion_scene != null


## End of the arena (boss defeated, Kaelen dead or scene change): model zeroed, minions
## freed and tokens at 0. Each minion returns its token and is freed BEFORE the reset; besides,
## Minion._has_token() asks AttackTokens, so no minion can be left believing it holds a token
## after an AttackTokens.reset().
func end_arena(free_minions := true) -> void:
	_connect_events(false)
	_active = false
	for minion in _minions.duplicate():
		if is_instance_valid(minion):
			minion.call(&"release_token")
			if free_minions:
				minion.queue_free()
	_minions.clear()
	model.reset()
	_last_budget = 0
	_boss = null
	_player = null
	_player_health = null
	var tokens := get_node_or_null(^"/root/AttackTokens")
	if tokens:
		tokens.call(&"reset")


func get_debug_info() -> Dictionary:
	_prune_minions()
	var tokens := get_node_or_null(^"/root/AttackTokens")
	var info := {
		"intensity": model.intensity,
		"phase": model.phase,
		"budget": _last_budget,
		"alive": _minions.size(),
		"cycle": model.cycle,
		"cycle_time": model.wave_timer,
		"tokens": tokens.call(&"holders_count") if tokens else 0,
	}
	if _boss and is_instance_valid(_boss) and _boss.tactics_enabled:
		info["boss_goal"] = _boss.tactics.goal_name()
		info["kaelen"] = _boss.memory.behavior_name()
		info["distracted"] = _boss.memory.distracted
	return info


## Model context built from the real state of the tree.
func build_context() -> Dictionary:
	var near := 0
	if _player:
		for minion in _minions:
			if minion.global_position.distance_to(_player.global_position) < NEAR_RANGE:
				near += 1
	var hp_ratio := 1.0
	if _player_health and _player_health.max_value > 0:
		hp_ratio = float(_player_health.current) / float(_player_health.max_value)
	return {
		hp_ratio = hp_ratio,
		enemies_near = near,
		enemies_alive = _minions.size(),
		time_since_hit = _time_since_hit,
		boss_phase = _boss.phase if _boss and is_instance_valid(_boss) else _boss_phase,
		boss_special = is_boss_special(_boss),
	}


## Boss "special attack": the phase-change roar, or a phase-2 attack (phase_min >= 2)
## or one with a spin (spin_degrees > 0, e.g. the tail sweep) in warning or active.
static func is_boss_special(boss: Boss) -> bool:
	if boss == null or not is_instance_valid(boss):
		return false
	if boss.state == Boss.State.ROAR:
		return true
	if boss.state == Boss.State.TELEGRAPH or boss.state == Boss.State.ACTIVE:
		var attack := boss.current_attack
		return attack != null and (attack.phase_min >= 2 or attack.spin_degrees > 0.0)
	return false


# --- Squad (pincer) ---------------------------------------------------------------------------

## While the boss goal is PINCER, hands the live minions encirclement points on the side of
## Kaelen OPPOSITE the boss (SquadTactics.pincer_points). When the pincer ends it clears the orders.
func _update_squad(delta: float) -> void:
	_squad_timer += delta
	if _squad_timer < SQUAD_INTERVAL:
		return
	_squad_timer = 0.0
	var on := _boss != null and is_instance_valid(_boss) and _boss.tactics_enabled \
			and _boss.state != Boss.State.DEAD and _boss.tactics.goal == BossTactics.Goal.PINCER \
			and _player != null
	if not on:
		if _pincer_active:
			_pincer_active = false
			for minion in _minions:
				if is_instance_valid(minion) and minion.has_method(&"clear_order"):
					minion.call(&"clear_order")
		return
	_pincer_active = true
	var squad: Array = []
	for minion in _minions:
		if is_instance_valid(minion) and minion.has_method(&"order_to") and not minion.call(&"is_retreating") \
				and minion.get(&"state") != MinionBrain.State.ATTACK \
				and minion.get(&"state") != MinionBrain.State.DEAD:
			squad.append(minion)
	var from: Array[Vector3] = []
	for minion: Node3D in squad:
		from.append(minion.global_position)
	var points := SquadTactics.pincer_points(_player.global_position, _boss.global_position, squad.size())
	var assignment := SquadTactics.assign_points(from, points)
	for i in squad.size():
		if assignment[i] >= 0:
			squad[i].call(&"order_to", points[assignment[i]], ORDER_DURATION)
			pincer_orders += 1


# --- Spawning ---------------------------------------------------------------------------------

## Spawns a group of `count` minions (without exceeding max_alive alive) at valid points; if the
## arena has an elite, the first of the group is the elite (1 elite + count-1 normal). Returns how many it spawned.
func spawn_wave(count: int) -> int:
	if _config == null or not _find_player():
		return 0
	var points := valid_spawn_points()
	if points.is_empty():
		return 0
	var spawned := 0
	var index := _spawn_count
	while spawned < count and _minions.size() < model.max_alive:
		var scene := _config.minion_scene
		if _config.elite_scene and spawned == 0:
			scene = _config.elite_scene
		var point := points[index % points.size()]
		index += 1
		_spawn_at(scene, point)
		spawned += 1
	_spawn_count = index
	return spawned


## Eligible spawn_points according to OrchestratorModel.select_spawn_points (by tier): 1) outside the cone
## of the camera and farther than 8 m from Kaelen; 2) if none, farther than 14 m even if visible; 3) if none and one
## attempt already failed (the retry), only the farthest one beyond 8 m. Empty = the wave is delayed.
func valid_spawn_points() -> Array[Node3D]:
	var camera := get_viewport().get_camera_3d()
	var nodes: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(&"spawn_point"):
		var point := node as Node3D
		if point == null or not point.is_inside_tree():
			continue
		if _arena_root and not _arena_root.is_ancestor_of(point):
			continue
		nodes.append(point)
	# Stable order by name: the selection is deterministic.
	nodes.sort_custom(func(a: Node3D, b: Node3D) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	var positions: Array[Vector3] = []
	var in_view: Array[bool] = []
	for point in nodes:
		positions.append(point.global_position)
		var probe := point.global_position + CHEST_OFFSET
		in_view.append(camera != null and not camera.is_position_behind(probe) and camera.is_position_in_frustum(probe))
	var pick := OrchestratorModel.select_spawn_points(positions, _player.global_position, in_view, _failed_waves > 0)
	last_spawn_tier = pick.tier
	var result: Array[Node3D] = []
	for i: int in pick.indices:
		result.append(nodes[i])
	return result


func _spawn_at(scene: PackedScene, point: Node3D) -> void:
	var minion := scene.instantiate() as Node3D
	_total_spawned += 1
	minion.name = "Minion%d" % _total_spawned
	var parent: Node = _arena_root if _arena_root else get_tree().current_scene
	parent.add_child(minion)
	var to_player := _player.global_position - point.global_position
	minion.global_position = _free_position(point.global_position, to_player)
	minion.rotation.y = atan2(-to_player.x, -to_player.z)
	# Waves spawn alerted: the points are farther than 8 m (normally beyond the minion's 12 m
	# detection radius) and, without this, they would stay IDLE and not pressure Kaelen.
	var minion_node := minion as Minion
	if minion_node:
		minion_node.alert()
	_minions.append(minion)


## Free position around the point: two minions in the same spot violently push each other out
## (their capsules overlap), so if someone is already within SPAWN_SEPARATION growing rings are tried,
## starting toward Kaelen (the points sit next to the walls).
func _free_position(origin: Vector3, to_player: Vector3) -> Vector3:
	var base_angle := atan2(to_player.z, to_player.x)
	for ring in 4:
		var radius := SPAWN_SEPARATION * ring
		for step in (1 if ring == 0 else 6):
			var angle := base_angle + step * TAU / 6.0
			var candidate := origin + Vector3(cos(angle), 0.0, sin(angle)) * radius
			if _is_free(candidate):
				return candidate
	return origin


func _is_free(position: Vector3) -> bool:
	for minion in _minions:
		if is_instance_valid(minion) and minion.global_position.distance_to(position) < SPAWN_SEPARATION:
			return false
	return true


# --- State ------------------------------------------------------------------------------------

func _find_player() -> bool:
	if _player and is_instance_valid(_player) and _player.is_inside_tree():
		return true
	_player = get_tree().get_first_node_in_group(&"player") as Node3D
	_player_health = _player.get_node_or_null(^"Health") as Health if _player else null
	return _player != null


func _prune_minions() -> void:
	_minions = _minions.filter(func(m) -> bool:
		return is_instance_valid(m) and m.is_in_group(&"enemy"))   # dead minions leave the group


func _connect_events(connect_it: bool) -> void:
	var events := get_node_or_null(^"/root/Events")
	if events == null:
		return
	_toggle(events.player_damaged, _on_player_damaged, connect_it)
	_toggle(events.boss_phase_changed, _on_boss_phase_changed, connect_it)
	_toggle(events.enemy_died, _on_enemy_died, connect_it)
	_toggle(events.boss_defeated, _on_arena_over, connect_it)
	_toggle(events.player_died, _on_player_died, connect_it)


static func _toggle(sig: Signal, callable: Callable, connect_it: bool) -> void:
	if connect_it and not sig.is_connected(callable):
		sig.connect(callable)
	elif not connect_it and sig.is_connected(callable):
		sig.disconnect(callable)


func _on_player_damaged(amount: int, _current: int, max_value: int) -> void:
	model.on_player_damaged(roundi(amount * OrchestratorModel.hp_damage_scale(max_value)))
	_time_since_hit = 0.0


func _on_boss_phase_changed(_boss_node: Node3D, phase: int) -> void:
	_boss_phase = phase


func _on_enemy_died(_enemy: Node3D, _cost: int) -> void:
	_prune_minions()


func _on_arena_over(_boss_node: Node3D) -> void:
	for minion in _minions.duplicate():
		if is_instance_valid(minion) and minion.has_node(^"Health"):
			(minion.get_node(^"Health") as Health).take_damage(1 << 20)   # the guardian falls, so do they
	end_arena(false)


func _on_player_died() -> void:
	for minion in _minions.duplicate():
		if is_instance_valid(minion) and minion.has_method(&"celebrate"):
			minion.call(&"celebrate")
	end_arena(false)
