class_name SpellFx
extends RefCounted
## A minion's spell, readable from afar in three beats (Plague Arcanist's cast):
## 1. a magic circle (Magic Circles addon) draws itself on Kaelen's spot over the windup;
## 2. an orb with a short trail leaves the caster's hand and arcs onto the circle;
## 3. a burst (sparks, mist and a ripple) when it lands, the instant the zone deals damage.
## Everything is made in code, PS1-dithered and frees itself.

const ORB_RADIUS := 0.18
const ORB_ARC := 1.6          # m the orb rises above the straight line at mid flight
const RIPPLE_HOLD := 0.15
const CIRCLE_FADE := 0.35


## Magic circle of `radius` m that forms over `appear` s at `pos` (a child of `parent`, which must
## not move with the caster). Returns it so the caller moves it while it tracks and stops it.
static func circle(parent: Node, pos: Vector3, radius: float, appear: float, element := "poison") -> MagicArea:
	if parent == null or not parent.is_inside_tree():
		return null
	MagicArea.default_transparency = 1
	var area := MagicArea.new()
	area.kind = "circle"
	area.element = element
	area.radius = radius
	area.light = false
	area.particles = true
	area.appear = maxf(appear, 0.05)
	area.duration = 30.0   # held until stop()
	area.seed = randf() * 10.0
	parent.add_child(area)
	area.global_position = pos + Vector3.UP * 0.06
	return area


static func stop_circle(area: MagicArea) -> void:
	if area and is_instance_valid(area) and area.is_inside_tree():
		area.stop(CIRCLE_FADE)


## Orb from `from` to `to` in `time` s along an arc; `on_land` is called when it arrives (and the
## orb frees itself). The orb is a child of `parent` (the level), so it outlives a dying caster.
static func orb(parent: Node, from: Vector3, to: Vector3, time: float, color: Color, edge: Color) -> Node3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var ball := Node3D.new()
	ball.name = "SpellOrb"
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = ORB_RADIUS
	sphere.height = ORB_RADIUS * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	sphere.material = mat
	mesh.mesh = sphere
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball.add_child(mesh)
	var trail := CPUParticles3D.new()
	trail.amount = 16
	trail.lifetime = 0.35
	trail.local_coords = false
	trail.spread = 180.0
	trail.initial_velocity_min = 0.1
	trail.initial_velocity_max = 0.5
	trail.gravity = Vector3.ZERO
	trail.scale_amount_min = 0.5
	trail.scale_amount_max = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.16
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	tmat.albedo_color = edge
	tmat.vertex_color_use_as_albedo = true
	quad.material = tmat
	trail.mesh = quad
	var fade := Gradient.new()
	fade.colors = PackedColorArray([color, Color(edge.r, edge.g, edge.b, 0.0)])
	trail.color_ramp = fade
	ball.add_child(trail)
	parent.add_child(ball)
	ball.global_position = from
	var tween := ball.create_tween()
	tween.tween_method(_fly.bind(ball, from, to), 0.0, 1.0, maxf(time, 0.05))
	tween.tween_callback(ball.queue_free)
	return ball


## A still orb for ShaderWarmup (its unshaded emissive material and the trail compile on load).
static func warmup_sample() -> Node3D:
	var holder := Node3D.new()
	holder.name = "SpellOrbSample"
	var sphere := SphereMesh.new()
	sphere.radius = ORB_RADIUS
	sphere.height = ORB_RADIUS * 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	sphere.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	holder.add_child(mi)
	return holder


static func _fly(t: float, node: Node3D, from: Vector3, to: Vector3) -> void:
	if is_instance_valid(node):
		node.global_position = from.lerp(to, t) + Vector3.UP * ORB_ARC * 4.0 * t * (1.0 - t)


## The caster was interrupted: the orb bursts into a small puff where it is.
static func fizzle(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.is_inside_tree():
		var fx := ImpactFx.instance(node.get_tree())
		if fx:
			fx._emit_sparks(node.global_position, 0.6, false, Color(0.6, 1.0, 0.3), Color(0.15, 0.55, 0.08))
	node.queue_free()


## Impact of the spell at `pos` (radius `radius`): coloured sparks and mist plus a ripple.
static func burst(parent: Node, pos: Vector3, radius: float, color: Color, edge: Color, element := "poison") -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var fx := ImpactFx.instance(parent.get_tree())
	if fx:
		fx._emit_sparks(pos + Vector3.UP * 0.3, 1.6, false, color, edge)
		fx._emit_dust(pos + Vector3.UP * 0.2, radius * 0.9, color.darkened(0.3), edge, 1.2)
	MagicArea.default_transparency = 1
	var ripple := MagicArea.new()
	ripple.kind = "ripple"
	ripple.element = element
	ripple.radius = radius * 1.2
	ripple.light = false
	ripple.particles = false
	ripple.one_shot = true
	ripple.appear = 0.15
	ripple.duration = RIPPLE_HOLD
	parent.add_child(ripple)
	ripple.global_position = pos + Vector3.UP * 0.08
