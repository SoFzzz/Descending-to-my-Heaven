extends "res://scripts/game/level_gameplay.gd"
## Raíz de `arena_N_gameplay.tscn` (Tarea 9). Además de lo de level_gameplay.gd (Kaelen en
## PlayerStart + material PSX): coloca al jefe (hijo `Boss`) en BossStart mirando a Kaelen,
## cierra las rejas, emite Events.arena_entered y arranca al Orquestador
## (Orchestrator.begin_arena), que genera los esbirros en los `spawn_point`; muestra la barra
## del jefe en el HUD de Kaelen. Con Events.boss_defeated oculta la barra y, GATE_OPEN_DELAY s
## después, baja GateExit (meta `open_offset`) y emite Events.arena_cleared. El ExitTrigger lo gestiona
## level_gameplay.gd; aquí solo se exige que la arena esté despejada (`_can_exit`).

const GATE_OPEN_DELAY := 3.0
const GATE_OPEN_TIME := 2.0
const GATE_CLOSE_TIME := 1.0
## El sonido de la reja dura más que el movimiento: se corta con un fundido pasado este tiempo.
const GATE_SOUND_MAX_TIME := 6.0
const GATE_SOUND_FADE := 1.5

@export var config: ArenaConfig
## Música del combate con el jefe: arranca (con fundido) cuando el jefe detecta a Kaelen.
@export var boss_music: AudioStream
## Sonido de las rejas de piedra al abrirse o cerrarse (3D, en la reja).
@export var gate_sound: AudioStream

var arena_cleared := false

@onready var boss: Boss = get_node_or_null(^"Boss") as Boss

var _gate_entry: Node3D
var _gate_exit: Node3D


func _ready() -> void:
	super._ready()
	var arena_id := config.arena_id if config else 1
	if boss:
		PSX.apply_psx(boss.get_node("Model"))
		var boss_start := level.get_node_or_null("BossStart") as Node3D
		if boss_start:
			boss.spawn_at(boss_start, player.global_position)
		else:
			push_warning("%s no tiene BossStart" % level.name)
		boss.health.died.connect(_on_boss_died)
		boss.state_changed.connect(_on_boss_state_changed)
	_gate_entry = level.get_node_or_null("GateEntry") as Node3D
	_gate_exit = level.get_node_or_null("GateExit") as Node3D
	_close_entry_gate()
	var hud := player.get_node_or_null(^"HUD") as Hud
	if hud and boss:
		hud.show_boss(boss.display_name, boss.health)
	var events := get_node_or_null(^"/root/Events")
	if events:
		events.boss_defeated.connect(_on_boss_defeated)
		events.arena_entered.emit(arena_id)
	var orchestrator := get_node_or_null(^"/root/Orchestrator")
	if orchestrator and config:
		orchestrator.begin_arena(config, self, boss)


# --- Rejas ------------------------------------------------------------------------------------

## La reja de entrada arranca abierta (bajada) y sube detrás de Kaelen.
func _close_entry_gate() -> void:
	if _gate_entry == null:
		return
	var closed := _gate_entry.position
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


# --- Jefe -------------------------------------------------------------------------------------

## La música del jefe empieza cuando deja de estar en reposo (detecta a Kaelen).
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
	var audio := _audio()
	if audio:
		audio.stop_music(MUSIC_FADE)
	get_tree().create_timer(GATE_OPEN_DELAY, false, true).timeout.connect(_on_gate_delay_finished)


func _on_gate_delay_finished() -> void:
	_open_exit_gate()
	var events := get_node_or_null(^"/root/Events")
	if events:
		events.arena_cleared.emit(config.arena_id if config else 1)


## Se puede salir por el ExitTrigger solo con el jefe derrotado (la reja ya se abrió o se abre).
func _can_exit() -> bool:
	return arena_cleared
