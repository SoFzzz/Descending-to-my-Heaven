class_name Tutorial
extends CanvasLayer
## Controls tutorial on the exterior path (child of ExteriorGameplay, after IntroDirector). One hint at
## a time at the bottom of the screen: the CURRENT binding of the action (what the player remapped in
## the options; the gamepad's buttons if that was the last device used) and what it does. Each hint
## waits for the player to do it, so it never gets in the way of someone who already knows:
## move → camera → roll → attack the dummy → heavy attack → lock on and strafe → heal → the warning
## auras → go up to the temple. A training dummy appears beside the path for the attack hints.

signal step_changed(key: String)
signal finished

const LAYER := 15
const FADE := 0.35
const KEY_COLOR := Color(1.0, 0.82, 0.45)
const TEXT_COLOR := Color(0.94, 0.94, 0.97)
const FONT_SIZE := 12
const BOTTOM := 132.0
const DUMMY := "res://scenes/enemies/training_dummy.tscn"
## Where the dummy stands: ahead of Kaelen along her facing, a little to the side of the path.
const DUMMY_AHEAD := 5.0
const DUMMY_SIDE := 1.6
const DUMMY_HEALTH := 99999
## Goals of each step.
const MOVE_DISTANCE := 3.0
const CAMERA_TURN := 0.8          # rad of accumulated camera yaw
const ATTACK_HITS := 2
const STRAFE_TIME := 0.6          # s moving sideways with the dummy locked
const INFO_TIME := 5.0            # s the informative hints (heal, auras) stay
const GO_TIME := 4.0

## [translation key, action shown]. Done-conditions are in _step_done().
const STEPS: Array[Array] = [
	["TUT_MOVE", &"move"], ["TUT_CAMERA", &"camera"], ["TUT_ROLL", &"roll"], ["TUT_ATTACK", &"attack"],
	["TUT_HEAVY", &"heavy_attack"], ["TUT_LOCK", &"lock_on"], ["TUT_HEAL", &"heal"], ["TUT_WARN", &""],
	["TUT_GO", &""],
]

var step := -1
var _player: Player
var _rig: CameraRig
var _pad := false
var _panel: PanelContainer
var _key_label: Label
var _text_label: Label
var _dummy: Node3D
var _dummy_hits := 0
var _from := Vector3.ZERO
var _last_yaw := 0.0
var _turned := 0.0
var _strafed := 0.0
var _step_time := 0.0
var _done_flags := {}


func _ready() -> void:
	layer = LAYER
	_build_ui()
	_start.call_deferred()   # the parent's _ready (which sets `player`) runs after its children's


func _start() -> void:
	var gameplay := get_parent()
	_player = gameplay.get(&"player") as Player if gameplay else null
	if _player == null:
		return
	_rig = _player.get_node_or_null(^"CameraRig") as CameraRig
	var intro := gameplay.get_node_or_null(^"IntroDirector") as IntroDirector
	if intro and intro.is_playing():
		await intro.finished
	elif intro:
		await get_tree().process_frame   # let the intro decide whether it plays
		if intro.is_playing():
			await intro.finished
	_next()


## Hint being shown: its translation key ("" when none).
func current_key() -> String:
	return STEPS[step][0] if step >= 0 and step < STEPS.size() else ""


func _input(event: InputEvent) -> void:
	# The hint follows the device in use: a pad press or stick shows the pad buttons.
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		_set_pad(true)
	elif event is InputEventKey or event is InputEventMouseButton:
		_set_pad(false)


func _set_pad(on: bool) -> void:
	if on != _pad:
		_pad = on
		_refresh()


func _process(delta: float) -> void:
	if step < 0 or step >= STEPS.size() or _player == null or not is_instance_valid(_player):
		return
	_step_time += delta
	_track(delta)
	if _step_done():
		_next()


## Watches what the player does for the current step.
func _track(delta: float) -> void:
	if _rig:
		_turned += absf(angle_difference(_last_yaw, _rig.yaw))
		_last_yaw = _rig.yaw
	if _player.state == Player.State.ROLL:
		_done_flags[&"roll"] = true
	if _player.is_heavy_attacking():
		_done_flags[&"heavy"] = true
	if _player.is_healing():
		_done_flags[&"heal"] = true
	var target := _player.get_lock_target()
	if target != null and target == _dummy and absf(_player.local_ground_velocity().x) > 1.0:
		_strafed += delta


func _step_done() -> bool:
	match current_key():
		"TUT_MOVE":
			return _player.global_position.distance_to(_from) >= MOVE_DISTANCE
		"TUT_CAMERA":
			return _turned >= CAMERA_TURN
		"TUT_ROLL":
			return _done_flags.has(&"roll")
		"TUT_ATTACK":
			return _dummy_hits >= ATTACK_HITS
		"TUT_HEAVY":
			return _done_flags.has(&"heavy")
		"TUT_LOCK":
			return _strafed >= STRAFE_TIME
		"TUT_HEAL":
			return _done_flags.has(&"heal") or _step_time >= INFO_TIME
		"TUT_WARN":
			return _step_time >= INFO_TIME
		"TUT_GO":
			return _step_time >= GO_TIME
	return true


func _next() -> void:
	step += 1
	_step_time = 0.0
	_from = _player.global_position
	_turned = 0.0
	_strafed = 0.0
	if _rig:
		_last_yaw = _rig.yaw
	if step >= STEPS.size():
		_fade_panel(0.0)
		finished.emit()
		return
	if current_key() == "TUT_ATTACK":
		_spawn_dummy()
	_refresh()
	_panel.modulate.a = 0.0
	_fade_panel(1.0)
	step_changed.emit(current_key())


func _refresh() -> void:
	if step < 0 or step >= STEPS.size():
		return
	var action: StringName = STEPS[step][1]
	_key_label.text = binding_text(action)
	_key_label.visible = not _key_label.text.is_empty()
	_text_label.text = tr(current_key())


## What to press for `action` on the device in use: the remapped binding (UserSettings.slot_text).
func binding_text(action: StringName) -> String:
	var settings := get_node_or_null(^"/root/UserSettings")
	var slot := &"pad" if _pad else &"kb"
	match action:
		&"":
			return ""
		&"move":
			if _pad:
				return "LS"
			if settings == null:
				return "W A S D"
			var keys: Array[String] = []
			for a in [&"move_forward", &"move_left", &"move_back", &"move_right"]:
				keys.append(String(settings.call(&"slot_text", a, slot)))
			return " ".join(keys)
		&"camera":
			return "RS" if _pad else tr("TUT_MOUSE")
	if settings == null:
		return String(action)
	return String(settings.call(&"slot_text", action, slot))


## A training dummy beside the path, standing on the ground, that cannot be destroyed.
func _spawn_dummy() -> void:
	if _dummy and is_instance_valid(_dummy):
		return
	var scene := load(DUMMY) as PackedScene
	if scene == null:
		return
	_dummy = scene.instantiate() as Node3D
	var forward := _player.get_facing()
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
	var side := forward.cross(Vector3.UP).normalized()
	var spot := _player.global_position + forward * DUMMY_AHEAD + side * DUMMY_SIDE
	get_parent().add_child(_dummy)
	_dummy.global_position = _ground_at(spot)
	_dummy.look_at(_player.global_position, Vector3.UP)
	_dummy.rotation.x = 0.0
	_dummy.rotation.z = 0.0
	var health := _dummy.get_node_or_null(^"Health") as Health
	if health:
		health.reset(DUMMY_HEALTH)
		health.changed.connect(func(_c: int, _m: int) -> void: _dummy_hits += 1)


func _ground_at(spot: Vector3) -> Vector3:
	var space := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 6.0, spot + Vector3.DOWN * 12.0, 1)
	var hit := space.intersect_ray(query)
	return hit.position if not hit.is_empty() else Vector3(spot.x, _player.global_position.y, spot.z)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.theme = DialogueBox.MENU_THEME
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	style.border_color = Color(0.55, 0.5, 0.42, 0.9)
	style.set_border_width_all(1)
	style.set_content_margin_all(8.0)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	_panel.add_theme_stylebox_override(&"panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_bottom = -BOTTOM
	_panel.modulate.a = 0.0
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	_panel.add_child(row)
	_key_label = Label.new()
	_key_label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_key_label.add_theme_color_override(&"font_color", KEY_COLOR)
	row.add_child(_key_label)
	_text_label = Label.new()
	_text_label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_text_label.add_theme_color_override(&"font_color", TEXT_COLOR)
	row.add_child(_text_label)
	add_child(_panel)


func _fade_panel(alpha: float) -> void:
	if _panel:
		_panel.create_tween().tween_property(_panel, "modulate:a", alpha, FADE)
