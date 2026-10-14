extends Node3D
## Menú principal (spec §10.1): la isla de fondo (instancia de exterior.tscn, sin Kaelen) con una
## cámara girando lento, el título y los botones Iniciar / Créditos / Salir. Créditos se oculta si
## aún no existe scenes/ui/credits.tscn. Foco inicial en Iniciar; navegable con flechas + Enter y ratón.

const ORBIT_SPEED := 0.06   # radianes por segundo

@onready var _pivot: Node3D = $CameraPivot
@onready var _camera: Camera3D = $CameraPivot/Camera3D
@onready var _start: Button = %Start
@onready var _credits: Button = %Credits
@onready var _quit: Button = %Quit


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_camera.look_at(_pivot.global_position)
	_credits.visible = ResourceLoader.exists(GameState.CREDITS_SCENE)
	_start.pressed.connect(_on_start)
	_credits.pressed.connect(_on_credits)
	_quit.pressed.connect(_on_quit)
	_start.grab_focus()


func _process(delta: float) -> void:
	_pivot.rotate_y(ORBIT_SPEED * delta)


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
