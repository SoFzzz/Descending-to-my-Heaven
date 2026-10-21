class_name IntroDirector
extends Node
## Opening of a new run (child of ExteriorGameplay): why Kaelen climbs the temple. Six lines in the
## ending's DialogueBox (they advance on a press, like the ending), told in three shots:
## - INTRO_01-03 (narrator): a slow aerial dolly from behind Kaelen toward the temple;
## - INTRO_04-05 (Kaelen): close on her face, looking at the temple;
## - INTRO_06 (narrator): over black, then the picture opens on her own camera and she gets control.
## Kaelen is locked (cutscene) and her HUD hidden meanwhile. Pause (Esc / Start) skips it. Runs only
## when GameState.intro_pending (set by start_new_game), so tests and other entries skip it.

signal finished

const LINES: Array[Array] = [
	["INTRO_01", 0], ["INTRO_02", 0], ["INTRO_03", 0],
	["INTRO_04", 1], ["INTRO_05", 1],
	["INTRO_06", 2],
]
const LAYER := 19
const FADE_IN := 1.4
const CUT := 0.35
const BOX_FADE := 0.6
const END_FADE := 0.9
## Aerial shot: from above and behind Kaelen toward the temple door, over DOLLY_TIME s.
const AERIAL_FROM := Vector3(0.0, 12.0, 10.0)
const AERIAL_TO := Vector3(0.0, 8.0, 2.0)
const AERIAL_LOOK_UP := 6.0
const DOLLY_TIME := 30.0
## Close shot: in front of Kaelen, at face height, looking back at her.
const CLOSE_AHEAD := 1.9
const CLOSE_SIDE := 0.5
const CLOSE_HEIGHT := 1.55

var playing := false
var _player: Player
var _layer: CanvasLayer
var _overlay: ColorRect
var _box: DialogueBox
var _skip_hint: Label
var _aerial: Camera3D
var _close: Camera3D
var _dolly: Tween
var _skipped := false
var _dolly_offset := Vector3.ZERO   # world-space travel of the aerial dolly


func _ready() -> void:
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state == null or not bool(game_state.get(&"intro_pending")):
		finished.emit.call_deferred()
		return
	game_state.set(&"intro_pending", false)
	_play.call_deferred()


## true while the intro runs (Tutorial waits for it).
func is_playing() -> bool:
	return playing


func _unhandled_input(event: InputEvent) -> void:
	if playing and not _skipped and event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		_skipped = true
		if _box:
			_box.advanced.emit()   # releases the line being awaited; the loop sees _skipped


func _play() -> void:
	var gameplay := get_parent()
	_player = gameplay.get(&"player") as Player if gameplay else null
	var level := gameplay.get(&"level") as Node3D if gameplay else null
	if _player == null or level == null:
		finished.emit()
		return
	playing = true
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state:
		game_state.set(&"cutscene_active", true)
	_player.set_cutscene(true)
	_set_hud(false)
	_build_ui()
	_build_cameras(level)
	_aerial.make_current()
	_dolly = create_tween()
	_dolly.tween_property(_aerial, "global_position", _aerial.global_position + _dolly_offset, DOLLY_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_fade(0.0, FADE_IN)
	await _wait(FADE_IN * 0.6)
	_box.fade(1.0, BOX_FADE)
	var shot := 0
	for entry in LINES:
		if _skipped or not is_inside_tree():
			break
		var next_shot: int = entry[1]
		if next_shot != shot:
			shot = next_shot
			await _cut_to(shot)
			if _skipped or not is_inside_tree():
				break
		_box.show_line(tr(entry[0]))
		await _box.advanced
	await _finish()


## Changes shot behind a short black (2 = black itself, for the last narrated line).
func _cut_to(shot: int) -> void:
	_fade(1.0, CUT)
	await _wait(CUT)
	if shot == 1:
		_close.make_current()
		_fade(0.0, CUT)
		await _wait(CUT)


func _finish() -> void:
	if not is_inside_tree():
		return
	_box.fade(0.0, BOX_FADE * 0.5)
	_fade(1.0, END_FADE * 0.5)
	await _wait(END_FADE * 0.5)
	if _dolly and _dolly.is_valid():
		_dolly.kill()
	var cam := _player.get_node_or_null(^"CameraRig/SpringArm3D/Camera3D") as Camera3D
	if cam:
		cam.make_current()
	var rig := _player.get_node_or_null(^"CameraRig") as CameraRig
	if rig:
		rig.snap_to_target()
	_player.set_cutscene(false)
	_set_hud(true)
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state:
		game_state.set(&"cutscene_active", false)
	_fade(0.0, END_FADE)
	await _wait(END_FADE)
	playing = false
	if _layer:
		_layer.queue_free()
	for c in [_aerial, _close]:
		if c:
			c.queue_free()
	finished.emit()


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = LAYER
	add_child(_layer)
	_box = DialogueBox.new()
	_layer.add_child(_box)
	_overlay = ColorRect.new()
	_overlay.color = Color.BLACK
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_overlay)
	_skip_hint = Label.new()
	_skip_hint.theme = DialogueBox.MENU_THEME
	_skip_hint.text = "%s: %s" % [_pause_label(), tr("INTRO_SKIP")]
	_skip_hint.add_theme_font_size_override(&"font_size", 10)
	_skip_hint.add_theme_color_override(&"font_color", Color(0.75, 0.75, 0.8, 0.8))
	_skip_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_skip_hint.offset_left = -200.0
	_skip_hint.offset_right = -16.0
	_skip_hint.offset_top = 12.0
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_layer.add_child(_skip_hint)


func _pause_label() -> String:
	var settings := get_node_or_null(^"/root/UserSettings")
	if settings and settings.has_method(&"slot_text"):
		return String(settings.call(&"slot_text", &"pause", &"kb"))
	return "Esc"


func _build_cameras(level: Node3D) -> void:
	var start := _player.global_position
	var temple := level.get_node_or_null(^"ExitTrigger") as Node3D
	if temple:
		_player.face_point(temple.global_position)   # she looks at the temple through the whole intro
	var forward := _player.get_facing()
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	var look := (temple.global_position if temple else start + forward * 40.0) + Vector3.UP * AERIAL_LOOK_UP
	# Aerial: AERIAL_FROM is in Kaelen's frame (y up, z behind her).
	_aerial = Camera3D.new()
	_aerial.name = "IntroAerial"
	get_parent().add_child(_aerial)
	_aerial.global_position = start - forward * AERIAL_FROM.z + Vector3.UP * AERIAL_FROM.y
	_aerial.look_at(look, Vector3.UP)
	# The dolly moves it toward the temple in world space (same frame conversion).
	var delta_local := AERIAL_TO - AERIAL_FROM
	_dolly_offset = -forward * delta_local.z + Vector3.UP * delta_local.y
	_close = Camera3D.new()
	_close.name = "IntroClose"
	get_parent().add_child(_close)
	_close.global_position = start + forward * CLOSE_AHEAD + right * CLOSE_SIDE + Vector3.UP * CLOSE_HEIGHT
	_close.look_at(start + Vector3.UP * (CLOSE_HEIGHT - 0.05), Vector3.UP)



func _set_hud(on: bool) -> void:
	var hud := _player.get_node_or_null(^"HUD")
	if hud:
		hud.set(&"visible", on)


func _fade(alpha: float, time: float) -> void:
	if _overlay:
		_overlay.create_tween().tween_property(_overlay, "modulate:a", alpha, time)


func _wait(seconds: float) -> void:
	if is_inside_tree():
		await get_tree().create_timer(seconds).timeout
