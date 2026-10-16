extends Node3D
## Root of a `<level>_gameplay.tscn` scene: instances the generated level (child `Level`, NEVER
## edited by hand: level_builder.gd overwrites it) and Kaelen. On start it places Kaelen at the
## level's `PlayerStart` and applies the PSX material to her.
##
## Level exit: if the level has an `ExitTrigger` (Area3D) and `exit_advances_level` is on, when
## Kaelen crosses it and `_can_exit()` allows it, it emits `exit_reached` (only once) and calls
## GameState.advance_level(). Derived scenes override `_can_exit()` (e.g. open gate).

## Kaelen crossed the ExitTrigger and the level change was requested.
signal exit_reached

const PSX := preload("res://scenes/levels/psx_test.gd")

## Torches with sound: maximum players per level and hearing range (m) of their crackle.
const TORCH_MAX_PLAYERS := 8
const TORCH_HEARING_DISTANCE := 9.0
const TORCH_UNIT_SIZE := 2.5
const TORCH_VOLUME_DB := -8.0
const MUSIC_FADE := 2.0
## Room ambience: a soft loop below the music.
const AMBIENCE_VOLUME_DB := -14.0
## When Kaelen dies the music and ambience fade out over this time and stop (only the death theme plays).
const DEATH_AUDIO_FADE := 0.5

## If false the ExitTrigger is not connected (e.g. arena 3, where another node directs the ending).
@export var exit_advances_level := true

@export_group("Audio")
## Level music (or ambience); null = silence (the previous music fades out).
@export var level_music: AudioStream
## Kaelen's footsteps on this floor (stone in arenas and temple, dirt outside).
@export var footstep_stream: AudioStream
## Torch loop (lights inside the `Level/Torches` node).
@export var torch_loop: AudioStream
## Looping level ambience (non-positional), quiet so it stays below the music.
@export var ambience: AudioStream

@onready var level: Node3D = $Level
@onready var player: Player = $Kaelen

var _exit_used := false
## true once Kaelen has died: no late music start (e.g. the boss noticing the fallen Kaelen) may
## play again.
var _player_dead := false


func _ready() -> void:
	PSX.apply_psx(player.get_node("Model"))
	_refill_player()
	var events := get_node_or_null(^"/root/Events")
	if events:
		events.player_died.connect(_on_player_died)
	player.footstep_stream = footstep_stream
	ImpactFx.instance(get_tree())   # impact sparks, dust and decals (emitter pool)
	_start_level_music()
	_add_torch_sounds()
	_start_ambience()
	var start := level.get_node_or_null("PlayerStart") as Node3D
	if start:
		player.spawn_at(start)
	else:
		push_warning("%s has no PlayerStart" % level.name)
	if exit_advances_level:
		var exit_trigger := level.get_node_or_null("ExitTrigger") as Area3D
		if exit_trigger:
			exit_trigger.body_entered.connect(_on_exit_trigger_body_entered)


## Kaelen enters each zone (and respawns) with the level's max health and full stamina; the HUD
## (which already listens to these signals) shows it from the first frame.
func _refill_player() -> void:
	var game_state := get_node_or_null(^"/root/GameState")
	if player.health:
		player.health.reset(game_state.get_player_max_hp() if game_state else -1)
	if player.stamina:
		player.stamina.refill()
	player.refill_heals()


## Kaelen's death: the music (boss or level) and the ambience fade out quickly and stop.
func _on_player_died() -> void:
	_player_dead = true
	var audio := _audio()
	if audio:
		audio.stop_music(DEATH_AUDIO_FADE)
	var ambience_player := get_node_or_null(^"Ambience") as AudioStreamPlayer
	if ambience_player:
		var tween := create_tween().set_ignore_time_scale(true)
		tween.tween_property(ambience_player, "volume_db", -60.0, DEATH_AUDIO_FADE)
		tween.tween_callback(ambience_player.stop)


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


## Lights of `Level/Torches`: the level scenes are generated (not hand-edited), so the sound is
## attached here at runtime as one AudioStreamPlayer3D per torch with a limited range.
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


## Virtual: true if Kaelen may leave the level through the ExitTrigger.
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
