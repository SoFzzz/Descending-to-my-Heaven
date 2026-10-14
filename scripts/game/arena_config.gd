class_name ArenaConfig
extends Resource
## Configuración de una arena: la escena de gameplay se la pasa al Orquestador
## (Orchestrator.begin_arena), que genera esbirros/élites con ella.

@export var arena_id: int = 1
## Presupuesto base de oleada (esbirro = 1, élite = 3); se multiplica por desempeño y fase del jefe.
@export var base_budget: float = 4.0
@export var minion_scene: PackedScene
## Opcional (puede ser null): sin ella solo se generan esbirros normales.
@export var elite_scene: PackedScene
## Esbirros vivos a la vez (spec: 6).
@export var max_alive := 6
## Tamaño de oleada en coste (esbirro 1, élite 3): entre min y max, limitado por max_alive.
@export var wave_size_min := 3
@export var wave_size_max := 4
## Ventana del jefe: segundos sin apariciones desde que muere el último esbirro de una oleada
## (la intensidad la escala x0.9..x1.3).
@export var clear_delay := 12.0
## Segundos entre entrar a la arena y la primera oleada.
@export var first_wave_delay := 3.0
