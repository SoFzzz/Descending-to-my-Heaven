extends Node3D
## Root of a `<level>_gameplay.tscn` scene: instances the generated level (child `Level`, NEVER
## edited by hand: level_builder.gd overwrites it) and Kaelen. On start it places Kaelen at the
## level's `PlayerStart` and applies the PSX material to her.
##
## Level exit: if the level has an `ExitTrigger` (Area3D) and `exit_advances_level` is on, when
## Kaelen crosses it and `_can_exit()` allows it, it emits `exit_reached` (only once) and calls
## GameState.advance_level(). Derived scenes override `_can_exit()` (e.g. open gate).
## The way out is shown, not cut: past an arena's exit gate (`GateExit` + generated `ExitRamp`)
## Kaelen climbs the stairs on her own (Player.scripted_walk) through the ExitTrigger; at a door
## without stairs (the temple) she walks in while the transition closes. The next scene is loaded in
## the background beforehand (GameState.preload_next_level) so the change does not stall.

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
## Directed way out: walking speed, the climb trigger (m past the exit gate) and how far she keeps
## walking past the ExitTrigger / into a door while the transition closes.
const EXIT_WALK_SPEED := 2.6
const CLIMB_TRIGGER_OFFSET := 2.0
const EXIT_WALK_ON := 2.0
## Safety: if the scene has not changed this long after the directed walk ended (a refused or stuck
## change), Kaelen gets her control back instead of staying locked.
const EXIT_WALK_TIMEOUT := 4.0

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
var _climbing := false
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
			_setup_exit_climb(exit_trigger)
	if _preload_on_start():
		var game_state := get_node_or_null(^"/root/GameState")
		if game_state:
			game_state.call(&"preload_next_level")


## Virtual: preload the next scene as soon as the level starts (the exterior: nothing to beat).
## Arenas wait for their boss to fall.
func _preload_on_start() -> bool:
	return exit_advances_level


## Stairs out (arenas 1-2): an Area3D a little past GateExit starts the climb.
func _setup_exit_climb(exit_trigger: Area3D) -> void:
	var gate := level.get_node_or_null("GateExit") as Node3D
	if gate == null or level.find_child("ExitRamp", true, false) == null:
		return
	var area := Area3D.new()
	area.name = "ClimbTrigger"
	area.collision_layer = 0
	area.collision_mask = exit_trigger.collision_mask
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 3.0, 1.5)
	shape.shape = box
	area.add_child(shape)
	level.add_child(area)
	var north := (exit_trigger.global_position - gate.global_position)
	north.y = 0.0
	north = north.normalized()
	area.global_position = gate.global_position + north * CLIMB_TRIGGER_OFFSET + Vector3(0, 1.5 - gate.global_position.y, 0)
	area.body_entered.connect(_on_climb_trigger_entered.bind(gate, exit_trigger))


func _on_climb_trigger_entered(body: Node3D, gate: Node3D, exit_trigger: Area3D) -> void:
	if _climbing or _exit_used or body != player or not _can_exit():
		return
	_climbing = true
	var north := exit_trigger.global_position - gate.global_position
	north.y = 0.0
	north = north.normalized()
	var foot := Vector3(gate.global_position.x, player.global_position.y, player.global_position.z) + north * 1.0
	var top := exit_trigger.global_position + north * EXIT_WALK_ON
	_begin_exit_walk.call_deferred([foot, top] as Array[Vector3])   # deferred: inside a physics signal


func _begin_exit_walk(points: Array[Vector3]) -> void:
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state:
		game_state.set(&"cutscene_active", true)
	player.set_cutscene(true)
	if not player.scripted_walk_finished.is_connected(_on_exit_walk_done):
		player.scripted_walk_finished.connect(_on_exit_walk_done, CONNECT_ONE_SHOT)
	player.scripted_walk(points, EXIT_WALK_SPEED)


func _on_exit_walk_done() -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(EXIT_WALK_TIMEOUT, false).timeout
	if not is_inside_tree() or not player.is_cutscene():
		return
	push_warning("%s: the level change did not happen after the exit walk; giving control back" % name)
	player.set_cutscene(false)
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state:
		game_state.set(&"cutscene_active", false)
	_exit_used = false
	_climbing = false


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
	if not _climbing:
		# A door without stairs (the temple): she walks in while the transition closes.
		_climbing = true
		var ahead := Vector3(player.velocity.x, 0.0, player.velocity.z)
		if ahead.length_squared() < 0.01:
			ahead = player.get_facing()
		ahead.y = 0.0
		var into := player.global_position + ahead.normalized() * (EXIT_WALK_ON + 1.0)
		_begin_exit_walk.call_deferred([into] as Array[Vector3])
	exit_reached.emit()
	if is_inside_tree():
		var game_state := get_node_or_null(^"/root/GameState")
		if game_state and game_state.has_method(&"advance_level"):
			game_state.call_deferred(&"advance_level")   # deferred: we are inside a physics signal
