extends CanvasLayer
## Pantalla de muerte (spec §10.4): con Events.player_died muestra "HAS MUERTO" con fundido y, tras
## SHOW_TIME, llama a GameState.reload_current_arena() (que hace su propio fundido a negro). Sin
## menú. Hijo del autoload GameState; GameState la oculta (hide_now) al cambiar de escena.

const FADE_IN := 1.0
const SHOW_TIME := 2.5   # desde la muerte hasta pedir la recarga
const DEATH_SOUND := preload("res://assets/audio/sfx/ui/death_screen.mp3")
const SOUND_FADE_OUT := 0.8

var _active := false
var _sound: AudioStreamPlayer

@onready var _root: Control = $Root


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	var events := get_node_or_null(^"/root/Events")
	if events:
		events.player_died.connect(_on_player_died)


func is_active() -> bool:
	return _active


func _on_player_died() -> void:
	if _active:
		return
	_active = true
	_root.visible = true
	_root.modulate.a = 0.0
	_play_death_sound()
	var tween := create_tween().set_ignore_time_scale(true)
	tween.tween_property(_root, ^"modulate:a", 1.0, FADE_IN)
	await get_tree().create_timer(SHOW_TIME, true, false, true).timeout
	if not _active:
		return   # ya se cambió de escena por otra vía
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state:
		game_state.call(&"reload_current_arena")
	# Si no hubo fundido (no se pudo recargar), no dejarla puesta para siempre.
	var transition: Node = game_state.get(&"transition") if game_state else null
	if transition == null or not transition.call(&"is_busy"):
		hide_now()


func _play_death_sound() -> void:
	if _sound == null:
		_sound = AudioStreamPlayer.new()
		_sound.stream = DEATH_SOUND
		_sound.bus = &"UI"
		add_child(_sound)
	_sound.volume_db = 0.0
	_sound.play()


## The sound is longer than the screen: when the scene changes it fades out.
func _fade_out_sound() -> void:
	if _sound == null or not _sound.playing:
		return
	var tween := create_tween().set_ignore_time_scale(true)
	tween.tween_property(_sound, "volume_db", -60.0, SOUND_FADE_OUT)
	tween.tween_callback(_sound.stop)


func hide_now() -> void:
	_fade_out_sound()
	_active = false
	_root.visible = false
