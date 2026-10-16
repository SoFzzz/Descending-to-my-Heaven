class_name BeamVfx
extends "res://assets/vfx/beam/vfx_beam_controller.gd"
## Rayo de Mecha King Ghidorah (pack "Beam VFX" de Binbun, CC0). El jefe solo enciende y apaga el
## nodo (`BossAttack.visual_path`): al encenderse el rayo se abre en OPEN_TIME segundos y al
## apagarse se cierra de golpe. El largo (`beam_length`) y el radio coinciden con la hitbox.

const OPEN_TIME := 0.18
## Onda de brasas en el suelo donde el rayo impacta (MagicArea "ripple" de Magic Circles 3D Free):
## anillos que se abren desde el punto de impacto; radio (m) y bajada desde el centro de la esfera.
const IMPACT_RIPPLE_RADIUS := 1.7
const IMPACT_RIPPLE_DROP := 0.3

var _elapsed := 0.0
var _ripple: MagicArea


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
	_sync_ripple()


func _sync_ripple() -> void:
	if visible and _ripple == null and is_inside_tree():
		MagicArea.default_transparency = 1
		_ripple = MagicArea.new()
		_ripple.element = "fire"
		_ripple.kind = "ripple"
		_ripple.radius = IMPACT_RIPPLE_RADIUS
		_ripple.particles = false
		_ripple.light = false
		_ripple.appear = 0.25
		_ripple.seed = 1.0
		add_child(_ripple)
		_ripple.top_level = true   # queda plana en el suelo aunque el rayo apunte en diagonal
	if _ripple:
		_ripple.visible = visible
		_ripple.process_mode = Node.PROCESS_MODE_INHERIT if visible else Node.PROCESS_MODE_DISABLED
		if visible:
			_ripple.play()


func _process(delta: float) -> void:
	_elapsed += delta
	open_amount = open_progress(_elapsed)
	if _ripple and beam_end_pivot:
		var end := beam_end_pivot.global_position
		_ripple.global_position = Vector3(end.x, end.y - IMPACT_RIPPLE_DROP, end.z)
		_ripple.visible = open_amount >= 1.0
