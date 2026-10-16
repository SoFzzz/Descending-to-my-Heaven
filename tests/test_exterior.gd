extends TestCase
# Exterior generado por level_builder.gd: estanques que tapan los huecos de la isla, siluetas de bosque,
# capas de niebla y la puerta del templo (hueco, ExitTrigger y arco) intactos.

const EXTERIOR := "res://scenes/levels/exterior.tscn"
# Huecos que atraviesan `island_main` (cajas x, z medidas con rayos, en el espacio del nivel): ojos y nariz.
const HOLES := [Rect2(-25, -19, 9, 16), Rect2(26, -19, 9, 16), Rect2(-2, 0, 13, 13)]


func _level() -> Node:
	return (load(EXTERIOR) as PackedScene).instantiate()


func test_ponds_cover_every_island_hole() -> void:
	var level := _level()
	var ponds := level.get_node("Ponds").get_children()
	assert_eq(ponds.size(), HOLES.size(), "un estanque por hueco")
	for hole: Rect2 in HOLES:
		var covered := false
		for p: MeshInstance3D in ponds:
			var half: Vector2 = p.get_meta("pond_half")
			var c := Vector2(p.position.x, p.position.z)
			var inside := true
			for corner in [hole.position, Vector2(hole.end.x, hole.position.y), Vector2(hole.position.x, hole.end.y), hole.end]:
				var d: Vector2 = (corner - c).abs() / half
				if pow(d.x, 3.0) + pow(d.y, 3.0) > 1.0:   # misma máscara que water_psx.gdshader
					inside = false
			covered = covered or inside
		assert_true(covered, "hueco %s sin estanque" % str(hole))
	for p: MeshInstance3D in ponds:
		assert_true((p.mesh.material as ShaderMaterial) != null, "%s sin material de agua" % p.name)
	level.free()


func test_forest_rings_and_mist_exist() -> void:
	var level := _level()
	var rings := level.get_node("Forest").get_children()
	assert_eq(rings.size(), 3, "tres anillos de bosque")
	for r: MeshInstance3D in rings:
		assert_true(r.mesh.get_surface_count() == 1 and r.mesh.surface_get_array_len(0) >= 360, "%s vacío" % r.name)
	assert_true(level.get_node("Mist").get_child_count() >= 2, "capas de niebla")
	level.free()


func test_temple_door_keeps_trigger_and_opening() -> void:
	var level := _level()
	var trig := level.get_node("ExitTrigger") as Area3D
	assert_true(trig != null and trig.collision_mask == 2, "ExitTrigger sigue detectando al jugador")
	assert_true(level.get_node_or_null("Temple/Arch") != null, "arco de la puerta")
	assert_true(level.get_node_or_null("Temple/Body/Door") != null and level.get_node_or_null("Temple/Body/DoorTop") != null, "hueco")
	assert_true(level.get_node_or_null("Temple/Decor/LeafE") != null and level.get_node_or_null("Temple/Decor/LeafW") != null, "hojas")
	assert_true(level.get_node_or_null("Temple/Decor/Finial") != null, "remate de la torre")
	level.free()
