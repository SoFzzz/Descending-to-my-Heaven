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
