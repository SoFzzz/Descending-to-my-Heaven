@tool
extends Node3D
## Escena de referencia de escalas (§7 del diseño). Reproduce el idle de cada modelo también
## en el editor (sin animación, los modelos de Mixamo se ven en pose de reposo, hundidos).
## Al ejecutarla (F6) imprime el tamaño medido de cada uno para compararlo con §7.4.

const EXPECTED := {
	"Kaelen": 1.70, "Skeleton": 1.75, "Knight": 2.10, "PlagueArcanist": 1.80,
	"TheWrapper": 2.00, "Blackhorn": 3.20, "BoneDragon": 3.6, "Ghidorah": 10.0,
}


func _ready() -> void:
	for model in $Models.get_children():
		var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player:
			for anim in ["idle", "idle-loop"]:
				if player.has_animation(anim):
					player.play(anim)
					break
	if Engine.is_editor_hint():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	for model in $Models.get_children():
		var box := _world_aabb(model)
		var expected: float = EXPECTED.get(model.name, 0.0)
		print("%-15s alto %5.2f m (esperado %5.2f)  largo %5.2f  suelo %+.2f" % [
			model.name, box.size.y, expected, max(box.size.x, box.size.z), box.position.y])


func _world_aabb(node: Node) -> AABB:
	# Caja que envuelve los huesos en su pose actual (funciona también sin ventana); para mallas
	# sin esqueleto se usa su AABB. Los huesos quedan un poco dentro de la malla: es aproximado.
	var pts: Array[Vector3] = []
	for skel: Skeleton3D in node.find_children("*", "Skeleton3D", true, false):
		for i in skel.get_bone_count():
			pts.append(skel.global_transform * skel.get_bone_global_pose(i).origin)
	if pts.is_empty():
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = mesh.global_transform * mesh.get_aabb()
			pts.append(b.position)
			pts.append(b.end)
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	return box
