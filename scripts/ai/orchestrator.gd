extends Node
## Autoload "Orchestrator": ritmo del combate (spec §8.3). Envuelve a OrchestratorModel (lógica
## pura y probada) y se encarga de lo que necesita el árbol: leer a Kaelen y a los esbirros,
## elegir puntos de aparición y generar/liberar esbirros.
##
## Ciclo de vida: el gameplay de la arena llama explícitamente a `begin_arena(config, self, boss)`
## al final de su _ready (después de emitir Events.arena_entered). Se prefiere esto a reaccionar
## a `arena_entered` porque esa señal solo trae el id y el Orquestador necesita el ArenaConfig, la
## raíz de la arena (para filtrar los spawn_point) y el jefe. `end_arena()` se dispara solo con
## Events.boss_defeated / Events.player_died y también lo llama GameState al cambiar de escena.
##
## Los autoloads se buscan por ruta (get_node_or_null) porque con `-s` no existen.

const NEAR_RANGE := 5.0           # enemigo "cerca" de Kaelen para la intensidad
const SPAWN_SEPARATION := 1.3     # distancia mínima entre esbirros recién generados
const SQUAD_INTERVAL := 0.35      # cada cuánto se reparten las órdenes de la pinza
const ORDER_DURATION := 0.9       # s que dura cada orden de posición (se renueva mientras siga la pinza)
const CHEST_OFFSET := Vector3(0.0, 1.0, 0.0)   # el punto se comprueba a media altura de esbirro

var model := OrchestratorModel.new()

var _config: ArenaConfig
var _arena_root: Node3D
var _boss: Boss
var _active := false
var _minions: Array = []
var _time_since_hit := 10.0       # arranca "tranquilo" para que la primera oleada sea normal
var _boss_phase := 1
var _last_budget := 0             # presupuesto de la última oleada generada (para depuración)
var _spawn_count := 0             # índice rotatorio de punto de aparición
var _failed_waves := 0            # intentos seguidos sin puntos válidos: desde el 2.º se admite el respaldo
var last_spawn_tier := OrchestratorModel.SpawnTier.NONE   # tier de la última selección (depuración)
var _total_spawned := 0           # para nombrar a los esbirros sin repetir
var _player: Node3D
var _player_health: Health
var _squad_timer := 0.0
var _pincer_active := false
## Órdenes de pinza repartidas en esta arena (depuración y simulación).
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


## `arena_root`: nodo bajo el que viven los spawn_point y donde se instancian los esbirros
## (por defecto la escena actual). `boss`: para leer su fase y sus ataques especiales.
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


## Fin de la arena (jefe derrotado, Kaelen muerta o cambio de escena): modelo a cero, esbirros
## liberados y fichas a 0. Cada esbirro devuelve su ficha y se libera ANTES del reset; además
## Minion._has_token() consulta a AttackTokens, así que ningún esbirro puede quedar creyendo que
## tiene ficha tras un AttackTokens.reset().
func end_arena() -> void:
	_connect_events(false)
	_active = false
	for minion in _minions:
		if is_instance_valid(minion):
			minion.call(&"release_token")
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


## Contexto del modelo a partir del estado real del árbol.
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


## "Ataque especial" del jefe: el rugido de cambio de fase, o un ataque de fase 2 (phase_min >= 2)
## o con giro (spin_degrees > 0, p. ej. el barrido de cola) en aviso o activo.
static func is_boss_special(boss: Boss) -> bool:
	if boss == null or not is_instance_valid(boss):
		return false
	if boss.state == Boss.State.ROAR:
		return true
	if boss.state == Boss.State.TELEGRAPH or boss.state == Boss.State.ACTIVE:
		var attack := boss.current_attack
		return attack != null and (attack.phase_min >= 2 or attack.spin_degrees > 0.0)
	return false


# --- Escuadra (pinza) -------------------------------------------------------------------------

## Mientras la meta del jefe es PINCER, reparte a los esbirros vivos puntos de cerco en el lado de
## Kaelen OPUESTO al jefe (SquadTactics.pincer_points). Al terminar la pinza retira las órdenes.
func _update_squad(delta: float) -> void:
	_squad_timer += delta
	if _squad_timer < SQUAD_INTERVAL:
		return
	_squad_timer = 0.0
	var on := _boss != null and is_instance_valid(_boss) and _boss.tactics_enabled 			and _boss.state != Boss.State.DEAD and _boss.tactics.goal == BossTactics.Goal.PINCER 			and _player != null
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
		if is_instance_valid(minion) and minion.has_method(&"order_to") and not minion.call(&"is_retreating") 				and minion.get(&"state") != MinionBrain.State.ATTACK:
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


# --- Generación -------------------------------------------------------------------------------

## Genera un grupo de `count` esbirros (sin pasar de max_alive vivos) en puntos válidos; si la
## arena tiene élite, el primero del grupo es el élite (1 élite + count-1 normales). Devuelve cuántos generó.
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


## spawn_point elegibles según OrchestratorModel.select_spawn_points (por tiers): 1) fuera del cono
## de la cámara y a > 8 m de Kaelen; 2) si no hay, a > 14 m aunque se vean; 3) si tampoco y ya falló
## un intento (el reintento), solo el más lejano a > 8 m. Vacío = la oleada se retrasa.
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
	# Orden estable por nombre: la selección es determinista.
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
	# Las oleadas nacen alertadas: los puntos están a > 8 m (normalmente más allá del radio de
	# detección de 12 m del esbirro) y, sin esto, se quedarían en IDLE sin presionar a Kaelen.
	var minion_node := minion as Minion
	if minion_node:
		minion_node.alert()
	_minions.append(minion)


## Posición libre alrededor del punto: dos esbirros en el mismo sitio se expulsan violentamente
## entre sí (solapan cápsulas), así que si ya hay alguien a < SPAWN_SEPARATION se prueban anillos
## crecientes, empezando hacia Kaelen (los puntos están junto a los muros).
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


# --- Estado -----------------------------------------------------------------------------------

func _find_player() -> bool:
	if _player and is_instance_valid(_player) and _player.is_inside_tree():
		return true
	_player = get_tree().get_first_node_in_group(&"player") as Node3D
	_player_health = _player.get_node_or_null(^"Health") as Health if _player else null
	return _player != null


func _prune_minions() -> void:
	_minions = _minions.filter(func(m) -> bool:
		return is_instance_valid(m) and m.is_in_group(&"enemy"))   # al morir salen del grupo


func _connect_events(connect_it: bool) -> void:
	var events := get_node_or_null(^"/root/Events")
	if events == null:
		return
	_toggle(events.player_damaged, _on_player_damaged, connect_it)
	_toggle(events.boss_phase_changed, _on_boss_phase_changed, connect_it)
	_toggle(events.enemy_died, _on_enemy_died, connect_it)
	_toggle(events.boss_defeated, _on_arena_over, connect_it)
	_toggle(events.player_died, end_arena, connect_it)


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
	end_arena()
