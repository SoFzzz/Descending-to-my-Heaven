class_name Credits
extends Control
## Pantalla de créditos (spec §10.4): equipo y lista de assets con autor y licencia (requisito CC BY)
## con botón para volver al menú. Lee res://assets/credits.txt y lo muestra en un ScrollContainer que
## sube solo, despacio. Al usar la rueda del ratón o las flechas arriba/abajo, el desplazamiento
## automático se pausa un rato. Esc o el botón vuelven al menú principal con el fundido de GameState.

const CREDITS_MUSIC := preload("res://assets/audio/bgm/ending_celtic_melancholy.mp3")
const CREDITS_PATH := "res://assets/credits.txt"
const MAIN_MENU_PATH := "res://scenes/ui/main_menu.tscn"
## Títulos de sección de credits.txt (en español) -> clave de traducción.
const SECTION_KEYS := {
	"Equipo": "CREDITS_SEC_TEAM", "Personajes y jefes": "CREDITS_SEC_CHARACTERS",
	"Escenario, armas y objetos": "CREDITS_SEC_WORLD", "Shaders": "CREDITS_SEC_SHADERS",
	"Audio": "CREDITS_SEC_AUDIO", "Interfaz": "CREDITS_SEC_UI", "Efectos visuales": "CREDITS_SEC_VFX",
	"Animaciones": "CREDITS_SEC_ANIMATIONS", "Motor": "CREDITS_SEC_ENGINE",
	"Gracias por jugar": "CREDITS_SEC_THANKS",
}
## Etiquetas que se traducen dentro de las líneas (la más larga primero).
const TOKEN_KEYS := [
	["Autor y licencia por confirmar", "CREDITS_AUTHOR_LICENSE_TBC"],
	["autor y licencia por confirmar", "CREDITS_AUTHOR_LICENSE_TBC"],
	["por confirmar", "CREDITS_TBC"],
	["Autor:", "CREDITS_AUTHOR"], ["Licencia:", "CREDITS_LICENSE"], ["Fuente:", "CREDITS_SOURCE"],
]
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
	_text.text = _credits_bbcode(localize(_load_credits()))
	_scroll.gui_input.connect(_on_scroll_gui_input)
	_back.pressed.connect(_go_back)
	_back.set_meta(&"ui_sound", &"back")
	_back.grab_focus()
	# Sin pista propia sigue la de Elysia (si ya suena, no se reinicia).
	var audio := get_node_or_null(^"/root/AudioManager")
	if audio:
		audio.play_music(CREDITS_MUSIC, 1.5)


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
		var audio := get_node_or_null(^"/root/AudioManager")
		if audio and not _leaving:
			audio.play_ui(audio.UI_BACK)
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
		return tr("CREDITS_FALLBACK")
	return text


## Traduce los títulos de sección y las etiquetas (Autor / Licencia / Fuente / por confirmar) del
## texto de créditos al idioma actual. En español no cambia nada. Los nombres de assets, autores y
## licencias no se traducen.
static func localize(plain: String) -> String:
	var lines := plain.replace("\r", "").split("\n")
	var out: PackedStringArray = []
	for line in lines:
		var key: String = SECTION_KEYS.get(line.strip_edges(), "")
		if key != "":
			out.append(TranslationServer.translate(StringName(key)))
			continue
		var text := line
		for token: Array in TOKEN_KEYS:
			var translated := TranslationServer.translate(StringName(token[1]))
			var original: String = token[0]
			if original.unicode_at(0) >= 97:   # empieza en minúscula
				translated = translated.substr(0, 1).to_lower() + translated.substr(1)
			if original.ends_with(":"):
				translated += ":"
			text = text.replace(original, translated)
		out.append(text)
	return "\n".join(out)


## Convierte el texto plano en BBCode centrado: escapa los corchetes para que no se interpreten como etiquetas.
func _credits_bbcode(plain: String) -> String:
	var escaped := plain.replace("[", "[lb]").replace("]", "[rb]")
	return "[center]%s[/center]" % escaped
