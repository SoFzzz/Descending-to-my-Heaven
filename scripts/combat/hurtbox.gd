class_name Hurtbox
extends Area3D
## Zona que recibe golpes: aplica el multiplicador de daño y lo pasa a su Health.

signal hurt(amount: int, source: Node)

@export var health: Health
@export var damage_multiplier := 1.0
@export var surface: StringName = &"flesh"


## Falso si su Health está invulnerable o muerta: el golpe no cuenta (ni sonido, ni reacción).
func can_be_hit() -> bool:
	return health == null or not (health.invulnerable or health.is_dead())


func receive_hit(amount: int, source: Node) -> void:
	var final := roundi(amount * damage_multiplier)
	if health:
		health.take_damage(final)
	if final > 0 and is_inside_tree():
		HitFlash.flash(HitFlash.model_for(self), HitFlash.color_for(self))
	hurt.emit(final, source)
