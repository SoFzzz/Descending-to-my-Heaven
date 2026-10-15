extends Node3D
## Raíz de una escena `<nivel>_gameplay.tscn`: instancia el nivel generado (hijo `Level`, NUNCA se
## edita: lo sobrescribe level_builder.gd) y a Kaelen. Al iniciar coloca a Kaelen en el
## `PlayerStart` del nivel y le aplica el material PSX.
##
## Salida del nivel: si el nivel tiene un `ExitTrigger` (Area3D) y `exit_advances_level` está activo,
## cuando Kaelen lo cruza y `_can_exit()` lo permite emite `exit_reached` (una sola vez) y pide
## GameState.advance_level(). Las escenas derivadas ajustan `_can_exit()` (p. ej. reja abierta).

## Kaelen cruzó el ExitTrigger y se pidió el paso de nivel.
signal exit_reached

const PSX := preload("res://scenes/levels/psx_test.gd")

## Si es false no se conecta el ExitTrigger (p. ej. la arena 3, donde el final lo dirige otro nodo).
@export var exit_advances_level := true

@onready var level: Node3D = $Level
@onready var player: Player = $Kaelen

var _exit_used := false


func _ready() -> void:
	PSX.apply_psx(player.get_node("Model"))
	var start := level.get_node_or_null("PlayerStart") as Node3D
	if start:
		player.spawn_at(start)
	else:
		push_warning("%s no tiene PlayerStart" % level.name)
	if exit_advances_level:
		var exit_trigger := level.get_node_or_null("ExitTrigger") as Area3D
		if exit_trigger:
			exit_trigger.body_entered.connect(_on_exit_trigger_body_entered)


## Virtual: true si Kaelen puede salir del nivel por el ExitTrigger.
func _can_exit() -> bool:
	return true


func _on_exit_trigger_body_entered(body: Node3D) -> void:
	if _exit_used or body != player or not _can_exit():
		return
	_exit_used = true
	exit_reached.emit()
	if is_inside_tree():
		var game_state := get_node_or_null(^"/root/GameState")
		if game_state and game_state.has_method(&"advance_level"):
			game_state.call_deferred(&"advance_level")   # deferred: we are inside a physics signal
