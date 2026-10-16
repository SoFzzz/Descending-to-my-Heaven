extends CanvasLayer
## Fade to black between scenes (FADE_TIME going to black and the same coming back). Lives as a
## child of the GameState autoload so it survives the scene change. With the screen black it asks
## its parent for `_swap_scene(path)` (pause, time_scale and token cleanup...) or, lacking it,
## changes scene directly.

signal covered   # the screen is black and the new scene was already requested

const FADE_TIME := 0.5

var _busy := false

@onready var _black: ColorRect = $Black


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_black.modulate.a = 0.0
	_black.visible = false


func is_busy() -> bool:
	return _busy


func fade_to(path: String) -> void:
	if _busy:
		return
	_busy = true
	_black.visible = true
	_black.mouse_filter = Control.MOUSE_FILTER_STOP   # no clicks during the fade
	await _fade(1.0)
	var parent := get_parent()
	if parent and parent.has_method(&"_swap_scene"):
		parent.call(&"_swap_scene", path)
	else:
		get_tree().change_scene_to_file(path)
	covered.emit()
	# change_scene_to_file is deferred: wait for the new scene to be in the tree.
	await get_tree().process_frame
	await get_tree().process_frame
	await _fade(0.0)
	_black.visible = false
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


func _fade(alpha: float) -> void:
	var tween := create_tween().set_ignore_time_scale(true)
	tween.tween_property(_black, ^"modulate:a", alpha, FADE_TIME)
	await tween.finished
