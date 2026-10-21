class_name AttackWarning
extends RefCounted
## Attack warnings, God of War style, always the same two colours so the player learns them:
## - DODGE (yellow): a well-timed roll goes through it.
## - ESCAPE (red): the roll's i-frames do not cover it; get out of the marked zone (or into its
##   safe spot) instead.
## Two coherent signals per attack: an aura on the attacker's model (psx_lit `aura` uniform) that
## rises progressively over the first part of the warning, holds through the blow and fades out
## (never pops in or out), and the ground warning (shaders/telegraph_ground.gdshader) in the same
## colour, whose fill reaches the edge when the blow lands.

enum Level { NONE, DODGE, ESCAPE }

const YELLOW := Color(1.0, 0.74, 0.12)
const YELLOW_CORE := Color(1.0, 0.95, 0.7)
const RED := Color(1.0, 0.14, 0.08)
const RED_CORE := Color(1.0, 0.7, 0.55)
const GROUND_SHADER := preload("res://shaders/telegraph_ground.gdshader")
const META_TWEEN := &"_aura_tween"
const META_VALUE := &"_aura_value"
## Share of the warning time the aura takes to rise (it is never shorter than AURA_MIN_RISE s).
const AURA_RISE_FRACTION := 0.45
const AURA_MIN_RISE := 0.25
const AURA_FADE := 0.35


static func color_for(level: int) -> Color:
	return RED if level == Level.ESCAPE else YELLOW


static func core_for(level: int) -> Color:
	return RED_CORE if level == Level.ESCAPE else YELLOW_CORE


## Seconds the aura takes to rise for a warning of `warning_time` s.
static func rise_time(warning_time: float) -> float:
	return maxf(AURA_MIN_RISE, warning_time * AURA_RISE_FRACTION)


# --- Aura on the model -----------------------------------------------------------------------

## Moves the aura of `model` (root of its PSX meshes) to `target` (0..1) in `time` s, from wherever
## it is now: a new warning while the previous one fades continues smoothly instead of jumping.
static func aura_to(model: Node, color: Color, target: float, time: float) -> void:
	if model == null or not model.is_inside_tree():
		return
	var mats := HitFlash._materials(model)
	if mats.is_empty():
		return
	var old: Variant = model.get_meta(META_TWEEN) if model.has_meta(META_TWEEN) else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var from := aura_of(model)
	for m in mats:
		(m as ShaderMaterial).set_shader_parameter(&"aura_color", color)
	if time <= 0.0:
		_set_aura(target, mats, model)
		return
	var tween := model.create_tween()
	model.set_meta(META_TWEEN, tween)
	tween.tween_method(_set_aura.bind(mats, model), from, target, time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Current aura of `model` (0 if it has none).
static func aura_of(model: Node) -> float:
	if model == null or not model.has_meta(META_VALUE):
		return 0.0
	return float(model.get_meta(META_VALUE))


static func _set_aura(value: float, mats: Array, model: Node) -> void:
	if is_instance_valid(model):
		model.set_meta(META_VALUE, value)
	for m in mats:
		if is_instance_valid(m):
			(m as ShaderMaterial).set_shader_parameter(&"aura", value)


# --- Ground warning --------------------------------------------------------------------------

## Turns a flat warning mesh (CylinderMesh disc or BoxMesh strip, as authored in the boss scenes)
## into a plane with the warning shader. `inner` > 0 (m) makes a disc a ring with a safe centre.
## Returns the material (null if the mesh is not one of those).
static func make_ground(mi: MeshInstance3D, level: int, inner := 0.0) -> ShaderMaterial:
	if mi == null or mi.mesh == null:
		return null
	var size := Vector2.ZERO
	var shape := 0
	if mi.mesh is CylinderMesh:
		var r := (mi.mesh as CylinderMesh).top_radius
		size = Vector2(r, r) * 2.0
		shape = 2 if inner > 0.0 else 0
	elif mi.mesh is BoxMesh:
		var b := (mi.mesh as BoxMesh).size
		size = Vector2(b.x, b.z)
		shape = 1
	else:
		return null
	var plane := PlaneMesh.new()
	plane.size = size
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter(&"color", color_for(level))
	mat.set_shader_parameter(&"core_color", core_for(level))
	mat.set_shader_parameter(&"shape", shape)
	mat.set_shader_parameter(&"inner", clampf(inner / maxf(size.x * 0.5, 0.01), 0.0, 0.95))
	mat.set_shader_parameter(&"half_size", size * 0.5)
	mat.set_shader_parameter(&"progress", 0.0)
	plane.material = mat
	mi.mesh = plane
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mat


## Ground warning for code-made zones (minions): a disc of `radius` m.
static func ground_disc(radius: float, level: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	mi.mesh = cyl
	make_ground(mi, level)
	return mi


static func set_progress(mi: GeometryInstance3D, value: float) -> void:
	var mat := _ground_material(mi)
	if mat:
		mat.set_shader_parameter(&"progress", clampf(value, 0.0, 1.0))


static func set_radius(mi: MeshInstance3D, radius: float) -> void:
	var plane := mi.mesh as PlaneMesh if mi else null
	if plane == null:
		return
	plane.size = Vector2(radius, radius) * 2.0
	var mat := plane.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter(&"half_size", plane.size * 0.5)


static func _ground_material(mi: GeometryInstance3D) -> ShaderMaterial:
	var m := mi as MeshInstance3D
	if m == null or m.mesh == null:
		return null
	return m.mesh.surface_get_material(0) as ShaderMaterial if m.mesh.get_surface_count() > 0 else null
