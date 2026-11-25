extends CanvasLayer
## Death screen (spec 10.4). On Events.player_died: waits DEATH_DELAY (Kaelen's fall), fades in the
## "YOU DIED" title and, after TITLE_TIME, a panel with three buttons: Retry
## (GameState.reload_current_arena), Back to menu and Quit. While the buttons are visible the tree
## is paused (this layer keeps running: PROCESS_MODE_ALWAYS) and the cursor is free.
## Child of the GameState autoload; GameState hides it (hide_now) on scene change.

const FADE_IN := 1.0
const DEATH_DELAY := 1.6   # from the death until the title appears (fall animation)
const TITLE_TIME := 1.2    # from the title appearing until the buttons appear
const BUTTONS_FADE := 0.4
## Death screen music: looping ogg (loop=true in the .import, spliced on the beat); it plays while
## the screen is visible and hide_now() fades it out.
const DEATH_SOUND := preload("res://assets/audio/bgm/death_screen_loop.ogg")
const SOUND_FADE_OUT := 0.8

## Fallback text if the translation key does not exist yet (tr() returns the key).
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
var _fade_tween: Tween
var _panel_tween: Tween
var _run_id := 0   # invalidates the waits of a previous death

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
	MenuNav.link_vertical([_retry, _menu, _quit])
	var events := get_node_or_null(^"/root/Events")
	if events:
		events.player_died.connect(_on_player_died)


## Translated text; without a translation (tr returns the key) uses the Spanish fallback.
func text_for(key: String) -> String:
	return fallback_text(key, tr(key))


## `translated` is what tr(key) returned: if it is the key itself the Spanish fallback is used.
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
		return   # the scene was already changed by another path
	_root.visible = true
	_root.modulate.a = 0.0
	_title.modulate.a = 1.0
	_fade_tween = _restart_tween(_fade_tween)
	_fade_tween.tween_property(_root, ^"modulate:a", 1.0, FADE_IN)
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
	_panel_tween = _restart_tween(_panel_tween)
	_panel_tween.tween_property(_panel, ^"modulate:a", 1.0, BUTTONS_FADE)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var audio := get_node_or_null(^"/root/AudioManager")
	if audio:
		audio.grab_focus_silent(_retry)
	else:
		_retry.grab_focus()


## Kills `old` (if alive) and returns a new tween that ignores time scale.
func _restart_tween(old: Tween) -> Tween:
	if old and old.is_valid():
		old.kill()
	return create_tween().set_ignore_time_scale(true)


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


## If the fade could not start (missing scene) the screen is not left locked.
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
	for tween: Tween in [_fade_tween, _panel_tween]:
		if tween and tween.is_valid():
			tween.kill()
	_fade_out_sound()
	_active = false
	_buttons_shown = false
	_run_id += 1
	_root.visible = false
