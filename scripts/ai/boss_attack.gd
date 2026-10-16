class_name BossAttack
extends Resource
## One boss attack (spec 8.2). Times are in seconds at phase 1 speed; phase 2 divides them by
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
## Metres the boss moves forward during ACTIVE (charge, pounce). 0 = stays put. It is spread in
## proportion to the active time and stops on hitting a wall or Kaelen.
@export var advance_distance := 0.0
## "Opener" attack: may start while the boss is still approaching (distance > engage_range), at any
## point of [min_range, max_range] and never twice in a row. The other attacks only start once the
## boss has reached engage_range. Set on the long-range ones (charge, pounce, beam) and left alone
## on the rest, so a boss without openers (Bone Dragon) does not change.
@export var opener := false
## Additional hitboxes (relative to the boss) activated together with `hitbox_path` in ACTIVE, dealing
## the same damage (e.g. the claws during the pounce).
@export var extra_hitbox_paths: Array[NodePath] = []
## Node3D (relative to the boss) visible only during ACTIVE (the beam effect).
@export var visual_path: NodePath
## While ACTIVE lasts (+ Boss.gated_grace) the hurtboxes of Boss.gated_hurtboxes can be hit
## (Ghidorah's heads come down when biting).
@export var exposes_hurtboxes := false
## Sound at the start of ACTIVE (the beam shot, for instance), at the boss's position.
@export var sfx_active: AudioStream
## Impact sound when this attack's blow reaches Kaelen (once per blow). Boss copies it to the
## `sfx_impact` of the attack's Hitbox and of its `extra_hitbox_paths`.
@export var sfx_hit: AudioStream


## Metres covered by the advance at `progress` (0-1) of ACTIVE.
func advance_at(progress: float) -> float:
	return advance_distance * clampf(progress, 0.0, 1.0)
