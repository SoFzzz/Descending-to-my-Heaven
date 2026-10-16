class_name Credits
extends Control
## Credits screen (spec 10.4): team and asset list with author and licence (CC BY requirement) with
## a button to go back to the menu. Reads res://assets/credits.txt and shows it in a ScrollContainer
## that scrolls up slowly by itself. Using the mouse wheel or the up/down arrows pauses the automatic
## scroll for a while. Esc or the button return to the main menu with GameState's fade.

const CREDITS_MUSIC := preload("res://assets/audio/bgm/ending_celtic_melancholy_loop.ogg")
const CREDITS_PATH := "res://assets/credits.txt"
const MAIN_MENU_PATH := "res://scenes/ui/main_menu.tscn"
## Section titles of credits.txt (in Spanish) -> translation key.
const SECTION_KEYS := {
	"Equipo": "CREDITS_SEC_TEAM", "Personajes y jefes": "CREDITS_SEC_CHARACTERS",
	"Escenario, armas y objetos": "CREDITS_SEC_WORLD", "Shaders": "CREDITS_SEC_SHADERS",
	"Audio": "CREDITS_SEC_AUDIO", "Interfaz": "CREDITS_SEC_UI", "Efectos visuales": "CREDITS_SEC_VFX",
	"Animaciones": "CREDITS_SEC_ANIMATIONS", "Motor": "CREDITS_SEC_ENGINE",
	"Gracias por jugar": "CREDITS_SEC_THANKS",
}
## Labels translated inside the lines (longest first).
const TOKEN_KEYS := [
	["Autor y licencia por confirmar", "CREDITS_AUTHOR_LICENSE_TBC"],
	["autor y licencia por confirmar", "CREDITS_AUTHOR_LICENSE_TBC"],
	["por confirmar", "CREDITS_TBC"],
	["Autor:", "CREDITS_AUTHOR"], ["Licencia:", "CREDITS_LICENSE"], ["Fuente:", "CREDITS_SOURCE"],
]
const AUTO_SCROLL_SPEED := 30.0   # pixels per second
const MANUAL_SCROLL_SPEED := 300.0   # pixels per second with the arrows
const PAUSE_AFTER_MANUAL := 4.0   # seconds without auto-scroll after manual interaction

var _scroll_y := 0.0      # float position: scroll_vertical is an int and auto-scroll moves in fractions
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
	# Without a track of its own it follows Elysia's (if it is already playing it is not restarted).
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


## Scrolls the content `amount` pixels (negative = up) and stops at the ends.
func _move(amount: float) -> void:
	var bar: VScrollBar = _scroll.get_v_scroll_bar()
	var max_pos := maxf(bar.max_value - bar.page, 0.0)
	# If the wheel or another source moved the bar, resync the float position.
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
	_leaving = true   # no double presses during the fade
	_back.disabled = true
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state:
		# _change_scene returns false while a fade is still running (e.g. the one entering the
		# credits): the button is re-enabled so the player can try again.
		if not game_state.call(&"_change_scene", MAIN_MENU_PATH):
			_leaving = false
			_back.disabled = false
	elif ResourceLoader.exists(MAIN_MENU_PATH):
		get_tree().change_scene_to_file(MAIN_MENU_PATH)


func _load_credits() -> String:
	var text := FileAccess.get_file_as_string(CREDITS_PATH)
	if text.is_empty():
		push_warning("Credits: could not read '%s'; showing the fallback text." % CREDITS_PATH)
		return tr("CREDITS_FALLBACK")
	return text


## Translates the section titles and labels (Autor / Licencia / Fuente / por confirmar) of the
## credits text into the current language. In Spanish nothing changes. Asset names, authors and
## licences are not translated.
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
			if original.unicode_at(0) >= 97:   # starts in lowercase
				translated = translated.substr(0, 1).to_lower() + translated.substr(1)
			if original.ends_with(":"):
				translated += ":"
			text = text.replace(original, translated)
		out.append(text)
	return "\n".join(out)


## Turns the plain text into centred BBCode: escapes the brackets so they are not parsed as tags.
func _credits_bbcode(plain: String) -> String:
	var escaped := plain.replace("[", "[lb]").replace("]", "[rb]")
	return "[center]%s[/center]" % escaped
