class_name GameSettings
extends Node
## Autoload "UserSettings": ajustes del jugador guardados en user://settings.cfg (ConfigFile).
##
## - Volumen por bus (Master / Music / SFX / UI) en lineal 0..1, aplicado en vivo a AudioServer.
## - Idioma ("es" / "en") con TranslationServer (traducciones en res://localization/translations.csv).
## - Sensibilidad de la cámara (ratón y stick derecho).
## - Controles: cada acción reasignable tiene dos "ranuras": teclado/ratón (SLOT_KB) y mando
##   (SLOT_PAD, botones y gatillos). Los ejes de los sticks (mover y cámara) son fijos.
## Se carga y aplica en _ready; cada cambio llama a save_settings().
## La lógica de eventos es estática o de instancia sin depender del árbol, para probarla sin escena.

signal locale_changed(locale: String)
signal volume_changed(bus: StringName, linear: float)
signal bindings_changed

const SAVE_PATH := "user://settings.cfg"
const DEFAULT_LOCALE := "es"
const LOCALES: Array[String] = ["es", "en"]
const BUSES: Array[StringName] = [&"Master", &"Music", &"SFX", &"UI"]
const MIN_DB := -60.0
const SENSITIVITY_MIN := 0.4
const SENSITIVITY_MAX := 2.0

const SLOT_KB := &"kb"
const SLOT_PAD := &"pad"

## Acciones que el jugador puede reasignar, en el orden en que salen en la pantalla de controles.
const REMAP_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right",
	&"attack", &"roll", &"heal", &"lock_on", &"pause",
]
## Acciones cuyo mando va en los ejes de los sticks (no se reasignan, solo se muestran).
const PAD_FIXED: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right"]
## Ejes de los gatillos (LT = 4, RT = 5): se aceptan como "botón" de mando.
const TRIGGER_AXES: Array[int] = [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]
const TRIGGER_THRESHOLD := 0.6

const PAD_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-Pad ↑", JOY_BUTTON_DPAD_DOWN: "D-Pad ↓",
	JOY_BUTTON_DPAD_LEFT: "D-Pad ←", JOY_BUTTON_DPAD_RIGHT: "D-Pad →",
}

var save_path := SAVE_PATH
var locale := DEFAULT_LOCALE
var look_sensitivity := 1.0
var volumes: Dictionary = {}   # StringName -> float lineal 0..1


func _init() -> void:
	reset_audio_defaults()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_menu_nav_keys()
	load_settings()


# --- Lógica pura de eventos ---------------------------------------------------------------------

static func slot_of(event: InputEvent) -> StringName:
	if event is InputEventKey or event is InputEventMouseButton:
		return SLOT_KB
	if event is InputEventJoypadButton:
		return SLOT_PAD
	if event is InputEventJoypadMotion and (event as InputEventJoypadMotion).axis in TRIGGER_AXES:
		return SLOT_PAD
	return &""


## true si el evento es una entrada de mando (cualquier botón o eje).
static func is_pad_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


static func is_remappable(action: StringName, slot: StringName) -> bool:
	if not REMAP_ACTIONS.has(action):
		return false
	return not (slot == SLOT_PAD and PAD_FIXED.has(action))


## Los dos eventos hacen lo mismo (misma tecla física, botón de ratón, botón de mando o gatillo).
static func same_binding(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return _key_code(a) == _key_code(b)
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		var ma := a as InputEventJoypadMotion
		var mb := b as InputEventJoypadMotion
		return ma.axis == mb.axis and signf(ma.axis_value) == signf(mb.axis_value)
	return false


static func _key_code(event: InputEvent) -> int:
	var key := event as InputEventKey
	return key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode


## Convierte una pulsación real en un evento "limpio" para guardarlo en el InputMap; null si no sirve
## (soltar, eco, movimiento del ratón, un stick, un gatillo a medias...).
static func capture(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return null
		var clean := InputEventKey.new()
		clean.physical_keycode = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return clean
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if not mouse.pressed or mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
				MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return null
		var clean_mouse := InputEventMouseButton.new()
		clean_mouse.button_index = mouse.button_index
		return clean_mouse
	if event is InputEventJoypadButton:
		var pad := event as InputEventJoypadButton
		if not pad.pressed:
			return null
		var clean_pad := InputEventJoypadButton.new()
		clean_pad.button_index = pad.button_index
		return clean_pad
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if motion.axis in TRIGGER_AXES and motion.axis_value >= TRIGGER_THRESHOLD:
			var clean_motion := InputEventJoypadMotion.new()
			clean_motion.axis = motion.axis
			clean_motion.axis_value = 1.0
			return clean_motion
	return null


static func serialize_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {"t": "key", "c": _key_code(event)}
	if event is InputEventMouseButton:
		return {"t": "mouse", "b": (event as InputEventMouseButton).button_index}
	if event is InputEventJoypadButton:
		return {"t": "pad", "b": (event as InputEventJoypadButton).button_index}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return {"t": "axis", "a": motion.axis, "v": motion.axis_value}
	return {}


static func deserialize_event(data: Variant) -> InputEvent:
	if not data is Dictionary:
		return null
	var d: Dictionary = data
	match str(d.get("t", "")):
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = int(d.get("c", 0)) as Key
			return key if key.physical_keycode != KEY_NONE else null
		"mouse":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(d.get("b", 0)) as MouseButton
			return mouse if mouse.button_index != 0 else null
		"pad":
			var pad := InputEventJoypadButton.new()
			pad.button_index = int(d.get("b", -1)) as JoyButton
			return pad if int(pad.button_index) >= 0 else null
		"axis":
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(d.get("a", 0)) as JoyAxis
			motion.axis_value = float(d.get("v", 1.0))
			return motion if motion.axis in TRIGGER_AXES else null
	return null


## Nombre corto de un evento para mostrar al jugador ("W", "Clic izq.", "RB"...). El idioma sale de
## TranslationServer; los botones del mando siempre usan los nombres de Xbox.
static func event_name(event: InputEvent) -> String:
	if event is InputEventKey:
		var code := _key_code(event)
		match code:
			KEY_SPACE: return TranslationServer.translate(&"KEY_SPACE")
			KEY_ESCAPE: return TranslationServer.translate(&"KEY_ESCAPE")
			KEY_ENTER, KEY_KP_ENTER: return TranslationServer.translate(&"KEY_ENTER")
			KEY_SHIFT: return "Shift"
			KEY_TAB: return "Tab"
		return OS.get_keycode_string(code as Key).capitalize() if code != KEY_NONE else "?"
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return TranslationServer.translate(&"MOUSE_LEFT")
			MOUSE_BUTTON_RIGHT: return TranslationServer.translate(&"MOUSE_RIGHT")
			MOUSE_BUTTON_MIDDLE: return TranslationServer.translate(&"MOUSE_MIDDLE")
		return TranslationServer.translate(&"MOUSE_OTHER") % (event as InputEventMouseButton).button_index
	if event is InputEventJoypadButton:
		var button := int((event as InputEventJoypadButton).button_index)
		return PAD_BUTTON_NAMES.get(button, "Btn %d" % button)
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		match motion.axis:
			JOY_AXIS_TRIGGER_LEFT: return "LT"
			JOY_AXIS_TRIGGER_RIGHT: return "RT"
			JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y: return "LS"
			JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y: return "RS"
	return "?"


## dB de un volumen lineal 0..1 (0 = silencio).
static func linear_to_bus_db(linear: float) -> float:
	if linear <= 0.001:
		return -80.0
	return maxf(linear_to_db(clampf(linear, 0.0, 1.0)), -80.0)


# --- Controles ----------------------------------------------------------------------------------

## Eventos de `action` que pertenecen a la ranura (teclado/ratón o mando). Los ejes de los sticks no cuentan.
func slot_events(action: StringName, slot: StringName) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if not InputMap.has_action(action):
		return out
	for event in InputMap.action_get_events(action):
		if slot_of(event) == slot:
			out.append(event)
	return out


## Texto con todo lo asignado a la ranura ("X / RB"); para los sticks fijos, el nombre del stick.
func slot_text(action: StringName, slot: StringName) -> String:
	if slot == SLOT_PAD and PAD_FIXED.has(action):
		return "LS"
	var names: Array[String] = []
	for event in slot_events(action, slot):
		names.append(event_name(event))
	return " / ".join(names) if not names.is_empty() else "—"


## Reasigna: la ranura de `action` pasa a tener solo `event`. Si otra acción reasignable ya usaba esa
## entrada en la misma ranura, intercambian (esa recibe lo que tenía `action`). Devuelve la acción
## intercambiada (o &"" si no hubo) o &"!" si no se pudo reasignar.
func rebind(action: StringName, slot: StringName, event: InputEvent) -> StringName:
	if event == null or not is_remappable(action, slot) or slot_of(event) != slot:
		return &"!"
	var previous := slot_events(action, slot)
	var swapped: StringName = &""
	for other in REMAP_ACTIONS:
		if other == action or not is_remappable(other, slot):
			continue
		for other_event in slot_events(other, slot):
			if same_binding(other_event, event):
				_replace_slot(other, slot, previous)
				swapped = other
				break
	_replace_slot(action, slot, [event])
	bindings_changed.emit()
	save_settings()
	return swapped


func _replace_slot(action: StringName, slot: StringName, events: Array) -> void:
	for old in slot_events(action, slot):
		InputMap.action_erase_event(action, old)
	for event: InputEvent in events:
		InputMap.action_add_event(action, event.duplicate())


## W/A/S/D también mueven el foco de los menús (además de flechas y D-Pad), como en el juego.
func add_menu_nav_keys() -> void:
	var pairs := {&"ui_up": KEY_W, &"ui_down": KEY_S, &"ui_left": KEY_A, &"ui_right": KEY_D}
	for action: StringName in pairs:
		if not InputMap.has_action(action):
			continue
		var event := InputEventKey.new()
		event.physical_keycode = pairs[action] as Key
		var present := false
		for existing in InputMap.action_get_events(action):
			if existing is InputEventKey and (existing as InputEventKey).physical_keycode == event.physical_keycode:
				present = true
		if not present:
			InputMap.action_add_event(action, event)


## Vuelve a los controles del proyecto (project.godot) y lo guarda.
func restore_default_bindings() -> void:
	InputMap.load_from_project_settings()
	add_menu_nav_keys()
	bindings_changed.emit()
	save_settings()


# --- Volumen ------------------------------------------------------------------------------------

func reset_audio_defaults() -> void:
	for bus in BUSES:
		volumes[bus] = 1.0


func get_volume(bus: StringName) -> float:
	return float(volumes.get(bus, 1.0))


func volume_db(bus: StringName) -> float:
	return linear_to_bus_db(get_volume(bus))


## Fija y aplica el volumen de un bus (lineal 0..1). Con `persist` también guarda.
func set_volume(bus: StringName, linear: float, persist := true) -> void:
	volumes[bus] = clampf(linear, 0.0, 1.0)
	_apply_bus(bus)
	volume_changed.emit(bus, get_volume(bus))
	if persist:
		save_settings()


## La música la ajusta también el AudioManager (baja durante la pausa): él suma su descuento a este valor.
func _apply_bus(bus: StringName) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, volume_db(bus))


func apply_volumes() -> void:
	for bus in BUSES:
		_apply_bus(bus)


# --- Idioma y cámara ----------------------------------------------------------------------------

func set_locale(new_locale: String, persist := true) -> void:
	if not LOCALES.has(new_locale):
		new_locale = DEFAULT_LOCALE
	locale = new_locale
	TranslationServer.set_locale(locale)
	locale_changed.emit(locale)
	if persist:
		save_settings()


func set_look_sensitivity(value: float, persist := true) -> void:
	look_sensitivity = clampf(value, SENSITIVITY_MIN, SENSITIVITY_MAX)
	if persist:
		save_settings()


# --- Guardar / cargar ---------------------------------------------------------------------------

func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("general", "locale", locale)
	cfg.set_value("general", "look_sensitivity", look_sensitivity)
	for bus in BUSES:
		cfg.set_value("audio", String(bus), get_volume(bus))
	for action in REMAP_ACTIONS:
		for slot in [SLOT_KB, SLOT_PAD]:
			if not is_remappable(action, slot):
				continue
			var list: Array = []
			for event in slot_events(action, slot):
				list.append(serialize_event(event))
			cfg.set_value("input", "%s.%s" % [action, slot], list)
	return cfg.save(save_path) == OK


## Lee el archivo (si existe), aplica idioma, volúmenes y controles. Sin archivo deja los valores del proyecto.
func load_settings() -> bool:
	var cfg := ConfigFile.new()
	var loaded := cfg.load(save_path) == OK
	if loaded:
		look_sensitivity = clampf(float(cfg.get_value("general", "look_sensitivity", 1.0)), SENSITIVITY_MIN, SENSITIVITY_MAX)
		for bus in BUSES:
			volumes[bus] = clampf(float(cfg.get_value("audio", String(bus), 1.0)), 0.0, 1.0)
		for action in REMAP_ACTIONS:
			for slot in [SLOT_KB, SLOT_PAD]:
				var key := "%s.%s" % [action, slot]
				if not is_remappable(action, slot) or not cfg.has_section_key("input", key):
					continue
				var events: Array = []
				for data in cfg.get_value("input", key, []):
					var event := deserialize_event(data)
					if event != null and slot_of(event) == slot:
						events.append(event)
				if not events.is_empty():
					_replace_slot(action, slot, events)
		locale = str(cfg.get_value("general", "locale", DEFAULT_LOCALE))
	set_locale(locale if LOCALES.has(locale) else DEFAULT_LOCALE, false)
	apply_volumes()
	bindings_changed.emit()
	return loaded
