class_name ForestRing
extends Node3D
## Ring of distant trees around the exterior (models from the "ps1-style tree pack").
##
## Built when entering the scene tree: one MultiMeshInstance3D per tree type (1 draw call each) with
## positions, rotations and scales drawn from a fixed seed, so the forest is identical in every run.
## It is not stored as a mesh in the scene because a MultiMesh does not serialise well when the level
## generator runs with --headless; the scene only stores these parameters.
## The material (forest_tree.gdshader) darkens the trees and blends them into the haze colour with
## distance and height (the trunks emerge from the fog sea).

const SHADER := preload("res://shaders/forest_tree.gdshader")

@export var tree_paths: PackedStringArray = []
@export var count := 90
@export var seed_value := 1
@export var center := Vector3.ZERO
@export var radius_range := Vector2(95.0, 130.0)
@export var base_range := Vector2(-12.0, -2.0)      # y of the tree base
@export var height_range := Vector2(30.0, 50.0)     # total height in metres
@export var fade_near := 10.0
@export var fade_far := 230.0
@export var haze_color := Color(0.42, 0.46, 0.55)
@export var dark_mul := 0.38
@export var base_haze := 0.6                          # haze at the base (0 = none)
## If not empty, trees are placed only at these positions (with random yaw) instead of the ring.
@export var fixed_positions: PackedVector3Array = []

var multimeshes: Array[MultiMeshInstance3D] = []


func _ready() -> void:
	build()


func build() -> void:
	for old in multimeshes:
		remove_child(old)   # leave the tree now so the new nodes can reuse the names
		old.queue_free()
	multimeshes.clear()
	if tree_paths.is_empty() or count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var kinds: Array[Dictionary] = []
	for p in tree_paths:
		var k := _load_kind(p)
		if not k.is_empty():
			kinds.append(k)
	if kinds.is_empty():
		return
	var per_kind: Array = []
	for _i in kinds.size():
		per_kind.append([])
	var total := fixed_positions.size() if not fixed_positions.is_empty() else count
	for k in total:
		if not fixed_positions.is_empty():
			var fh := rng.randf_range(height_range.x, height_range.y)
			per_kind[rng.randi() % kinds.size()].append([fixed_positions[k], rng.randf_range(0.0, TAU), fh])
			continue
		var ang := (k + rng.randf_range(-0.4, 0.4)) * TAU / count
		var rad := rng.randf_range(radius_range.x, radius_range.y)
		var h := rng.randf_range(height_range.x, height_range.y)
		var pos := center + Vector3(cos(ang) * rad, rng.randf_range(base_range.x, base_range.y), sin(ang) * rad)
		var yaw := rng.randf_range(0.0, TAU)
		var kind := rng.randi() % kinds.size()
		per_kind[kind].append([pos, yaw, h])
	for i in kinds.size():
		var items: Array = per_kind[i]
		if items.is_empty():
			continue
		var kd: Dictionary = kinds[i]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = kd.mesh
		mm.instance_count = items.size()
		var norm: Transform3D = kd.norm
		for j in items.size():
			var it: Array = items[j]
			var xf := Transform3D(Basis(Vector3.UP, it[1]).scaled(Vector3.ONE * it[2]), it[0]) * norm
			mm.set_instance_transform(j, xf)
			mm.set_instance_custom_data(j, Color(it[0].y, it[2], 0.0, 0.0))
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("albedo_tex", kd.tex)
		mat.set_shader_parameter("fade_near", fade_near)
		mat.set_shader_parameter("fade_far", fade_far)
		mat.set_shader_parameter("haze_color", haze_color)
		mat.set_shader_parameter("dark_mul", dark_mul)
		mat.set_shader_parameter("base_haze", base_haze)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Trees%d" % (i + 1)
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(center - Vector3(320, 120, 320), Vector3(640, 300, 640))
		add_child(mmi)
		multimeshes.append(mmi)


## Loads a model and computes the transform that leaves it with height 1, base at y=0 and centred on
## x/z (the FBX carries its own scale and axis rotation on the mesh node).
func _load_kind(path: String) -> Dictionary:
	var ps := load(path) as PackedScene
	if ps == null:
		return {}
	var root := ps.instantiate()
	var mi := _find_mesh(root)
	if mi == null or mi.mesh == null:
		root.free()
		return {}
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n is Node3D and n != root:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var mesh := mi.mesh
	var bb := xf * mesh.get_aabb()
	var h := maxf(bb.size.y, 0.001)
	var base := Vector3(bb.position.x + bb.size.x * 0.5, bb.position.y, bb.position.z + bb.size.z * 0.5)
	var norm := Transform3D(xf.basis * (1.0 / h), (xf.origin - base) / h)
	var tex: Texture2D = null
	var src := mesh.surface_get_material(0)
	if src is BaseMaterial3D:
		tex = (src as BaseMaterial3D).albedo_texture
	root.free()
	return {"mesh": mesh, "norm": norm, "tex": tex}


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
