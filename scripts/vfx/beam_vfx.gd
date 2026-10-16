class_name BeamVfx
extends "res://assets/vfx/beam/vfx_beam_controller.gd"
## Mecha King Ghidorah's beam (Binbun's "Beam VFX" pack, CC0). The boss only turns the node on and
## off (`BossAttack.visual_path`): when turned on the beam opens over OPEN_TIME seconds and when
## turned off it closes at once. Its length (`beam_length`) and radius match the hitbox.

const OPEN_TIME := 0.18
## Ember wave on the ground where the beam hits (MagicArea "ripple" from Magic Circles 3D Free):
## rings that open from the impact point; radius (m) and drop from the sphere's center.
const IMPACT_RIPPLE_RADIUS := 1.7
const IMPACT_RIPPLE_DROP := 0.3

var _elapsed := 0.0
var _ripple: MagicArea


## Opening (0-1) of the beam after `elapsed` seconds on.
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
		_ripple.top_level = true   # stays flat on the ground even if the beam points diagonally
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
