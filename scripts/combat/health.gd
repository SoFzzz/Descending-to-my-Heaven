class_name Health
extends Node
## Vida reutilizable (jugador, jefes, esbirros): recibe daño, avisa por señales y muere una sola vez.

signal changed(current: int, max_value: int)
signal died

@export var max_value: int = 100
var current: int = 100
var invulnerable: bool = false


func _ready() -> void:
	current = max_value


func take_damage(amount: int) -> void:
	if invulnerable or is_dead():
		return
	current = maxi(0, current - amount)
	changed.emit(current, max_value)
	if current == 0:
		died.emit()


func reset(new_max: int = -1) -> void:
	if new_max > 0:
		max_value = new_max
	current = max_value
	changed.emit(current, max_value)


func is_dead() -> bool:
	return current <= 0
