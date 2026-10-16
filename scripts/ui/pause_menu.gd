extends CanvasLayer
## Pause menu (spec 10.2). Child of the GameState autoload: it exists in every scene, but "pause"
## only opens it if the current scene has a node in the "player" group and GameState.can_pause()
## (no fade or death screen). Pauses with get_tree().paused and keeps running thanks to
## PROCESS_MODE_ALWAYS. Frees the cursor on open and recaptures it on close.

@onready var _root: Control = $Root
@onready var _continue: Button = %Continue
@onready var _options: Button = %Options
@onready var _options_menu: OptionsMenu = $Root/OptionsMenu
@onready var _menu: Button = %MainMenu
@onready var _quit: Button = %Quit


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	_continue.set_meta(&"ui_sound", &"none")   # closing already plays its own sound
	_continue.pressed.connect(close)
	_options.pressed.connect(_options_menu.open)
	_options_menu.closed.connect(_on_options_closed)
	_menu.pressed.connect(_on_main_menu)
	_quit.pressed.connect(_on_quit)


func _on_options_closed() -> void:
	var audio := get_node_or_null(^"/root/AudioManager")
	if audio:
		audio.grab_focus_silent(_options)
	else:
		_options.grab_focus()


func is_open() -> bool:
	return _root.visible


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause") or _options_menu.is_open():
		return
	if is_open():
		close()
	elif can_open():
		open()
	else:
		return
	get_viewport().set_input_as_handled()


func can_open() -> bool:
	var tree := get_tree()
	if tree.paused or tree.current_scene == null:
		return false
	if tree.get_first_node_in_group(&"player") == null:
		return false
	var game_state := get_node_or_null(^"/root/GameState")
	return game_state == null or game_state.call(&"can_pause")


func open() -> void:
	get_tree().paused = true
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var audio := get_node_or_null(^"/root/AudioManager")
	if audio:
		audio.play_ui(audio.UI_PAUSE_OPEN)
		audio.grab_focus_silent(_continue)
	else:
		_continue.grab_focus()


func close() -> void:
	_options_menu.visible = false
	if _root.visible:
		var audio := get_node_or_null(^"/root/AudioManager")
		if audio:
			audio.play_ui(audio.UI_PAUSE_CLOSE)
	_root.visible = false
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Hides without touching pause or cursor (GameState calls it on scene change).
func close_silently() -> void:
	_options_menu.visible = false
	_root.visible = false


func _on_main_menu() -> void:
	# Stays paused during the fade; GameState._swap_scene unpauses on the scene change.
	_root.visible = false
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state:
		game_state.call(&"go_to_main_menu")
	else:
		get_tree().paused = false


func _on_quit() -> void:
	get_tree().quit()
