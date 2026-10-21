extends "res://scripts/game/level_gameplay.gd"
## Root of `arena_N_gameplay.tscn`. On top of level_gameplay.gd (Kaelen at PlayerStart + PSX
## material) it places the boss (child `Boss`) at BossStart facing Kaelen, closes the gates, emits
## Events.arena_entered and starts the Orchestrator (Orchestrator.begin_arena), which spawns the
## minions at the `spawn_point`s; it shows the boss bar in Kaelen's HUD. On Events.boss_defeated it
## hides the bar and, GATE_OPEN_DELAY s later, lowers GateExit (meta `open_offset`) and emits
## Events.arena_cleared. The ExitTrigger is handled by level_gameplay.gd; here we only require the
## arena to be cleared (`_can_exit`).

const GATE_OPEN_DELAY := 3.0
## Arrival from the floor below (GameState.arrival_walk): Kaelen appears on the entry landing,
## ARRIVAL_BEHIND_GATE m behind the open entry gate, and walks to PlayerStart; the gate rises behind
## her and only then do the boss and the Orchestrator start.
const ARRIVAL_BEHIND_GATE := 3.5
const ARRIVAL_SPEED := 3.0
## Safety margin over the walk's own duration: if something blocks her, the arrival ends anyway.
const ARRIVAL_TIMEOUT_MARGIN := 2.5
## Narrated line about this floor's guardian, shown while she walks in (Narration).
const LORE_KEYS := {1: "FLOOR_LORE_1", 2: "FLOOR_LORE_2", 3: "FLOOR_LORE_3"}
const LORE_HOLD := 3.0
const GATE_OPEN_TIME := 2.0
const GATE_CLOSE_TIME := 1.0
## The gate sound outlasts the movement: it is cut with a fade after this time.
const GATE_SOUND_MAX_TIME := 6.0
const GATE_SOUND_FADE := 1.5

@export var config: ArenaConfig
## Boss fight music: starts (with a fade) when the boss notices Kaelen.
@export var boss_music: AudioStream
## Sound of the stone gates opening or closing (3D, at the gate).
@export var gate_sound: AudioStream

var arena_cleared := false
## true while Kaelen walks in from the entry stairs.
var arriving := false

@onready var boss: Boss = get_node_or_null(^"Boss") as Boss

var _gate_entry: Node3D
var _gate_exit: Node3D
var _closed_entry := Vector3.INF   # the entry gate's closed position (as authored)


func _ready() -> void:
	super._ready()
	var arena_id := config.arena_id if config else 1
	if boss:
		PSX.apply_psx(boss.get_node("Model"))
		var boss_start := level.get_node_or_null("BossStart") as Node3D
		if boss_start:
			boss.spawn_at(boss_start, player.global_position)
		else:
			push_warning("%s has no BossStart" % level.name)
		boss.health.died.connect(_on_boss_died)
		boss.state_changed.connect(_on_boss_state_changed)
	_gate_entry = level.get_node_or_null("GateEntry") as Node3D
	_gate_exit = level.get_node_or_null("GateExit") as Node3D
	var hud := player.get_node_or_null(^"HUD") as Hud
	if hud and boss:
		hud.show_boss(boss.display_name, boss.health)
	var events := get_node_or_null(^"/root/Events")
	if events:
		events.boss_defeated.connect(_on_boss_defeated)
		events.arena_entered.emit(arena_id)
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state and bool(game_state.get(&"arrival_walk")) and _start_arrival():
		game_state.set(&"arrival_walk", false)
		return
	_close_entry_gate()
	_start_fight()


func _preload_on_start() -> bool:
	return false   # the next floor is preloaded when the boss falls


## The fight proper: the Orchestrator starts its waves (the boss is already active).
func _start_fight() -> void:
	var orchestrator := get_node_or_null(^"/root/Orchestrator")
	if orchestrator and config:
		orchestrator.begin_arena(config, self, boss)


## Arrival walk from the entry landing to PlayerStart. Returns false (normal start) if the level has
## no entry gate or PlayerStart.
func _start_arrival() -> bool:
	var start := level.get_node_or_null("PlayerStart") as Node3D
	if _gate_entry == null or start == null:
		return false
	arriving = true
	var back := start.global_basis.z   # PlayerStart faces the arena (-Z); the entry hall is behind
	back.y = 0.0
	back = back.normalized()
	var from := Marker3D.new()
	add_child(from)
	var along := (_gate_entry.global_position - start.global_position).dot(back) + ARRIVAL_BEHIND_GATE
	from.global_transform = Transform3D(start.global_basis, start.global_position + back * along)
	player.spawn_at(from)
	from.queue_free()
	if boss:
		boss.process_mode = Node.PROCESS_MODE_DISABLED
	_open_entry_gate_now()
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state:
		game_state.set(&"cutscene_active", true)
	player.set_cutscene(true)
	player.scripted_walk_finished.connect(_on_arrival_finished, CONNECT_ONE_SHOT)
	player.scripted_walk([start.global_position] as Array[Vector3], ARRIVAL_SPEED)
	var lore: String = LORE_KEYS.get(config.arena_id if config else 0, "")
	if not lore.is_empty():
		Narration.say(self, tr(lore), LORE_HOLD)
	var timeout := along / ARRIVAL_SPEED + ARRIVAL_TIMEOUT_MARGIN
	get_tree().create_timer(timeout, false).timeout.connect(_on_arrival_timeout)
	return true


func _on_arrival_timeout() -> void:
	if arriving:
		push_warning("%s: the arrival walk did not finish; ending it" % name)
		player.set_cutscene(false)   # ends the walk -> scripted_walk_finished -> _on_arrival_finished


func _on_arrival_finished() -> void:
	arriving = false
	var start := level.get_node_or_null("PlayerStart") as Node3D
	if start:
		player.face_point(start.global_position - start.global_basis.z)
	player.set_cutscene(false)
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state:
		game_state.set(&"cutscene_active", false)
	if boss:
		boss.process_mode = Node.PROCESS_MODE_INHERIT
	_close_entry_gate()
	_start_fight()


## The entry gate lowered (open) from the first physics step: Kaelen walks in under it.
func _open_entry_gate_now() -> void:
	var closed := _gate_entry.position
	_closed_entry = closed
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(_gate_entry, "position", closed + _open_offset(_gate_entry), 0.0)


# --- Gates ------------------------------------------------------------------------------------

## The entry gate starts open (lowered) and rises behind Kaelen.
func _close_entry_gate() -> void:
	if _gate_entry == null:
		return
	var closed := _closed_entry
	if closed == Vector3.INF:
		closed = _gate_entry.position
		_closed_entry = closed
	# from(): the open position is applied on the tween's first step (an AnimatableBody3D moved in
	# _ready, before it is in the physics space, gets its old transform back).
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(_gate_entry, "position", closed, GATE_CLOSE_TIME).from(closed + _open_offset(_gate_entry))
	_play_gate_sound(_gate_entry)


func _open_exit_gate() -> void:
	if _gate_exit == null:
		return
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(_gate_exit, "position", _gate_exit.position + _open_offset(_gate_exit), GATE_OPEN_TIME)
	_play_gate_sound(_gate_exit)


func _play_gate_sound(gate: Node3D) -> void:
	if gate_sound == null:
		return
	var sound := AudioStreamPlayer3D.new()
	sound.stream = gate_sound
	sound.bus = &"SFX"
	sound.unit_size = 12.0
	add_child(sound)
	sound.global_position = gate.global_position
	sound.play()
	var tween := create_tween()   # pauses with the tree, like the sound
	tween.tween_interval(GATE_SOUND_MAX_TIME - GATE_SOUND_FADE)
	tween.tween_property(sound, "volume_db", -60.0, GATE_SOUND_FADE)
	tween.tween_callback(sound.queue_free)


static func _open_offset(gate: Node3D) -> Vector3:
	return gate.get_meta(&"open_offset", Vector3(0, -6.1, 0))


# --- Boss -------------------------------------------------------------------------------------

## The boss music starts when the boss leaves idle (notices Kaelen).
func _on_boss_state_changed(state: Boss.State) -> void:
	if state == Boss.State.IDLE or boss_music == null or boss.health.is_dead() or _player_dead:
		return
	var audio := _audio()
	if audio:
		audio.play_music(boss_music, MUSIC_FADE)


func _on_boss_died() -> void:
	var hud := player.get_node_or_null(^"HUD") as Hud
	if hud:
		hud.hide_boss()


func _on_boss_defeated(defeated: Node3D) -> void:
	if defeated != boss or arena_cleared:
		return
	arena_cleared = true
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state:
		game_state.call(&"preload_next_level")   # loads while the gate opens and she climbs
	var audio := _audio()
	if audio:
		audio.stop_music(MUSIC_FADE)
	get_tree().create_timer(GATE_OPEN_DELAY, false, true).timeout.connect(_on_gate_delay_finished)


func _on_gate_delay_finished() -> void:
	_open_exit_gate()
	var events := get_node_or_null(^"/root/Events")
	if events:
		events.arena_cleared.emit(config.arena_id if config else 1)


## The ExitTrigger can be used only with the boss defeated (the gate has opened or is opening).
func _can_exit() -> bool:
	return arena_cleared
