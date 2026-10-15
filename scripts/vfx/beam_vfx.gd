class_name BeamVfx
extends "res://assets/vfx/beam/vfx_beam_controller.gd"
## Rayo de Mecha King Ghidorah (pack "Beam VFX" de Binbun, CC0). El jefe solo enciende y apaga el
## nodo (`BossAttack.visual_path`): al encenderse el rayo se abre en OPEN_TIME segundos y al
## apagarse se cierra de golpe. El largo (`beam_length`) y el radio coinciden con la hitbox.

const OPEN_TIME := 0.18

var _elapsed := 0.0


## Apertura (0-1) del rayo tras `elapsed` segundos encendido.
static func open_progress(elapsed: float, duration: float = OPEN_TIME) -> float:
	if duration <= 0.0:
		return 1.0
	return clampf(elapsed / duration, 0.0, 1.0)


func _ready() -> void:
	super()
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func _on_visibility_changed() -> void:
	_elapsed = 0.0
	open_amount = 0.0
	set_process(visible)


func _process(delta: float) -> void:
	_elapsed += delta
	open_amount = open_progress(_elapsed)
	if open_amount >= 1.0:
		set_process(false)
