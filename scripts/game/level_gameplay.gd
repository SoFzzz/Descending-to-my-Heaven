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

## Antorchas con sonido: máximo de reproductores por nivel y alcance (m) de su crepitar.
const TORCH_MAX_PLAYERS := 8
const TORCH_HEARING_DISTANCE := 9.0
const TORCH_UNIT_SIZE := 2.5
const TORCH_VOLUME_DB := -8.0
const MUSIC_FADE := 2.0
## Ambiente de la sala: bucle suave por debajo de la música.
const AMBIENCE_VOLUME_DB := -14.0

## Si es false no se conecta el ExitTrigger (p. ej. la arena 3, donde el final lo dirige otro nodo).
@export var exit_advances_level := true

@export_group("Audio")
## Música (o ambiente) del nivel; null = silencio (la música anterior se apaga con un fundido).
@export var level_music: AudioStream
## Pasos de Kaelen en este suelo (piedra en arenas y templo, tierra en el exterior).
@export var footstep_stream: AudioStream
## Bucle de las antorchas (luces dentro del nodo `Level/Torches`).
@export var torch_loop: AudioStream
## Ambiente del nivel en bucle (sin posición), a poco volumen para que quede debajo de la música.
@export var ambience: AudioStream

@onready var level: Node3D = $Level
@onready var player: Player = $Kaelen

var _exit_used := false


func _ready() -> void:
	PSX.apply_psx(player.get_node("Model"))
	player.footstep_stream = footstep_stream
	_start_level_music()
	_add_torch_sounds()
	_start_ambience()
	var start := level.get_node_or_null("PlayerStart") as Node3D
	if start:
		player.spawn_at(start)
	else:
		push_warning("%s no tiene PlayerStart" % level.name)
	if exit_advances_level:
		var exit_trigger := level.get_node_or_null("ExitTrigger") as Area3D
		if exit_trigger:
			exit_trigger.body_entered.connect(_on_exit_trigger_body_entered)


func _audio() -> Node:
	return get_node_or_null(^"/root/AudioManager")


func _start_level_music() -> void:
	var audio := _audio()
	if audio:
		audio.play_music(level_music, MUSIC_FADE)


func _start_ambience() -> void:
	if ambience == null:
		return
	var sound := AudioStreamPlayer.new()
	sound.name = "Ambience"
	sound.stream = ambience
	sound.bus = &"SFX"
	sound.volume_db = AMBIENCE_VOLUME_DB
	sound.autoplay = true
	add_child(sound)


## Luces de `Level/Torches`: las escenas del nivel son generadas (no se editan), así que el sonido se
## cuelga aquí, en ejecución, como un AudioStreamPlayer3D por antorcha con alcance limitado.
func _add_torch_sounds() -> void:
	if torch_loop == null:
		return
	var torches := level.get_node_or_null(^"Torches")
	if torches == null:
		return
	var added := 0
	for light in torches.get_children():
		if added >= TORCH_MAX_PLAYERS:
			break
		if not light is OmniLight3D:
			continue
		var sound := AudioStreamPlayer3D.new()
		sound.name = "TorchSound"
		sound.stream = torch_loop
		sound.bus = &"SFX"
		sound.max_distance = TORCH_HEARING_DISTANCE
		sound.unit_size = TORCH_UNIT_SIZE
		sound.volume_db = TORCH_VOLUME_DB
		sound.autoplay = true
		light.add_child(sound)
		added += 1


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
