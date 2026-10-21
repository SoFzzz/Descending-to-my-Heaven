class_name Narration
extends CanvasLayer
## One narrated line over the action (no input needed): fades in low on the screen, holds and fades
## out, then frees itself. Used on arriving at each floor (FLOOR_LORE_*), so the climb tells the
## story between the fights. Same font and narrator grey as the ending's DialogueBox.

const LAYER := 18
const FONT_SIZE := 14
const FADE := 0.8
const BOTTOM := 96.0

var _label: Label


## Shows `text` for `hold` s (plus the fades) as a child of `parent`. Returns it.
static func say(parent: Node, text: String, hold := 3.5) -> Narration:
	if parent == null or not parent.is_inside_tree() or text.is_empty():
		return null
	var n := Narration.new()
	parent.add_child(n)
	n._run(text, hold)
	return n


func _run(text: String, hold: float) -> void:
	layer = LAYER
	_label = Label.new()
	_label.theme = DialogueBox.MENU_THEME
	_label.text = text
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_label.add_theme_color_override(&"font_color", DialogueBox.NARRATOR_COLOR)
	_label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override(&"shadow_offset_x", 1)
	_label.add_theme_constant_override(&"shadow_offset_y", 1)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_label.offset_left = DialogueBox.SIDE_MARGIN
	_label.offset_right = -DialogueBox.SIDE_MARGIN
	_label.offset_top = -BOTTOM - 40.0
	_label.offset_bottom = -BOTTOM
	_label.modulate.a = 0.0
	add_child(_label)
	var tween := create_tween()
	tween.tween_property(_label, "modulate:a", 1.0, FADE)
	tween.tween_interval(hold)
	tween.tween_property(_label, "modulate:a", 0.0, FADE)
	tween.tween_callback(queue_free)


func text() -> String:
	return _label.text if _label else ""
