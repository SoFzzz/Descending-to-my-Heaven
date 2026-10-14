extends Node3D
## Raíz de una escena `<nivel>_gameplay.tscn`: instancia el nivel generado (hijo `Level`, NUNCA se
## edita: lo sobrescribe level_builder.gd) y a Kaelen. Al iniciar coloca a Kaelen en el
## `PlayerStart` del nivel y le aplica el material PSX.

const PSX := preload("res://scenes/levels/psx_test.gd")

@onready var level: Node3D = $Level
@onready var player: Player = $Kaelen


func _ready() -> void:
	PSX.apply_psx(player.get_node("Model"))
	var start := level.get_node_or_null("PlayerStart") as Node3D
	if start:
		player.spawn_at(start)
	else:
		push_warning("%s no tiene PlayerStart" % level.name)
