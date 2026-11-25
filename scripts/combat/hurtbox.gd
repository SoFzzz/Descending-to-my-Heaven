class_name Hurtbox
extends Area3D
## Zone that receives hits: applies the damage multiplier and passes it to its Health.

signal hurt(amount: int, source: Node)

@export var health: Health
@export var damage_multiplier := 1.0
@export var surface: StringName = &"flesh"
## Optional owner that applies the damage itself (the boss: its hurtboxes have no Health). While its
## is_invulnerable() is true (roars) the hit is ignored whole: no hit-stop, sound, sparks or flash.
var guard: Node = null


## False if its Health is invulnerable or dead, or its guard is invulnerable: the hit does not count
## (no sound, no reaction).
func can_be_hit() -> bool:
	if guard != null and is_instance_valid(guard) and guard.call(&"is_invulnerable"):
		return false
	return health == null or not (health.invulnerable or health.is_dead())


func receive_hit(amount: int, source: Node) -> void:
	var final := roundi(amount * damage_multiplier)
	if health:
		health.take_damage(final)
	if final > 0 and is_inside_tree():
		HitFlash.flash(HitFlash.model_for(self), HitFlash.color_for(self))
	hurt.emit(final, source)
