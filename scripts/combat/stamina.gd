class_name Stamina
extends Node
## Aguante: se gasta con acciones y se regenera pasado un retardo desde el último gasto.

signal changed(current: float, max_value: float)

@export var max_value := 100.0
@export var regen_per_sec := 30.0
@export var regen_delay := 0.6

var current: float = 100.0
var _time_since_spend: float = 1.0e9  # al crear, regenera sin esperar


func _ready() -> void:
	current = max_value


func _process(delta: float) -> void:
	tick(delta)


## Se permite gastar mientras quede algo (aunque no alcance); con 0 no se puede.
func try_spend(amount: float) -> bool:
	if current <= 0.0:
		return false
	current = maxf(0.0, current - amount)
	_time_since_spend = 0.0
	changed.emit(current, max_value)
	return true


func tick(delta: float) -> void:
	_time_since_spend += delta
	var regen_time := minf(delta, _time_since_spend - regen_delay)
	if regen_time <= 0.0:
		return
	var new_value := minf(max_value, current + regen_per_sec * regen_time)
	if new_value != current:
		current = new_value
		changed.emit(current, max_value)
