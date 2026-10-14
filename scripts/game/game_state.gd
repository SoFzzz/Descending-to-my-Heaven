extends Node
## Autoload "GameState": progreso de la partida y todos los cambios de escena.
##
## Dos índices distintos:
## - `scene_index` (0..3): posición en LEVEL_SCENES. 0 = exterior, 1..3 = arenas 1..3.
## - `current_level` (0..2, Contrato): nivel de vida máxima (MAX_HP_BY_LEVEL). Baja tras cada jefe:
##   exterior y arena 1 → 0 (100), arena 2 → 1 (70), arena 3 → 2 (40). Ver level_for_scene().
##
## Al iniciar (fuera de las pruebas) crea como hijos propios la transición (fundido), el menú de
## pausa y la pantalla de muerte: al ser hijos de un autoload sobreviven a los cambios de escena y
## existen en toda escena jugable sin editar las escenas de nivel.

const MAX_HP_BY_LEVEL: Array[int] = [100, 70, 40]
## El final ocurre dentro de arena_3 (pasillo y sala de Elysia).
const LEVEL_SCENES: Array[String] = [
	"res://scenes/levels/exterior_gameplay.tscn",
	"res://scenes/levels/arena_1_gameplay.tscn",
	"res://scenes/levels/arena_2_gameplay.tscn",
	"res://scenes/levels/arena_3_gameplay.tscn",
]
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const CREDITS_SCENE := "res://scenes/ui/credits.tscn"
const TRANSITION_SCENE := "res://scenes/ui/transition.tscn"
const PAUSE_MENU_SCENE := "res://scenes/ui/pause_menu.tscn"
const DEATH_SCREEN_SCENE := "res://scenes/ui/death_screen.tscn"

var current_level: int = 0   # 0, 1, 2
var scene_index: int = 0     # 0 = exterior, 1..3 = arenas
## Última ruta pedida a _change_scene (para pruebas y depuración).
var last_requested_scene: String = ""

var transition: Node = null
var pause_menu: Node = null
var death_screen: Node = null


func _ready() -> void:
	transition = _add_ui(TRANSITION_SCENE)
	pause_menu = _add_ui(PAUSE_MENU_SCENE)
	death_screen = _add_ui(DEATH_SCREEN_SCENE)


func _add_ui(path: String) -> Node:
	if not ResourceLoader.exists(path):
		push_warning("GameState: falta %s" % path)
		return null
	var node := (load(path) as PackedScene).instantiate()
	add_child(node)
	return node


func get_player_max_hp() -> int:
	return MAX_HP_BY_LEVEL[clampi(current_level, 0, MAX_HP_BY_LEVEL.size() - 1)]


## Ruta de la escena jugable para un índice de escena (0 = exterior, 1..3 = arenas); "" si no existe.
func scene_for_level(level: int) -> String:
	if level < 0 or level >= LEVEL_SCENES.size():
		return ""
	return LEVEL_SCENES[level]


## Nivel de vida (current_level) que corresponde a un índice de escena.
func level_for_scene(index: int) -> int:
	return clampi(index - 1, 0, MAX_HP_BY_LEVEL.size() - 1)


func start_new_game() -> void:
	if _change_scene(scene_for_level(0)):
		_set_scene_index(0)


## Tras boss_defeated: siguiente arena; desde la arena 3, el final (créditos o, si no existen, el menú).
func advance_level() -> void:
	var next := scene_index + 1
	if next >= LEVEL_SCENES.size():
		_change_scene(CREDITS_SCENE if ResourceLoader.exists(CREDITS_SCENE) else MAIN_MENU_SCENE)
		return
	if _change_scene(scene_for_level(next)):
		_set_scene_index(next)


## Reaparición tras morir: recarga la escena actual (Kaelen nueva, jefe a vida completa, sin
## esbirros sobrantes). La vida máxima no cambia: Kaelen hace health.reset(get_player_max_hp()).
func reload_current_arena() -> void:
	var path := _current_scene_path()
	var index := LEVEL_SCENES.find(path)
	if _change_scene(path) and index >= 0:
		scene_index = index


func go_to_main_menu() -> void:
	_change_scene(MAIN_MENU_SCENE)


## true si no hay fundido en curso ni pantalla de muerte (el menú de pausa lo consulta).
func can_pause() -> bool:
	if transition and transition.call(&"is_busy"):
		return false
	if death_screen and death_screen.call(&"is_active"):
		return false
	return true


func _set_scene_index(index: int) -> void:
	scene_index = index
	current_level = level_for_scene(index)


func _current_scene_path() -> String:
	if is_inside_tree():
		var scene := get_tree().current_scene
		if scene and not scene.scene_file_path.is_empty():
			return scene.scene_file_path
	return scene_for_level(scene_index)


## Pide el cambio de escena con fundido. Devuelve false (y no cambia) si la escena no existe o ya hay
## un fundido en curso. Las pruebas lo sustituyen para no cambiar de escena.
func _change_scene(path: String) -> bool:
	last_requested_scene = path
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("GameState: la escena '%s' no existe; no se cambia" % path)
		return false
	if not is_inside_tree():
		return false
	if transition and transition.call(&"is_busy"):
		return false
	if transition:
		transition.call(&"fade_to", path)
	else:
		_swap_scene(path)
	return true


## Cambio inmediato y limpieza del estado global. La transición lo llama con la pantalla en negro.
func _swap_scene(path: String) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	var tokens := get_node_or_null(^"/root/AttackTokens")
	if tokens:
		tokens.call(&"reset")
	var orchestrator := get_node_or_null(^"/root/Orchestrator")
	if orchestrator:
		orchestrator.call(&"end_arena")
	if pause_menu:
		pause_menu.call(&"close_silently")
	if death_screen:
		death_screen.call(&"hide_now")
	get_tree().change_scene_to_file(path)
