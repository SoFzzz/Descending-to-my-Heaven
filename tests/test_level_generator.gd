extends TestCase
# Escenas generadas por level_builder.gd: la navegación horneada solo cubre el suelo, cada arena tiene
# 6 spawn_point y ninguna cámara de las escenas es `current` (el final las activa por código).

const ARENAS := ["arena_1", "arena_2", "arena_3"]
const NAV_MAX_Y := 2.1   # suelo a 0.5 + escalones de hasta 1.5 m; muros y techo estaban en 8–12 m


func test_nav_vertices_stay_near_floor() -> void:
	for id in ARENAS:
		var level := (load("res://scenes/levels/%s.tscn" % id) as PackedScene).instantiate()
		for region in level.find_children("*", "NavigationRegion3D", false, false):
			var verts: PackedVector3Array = (region as NavigationRegion3D).navigation_mesh.get_vertices()
			assert_true(verts.size() > 0, "%s/%s sin vértices" % [id, region.name])
			for v in verts:
				assert_true(v.y > -0.5 and v.y < NAV_MAX_Y, "%s/%s vértice a y=%.2f" % [id, region.name, v.y])
		level.free()


func test_six_spawn_points_per_arena() -> void:
	for id in ARENAS:
		var level := (load("res://scenes/levels/%s.tscn" % id) as PackedScene).instantiate()
		var spawns := level.get_node("Spawns").get_children()
		assert_eq(spawns.size(), 6, id)
		for i in 6:
			assert_true(level.get_node("Spawns/Spawn%d" % (i + 1)).is_in_group(&"spawn_point"), "%s Spawn%d" % [id, i + 1])
		level.free()


func test_no_level_camera_is_current() -> void:
	var level := (load("res://scenes/levels/arena_3.tscn") as PackedScene).instantiate()
	for cam in level.find_children("*", "Camera3D", true, false):
		assert_true(not (cam as Camera3D).current, "%s no debe ser current" % cam.name)
	level.free()
