extends CanvasLayer
## Pantalla de muerte (spec §10.4). Con Events.player_died: espera DEATH_DELAY (la caída de Kaelen),
## muestra "HAS MUERTO" con fundido y, pasado TITLE_TIME, un panel con tres botones: Reintentar
## (GameState.reload_current_arena), Volver al menú y Salir del juego. Mientras los botones están
## visibles el árbol está en pausa (esta capa sigue activa: PROCESS_MODE_ALWAYS) y el cursor libre.
## Hijo del autoload GameState; GameState la oculta (hide_now) al cambiar de escena.

const FADE_IN := 1.0
const DEATH_DELAY := 1.6   # desde la muerte hasta que aparece el título (animación de caída)
const TITLE_TIME := 1.2    # desde que aparece el título hasta que aparecen los botones
const BUTTONS_FADE := 0.4
## Música de la pantalla de muerte: ogg en bucle (loop=true en el .import, empalmado en compás);
## suena mientras la pantalla esté visible y hide_now() la corta con fundido.
const DEATH_SOUND := preload("res://assets/audio/bgm/death_screen_loop.ogg")
const SOUND_FADE_OUT := 0.8

## Texto de respaldo si la clave de traducción no existe todavía (tr() devuelve la clave).
const FALLBACKS := {
	"DEATH_TITLE": "HAS MUERTO",
	"DEATH_RETRY": "Reintentar",
	"DEATH_MENU": "Volver al menú",
	"DEATH_QUIT": "Salir del juego",
}

var _active := false
var _buttons_shown := false
var _sound: AudioStreamPlayer
var _sound_tween: Tween
var _run_id := 0   # invalida las esperas de una muerte anterior

@onready var _root: Control = $Root
@onready var _title: Label = %Title
@onready var _panel: Control = %Panel
@onready var _retry: Button = %Retry
@onready var _menu: Button = %Menu
@onready var _quit: Button = %Quit


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	_apply_texts()
	_retry.pressed.connect(_on_retry)
	_menu.pressed.connect(_on_menu)
	_quit.pressed.connect(_on_quit)
	var events := get_node_or_null(^"/root/Events")
	if events:
		events.player_died.connect(_on_player_died)


## Texto traducido; si no hay traducción (tr devuelve la clave) usa el español de respaldo.
func text_for(key: String) -> String:
	return fallback_text(key, tr(key))


## `translated` es lo que devolvió tr(key): si es la propia clave se usa el español de respaldo.
static func fallback_text(key: String, translated: String) -> String:
	return FALLBACKS.get(key, key) if translated == key else translated


func _apply_texts() -> void:
	_title.text = text_for("DEATH_TITLE")
	_retry.text = text_for("DEATH_RETRY")
	_menu.text = text_for("DEATH_MENU")
	_quit.text = text_for("DEATH_QUIT")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_texts()


func is_active() -> bool:
	return _active


func buttons_visible() -> bool:
	return _buttons_shown


func _on_player_died() -> void:
	if _active:
		return
	_active = true
	_buttons_shown = false
	_run_id += 1
	var run := _run_id
	_apply_texts()
	_root.visible = false
	_panel.visible = false
	_play_death_sound()
	await get_tree().create_timer(DEATH_DELAY, true, false, true).timeout
	if run != _run_id or not _active:
		return   # ya se cambió de escena por otra vía
	_root.visible = true
	_root.modulate.a = 0.0
	_title.modulate.a = 1.0
	create_tween().set_ignore_time_scale(true).tween_property(_root, ^"modulate:a", 1.0, FADE_IN)
	await get_tree().create_timer(TITLE_TIME, true, false, true).timeout
	if run != _run_id or not _active:
		return
	_show_buttons()


func _show_buttons() -> void:
	_buttons_shown = true
	for button in [_retry, _menu, _quit]:
		button.disabled = false
	_panel.visible = true
	_panel.modulate.a = 0.0
	create_tween().set_ignore_time_scale(true).tween_property(_panel, ^"modulate:a", 1.0, BUTTONS_FADE)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var audio := get_node_or_null(^"/root/AudioManager")
	if audio:
		audio.grab_focus_silent(_retry)
	else:
		_retry.grab_focus()


func _lock_buttons() -> void:
	for button in [_retry, _menu, _quit]:
		button.disabled = true


func _on_retry() -> void:
	_lock_buttons()
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state:
		game_state.call(&"reload_current_arena")
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_after_leave(game_state)


func _on_menu() -> void:
	_lock_buttons()
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state:
		game_state.call(&"go_to_main_menu")
	_after_leave(game_state)


func _on_quit() -> void:
	get_tree().quit()


## Si no se pudo iniciar el fundido (escena inexistente) no se deja la pantalla bloqueada.
func _after_leave(game_state: Node) -> void:
	var transition: Node = game_state.get(&"transition") if game_state else null
	if transition == null or not transition.call(&"is_busy"):
		hide_now()
		get_tree().paused = false


func _play_death_sound() -> void:
	if _sound == null:
		_sound = AudioStreamPlayer.new()
		_sound.stream = DEATH_SOUND
		_sound.bus = &"UI"
		add_child(_sound)
	if _sound_tween and _sound_tween.is_valid():
		_sound_tween.kill()   # a fade-out from a previous death must not stop this one
	_sound.volume_db = 0.0
	_sound.play()


## The music loops while the screen is up: when the scene changes it fades out.
func _fade_out_sound() -> void:
	if _sound == null or not _sound.playing:
		return
	if _sound_tween and _sound_tween.is_valid():
		_sound_tween.kill()
	_sound_tween = create_tween().set_ignore_time_scale(true)
	_sound_tween.tween_property(_sound, "volume_db", -60.0, SOUND_FADE_OUT)
	_sound_tween.tween_callback(_sound.stop)


func hide_now() -> void:
	_fade_out_sound()
	_active = false
	_buttons_shown = false
	_run_id += 1
	_root.visible = false
