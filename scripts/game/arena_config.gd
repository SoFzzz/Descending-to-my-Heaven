class_name ArenaConfig
extends Resource
## Configuración de una arena: la escena de gameplay se la pasa al Orquestador
## (Orchestrator.begin_arena), que genera esbirros/élites con ella.

@export var arena_id: int = 1
## Umbral de presión: base x desempeño del jugador x fase del jefe >= base -> grupo grande
## (wave_size_max); por debajo, grupo pequeño (wave_size_min).
@export var base_budget: float = 4.0
@export var minion_scene: PackedScene
## Opcional (puede ser null): sin ella el grupo es de esbirros normales. Con ella, cada grupo lleva
## exactamente 1 élite en lugar de uno de sus esbirros (1 élite + 1 o 2 normales).
@export var elite_scene: PackedScene
## Esbirros vivos a la vez, élite incluida (límite duro: 3).
@export var max_alive := 3
## Tamaño del grupo (esbirros, élite incluida): lo decide el Orquestador entre min y max.
@export var wave_size_min := 2
@export var wave_size_max := 3
## Ventana del jefe: segundos sin apariciones desde que muere el último esbirro de una oleada
## (la intensidad la escala x0.9..x1.3).
@export var clear_delay := 12.0
## Segundos entre entrar a la arena y la primera oleada.
@export var first_wave_delay := 3.0
