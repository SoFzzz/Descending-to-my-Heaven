class_name OptionsMenu
extends Control
## Menú de opciones (overlay reutilizable): lo abren el menú principal y el de pausa y avisan con
## `closed` al volver. Tres pestañas: Controles (reasignar teclado/ratón y mando, sensibilidad de
## cámara, restaurar), Volumen (Master / Music / SFX / UI en vivo) e Idioma (español / inglés).
## Todo se guarda con el autoload UserSettings. Se navega con flechas / D-pad / stick, Enter / A para
## elegir, Esc / B para volver y LB / RB para cambiar de pestaña.
## Al reasignar: se elige una fila, se pulsa Enter / A / clic, y se pulsa la nueva tecla o botón.

signal closed

const TAB_CONTROLS := 0
const TAB_VOLUME := 1
const TAB_LANGUAGE := 2
const TAB_KEYS: Array[String] = ["OPT_TAB_CONTROLS", "OPT_TAB_VOLUME", "OPT_TAB_LANGUAGE"]
const ACTION_KEYS := {
	&"move_forward": "ACT_MOVE_FORWARD", &"move_back": "ACT_MOVE_BACK",
	&"move_left": "ACT_MOVE_LEFT", &"move_right": "ACT_MOVE_RIGHT",
	&"attack": "ACT_ATTACK", &"roll": "ACT_ROLL", &"lock_on": "ACT_LOCK_ON", &"pause": "ACT_PAUSE",
}
const BUS_KEYS := {&"Master": "VOL_MASTER", &"Music": "VOL_MUSIC", &"SFX": "VOL_SFX", &"UI": "VOL_UI"}
const COL_ACTION := 150.0
const COL_KB := 150.0
const COL_PAD := 118.0
const SAVE_DELAY := 0.4
const SLIDER_SOUND_GAP_MS := 90

var _tab := TAB_CONTROLS
var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _restore: Button
var _back: Button
var _status: Label
var _scroll: ScrollContainer
var _rows: Dictionary = {}          # Array [action, slot] -> Button / Label
var _sliders: Dictionary = {}       # bus -> HSlider
var _volume_labels: Dictionary = {}  # bus -> Label
var _sens_slider: HSlider
var _sens_label: Label
var _lang_buttons: Dictionary = {}  # locale -> Button
var _capture_action: StringName = &""
var _capture_slot: StringName = &""
var _capture_button: Button
var _save_timer: Timer
var _last_slider_sound := 0
var _status_key := "OPT_CONTROLS_HINT"
var _status_arg: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_save_timer.timeout.connect(_save_now)
	add_child(_save_timer)
	_refresh_all()


func _settings() -> GameSettings:
	return get_node_or_null(^"/root/UserSettings") as GameSettings


func _audio() -> Node:
	return get_node_or_null(^"/root/AudioManager")


func is_open() -> bool:
	return visible


func is_capturing() -> bool:
	return _capture_action != &""


## Muestra el menú en la pestaña de controles con el foco en ella (sin sonido de "mover").
func open() -> void:
	visible = true
	_select_tab(TAB_CONTROLS)
	_set_status("OPT_CONTROLS_HINT")
	_focus(_tab_buttons[TAB_CONTROLS])


func close() -> void:
	if not visible:
		return
	_cancel_capture()
	_save_now()
	visible = false
	closed.emit()


# --- Construcción -------------------------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.06, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(508.0, 330.0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 5)
	panel.add_child(box)

	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "OPT_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override(&"separation", 4)
	box.add_child(tabs)
	var group := ButtonGroup.new()
	for i in TAB_KEYS.size():
		var tab := Button.new()
		tab.theme_type_variation = &"TabButton"
		tab.text = TAB_KEYS[i]
		tab.toggle_mode = true
		tab.button_group = group
		tab.set_meta(&"ui_sound", &"none")
		tab.pressed.connect(_select_tab.bind(i))
		tab.focus_entered.connect(_select_tab.bind(i))
		tabs.add_child(tab)
		_tab_buttons.append(tab)

	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.custom_minimum_size = Vector2(0.0, 196.0)
	box.add_child(stack)
	_pages = [_build_controls_page(), _build_volume_page(), _build_language_page()]
	for page in _pages:
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.add_child(page)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override(&"font_size", 11)
	_status.add_theme_color_override(&"font_color", Color(0.85, 0.8, 1.0))
	_status.custom_minimum_size = Vector2(0.0, 14.0)
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	box.add_child(_status)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override(&"separation", 16)
	box.add_child(bottom)
	_restore = Button.new()
	_restore.text = "OPT_RESTORE"
	_restore.pressed.connect(_on_restore)
	bottom.add_child(_restore)
	_back = Button.new()
	_back.text = "OPT_BACK"
	_back.set_meta(&"ui_sound", &"back")
	_back.pressed.connect(close)
	bottom.add_child(_back)


func _build_controls_page() -> Control:
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	var list := VBoxContainer.new()
	list.add_theme_constant_override(&"separation", 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(list)
	list.add_child(_row(_header_label("OPT_COL_ACTION", COL_ACTION), _header_label("OPT_COL_KEYBOARD", COL_KB), _header_label("OPT_COL_GAMEPAD", COL_PAD)))
	for action in GameSettings.REMAP_ACTIONS:
		var name_label := _header_label(ACTION_KEYS[action], COL_ACTION)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var kb := _cell_button(action, GameSettings.SLOT_KB)
		var pad: Control
		if GameSettings.is_remappable(action, GameSettings.SLOT_PAD):
			pad = _cell_button(action, GameSettings.SLOT_PAD)
		else:
			var fixed := Label.new()
			fixed.custom_minimum_size = Vector2(COL_PAD, 0.0)
			fixed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			fixed.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			fixed.add_theme_font_size_override(&"font_size", 13)
			fixed.add_theme_color_override(&"font_color", Color(0.85, 0.8, 1.0))
			pad = fixed
			_rows[[action, GameSettings.SLOT_PAD]] = fixed
		list.add_child(_row(name_label, kb, pad))
	var sens_name := _header_label("OPT_SENSITIVITY", COL_ACTION)
	sens_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_sens_slider = HSlider.new()
	_sens_slider.min_value = GameSettings.SENSITIVITY_MIN
	_sens_slider.max_value = GameSettings.SENSITIVITY_MAX
	_sens_slider.step = 0.05
	_sens_slider.custom_minimum_size = Vector2(COL_KB, 18.0)
	_sens_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sens_slider.value_changed.connect(_on_sensitivity_changed)
	_sens_label = _header_label("", COL_PAD)
	_sens_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	list.add_child(_row(sens_name, _sens_slider, _sens_label))
	var note := Label.new()
	note.text = "OPT_FIXED_NOTE"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(COL_ACTION + COL_KB + COL_PAD, 0.0)
	note.add_theme_font_size_override(&"font_size", 11)
	note.add_theme_color_override(&"font_color", Color(0.8, 0.76, 0.92))
	list.add_child(note)
	return _scroll


func _build_volume_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override(&"separation", 14)
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	for bus in GameSettings.BUSES:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override(&"separation", 10)
		var name_label := _header_label(BUS_KEYS[bus], 120.0)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.custom_minimum_size = Vector2(220.0, 18.0)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(_on_volume_changed.bind(bus))
		row.add_child(slider)
		var value := _header_label("", 44.0)
		value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		row.add_child(value)
		_sliders[bus] = slider
		_volume_labels[bus] = value
		page.add_child(row)
	return page


func _build_language_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override(&"separation", 10)
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	var pick := _header_label("OPT_LANGUAGE_PICK", 400.0)
	pick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(pick)
	var group := ButtonGroup.new()
	for loc in GameSettings.LOCALES:
		var holder := CenterContainer.new()
		var button := Button.new()
		button.theme_type_variation = &"TabButton"
		button.text = "LANG_" + loc.to_upper()
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(180.0, 28.0)
		button.pressed.connect(_on_language_picked.bind(loc))
		holder.add_child(button)
		page.add_child(holder)
		_lang_buttons[loc] = button
	return page


func _header_label(key: String, width: float) -> Label:
	var label := Label.new()
	label.text = key
	label.custom_minimum_size = Vector2(width, 0.0)
	label.add_theme_font_size_override(&"font_size", 13)
	return label


func _cell_button(action: StringName, slot: StringName) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"CellButton"
	button.custom_minimum_size = Vector2(COL_KB if slot == GameSettings.SLOT_KB else COL_PAD, 19.0)
	button.add_theme_font_override(&"font", ThemeDB.fallback_font)   # nombres de teclas legibles
	button.add_theme_constant_override(&"outline_size", 3)
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.pressed.connect(_begin_capture.bind(action, slot, button))
	_rows[[action, slot]] = button
	return button


func _row(a: Control, b: Control, c: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	row.add_child(a)
	row.add_child(b)
	row.add_child(c)
	return row


# --- Estado -------------------------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_all()


func _refresh_all() -> void:
	var settings := _settings()
	if settings == null:
		return
	for key: Array in _rows:
		var control: Control = _rows[key]
		var text := settings.slot_text(key[0], key[1])
		if control is Button:
			(control as Button).text = text
		else:
			(control as Label).text = text
	for bus in GameSettings.BUSES:
		var slider: HSlider = _sliders[bus]
		slider.set_value_no_signal(settings.get_volume(bus))
		(_volume_labels[bus] as Label).text = "%d%%" % roundi(settings.get_volume(bus) * 100.0)
	_sens_slider.set_value_no_signal(settings.look_sensitivity)
	_sens_label.text = "%.2fx" % settings.look_sensitivity
	for loc: String in _lang_buttons:
		(_lang_buttons[loc] as Button).set_pressed_no_signal(loc == settings.locale)
	_show_status()


func _set_status(key: String, arg := "") -> void:
	_status_key = key
	_status_arg = arg
	_show_status()


func _show_status() -> void:
	if _status == null:
		return
	var text := TranslationServer.translate(StringName(_status_key))
	_status.text = text % _status_arg if "%s" in text else text


func _select_tab(index: int) -> void:
	_tab = index
	for i in _pages.size():
		_pages[i].visible = i == index
		_tab_buttons[i].set_pressed_no_signal(i == index)
	_restore.visible = index == TAB_CONTROLS
	if index == TAB_CONTROLS and not is_capturing():
		_set_status("OPT_CONTROLS_HINT")
	elif index != TAB_CONTROLS:
		_status.text = ""
		_status_key = "OPT_CONTROLS_HINT"


func _focus(control: Control) -> void:
	var audio := _audio()
	if audio and control is BaseButton:
		audio.grab_focus_silent(control)
	else:
		control.grab_focus()


# --- Reasignación -------------------------------------------------------------------------------

func _begin_capture(action: StringName, slot: StringName, button: Button) -> void:
	if is_capturing():
		return
	_capture_action = action
	_capture_slot = slot
	_capture_button = button
	button.text = "..."
	_set_status("OPT_PRESS_PAD" if slot == GameSettings.SLOT_PAD else "OPT_PRESS_ANY")


func _cancel_capture() -> void:
	if not is_capturing():
		return
	_capture_action = &""
	_capture_slot = &""
	_capture_button = null
	_refresh_all()
	_set_status("OPT_CONTROLS_HINT")


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if is_capturing():
		_capture_input(event)
		return
	if event is InputEventJoypadButton and event.pressed and not event.is_echo():
		var step := 0
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			step = -1
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			step = 1
		if step != 0:
			var next := clampi(_tab + step, 0, TAB_KEYS.size() - 1)
			if next != _tab:
				_select_tab(next)
				_tab_buttons[next].grab_focus()
				get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if visible and not is_capturing() and event.is_action_pressed(&"ui_cancel"):
		var audio := _audio()
		if audio:
			audio.play_ui(audio.UI_BACK)
		close()
		get_viewport().set_input_as_handled()


func _capture_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.is_echo() and \
			(event as InputEventKey).physical_keycode == KEY_ESCAPE:
		_cancel_capture()
		return
	if event is InputEventJoypadButton and event.pressed and \
			(event as InputEventJoypadButton).button_index == JOY_BUTTON_BACK:
		_cancel_capture()
		return
	var captured := GameSettings.capture(event)
	if captured == null or GameSettings.slot_of(captured) != _capture_slot:
		return
	apply_capture(captured)


## Asigna `event` a la acción en captura (separado de _input para poder probarlo).
func apply_capture(event: InputEvent) -> void:
	var settings := _settings()
	if settings == null or not is_capturing():
		return
	var action := _capture_action
	var slot := _capture_slot
	_capture_action = &""
	_capture_slot = &""
	_capture_button = null
	var swapped := settings.rebind(action, slot, event)
	_refresh_all()
	if swapped != &"" and swapped != &"!":
		_set_status("OPT_SWAPPED", tr(ACTION_KEYS[swapped]))
	else:
		_set_status("OPT_ASSIGNED", GameSettings.event_name(event))


func _on_restore() -> void:
	var settings := _settings()
	if settings == null:
		return
	settings.restore_default_bindings()
	settings.set_look_sensitivity(1.0)
	_refresh_all()
	_set_status("OPT_RESTORED")


# --- Volumen, cámara e idioma -------------------------------------------------------------------

func _on_volume_changed(value: float, bus: StringName) -> void:
	var settings := _settings()
	if settings == null:
		return
	settings.set_volume(bus, value, false)
	(_volume_labels[bus] as Label).text = "%d%%" % roundi(value * 100.0)
	_schedule_save()
	_slider_feedback()


func _on_sensitivity_changed(value: float) -> void:
	var settings := _settings()
	if settings == null:
		return
	settings.set_look_sensitivity(value, false)
	_sens_label.text = "%.2fx" % value
	_schedule_save()


func _on_language_picked(loc: String) -> void:
	var settings := _settings()
	if settings:
		settings.set_locale(loc)
	_refresh_all()


func _slider_feedback() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_slider_sound < SLIDER_SOUND_GAP_MS:
		return
	_last_slider_sound = now
	var audio := _audio()
	if audio:
		audio.play_ui(audio.UI_MOVE)


func _schedule_save() -> void:
	if _save_timer and is_inside_tree():
		_save_timer.start()


func _save_now() -> void:
	var settings := _settings()
	if settings:
		settings.save_settings()
