extends CanvasLayer
## Fundido a negro entre escenas (FADE_TIME al ir a negro y otro tanto al volver). Vive como hijo
## del autoload GameState, así sobrevive al cambio de escena. Con la pantalla en negro pide a su
## padre `_swap_scene(path)` (limpieza de pausa, time_scale, fichas…) o, si no lo tiene, cambia
## de escena directamente.

signal covered   # la pantalla está en negro y ya se pidió la escena nueva

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
	_black.mouse_filter = Control.MOUSE_FILTER_STOP   # sin clics durante el fundido
	await _fade(1.0)
	var parent := get_parent()
	if parent and parent.has_method(&"_swap_scene"):
		parent.call(&"_swap_scene", path)
	else:
		get_tree().change_scene_to_file(path)
	covered.emit()
	# change_scene_to_file es diferido: se espera a que la escena nueva esté en el árbol.
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
