class_name ImpactFx
extends Node
## Cheap impact effects using the resources of "Storm & Wind 3D Free" and "Magic Circles 3D Free"
## (heyheythere, CC BY 4.0; addons/storm_wind and addons/magic_circles, plugins not enabled):
##
## - Sparks at the hit point (`sparks`), driven by Events.hit_landed.
## - Dust and debris when rolling, on boss ground hits and when minions die (`dust`, `puff`).
## - Magic seal on the ground (`seal`): telegraph of the repel and the phase 2 roar.
##
## It is a single node hanging from the root (`ImpactFx.instance(tree)`) with fixed pools of one-shot
## CPUParticles3D that are reused: hitting creates no nodes or meshes, it only repositions and
## restarts an emitter. All use Storm & Wind's `spark.gdshader` (a single shader to compile; see
## `ShaderWarmup`, which draws it once during loading). With dithered transparency to match the
## PSX look.

const SPARK_SHADER := "res://addons/storm_wind/shaders/spark.gdshader"
const NODE_NAME := "ImpactFx"
const SPARK_POOL := 6
const DUST_POOL := 6   # hits, deaths and corpses share it
## Boss attacks that hit the ground: they kick up dust where the hitbox lands.
const GROUND_ATTACKS: Array[StringName] = [&"slam", &"stomp", &"pounce"]

const SPARK_COLOR := Color(1.0, 0.78, 0.38)
const SPARK_EDGE := Color(1.0, 0.45, 0.12)
const HEAL_COLOR := Color(0.55, 1.0, 0.6)
const HEAL_EDGE := Color(0.2, 0.75, 0.35)
const HEAL_SPARK := Color(1.0, 0.92, 0.5)
const DUST_COLOR := Color(0.62, 0.58, 0.52)
const DUST_EDGE := Color(0.38, 0.35, 0.32)
## Organic surfaces get a splash as heavy as the bone hit, in the creature's colour:
## [spark colour, spark edge, mist colour, mist edge].
const ORGANIC := {
	&"flesh": [Color(0.85, 0.16, 0.1), Color(0.4, 0.03, 0.02), Color(0.5, 0.1, 0.07), Color(0.25, 0.04, 0.03)],   # TheWrapper, Blackhorn, Kaelen
	&"ichor": [Color(0.65, 1.0, 0.35), Color(0.18, 0.5, 0.1), Color(0.38, 0.6, 0.22), Color(0.16, 0.3, 0.08)],   # Plague Arcanist
	&"straw": [Color(1.0, 0.86, 0.42), Color(0.62, 0.42, 0.12), Color(0.72, 0.62, 0.36), Color(0.42, 0.33, 0.16)],   # Straw Reaper
}

static var _instance: ImpactFx

var _sparks: Array[CPUParticles3D] = []
var _dust: Array[CPUParticles3D] = []
var _next_spark := 0
var _next_dust := 0


## The shared node, created (and connected to Events.hit_landed) the first time. null without a tree.
static func instance(tree: SceneTree) -> ImpactFx:
	if tree == null:
		return null
	if is_instance_valid(_instance):
		return _instance
	var fx := ImpactFx.new()
	fx.name = NODE_NAME
	fx.process_mode = Node.PROCESS_MODE_PAUSABLE
	tree.root.add_child.call_deferred(fx)
	_instance = fx
	fx._build()
	var events := tree.root.get_node_or_null(^"Events")
	if events and not events.hit_landed.is_connected(fx._on_hit_landed):
		events.hit_landed.connect(fx._on_hit_landed)
	return fx


## Sparks at `pos`; `power` 1 = normal hit, more = more sparks.
static func sparks(tree: SceneTree, pos: Vector3, power := 1.0, hot := true) -> void:
	var fx := instance(tree)
	if fx:
		fx._emit_sparks(pos, power, hot)


## Dust/debris cloud at `pos` (ground); `size` is the approximate radius in meters.
static func dust(tree: SceneTree, pos: Vector3, size := 1.0) -> void:
	var fx := instance(tree)
	if fx:
		fx._emit_dust(pos, size, DUST_COLOR, DUST_EDGE, 0.9)


## Healing: a green puff that rises and golden sparks around `pos` (Kaelen's feet).
static func heal(tree: SceneTree, pos: Vector3) -> void:
	var fx := instance(tree)
	if fx:
		fx._emit_dust(pos + Vector3.UP * 0.2, 0.6, HEAL_COLOR, HEAL_EDGE, 1.6)
		fx._emit_sparks(pos + Vector3.UP * 0.9, 0.7, true, HEAL_SPARK, HEAL_EDGE)


## Dark smoke with embers (a minion's death).
static func puff(tree: SceneTree, pos: Vector3, size := 0.8) -> void:
	var fx := instance(tree)
	if fx:
		fx._emit_dust(pos, size, Color(0.3, 0.27, 0.27), Color(0.12, 0.1, 0.1), 0.7)
		fx._emit_sparks(pos + Vector3.UP * 0.3, 0.5, true)


## Magic seal (MagicArea "circle") that forms over `form` s on the ground under `source`, holds
## for a moment and fades out. Meant to warn of the repel and the phase 2 roar.
static func seal(source: Node3D, radius: float, form: float, element := "fire") -> Node3D:
	if source == null or not source.is_inside_tree() or source.get_parent() == null:
		return null
	MagicArea.default_transparency = 1
	var area := MagicArea.new()
	area.element = element
	area.kind = "circle"
	area.radius = radius
	area.particles = false
	area.light = false
	area.one_shot = true
	area.appear = maxf(form, 0.05)
	area.duration = 0.1
	area.seed = randf() * 10.0
	source.get_parent().add_child(area)
	area.global_position = Vector3(source.global_position.x, source.global_position.y + 0.08, source.global_position.z)
	return area


## Samples of each effect so ShaderWarmup draws them once during loading.
static func warmup_samples() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var holder := ImpactFx.new()
	holder._build()
	for p: CPUParticles3D in [holder._sparks[0], holder._dust[0]]:
		holder.remove_child(p)
		p.one_shot = false   # whoever draws it sets emitting = true once inside the tree
		out.append(p)
	holder.free()
	MagicArea.default_transparency = 1
	StormFX.default_transparency = 1
	var ring := MagicArea.new()
	ring.kind = "circle"
	ring.element = "fire"
	ring.radius = 1.0
	ring.light = false
	ring.particles = false
	out.append(ring)
	out.append(SpellFx.warmup_sample())   # the Plague Arcanist's orb
	var ripple := MagicArea.new()   # beam impact ripple (BeamVfx)
	ripple.kind = "ripple"
	ripple.element = "fire"
	ripple.radius = 1.0
	ripple.light = false
	ripple.particles = false
	out.append(ripple)
	var gust := StormFX.new()
	gust.kind = "gust"
	gust.style = "ash"
	gust.radius = 1.0
	gust.height = 1.0
	gust.light = false
	out.append(gust)
	return out


func _on_hit_landed(pos: Vector3, surface: StringName) -> void:
	match surface:
		&"metal":
			_emit_sparks(pos, 1.6, true)
		&"bone":
			_emit_sparks(pos, 0.7, true)
			_emit_dust(pos, 0.45, Color(0.82, 0.8, 0.74), Color(0.55, 0.52, 0.48), 0.8)
		_:
			if ORGANIC.has(surface):
				var c: Array = ORGANIC[surface]
				_emit_sparks(pos, 1.1, false, c[0], c[1])
				_emit_dust(pos, 0.55, c[2], c[3], 0.8)
			else:
				_emit_sparks(pos, 0.8, false)


func _build() -> void:
	StormFX.default_transparency = 1
	for i in SPARK_POOL:
		var p := _make_particles(false)
		_sparks.append(p)
		add_child(p)
	for i in DUST_POOL:
		var p := _make_particles(true)
		_dust.append(p)
		add_child(p)


func _make_particles(is_dust: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = load(SPARK_SHADER) as Shader
	mat.set_shader_parameter(&"transparency", 1)
	mat.set_shader_parameter(&"dither_size", 1.0)
	p.direction = Vector3.UP
	var fade := Gradient.new()
	if is_dust:
		quad.size = Vector2.ONE * 1.1
		mat.set_shader_parameter(&"shape", 1.0)
		p.amount = 12
		p.lifetime = 0.8
		p.spread = 100.0
		p.initial_velocity_min = 0.6
		p.initial_velocity_max = 2.2
		p.gravity = Vector3(0.0, 0.4, 0.0)
		p.damping_min = 1.5
		p.damping_max = 2.5
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.5
		var grow := Curve.new()
		grow.add_point(Vector2(0.0, 0.4))
		grow.add_point(Vector2(1.0, 1.3))
		p.scale_amount_curve = grow
		fade.offsets = PackedFloat32Array([0.0, 0.15, 0.5, 1.0])
		fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	else:
		quad.size = Vector2.ONE * 0.17
		mat.set_shader_parameter(&"shape", 0.0)
		mat.set_shader_parameter(&"color", SPARK_COLOR)
		mat.set_shader_parameter(&"edge_color", SPARK_EDGE)
		mat.set_shader_parameter(&"energy", 1.9)
		p.amount = 14
		p.lifetime = 0.42
		p.spread = 70.0
		p.initial_velocity_min = 2.5
		p.initial_velocity_max = 6.0
		p.gravity = Vector3(0.0, -11.0, 0.0)
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.2
		fade.offsets = PackedFloat32Array([0.0, 0.1, 0.6, 1.0])
		fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	p.color_ramp = fade
	p.mesh = quad
	p.material_override = mat
	return p


func _emit_sparks(pos: Vector3, power: float, hot: bool, tint := Color(0, 0, 0, 0), edge := Color(0, 0, 0, 0)) -> void:
	if not is_inside_tree():
		return
	var p := _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % _sparks.size()
	var mat := p.material_override as ShaderMaterial
	var base := SPARK_COLOR if hot else Color(1.0, 0.7, 0.5)
	var rim := SPARK_EDGE if hot else Color(0.8, 0.12, 0.06)
	mat.set_shader_parameter(&"color", base if tint.a == 0.0 else tint)
	mat.set_shader_parameter(&"edge_color", rim if edge.a == 0.0 else edge)
	p.amount = clampi(roundi(14.0 * power), 4, 24)
	p.global_position = pos
	p.restart()
	p.emitting = true


func _emit_dust(pos: Vector3, size: float, color: Color, edge: Color, energy: float) -> void:
	if not is_inside_tree():
		return
	var p := _dust[_next_dust]
	_next_dust = (_next_dust + 1) % _dust.size()
	var mat := p.material_override as ShaderMaterial
	mat.set_shader_parameter(&"color", color)
	mat.set_shader_parameter(&"edge_color", edge)
	mat.set_shader_parameter(&"energy", energy)
	(p.mesh as QuadMesh).size = Vector2.ONE * 1.1 * clampf(size, 0.3, 3.0)
	p.initial_velocity_max = 1.4 + 0.8 * size
	p.global_position = pos
	p.restart()
	p.emitting = true
