extends Node
## Menú principal (spec §10.1). Mitad izquierda: título (DungeonFont) y botones Iniciar / Opciones /
## Créditos / Salir; mitad derecha: la silueta negra de la isla flotante (IslandSilhouette) sobre un
## cielo violeta crepuscular con resplandor, estrellas que titilan y ceniza brillante
## (assets/ui/menu/menu_sky.png, scripts/tools/gen_menu_bg.py). Opciones abre el overlay OptionsMenu. Créditos se oculta si aún no
## existe scenes/ui/credits.tscn. Foco inicial en Iniciar; navegable con flechas + Enter, mando y ratón.
## Animaciones con Tweens (todas cortas o ambientales, ninguna bloquea la entrada): entrada escalonada,
## realce de botones al enfocar / pasar el ratón y salida con fundido a negro.

const CREDITS_SCENE := "res://scenes/ui/credits.tscn"   # igual que GameState.CREDITS_SCENE
const MENU_MUSIC := preload("res://assets/audio/bgm/menu_sadness_piano.mp3")

const INTRO_FADE := 0.7           # fundido desde negro
const TITLE_DELAY := 0.25
const TITLE_TIME := 0.6
const TITLE_SLIDE := 18.0         # px que sube el título al aparecer
const BUTTON_DELAY := 0.5
const BUTTON_STAGGER := 0.12
const BUTTON_TIME := 0.4
const BUTTON_SLIDE := 48.0        # px desde la izquierda
const ISLAND_DELAY := 0.15
const ISLAND_TIME := 0.9
const HOVER_TIME := 0.14
const HOVER_SHIFT := 8.0          # px a la derecha al enfocar
const HOVER_SCALE := 1.05
const HOVER_FLASH := 1.35         # brillo inicial al enfocar
const PULSE_PERIOD := 1.3
const TITLE_GLOW_PERIOD := 4.0
const GLOW_PERIOD := 6.0
const EXIT_TIME := 0.4            # salida de Iniciar / Créditos antes del fundido de GameState
const QUIT_TIME := 0.25

var _tweens: Dictionary = {}      # Button -> Array[Tween] del realce
var _leaving := false
var _intro: Tween

@onready var _start: Button = %Start
@onready var _options: Button = %Options
@onready var _credits: Button = %Credits
@onready var _quit: Button = %Quit
@onready var _fade: ColorRect = $UI/Root/Fade
@onready var _title: Label = $UI/Root/Title
@onready var _panel: Control = $UI/Root/Panel
@onready var _island: IslandSilhouette = $UI/Root/Island
@onready var _hint: Label = $UI/Root/Hint
@onready var _glow: TextureRect = $UI/Root/Glow
@onready var _options_menu: OptionsMenu = $UI/Root/OptionsMenu


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_credits.visible = ResourceLoader.exists(CREDITS_SCENE)
	(_credits.get_parent() as Control).visible = _credits.visible
	_start.pressed.connect(_on_start)
	_options.pressed.connect(_on_options)
	_options_menu.closed.connect(_on_options_closed)
	_credits.pressed.connect(_on_credits)
	_quit.pressed.connect(_on_quit)
	for button in _buttons():
		button.mouse_entered.connect(_refresh_highlight.bind(button))
		button.mouse_exited.connect(_refresh_highlight.bind(button))
		button.focus_entered.connect(_refresh_highlight.bind(button))
		button.focus_exited.connect(_refresh_highlight.bind(button))
		button.resized.connect(_on_button_resized.bind(button))
		_tweens[button] = []
	var audio := get_node_or_null(^"/root/AudioManager")
	if audio:
		audio.grab_focus_silent(_start)   # el foco inicial no suena
		audio.play_music(MENU_MUSIC, 1.5)
	else:
		_start.grab_focus()
	_play_intro()
	_start_title_glow()
	_start_sky_glow()


func _exit_tree() -> void:
	for button: Button in _tweens:
		_kill(button)


func _buttons() -> Array[Button]:
	return [_start, _options, _credits, _quit]


func _on_button_resized(button: Button) -> void:
	button.pivot_offset = Vector2(0.0, button.size.y * 0.5)


# --- Entrada ------------------------------------------------------------------------------------

func _play_intro() -> void:
	_fade.color.a = 1.0
	_title.modulate.a = 0.0
	_hint.modulate.a = 0.0
	_island.modulate.a = 0.0
	_glow.modulate.a = 0.0
	_panel.modulate.a = 0.0
	var title_y := _title.position.y
	_title.position.y = title_y + TITLE_SLIDE
	_intro = create_tween().set_parallel(true)
	_intro.tween_property(_fade, ^"color:a", 0.0, INTRO_FADE)
	_intro.tween_property(_island, ^"modulate:a", 1.0, ISLAND_TIME).set_delay(ISLAND_DELAY)
	_intro.tween_property(_glow, ^"modulate:a", 1.0, ISLAND_TIME * 1.5).set_delay(ISLAND_DELAY)
	_intro.tween_property(_title, ^"modulate:a", 1.0, TITLE_TIME).set_delay(TITLE_DELAY)
	_intro.tween_property(_title, ^"position:y", title_y, TITLE_TIME).set_delay(TITLE_DELAY) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_intro.tween_property(_panel, ^"modulate:a", 1.0, BUTTON_TIME).set_delay(BUTTON_DELAY - 0.1)
	var buttons := _buttons()
	for i in buttons.size():
		var slot := buttons[i].get_parent() as Control
		slot.modulate.a = 0.0
		buttons[i].position.x = -BUTTON_SLIDE
		var delay := BUTTON_DELAY + BUTTON_STAGGER * i
		_intro.tween_property(slot, ^"modulate:a", 1.0, BUTTON_TIME).set_delay(delay)
		_intro.tween_property(buttons[i], ^"position:x", 0.0, BUTTON_TIME).set_delay(delay) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_intro.tween_property(_hint, ^"modulate:a", 1.0, 0.5).set_delay(BUTTON_DELAY + BUTTON_STAGGER * float(buttons.size()))


## Brillo lento del título (ambiental, no bloquea nada).
func _start_title_glow() -> void:
	var glow := create_tween().set_loops()
	glow.tween_property(_title, ^"self_modulate", Color(1.12, 1.08, 1.0), TITLE_GLOW_PERIOD * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	glow.tween_property(_title, ^"self_modulate", Color(0.88, 0.86, 0.84), TITLE_GLOW_PERIOD * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Respiración lenta del resplandor tras la isla (ambiental).
func _start_sky_glow() -> void:
	var glow := create_tween().set_loops()
	glow.tween_property(_glow, ^"self_modulate", Color(1.0, 1.0, 1.0, 0.7), GLOW_PERIOD * 0.5) 			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	glow.tween_property(_glow, ^"self_modulate", Color(1.0, 1.0, 1.0, 1.0), GLOW_PERIOD * 0.5) 			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# --- Realce de botones --------------------------------------------------------------------------

func _kill(button: Button) -> void:
	for tween: Tween in _tweens.get(button, []):
		if tween and tween.is_valid():
			tween.kill()
	_tweens[button] = []


func _refresh_highlight(button: Button) -> void:
	if _leaving or not is_instance_valid(button) or not button.is_inside_tree():
		return
	var on := button.has_focus() or button.is_hovered()
	if bool(button.get_meta(&"hl", false)) == on:
		return
	button.set_meta(&"hl", on)
	_kill(button)
	var enter := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var tweens: Array = [enter]
	_tweens[button] = tweens
	# Mientras la entrada escalonada mueve el botón no se pisa su posición.
	if not (_intro != null and _intro.is_valid() and _intro.is_running()):
		enter.tween_property(button, ^"position:x", HOVER_SHIFT if on else 0.0, HOVER_TIME)
	enter.tween_property(button, ^"scale", Vector2.ONE * (HOVER_SCALE if on else 1.0), HOVER_TIME)
	if on:
		button.modulate = Color(HOVER_FLASH, HOVER_FLASH, HOVER_FLASH)
		enter.tween_property(button, ^"modulate", Color.WHITE, HOVER_TIME * 2.0)
		if button.has_focus():
			enter.finished.connect(_start_pulse.bind(button), CONNECT_ONE_SHOT)
	else:
		enter.tween_property(button, ^"modulate", Color.WHITE, HOVER_TIME)


## Pulso suave del recuadro de selección mientras el botón sigue enfocado.
func _start_pulse(button: Button) -> void:
	if _leaving or not is_instance_valid(button) or not button.has_focus():
		return
	var pulse := create_tween().set_loops()
	pulse.tween_property(button, ^"modulate", Color(0.8, 0.78, 0.78), PULSE_PERIOD * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(button, ^"modulate", Color.WHITE, PULSE_PERIOD * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	(_tweens[button] as Array).append(pulse)


# --- Salida -------------------------------------------------------------------------------------

func _on_start() -> void:
	if _begin_leave(EXIT_TIME, true):
		await get_tree().create_timer(EXIT_TIME, true, false, true).timeout
		var game_state := get_node_or_null(^"/root/GameState")
		if game_state:
			game_state.call(&"start_new_game")


func _on_options() -> void:
	if _leaving:
		return
	_set_buttons_disabled(true)
	_options_menu.open()


func _on_options_closed() -> void:
	_set_buttons_disabled(false)
	var audio := get_node_or_null(^"/root/AudioManager")
	if audio:
		audio.grab_focus_silent(_options)
	else:
		_options.grab_focus()


func _on_credits() -> void:
	if _begin_leave(EXIT_TIME, true):
		await get_tree().create_timer(EXIT_TIME, true, false, true).timeout
		var game_state := get_node_or_null(^"/root/GameState")
		if game_state == null or not game_state.call(&"_change_scene", CREDITS_SCENE):
			_cancel_leave()


func _on_quit() -> void:
	if _begin_leave(QUIT_TIME, false):
		await get_tree().create_timer(QUIT_TIME, true, false, true).timeout
		get_tree().quit()


## Bloquea la entrada (sin dobles pulsaciones) y lanza la animación de salida: la interfaz se
## desliza a la izquierda, la isla se aleja y la pantalla se funde a negro. Devuelve false si ya se
## estaba saliendo.
func _begin_leave(time: float, island_recedes: bool) -> bool:
	if _leaving:
		return false
	_leaving = true
	_set_buttons_disabled(true)
	for button in _buttons():
		_kill(button)
	if _intro and _intro.is_valid():
		_intro.kill()
	var out := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	out.tween_property(_fade, ^"color:a", 1.0, time)
	out.tween_property(_panel, ^"position:x", _panel.position.x - 24.0, time)
	out.tween_property(_title, ^"modulate:a", 0.0, time)
	if island_recedes:
		out.tween_property(_island, ^"distance_scale", 1.6, time)
	return true


func _cancel_leave() -> void:
	_leaving = false
	_set_buttons_disabled(false)
	_fade.color.a = 0.0
	_title.modulate.a = 1.0
	_panel.position.x = 36.0
	_island.distance_scale = 1.0
	_start.grab_focus()


func _set_buttons_disabled(on: bool) -> void:
	for button in _buttons():
		button.disabled = on
