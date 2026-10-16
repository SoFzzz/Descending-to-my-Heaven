class_name ImpactFx
extends Node
## Efectos de impacto baratos con los recursos de "Storm & Wind 3D Free" y "Magic Circles 3D Free"
## (heyheythere, CC BY 4.0; addons/storm_wind y addons/magic_circles, sin activar los plugins):
##
## - Chispas en el punto de golpe (`sparks`), a partir de Events.hit_landed.
## - Polvo y escombro al rodar, en golpes al suelo de los jefes y al morir los esbirros (`dust`, `puff`).
## - Sello mágico en el suelo (`seal`): aviso de la repulsión y rugido de la fase 2.
##
## Es un único nodo colgado de la raíz (`ImpactFx.instance(tree)`) con reservas fijas de CPUParticles3D
## de un disparo que se reutilizan: golpear no crea nodos ni mallas, solo recoloca y reinicia un
## emisor. Todos usan `spark.gdshader` de Storm & Wind (un solo shader por compilar; ver
## `ShaderWarmup`, que lo dibuja una vez durante la carga). Con un transparente tramado (dither) para
## que encaje con el aspecto PSX.

const SPARK_SHADER := "res://addons/storm_wind/shaders/spark.gdshader"
const NODE_NAME := "ImpactFx"
const SPARK_POOL := 6
const DUST_POOL := 4
## Ataques de jefe que golpean el suelo: levantan polvo donde cae la hitbox.
const GROUND_ATTACKS: Array[StringName] = [&"slam", &"stomp", &"pounce"]

const SPARK_COLOR := Color(1.0, 0.92, 0.65)
const SPARK_EDGE := Color(1.0, 0.45, 0.12)
const DUST_COLOR := Color(0.62, 0.58, 0.52)
const DUST_EDGE := Color(0.38, 0.35, 0.32)

static var _instance: ImpactFx

var _sparks: Array[CPUParticles3D] = []
var _dust: Array[CPUParticles3D] = []
var _next_spark := 0
var _next_dust := 0


## El nodo compartido, creado (y conectado a Events.hit_landed) la primera vez. null sin árbol.
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


## Chispas en `pos`; `power` 1 = golpe normal, más = más chispas.
static func sparks(tree: SceneTree, pos: Vector3, power := 1.0, hot := true) -> void:
	var fx := instance(tree)
	if fx:
		fx._emit_sparks(pos, power, hot)


## Nube de polvo/escombro en `pos` (suelo); `size` en metros de radio aproximado.
static func dust(tree: SceneTree, pos: Vector3, size := 1.0) -> void:
	var fx := instance(tree)
	if fx:
		fx._emit_dust(pos, size, DUST_COLOR, DUST_EDGE, 0.9)


## Humo oscuro con brasas (muerte de un esbirro).
static func puff(tree: SceneTree, pos: Vector3, size := 0.8) -> void:
	var fx := instance(tree)
	if fx:
		fx._emit_dust(pos, size, Color(0.3, 0.27, 0.27), Color(0.12, 0.1, 0.1), 0.7)
		fx._emit_sparks(pos + Vector3.UP * 0.3, 0.5, true)


## Sello mágico (MagicArea "circle") que se forma durante `form` s sobre el suelo bajo `source`, se
## mantiene un instante y se desvanece. Pensado para avisar de la repulsión y el rugido de fase 2.
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


## Muestras de cada efecto para que ShaderWarmup las dibuje una vez durante la carga.
static func warmup_samples() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var holder := ImpactFx.new()
	holder._build()
	for p: CPUParticles3D in [holder._sparks[0], holder._dust[0]]:
		holder.remove_child(p)
		p.one_shot = false   # el que lo dibuja pone emitting = true ya dentro del árbol
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
		mat.set_shader_parameter(&"energy", 2.2)
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


func _emit_sparks(pos: Vector3, power: float, hot: bool) -> void:
	if not is_inside_tree():
		return
	var p := _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % _sparks.size()
	var mat := p.material_override as ShaderMaterial
	mat.set_shader_parameter(&"color", SPARK_COLOR if hot else Color(1.0, 0.7, 0.5))
	mat.set_shader_parameter(&"edge_color", SPARK_EDGE if hot else Color(0.8, 0.12, 0.06))
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
