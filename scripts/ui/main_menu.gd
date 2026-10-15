extends Node
## Menú principal (spec §10.1): fondo 2D (cielo burdeos con luna y la silueta negra de la mazmorra,
## generados con scripts/tools/gen_menu_bg.py), el título y los botones Iniciar / Créditos / Salir. Créditos se oculta si
## aún no existe scenes/ui/credits.tscn. Foco inicial en Iniciar; navegable con flechas + Enter y ratón.

const MENU_MUSIC := preload("res://assets/audio/bgm/menu_sadness_piano.mp3")

@onready var _start: Button = %Start
@onready var _credits: Button = %Credits
@onready var _quit: Button = %Quit


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_credits.visible = ResourceLoader.exists(GameState.CREDITS_SCENE)
	_start.pressed.connect(_on_start)
	_credits.pressed.connect(_on_credits)
	_quit.pressed.connect(_on_quit)
	_start.grab_focus()   # the AudioManager ignores the focus of a button that has just appeared
	var audio := get_node_or_null(^"/root/AudioManager")
	if audio:
		audio.play_music(MENU_MUSIC, 1.5)


func _on_start() -> void:
	_set_buttons_disabled(true)   # sin dobles pulsaciones durante el fundido
	GameState.start_new_game()


func _on_credits() -> void:
	_set_buttons_disabled(true)
	if not GameState.call(&"_change_scene", GameState.CREDITS_SCENE):
		_set_buttons_disabled(false)


func _on_quit() -> void:
	get_tree().quit()


func _set_buttons_disabled(on: bool) -> void:
	for button: Button in [_start, _credits, _quit]:
		button.disabled = on
