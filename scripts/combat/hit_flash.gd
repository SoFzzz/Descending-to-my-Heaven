class_name HitFlash
extends RefCounted
## Parpadeo de material al recibir un golpe: sube el uniform `hit_flash` de los materiales PSX
## (shaders/psx/psx_lit.gdshader) del modelo a 1 y lo baja a 0 en ~0,1 s. Barato: solo toca los
## materiales ya aplicados por PSX.apply_psx (nada de overlays ni pases extra) y un Tween atado al
## modelo (se libera con él y se pausa con el juego).

const DURATION := 0.1
const COLOR_ENEMY := Color(1.0, 1.0, 1.0)
const COLOR_PLAYER := Color(1.0, 0.25, 0.2)
const META_TWEEN := &"_hit_flash_tween"
const META_MATS := &"_hit_flash_mats"


## Parpadea el modelo `model` (nodo raíz de las mallas) con `color`.
static func flash(model: Node, color: Color = COLOR_ENEMY, duration: float = DURATION) -> void:
	if model == null or not model.is_inside_tree():
		return
	var mats := _materials(model)
	if mats.is_empty():
		return
	var old: Variant = model.get_meta(META_TWEEN) if model.has_meta(META_TWEEN) else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	_set_all(mats, 1.0, color)
	var tween := model.create_tween()
	model.set_meta(META_TWEEN, tween)
	tween.tween_method(_set_amount.bind(mats, color), 1.0, 0.0, duration)
	tween.tween_callback(_set_all.bind(mats, 0.0, color))


## Apaga el parpadeo ya.
static func clear(model: Node) -> void:
	if model == null:
		return
	var old: Variant = model.get_meta(META_TWEEN) if model.has_meta(META_TWEEN) else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	_set_all(_materials(model), 0.0, Color.WHITE)


## Valor actual del parpadeo del primer material (0 si no hay).
static func amount(model: Node) -> float:
	var mats := _materials(model)
	if mats.is_empty():
		return 0.0
	return float((mats[0] as ShaderMaterial).get_shader_parameter(&"hit_flash"))


## Modelo que parpadea cuando `node` (una Hurtbox) recibe un golpe: el hijo `Model` (o el de
## `model_path`) del primer ancestro jefe / esbirro / jugador.
static func model_for(node: Node) -> Node:
	var cur := node.get_parent()
	while cur != null:
		if cur.is_in_group(&"boss") or cur.is_in_group(&"enemy") or cur.is_in_group(&"player"):
			var path: Variant = cur.get(&"model_path")
			var model := cur.get_node_or_null(path if path is NodePath else ^"Model")
			return model
		cur = cur.get_parent()
	return null


static func color_for(node: Node) -> Color:
	var cur := node.get_parent()
	while cur != null:
		if cur.is_in_group(&"player"):
			return COLOR_PLAYER
		cur = cur.get_parent()
	return COLOR_ENEMY


static func _materials(model: Node) -> Array:
	var cached: Variant = model.get_meta(META_MATS) if model.has_meta(META_MATS) else null
	if cached is Array and not (cached as Array).is_empty():
		var ok := true
		for m in cached:
			if not is_instance_valid(m):
				ok = false
				break
		if ok:
			return cached
	var found: Array = []
	_collect(model, found)
	model.set_meta(META_MATS, found)
	return found


static func _collect(node: Node, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(i) as ShaderMaterial
			if mat and mat.shader and mat.shader.resource_path.ends_with("psx_lit.gdshader"):
				out.append(mat)
	for c in node.get_children():
		_collect(c, out)


static func _set_amount(value: float, mats: Array, color: Color) -> void:
	_set_all(mats, value, color)


static func _set_all(mats: Array, value: float, color: Color) -> void:
	for m in mats:
		if is_instance_valid(m):
			(m as ShaderMaterial).set_shader_parameter(&"hit_flash", value)
			(m as ShaderMaterial).set_shader_parameter(&"hit_flash_color", color)
