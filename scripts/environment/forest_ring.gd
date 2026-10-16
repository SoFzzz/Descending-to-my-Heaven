class_name ForestRing
extends Node3D
## Anillo de árboles lejanos del exterior (modelos del pack "ps1-style tree pack").
##
## Se construye al entrar al árbol de escena: un MultiMeshInstance3D por tipo de árbol (1 llamada de dibujo
## cada uno) con posiciones, giros y escalas sacados de una semilla fija, así que el bosque es idéntico en
## cada partida. No se guarda como malla en la escena porque un MultiMesh no se serializa bien si el
## generador de niveles corre con --headless; la escena solo guarda estos parámetros.
## El material (forest_tree.gdshader) oscurece los árboles y los funde hacia el color de la bruma con la
## distancia y con la altura (los pies salen del mar de niebla).

const SHADER := preload("res://shaders/forest_tree.gdshader")

@export var tree_paths: PackedStringArray = []
@export var count := 90
@export var seed_value := 1
@export var center := Vector3.ZERO
@export var radius_range := Vector2(95.0, 130.0)
@export var base_range := Vector2(-12.0, -2.0)      # y del pie del árbol
@export var height_range := Vector2(30.0, 50.0)     # altura total en metros
@export var fade_near := 10.0
@export var fade_far := 230.0
@export var haze_color := Color(0.42, 0.46, 0.55)
@export var dark_mul := 0.38
@export var base_haze := 0.6                          # bruma en el pie (0 = ninguna)
## Si no está vacío, se colocan árboles solo en estas posiciones (con giro aleatorio) en vez del anillo.
@export var fixed_positions: PackedVector3Array = []

var multimeshes: Array[MultiMeshInstance3D] = []


func _ready() -> void:
	build()


func build() -> void:
	for m in multimeshes:
		m.queue_free()
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


# Carga el modelo, y calcula la transformación que lo deja con altura 1, pie en y=0 y centrado en x/z
# (el FBX trae su propia escala y rotación de eje en el nodo de la malla).
func _load_kind(path: String) -> Dictionary:
	var ps := load(path) as PackedScene
	if ps == null:
		return {}
	var root := ps.instantiate()
	var mi := _find_mesh(root)
	if mi == null:
		root.free()
		return {}
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n != root:
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


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null
