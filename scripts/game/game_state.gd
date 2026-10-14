extends Node
## Autoload "GameState": progreso de la partida. Stub de la Tarea 1 (A lo completa en la Tarea 10).

const MAX_HP_BY_LEVEL: Array[int] = [100, 70, 40]
## El final ocurre dentro de arena_3 (pasillo y sala de Elysia).
const LEVEL_SCENES: Array[String] = [
	"res://scenes/levels/exterior_gameplay.tscn",
	"res://scenes/levels/arena_1_gameplay.tscn",
	"res://scenes/levels/arena_2_gameplay.tscn",
	"res://scenes/levels/arena_3_gameplay.tscn",
]

var current_level: int = 0   # 0, 1, 2


func get_player_max_hp() -> int:
	return MAX_HP_BY_LEVEL[clampi(current_level, 0, MAX_HP_BY_LEVEL.size() - 1)]


func start_new_game() -> void:
	pass


func advance_level() -> void:
	pass


func reload_current_arena() -> void:
	pass


func go_to_main_menu() -> void:
	pass
