extends TestCase
# Xbox gamepad (XInput): every game action has a gamepad event, menus are navigated with
# D-pad / stick and A / B, and simulated events (parse_input_event) trigger the actions.
# Layout: left stick move, right stick camera, X / RB attack, B roll, Y heal, R3 (RS) lock on,
# Start pause, A / B accept / cancel in menus, LB / RB switch tabs in options.

const GAMEPLAY_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right",
	&"camera_left", &"camera_right", &"camera_up", &"camera_down",
	&"attack", &"heavy_attack", &"roll", &"heal", &"lock_on", &"pause",
]


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _pad_button(index: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = pressed
	return event


func _pad_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func _has_pad_event(action: StringName) -> bool:
	for event in InputMap.action_get_events(action):
		if GameSettings.is_pad_event(event):
			return true
	return false


func test_every_gameplay_action_has_a_gamepad_event() -> void:
	InputMap.load_from_project_settings()
	for action in GAMEPLAY_ACTIONS:
		assert_true(_has_pad_event(action), "%s has a gamepad event" % action)


func test_menu_actions_have_gamepad_events() -> void:
	for action: StringName in [&"ui_accept", &"ui_cancel", &"ui_up", &"ui_down", &"ui_left", &"ui_right"]:
		assert_true(_has_pad_event(action), "%s works with the gamepad" % action)
	assert_true(InputMap.event_is_action(_pad_button(JOY_BUTTON_A, true), &"ui_accept"), "A accepts")
	assert_true(InputMap.event_is_action(_pad_button(JOY_BUTTON_B, true), &"ui_cancel"), "B cancels")
	assert_true(InputMap.event_is_action(_pad_button(JOY_BUTTON_DPAD_DOWN, true), &"ui_down"), "D-pad down")
	assert_true(InputMap.event_is_action(_pad_axis(JOY_AXIS_LEFT_Y, 1.0), &"ui_down"), "left stick down")


func test_xbox_layout() -> void:
	InputMap.load_from_project_settings()
	assert_true(InputMap.event_is_action(_pad_button(JOY_BUTTON_RIGHT_SHOULDER, true), &"attack"), "RB attacks")
	assert_true(InputMap.event_is_action(_pad_button(JOY_BUTTON_X, true), &"attack"), "X attacks")
	assert_true(InputMap.event_is_action(_pad_button(JOY_BUTTON_B, true), &"roll"), "B rolls")
	assert_true(InputMap.event_is_action(_pad_button(JOY_BUTTON_Y, true), &"heal"), "Y heals")
	assert_true(InputMap.event_is_action(_pad_button(JOY_BUTTON_RIGHT_STICK, true), &"lock_on"), "R3 locks on")
	assert_true(InputMap.event_is_action(_pad_button(JOY_BUTTON_START, true), &"pause"), "Start pauses")
	assert_true(InputMap.event_is_action(_pad_axis(JOY_AXIS_LEFT_X, -1.0), &"move_left"), "left stick moves")
	assert_true(InputMap.event_is_action(_pad_axis(JOY_AXIS_RIGHT_X, 1.0), &"camera_right"), "right stick looks")
	assert_true(InputMap.event_is_action(_pad_axis(JOY_AXIS_RIGHT_Y, -1.0), &"camera_up"), "right stick looks up")


func test_simulated_gamepad_events_press_the_actions() -> void:
	InputMap.load_from_project_settings()
	_send(_pad_button(JOY_BUTTON_B, true))
	assert_true(Input.is_action_pressed(&"roll"), "B pressed -> roll")
	_send(_pad_button(JOY_BUTTON_B, false))
	assert_true(not Input.is_action_pressed(&"roll"), "B released")
	_send(_pad_button(JOY_BUTTON_RIGHT_SHOULDER, true))
	assert_true(Input.is_action_pressed(&"attack"), "RB pressed -> attack")
	_send(_pad_button(JOY_BUTTON_RIGHT_SHOULDER, false))
	_send(_pad_axis(JOY_AXIS_LEFT_X, 1.0))
	assert_true(Input.is_action_pressed(&"move_right"), "left stick right -> move_right")
	assert_almost(Input.get_action_strength(&"move_right"), 1.0)
	_send(_pad_axis(JOY_AXIS_LEFT_X, 0.0))
	_send(_pad_axis(JOY_AXIS_RIGHT_X, -1.0))
	assert_true(Input.get_action_strength(&"camera_left") > 0.9, "right stick left -> camera_left")
	_send(_pad_axis(JOY_AXIS_RIGHT_X, 0.0))
	_send(_pad_axis(JOY_AXIS_LEFT_X, 0.1))
	assert_true(not Input.is_action_pressed(&"move_left") and Input.get_action_strength(&"move_right") < 0.01, "dead zone")
	_send(_pad_axis(JOY_AXIS_LEFT_X, 0.0))
	_send(_pad_button(JOY_BUTTON_A, true))
	assert_true(Input.is_action_pressed(&"ui_accept"), "A -> ui_accept")
	_send(_pad_button(JOY_BUTTON_A, false))


func test_gamepad_buttons_use_xbox_names() -> void:
	var names := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
			JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
			JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
			JOY_BUTTON_START: "Start", JOY_BUTTON_BACK: "Back"}
	for index: int in names:
		assert_eq(GameSettings.event_name(_pad_button(index as JoyButton, true)), names[index])
	assert_eq(GameSettings.event_name(_pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)), "LT")
	assert_eq(GameSettings.event_name(_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)), "RT")


func test_options_menu_captures_a_gamepad_button() -> void:
	InputMap.load_from_project_settings()
	var settings := GameSettings.new()
	settings.save_path = "user://test_gamepad_settings.cfg"
	var menu := OptionsMenu.new()
	# Without a tree: apply_capture looks up the autoload, so the data path is tested with GameSettings.
	var event := GameSettings.capture(_pad_button(JOY_BUTTON_DPAD_UP, true))
	assert_true(event != null)
	assert_eq(settings.rebind(&"lock_on", GameSettings.SLOT_PAD, event), &"")
	assert_true(InputMap.event_is_action(_pad_button(JOY_BUTTON_DPAD_UP, true), &"lock_on"), "D-pad up now locks on")
	assert_true(not InputMap.event_is_action(_pad_button(JOY_BUTTON_RIGHT_STICK, true), &"lock_on"), "R3 no longer does")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.save_path))
	InputMap.load_from_project_settings()
	menu.free()
	settings.free()
