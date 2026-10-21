extends Node
## Autoload "Events": global signal bus shared by gameplay, UI and audio.

@warning_ignore_start("unused_signal")
signal player_damaged(amount: int, current: int, max_value: int)
signal player_died
signal enemy_died(enemy: Node3D, cost: int)
signal boss_phase_changed(boss: Node3D, phase: int)
signal boss_defeated(boss: Node3D)
signal arena_entered(arena_id: int)
signal arena_cleared(arena_id: int)
signal hit_landed(position: Vector3, surface: StringName)   # &"flesh", &"ichor", &"straw", &"bone", &"metal"
@warning_ignore_restore("unused_signal")
