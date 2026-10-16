class_name Stamina
extends Node
## Stamina: spent by actions and regenerated after a delay since the last expense.

signal changed(current: float, max_value: float)

@export var max_value := 100.0
@export var regen_per_sec := 30.0
@export var regen_delay := 0.6

var current: float = 100.0
var _time_since_spend: float = 1.0e9  # on creation, regenerates without waiting


func _ready() -> void:
	current = max_value


func _process(delta: float) -> void:
	tick(delta)


## Fills the stamina to the maximum and reports it (the HUD bar reflects it).
func refill() -> void:
	current = max_value
	_time_since_spend = 1.0e9
	changed.emit(current, max_value)


## Spending is allowed while anything is left (even if it falls short); with 0 it is not.
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
