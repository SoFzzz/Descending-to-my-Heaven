extends Control
## Escena de prueba del look PSX: la escena 3D se dibuja en un SubViewport de 320x240
## y se muestra escalada (filtro nearest) con el postproceso pp_band_dither.
## A cada malla de los modelos le pone un duplicado de psx_base.tres con la textura
## que traía su material original (así Kaelen conserva cuerpo y pelo por separado).

const PSX_BASE := preload("res://assets/materials/psx_base.tres")

@onready var _viewport: SubViewport = $SubViewport
@onready var _screen: TextureRect = $Screen

func _ready() -> void:
	_screen.texture = _viewport.get_texture()
	for model in get_tree().get_nodes_in_group("psx_model"):
		apply_psx(model)

static func apply_psx(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			var mat := PSX_BASE.duplicate() as ShaderMaterial
			if src is BaseMaterial3D and src.albedo_texture:
				mat.set_shader_parameter("albedoTex", src.albedo_texture)
				mat.set_shader_parameter("modulate_color", src.albedo_color)
			mi.set_surface_override_material(i, mat)
	for c in node.get_children():
		apply_psx(c)
