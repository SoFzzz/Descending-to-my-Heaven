class_name HitFlash
extends RefCounted
## Material flash on taking a hit: raises the `hit_flash` uniform of the model's PSX materials
## (shaders/psx/psx_lit.gdshader) to 1 and lowers it to 0 in ~0.1 s. Cheap: it only touches the
## materials already applied by PSX.apply_psx (no overlays or extra passes) and a Tween bound to the
## model (freed with it and paused with the game).

const DURATION := 0.1
const COLOR_ENEMY := Color(1.0, 1.0, 1.0)
const COLOR_PLAYER := Color(1.0, 0.25, 0.2)
const META_TWEEN := &"_hit_flash_tween"
const META_MATS := &"_hit_flash_mats"


## Flashes `model` (root node of the meshes) with `color`.
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


## Soft, progressive glow (rises to `peak` and falls to 0 in `duration` s): healing, buffs. Unlike
## `flash`, it never fully covers the texture (peak < 1).
static func glow(model: Node, color: Color, peak: float, duration: float) -> void:
	if model == null or not model.is_inside_tree():
		return
	var mats := _materials(model)
	if mats.is_empty():
		return
	var old: Variant = model.get_meta(META_TWEEN) if model.has_meta(META_TWEEN) else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	_set_all(mats, 0.0, color)
	var tween := model.create_tween()
	model.set_meta(META_TWEEN, tween)
	tween.tween_method(_set_pulse.bind(mats, color, peak), 0.0, 1.0, duration)
	tween.tween_callback(_set_all.bind(mats, 0.0, color))


## Turns the flash off immediately.
static func clear(model: Node) -> void:
	if model == null:
		return
	var old: Variant = model.get_meta(META_TWEEN) if model.has_meta(META_TWEEN) else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	_set_all(_materials(model), 0.0, Color.WHITE)


## Current flash value of the first material (0 if there is none).
static func amount(model: Node) -> float:
	var mats := _materials(model)
	if mats.is_empty():
		return 0.0
	return float((mats[0] as ShaderMaterial).get_shader_parameter(&"hit_flash"))


## Model that flashes when `node` (a Hurtbox) takes a hit: the `Model` child (or the one at
## `model_path`) of the first boss / minion / player ancestor.
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


static func _set_pulse(t: float, mats: Array, color: Color, peak: float) -> void:
	_set_all(mats, peak * sin(PI * clampf(t, 0.0, 1.0)), color)


static func _set_all(mats: Array, value: float, color: Color) -> void:
	for m in mats:
		if is_instance_valid(m):
			(m as ShaderMaterial).set_shader_parameter(&"hit_flash", value)
			(m as ShaderMaterial).set_shader_parameter(&"hit_flash_color", color)
