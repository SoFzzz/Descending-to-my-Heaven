class_name BossAttack
extends Resource
## One boss attack (spec §8.2). Times are in seconds at phase 1 speed; phase 2 divides them by
## Boss.PHASE2_SPEED. Ranges are measured horizontally from the boss origin to Kaelen's origin.
## The warning on the floor is the node Telegraphs/<id> of the boss scene.

@export var id: StringName
@export var min_range: float = 0.0
@export var max_range: float = 4.0
@export var telegraph_time: float = 0.8
@export var active_time: float = 0.3
@export var recovery_time: float = 1.0
@export var base_weight: float = 1.0
@export var damage: int = 20
@export var animation: StringName
@export var hitbox_path: NodePath   # relative to the boss root
@export var phase_min := 1
## Covers the boss's sides: gets the anticipation bonus when Kaelen keeps dodging to one side.
@export var lateral := false
## Body turn (degrees) spread over active_time (the Bone Dragon's tail sweep spins 360°).
@export var spin_degrees := 0.0
## Metros que el jefe avanza hacia delante mientras dura ACTIVE (embestida, salto). 0 = se queda
## quieto. Se reparte en proporción al tiempo activo y se detiene al chocar con un muro o con Kaelen.
@export var advance_distance := 0.0
## Ataque "de apertura": puede empezar mientras el jefe todavía se acerca (distancia > engage_range),
## en cualquier punto de [min_range, max_range] y nunca dos veces seguidas. Los demás ataques
## solo salen cuando el jefe ya llegó a engage_range. Se pone en los de largo alcance (embestida,
## salto, rayo) y no se toca en los demás: así un jefe sin aperturas (Bone Dragon) no cambia.
@export var opener := false
## Hitboxes adicionales (relativas al jefe) que se activan junto a `hitbox_path` en ACTIVE y hacen el
## mismo daño (p. ej. las garras con el salto).
@export var extra_hitbox_paths: Array[NodePath] = []
## Node3D (relativo al jefe) visible solo durante ACTIVE (el efecto del rayo).
@export var visual_path: NodePath
## Mientras dura ACTIVE (+ Boss.gated_grace) las hurtboxes de Boss.gated_hurtboxes se pueden golpear
## (las cabezas de Ghidorah bajan al morder).
@export var exposes_hurtboxes := false


## Metros recorridos por el avance al `progress` (0–1) de ACTIVE.
func advance_at(progress: float) -> float:
	return advance_distance * clampf(progress, 0.0, 1.0)
