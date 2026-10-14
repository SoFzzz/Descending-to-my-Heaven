class_name Hurtbox
extends Area3D
## Zona que recibe golpes: aplica el multiplicador de daño y lo pasa a su Health.

signal hurt(amount: int, source: Node)

@export var health: Health
@export var damage_multiplier := 1.0
@export var surface: StringName = &"flesh"


func receive_hit(amount: int, source: Node) -> void:
	var final := roundi(amount * damage_multiplier)
	if health:
		health.take_damage(final)
	hurt.emit(final, source)
