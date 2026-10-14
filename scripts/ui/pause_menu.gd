extends CanvasLayer
## Menú de pausa (spec §10.2). Hijo del autoload GameState: existe en todas las escenas, pero solo
## se abre con "pause" si la escena actual tiene un nodo en el grupo "player" y GameState.can_pause()
## (sin fundido ni pantalla de muerte). Pausa con get_tree().paused y sigue activo con
## PROCESS_MODE_ALWAYS. Libera el cursor al abrir y lo recaptura al cerrar.

@onready var _root: Control = $Root
@onready var _continue: Button = %Continue
@onready var _menu: Button = %MainMenu
@onready var _quit: Button = %Quit


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	_continue.pressed.connect(close)
	_menu.pressed.connect(_on_main_menu)
	_quit.pressed.connect(_on_quit)


func is_open() -> bool:
	return _root.visible


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
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
	_continue.grab_focus()


func close() -> void:
	_root.visible = false
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Oculta sin tocar pausa ni cursor (GameState lo llama al cambiar de escena).
func close_silently() -> void:
	_root.visible = false


func _on_main_menu() -> void:
	# Sigue en pausa durante el fundido; GameState._swap_scene quita la pausa al cambiar de escena.
	_root.visible = false
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state:
		game_state.call(&"go_to_main_menu")
	else:
		get_tree().paused = false


func _on_quit() -> void:
	get_tree().quit()
