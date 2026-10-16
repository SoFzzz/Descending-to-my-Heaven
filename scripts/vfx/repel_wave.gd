class_name RepelWave
extends MeshInstance3D
## Onda de choque de la repulsion de los jefes: un anillo plano que crece desde el jefe hasta el radio
## del empuje y se desvanece. Se crea en codigo (sin escena) y se libera solo.

const DURATION := 0.4
const START_FRACTION := 0.15
const COLOR := Color(1.0, 0.55, 0.25)

static var _mesh: TorusMesh


## Crea la onda en el suelo bajo `boss` (hermana suya, para que no gire con el jefe).
static func spawn(boss: Node3D, radius: float) -> RepelWave:
	if not boss.is_inside_tree() or boss.get_parent() == null:
		return null
	var wave := RepelWave.new()
	wave.mesh = _shared_mesh()
	wave.material_override = _new_material()   # propio: son pocas (una cada >= 7 s) y cada una se desvanece
	wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	boss.get_parent().add_child(wave)
	wave.global_position = boss.global_position + Vector3.UP * 0.15
	wave.scale = Vector3(radius * START_FRACTION, 1.0, radius * START_FRACTION)
	var tween := wave.create_tween().set_parallel(true)
	tween.tween_property(wave, "scale", Vector3(radius, 1.0, radius), DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(wave._set_alpha, 1.0, 0.0, DURATION)
	tween.chain().tween_callback(wave.queue_free)
	return wave


func _set_alpha(alpha: float) -> void:
	(material_override as StandardMaterial3D).albedo_color = Color(COLOR.r, COLOR.g, COLOR.b, alpha * 0.8)


static func _shared_mesh() -> TorusMesh:
	if _mesh == null:
		_mesh = TorusMesh.new()
		_mesh.inner_radius = 0.93
		_mesh.outer_radius = 1.0
		_mesh.rings = 32
		_mesh.ring_segments = 6
	return _mesh


static func _new_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(COLOR.r, COLOR.g, COLOR.b, 0.8)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
