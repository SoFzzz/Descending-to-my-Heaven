extends Control
## Pantalla de créditos (spec §10.4): equipo y lista de assets con autor y licencia (requisito CC BY)
## con botón para volver al menú. Lee res://assets/credits.txt y lo muestra en un ScrollContainer que
## sube solo, despacio. Al usar la rueda del ratón o las flechas arriba/abajo, el desplazamiento
## automático se pausa un rato. Esc o el botón vuelven al menú principal con el fundido de GameState.

const CREDITS_PATH := "res://assets/credits.txt"
const MAIN_MENU_PATH := "res://scenes/ui/main_menu.tscn"
const FALLBACK_TEXT := "Descending to my Heaven\n\nNo se pudo cargar la lista de créditos."
const AUTO_SCROLL_SPEED := 30.0   # píxeles por segundo
const MANUAL_SCROLL_SPEED := 300.0   # píxeles por segundo con las flechas
const PAUSE_AFTER_MANUAL := 4.0   # segundos sin auto-scroll tras interactuar a mano

var _scroll_y := 0.0      # posición en float: scroll_vertical es entero y el auto-scroll va a fracciones
var _pause_left := 0.0
var _leaving := false

@onready var _scroll: ScrollContainer = %Scroll
@onready var _text: RichTextLabel = %Text
@onready var _back: Button = %Back


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_text.text = _credits_bbcode(_load_credits())
	_scroll.gui_input.connect(_on_scroll_gui_input)
	_back.pressed.connect(_go_back)
	_back.grab_focus()


func _process(delta: float) -> void:
	var manual := Input.get_axis(&"ui_up", &"ui_down")
	if manual != 0.0:
		_pause_left = PAUSE_AFTER_MANUAL
		_move(manual * MANUAL_SCROLL_SPEED * delta)
	elif _pause_left > 0.0:
		_pause_left -= delta
	else:
		_move(AUTO_SCROLL_SPEED * delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_go_back()
		get_viewport().set_input_as_handled()


## Desplaza el contenido `amount` píxeles (negativo = hacia arriba) y se detiene en los extremos.
func _move(amount: float) -> void:
	var bar: VScrollBar = _scroll.get_v_scroll_bar()
	var max_pos := maxf(bar.max_value - bar.page, 0.0)
	# Si la rueda u otra fuente movió la barra, resincronizar la posición en float.
	if absf(float(_scroll.scroll_vertical) - _scroll_y) >= 1.0:
		_scroll_y = float(_scroll.scroll_vertical)
	_scroll_y = clampf(_scroll_y + amount, 0.0, max_pos)
	_scroll.scroll_vertical = int(_scroll_y)


func _on_scroll_gui_input(event: InputEvent) -> void:
	var wheel := event as InputEventMouseButton
	if wheel and wheel.pressed and wheel.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_pause_left = PAUSE_AFTER_MANUAL


func _go_back() -> void:
	if _leaving:
		return
	_leaving = true   # sin dobles pulsaciones durante el fundido
	_back.disabled = true
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state:
		# _change_scene devuelve false si aún hay un fundido en curso (p. ej. el de entrada a
		# los créditos): se reactiva el botón para poder volver a intentarlo.
		if not game_state.call(&"_change_scene", MAIN_MENU_PATH):
			_leaving = false
			_back.disabled = false
	elif ResourceLoader.exists(MAIN_MENU_PATH):
		get_tree().change_scene_to_file(MAIN_MENU_PATH)


func _load_credits() -> String:
	var text := FileAccess.get_file_as_string(CREDITS_PATH)
	if text.is_empty():
		push_warning("Créditos: no se pudo leer '%s'; se muestra el texto de respaldo." % CREDITS_PATH)
		return FALLBACK_TEXT
	return text


## Convierte el texto plano en BBCode centrado: escapa los corchetes para que no se interpreten como etiquetas.
func _credits_bbcode(plain: String) -> String:
	var escaped := plain.replace("[", "[lb]").replace("]", "[rb]")
	return "[center]%s[/center]" % escaped
