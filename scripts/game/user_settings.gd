class_name GameSettings
extends Node
## Autoload "UserSettings": player settings stored in user://settings.cfg (ConfigFile).
##
## - Volume per bus (Master / Music / SFX / UI) as linear 0..1, applied live to AudioServer.
## - Language ("es" / "en") through TranslationServer (translations in res://localization/translations.csv).
## - Camera sensitivity (mouse and right stick).
## - Controls: each remappable action has two "slots": keyboard/mouse (SLOT_KB) and gamepad
##   (SLOT_PAD, buttons and triggers). The stick axes (move and camera) are fixed.
## - Display: window mode, windowed size (multiples of 640x360), VSync and FPS cap; Alt+Enter toggles fullscreen.
## Loaded and applied in _ready; every change calls save_settings().
## The event logic is static, or instance-level without depending on the tree, so it can be tested
## without a scene.

signal locale_changed(locale: String)
signal volume_changed(bus: StringName, linear: float)
signal bindings_changed
signal display_changed

const SAVE_PATH := "user://settings.cfg"
const DEFAULT_LOCALE := "es"
const LOCALES: Array[String] = ["es", "en"]
const BUSES: Array[StringName] = [&"Master", &"Music", &"SFX", &"UI"]
const MIN_DB := -60.0
const SENSITIVITY_MIN := 0.4
const SENSITIVITY_MAX := 2.0

## Window modes. FULLSCREEN is a borderless window covering the monitor (fast alt-tab, keeps the
## desktop resolution); EXCLUSIVE takes over the display (true exclusive fullscreen on Windows).
const MODE_WINDOWED := 0
const MODE_FULLSCREEN := 1
const MODE_EXCLUSIVE := 2
const WINDOW_MODES: Array[int] = [MODE_WINDOWED, MODE_FULLSCREEN, MODE_EXCLUSIVE]
const BASE_SIZE := Vector2i(640, 360)
## Windowed sizes are whole multiples of the 640x360 base resolution (pixel-perfect stretch).
const WINDOW_SCALES: Array[int] = [1, 2, 3, 4]
const DEFAULT_SCALE := 2
const FPS_LIMITS: Array[int] = [0, 30, 60, 120]   # 0 = unlimited
const TITLE_BAR_MARGIN := 48   # room kept for the title bar and the taskbar when checking fit

const SLOT_KB := &"kb"
const SLOT_PAD := &"pad"

## Actions the player can remap, in the order they appear on the controls screen.
const REMAP_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right",
	&"attack", &"roll", &"heal", &"lock_on", &"pause",
]
## Actions whose gamepad input is on the stick axes (not remappable, only displayed).
const PAD_FIXED: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right"]
## Trigger axes (LT = 4, RT = 5): accepted as a gamepad "button".
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
var volumes: Dictionary = {}   # StringName -> linear float 0..1
var window_mode := MODE_WINDOWED
var window_scale := DEFAULT_SCALE
var vsync := true
var fps_limit := 0


func _init() -> void:
	reset_audio_defaults()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_menu_nav_keys()
	load_settings()


## Alt+Enter toggles between windowed and fullscreen from anywhere (menus, pause, game).
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo() and event.alt_pressed and 			(event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


# --- Pure event logic ---------------------------------------------------------------------------

static func slot_of(event: InputEvent) -> StringName:
	if event is InputEventKey or event is InputEventMouseButton:
		return SLOT_KB
	if event is InputEventJoypadButton:
		return SLOT_PAD
	if event is InputEventJoypadMotion and (event as InputEventJoypadMotion).axis in TRIGGER_AXES:
		return SLOT_PAD
	return &""


## true if the event is a gamepad input (any button or axis).
static func is_pad_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


static func is_remappable(action: StringName, slot: StringName) -> bool:
	if not REMAP_ACTIONS.has(action):
		return false
	return not (slot == SLOT_PAD and PAD_FIXED.has(action))


## Both events are the same input (same physical key, mouse button, gamepad button or trigger).
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


## Turns a real press into a "clean" event to store in the InputMap; null if unusable
## (release, echo, mouse motion, a stick, a half-pressed trigger...).
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
			key.physical_keycode = int(_number(d.get("c"), 0.0)) as Key
			return key if key.physical_keycode != KEY_NONE else null
		"mouse":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(_number(d.get("b"), 0.0)) as MouseButton
			return mouse if mouse.button_index != 0 else null
		"pad":
			var pad := InputEventJoypadButton.new()
			pad.button_index = int(_number(d.get("b"), -1.0)) as JoyButton
			return pad if int(pad.button_index) >= 0 else null
		"axis":
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(_number(d.get("a"), 0.0)) as JoyAxis
			motion.axis_value = _number(d.get("v"), 1.0)
			return motion if motion.axis in TRIGGER_AXES else null
	return null


## Short name of an event to show the player ("W", "Left click", "RB"...). The language comes from
## TranslationServer; gamepad buttons always use the Xbox names.
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


## dB of a linear volume 0..1 (0 = silence).
static func linear_to_bus_db(linear: float) -> float:
	if linear <= 0.001:
		return -80.0
	return maxf(linear_to_db(clampf(linear, 0.0, 1.0)), -80.0)


# --- Controls -----------------------------------------------------------------------------------

## Events of `action` that belong to the slot (keyboard/mouse or gamepad). Stick axes do not count.
func slot_events(action: StringName, slot: StringName) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if not InputMap.has_action(action):
		return out
	for event in InputMap.action_get_events(action):
		if slot_of(event) == slot:
			out.append(event)
	return out


## Text with everything assigned to the slot ("X / RB"); for the fixed sticks, the stick name.
func slot_text(action: StringName, slot: StringName) -> String:
	if slot == SLOT_PAD and PAD_FIXED.has(action):
		return "LS"
	var names: Array[String] = []
	for event in slot_events(action, slot):
		names.append(event_name(event))
	return " / ".join(names) if not names.is_empty() else "—"


## Rebinds: the slot of `action` ends up with only `event`. If another remappable action already used
## that input in the same slot, they swap (that one receives what `action` had). Returns the swapped
## action (or &"" if none) or &"!" if the rebind was not possible.
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


## W/A/S/D also move the menu focus (besides arrows and D-Pad), as in the game.
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


## Restores the project controls (project.godot) and saves them.
func restore_default_bindings() -> void:
	InputMap.load_from_project_settings()
	add_menu_nav_keys()
	bindings_changed.emit()
	save_settings()


# --- Volume -------------------------------------------------------------------------------------

func reset_audio_defaults() -> void:
	for bus in BUSES:
		volumes[bus] = 1.0


func get_volume(bus: StringName) -> float:
	return float(volumes.get(bus, 1.0))


func volume_db(bus: StringName) -> float:
	return linear_to_bus_db(get_volume(bus))


## Sets and applies a bus volume (linear 0..1). With `persist` it also saves.
func set_volume(bus: StringName, linear: float, persist := true) -> void:
	volumes[bus] = clampf(_number(linear, 1.0), 0.0, 1.0)
	_apply_bus(bus)
	volume_changed.emit(bus, get_volume(bus))
	if persist:
		save_settings()


## The music bus is also driven by AudioManager (it drops while paused and ducks during the ending), so
## it adds its offsets on top of this value; its refresh is used when it exists.
func _apply_bus(bus: StringName) -> void:
	if bus == &"Music":
		var audio := get_node_or_null(^"/root/AudioManager") if is_inside_tree() else null
		if audio:
			audio.call(&"refresh_music_bus")
			return
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, volume_db(bus))


func apply_volumes() -> void:
	for bus in BUSES:
		_apply_bus(bus)


# --- Language and camera ------------------------------------------------------------------------

func set_locale(new_locale: String, persist := true) -> void:
	if not LOCALES.has(new_locale):
		new_locale = DEFAULT_LOCALE
	locale = new_locale
	TranslationServer.set_locale(locale)
	locale_changed.emit(locale)
	if persist:
		save_settings()


func set_look_sensitivity(value: float, persist := true) -> void:
	look_sensitivity = clampf(_number(value, 1.0), SENSITIVITY_MIN, SENSITIVITY_MAX)
	if persist:
		save_settings()


# --- Display ------------------------------------------------------------------------------------

static func sanitize_mode(value: Variant) -> int:
	if value is int and WINDOW_MODES.has(value):
		return value
	return MODE_WINDOWED


static func sanitize_scale(value: Variant) -> int:
	if value is int and WINDOW_SCALES.has(value):
		return value
	return DEFAULT_SCALE


static func sanitize_fps(value: Variant) -> int:
	if value is int and FPS_LIMITS.has(value):
		return value
	return 0


static func sanitize_vsync(value: Variant) -> bool:
	return value if value is bool else true


static func scale_size(scale: int) -> Vector2i:
	return BASE_SIZE * scale


## Scales whose window fits in a usable screen area of `usable` pixels (the 1x window always counts).
static func scales_that_fit(usable: Vector2i) -> Array[int]:
	var out: Array[int] = []
	for scale in WINDOW_SCALES:
		var size := scale_size(scale)
		if scale == WINDOW_SCALES[0] or (size.x <= usable.x and size.y + TITLE_BAR_MARGIN <= usable.y):
			out.append(scale)
	return out


## Scales offered on the monitor the window is on.
func available_scales() -> Array[int]:
	if DisplayServer.get_name() == "headless":
		return WINDOW_SCALES.duplicate()
	var screen := DisplayServer.window_get_current_screen()
	return scales_that_fit(DisplayServer.screen_get_usable_rect(screen).size)


func set_window_mode(mode: int, persist := true) -> void:
	window_mode = sanitize_mode(mode)
	_finish_display_change(persist)


func set_window_scale(scale: int, persist := true) -> void:
	window_scale = sanitize_scale(scale)
	_finish_display_change(persist)


func set_vsync(enabled: bool, persist := true) -> void:
	vsync = enabled
	_finish_display_change(persist)


func set_fps_limit(limit: int, persist := true) -> void:
	fps_limit = sanitize_fps(limit)
	_finish_display_change(persist)


func toggle_fullscreen() -> void:
	set_window_mode(MODE_WINDOWED if window_mode != MODE_WINDOWED else MODE_FULLSCREEN)


func _finish_display_change(persist: bool) -> void:
	apply_display()
	display_changed.emit()
	if persist:
		save_settings()


## Pushes mode, size, vsync and the FPS cap to the engine. Does nothing outside the tree (tests build
## loose instances) and the window calls are skipped without a real window (headless).
func apply_display() -> void:
	if not is_inside_tree():
		return
	Engine.max_fps = fps_limit
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	match window_mode:
		MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		MODE_EXCLUSIVE:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			_apply_window_size()
			_apply_window_size.call_deferred()   # the mode switch finishes a frame later


func _apply_window_size() -> void:
	if window_mode != MODE_WINDOWED:
		return
	var scales := available_scales()
	var scale := window_scale
	while scale > 1 and not scales.has(scale):
		scale -= 1
	var size := scale_size(scale)
	var screen := DisplayServer.window_get_current_screen()
	var area := DisplayServer.screen_get_usable_rect(screen)
	DisplayServer.window_set_size(size)
	var decorated := DisplayServer.window_get_size_with_decorations()
	DisplayServer.window_set_position(area.position + (area.size - decorated) / 2)


# --- Save / load --------------------------------------------------------------------------------

func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("general", "locale", locale)
	cfg.set_value("general", "look_sensitivity", look_sensitivity)
	cfg.set_value("display", "window_mode", window_mode)
	cfg.set_value("display", "window_scale", window_scale)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "fps_limit", fps_limit)
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


## Reads the file (if it exists) and applies language, volumes and controls. Without a file the
## project defaults stay. Values of the wrong type or out of range (a hand-edited or corrupt file)
## fall back to their defaults instead of raising errors.
func load_settings() -> bool:
	var cfg := ConfigFile.new()
	var loaded := cfg.load(save_path) == OK
	if loaded:
		look_sensitivity = clampf(_number(cfg.get_value("general", "look_sensitivity", 1.0), 1.0),
				SENSITIVITY_MIN, SENSITIVITY_MAX)
		for bus in BUSES:
			volumes[bus] = clampf(_number(cfg.get_value("audio", String(bus), 1.0), 1.0), 0.0, 1.0)
		_load_bindings(cfg)
		window_mode = sanitize_mode(cfg.get_value("display", "window_mode", MODE_WINDOWED))
		window_scale = sanitize_scale(cfg.get_value("display", "window_scale", DEFAULT_SCALE))
		vsync = sanitize_vsync(cfg.get_value("display", "vsync", true))
		fps_limit = sanitize_fps(cfg.get_value("display", "fps_limit", 0))
		var stored_locale: Variant = cfg.get_value("general", "locale", DEFAULT_LOCALE)
		locale = stored_locale if stored_locale is String else DEFAULT_LOCALE
	set_locale(locale if LOCALES.has(locale) else DEFAULT_LOCALE, false)
	apply_volumes()
	apply_display()
	bindings_changed.emit()
	return loaded


func _load_bindings(cfg: ConfigFile) -> void:
	for action in REMAP_ACTIONS:
		for slot in [SLOT_KB, SLOT_PAD]:
			var key := "%s.%s" % [action, slot]
			if not is_remappable(action, slot) or not cfg.has_section_key("input", key):
				continue
			var stored: Variant = cfg.get_value("input", key, [])
			var events: Array = []
			for data in stored if stored is Array else []:
				var event := deserialize_event(data)
				if event != null and slot_of(event) == slot:
					events.append(event)
			if not events.is_empty():
				_replace_slot(action, slot, events)


## `value` as a finite float; `fallback` for anything else (wrong type, NaN, infinity).
static func _number(value: Variant, fallback: float) -> float:
	if (value is int or value is float) and is_finite(float(value)):
		return float(value)
	return fallback
