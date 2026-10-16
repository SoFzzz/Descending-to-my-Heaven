class_name ArenaConfig
extends Resource
## Configuration of one arena. The gameplay scene hands it to the Orchestrator
## (Orchestrator.begin_arena), which spawns minions and elites from it.

@export var arena_id: int = 1
## Pressure threshold: base x player performance x boss phase >= base -> large group
## (wave_size_max); below it, small group (wave_size_min).
@export var base_budget: float = 4.0
@export var minion_scene: PackedScene
## Optional (may be null): without it every group is made of regular minions. With it, each group
## carries exactly 1 elite in place of one of its minions (1 elite + 1 or 2 regular ones).
@export var elite_scene: PackedScene
## Minions alive at once, elite included (hard limit: 3).
@export var max_alive := 3
## Group size (minions, elite included): the Orchestrator picks it between min and max.
@export var wave_size_min := 2
@export var wave_size_max := 3
## Boss window: seconds without spawns after the last minion of a wave dies
## (the intensity scales it x0.9..x1.3).
@export var clear_delay := 12.0
## Seconds between entering the arena and the first wave.
@export var first_wave_delay := 3.0
