extends CanvasLayer
## Scene transition: a closing iris to black, optionally a title card (zone name in DungeonFont)
## while the screen is black, and an opening iris. Lives as a child of the GameState autoload so it
## survives the scene change. With the screen black it asks its parent for `_swap_scene(path)` (pause,
## time_scale and token cleanup...) or, lacking it, changes scene directly.
##
## - Plain fade (menus, credits): FADE_TIME each way.
## - Card (entering the temple, climbing a floor): CLOSE_TIME, title card, OPEN_TIME. Any key press
##   during the card cuts the remaining hold. Kaelen is locked while the screen closes and the new
##   scene stays paused until the iris is half open, so nothing happens (no control, no boss) in black.
## - Quick (retry after dying): QUICK_TIME each way, no card.

signal covered   # the screen is black and the new scene was already requested

const FADE_TIME := 0.5
const CLOSE_TIME := 0.5
const OPEN_TIME := 0.6
const QUICK_TIME := 0.25
const CARD_IN := 0.35
const CARD_HOLD := 0.7
const CARD_OUT := 0.25
const CARD_OUT_SKIPPED := 0.1
const TITLE_SIZE := 44
const SUBTITLE_SIZE := 20
const FONT := preload("res://assets/fonts/DungeonFont.ttf")
const IRIS := preload("res://assets/shaders/transition_iris.gdshader")
const TITLE_COLOR := Color(0.86, 0.84, 0.8)
const SUBTITLE_COLOR := Color(0.55, 0.55, 0.55)

var _busy := false
var _cover := 0.0
var _can_skip := false
var _skip := false
var _paused_by_me := false
var _card: Control
var _title: Label
var _subtitle: Label
var _rule: ColorRect

@onready var _black: ColorRect = $Black


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var material := ShaderMaterial.new()
	material.shader = IRIS
	_black.material = material
	_set_cover(0.0)
	_black.visible = false
	_build_card()


func is_busy() -> bool:
	return _busy


## 0 = clear screen, 1 = fully black.
func get_cover() -> float:
	return _cover


## true once a key press cut the title card's hold (it then fades out quickly).
func card_skipped() -> bool:
	return _skip


func is_black() -> bool:
	return _cover >= 0.999


## Changes to `path` behind the transition. With a non-empty `title` it shows the card; `quick`
## uses the short fade without a card. Ignored while another transition runs.
func fade_to(path: String, title := "", subtitle := "", quick := false) -> void:
	if _busy:
		return
	_busy = true
	var carded := not title.is_empty() and not quick
	_skip = false
	_can_skip = false
	_black.visible = true
	_black.mouse_filter = Control.MOUSE_FILTER_STOP   # no clicks during the fade
	if carded:
		_lock_player()
	var close_time := QUICK_TIME if quick else (CLOSE_TIME if carded else FADE_TIME)
	await _tween_cover(1.0, close_time)
	var parent := get_parent()
	if parent and parent.has_method(&"_swap_scene"):
		parent.call(&"_swap_scene", path)
	else:
		get_tree().change_scene_to_file(path)
	covered.emit()
	# change_scene_to_file is deferred: wait for the new scene to be in the tree.
	await get_tree().process_frame
	await get_tree().process_frame
	if carded:
		get_tree().paused = true   # the new scene waits in black: no control, no boss, no timers
		_paused_by_me = true
		await _show_card(title, subtitle)
	var open_time := QUICK_TIME if quick else (OPEN_TIME if carded else FADE_TIME)
	await _open(open_time)
	_release()
	_black.visible = false
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


func _input(event: InputEvent) -> void:
	if not _can_skip or event.is_echo() or not event.is_pressed():
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		_skip = true


func _set_cover(value: float) -> void:
	_cover = value
	(_black.material as ShaderMaterial).set_shader_parameter(&"cover", value)


func _tween_cover(to: float, time: float) -> void:
	var tween := create_tween().set_ignore_time_scale(true)
	tween.tween_method(_set_cover, _cover, to, time)
	await tween.finished


## Opens the iris; the scene is released from its pause when it is half open.
func _open(time: float) -> void:
	var tween := create_tween().set_ignore_time_scale(true).set_parallel()
	tween.tween_method(_set_cover, _cover, 0.0, time)
	tween.tween_callback(_release).set_delay(time * 0.5)
	await tween.finished


func _release() -> void:
	if _paused_by_me:
		_paused_by_me = false
		get_tree().paused = false


## Kaelen cannot move, roll or attack while the screen closes (she is also invulnerable).
func _lock_player() -> void:
	for node in get_tree().get_nodes_in_group(&"player"):
		if node.has_method(&"set_cutscene"):
			node.call(&"set_cutscene", true)


func _build_card() -> void:
	_card = Control.new()
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.modulate.a = 0.0
	_card.visible = false
	add_child(_card)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(box)
	_title = _make_label(TITLE_SIZE, TITLE_COLOR)
	box.add_child(_title)
	var rule_row := CenterContainer.new()
	rule_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule_row)
	_rule = ColorRect.new()
	_rule.color = SUBTITLE_COLOR
	_rule.custom_minimum_size = Vector2(240, 2)
	_rule.pivot_offset = Vector2(120, 1)
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule_row.add_child(_rule)
	_subtitle = _make_label(SUBTITLE_SIZE, SUBTITLE_COLOR)
	box.add_child(_subtitle)


func _make_label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override(&"font", FONT)
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## The card over black: fades in, holds (a key press cuts the hold) and fades out.
func _show_card(title: String, subtitle: String) -> void:
	_title.text = title
	_subtitle.text = subtitle
	_subtitle.visible = not subtitle.is_empty()
	_rule.visible = not subtitle.is_empty()
	_rule.scale.x = 0.0
	_card.modulate.a = 0.0
	_card.visible = true
	var tween := create_tween().set_ignore_time_scale(true).set_parallel()
	tween.tween_property(_card, "modulate:a", 1.0, CARD_IN)
	tween.tween_property(_rule, "scale:x", 1.0, CARD_IN * 1.5).set_trans(Tween.TRANS_SINE)
	await tween.finished
	_can_skip = true
	var left := CARD_HOLD
	while left > 0.0 and not _skip:
		await get_tree().process_frame
		left -= get_process_delta_time()
	_can_skip = false
	var out := create_tween().set_ignore_time_scale(true)
	out.tween_property(_card, "modulate:a", 0.0, CARD_OUT_SKIPPED if _skip else CARD_OUT)
	await out.finished
	_card.visible = false
