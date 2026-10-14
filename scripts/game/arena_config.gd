class_name ArenaConfig
extends Resource
## Configuración de una arena: la usan la escena de gameplay (esbirros iniciales) y el
## Orquestador (Orchestrator.begin_arena, Tarea 12).

@export var arena_id: int = 1
@export var base_budget: float = 0.0
@export var minion_scene: PackedScene
@export var elite_scene: PackedScene
@export var max_alive := 6
