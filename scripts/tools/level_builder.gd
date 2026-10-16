extends SceneTree
## Parametric, deterministic level generator (design doc section 6). NOT procedural:
## the plan of each scene is in the tables below (LEVELS); to change the map edit a number
## and run it again. Overwrites the output scenes.
##
## Run from the project root:
##   godot --headless --path . -s res://scripts/tools/level_builder.gd            (all)
##   godot --headless --path . -s res://scripts/tools/level_builder.gd -- arena_2 (one)
##   ... -- out=C:/path/   writes to another folder (trailing slash) without touching the game scenes.
##
## Conventions: 1 unit = 1 m; south is +Z and north is -Z (Marker3D nodes face -Z, i.e. north,
## unless stated otherwise). All geometry is CSG with collision on layer 1 (`world`).
## Fixed names used by the gameplay code: PlayerStart, BossStart, Spawns/Spawn1..6 (group
## "spawn_point"), GateEntry, GateExit (AnimatableBody3D; meta "open_offset" = offset to open them),
## ExitTrigger, Gameplay and, in arena 3, Ending/EndingTrigger, Ending/EndingCam1..2.

const OUT_DIR := "res://scenes/levels/"
const TEX := "res://assets/environment/textures/"
const BASE_ENV := "res://assets/environment/base_env.tres"
const ELYSIA := "res://assets/characters/elysia/elysia.glb"
const KIT := "res://assets/environment/kit/"
const KIT_LIB := KIT + "dungeon_kit.meshlib"
const PSX_BASE := "res://assets/materials/psx_base.tres"
# MeshLibrary pieces (ids = order). See _source/tools/export_dungeon_kit.py for their shape.
const KIT_ITEMS := ["floor", "ceiling", "wall", "wall_skull", "wall_window", "wall_ruin", "wall_corner"]

const WALL_T := 1.0          # wall thickness
const GATE_W := 6.0          # arena gate: 6 x 6 m (section 7.3)
const GATE_H := 6.0
const STEP_H := 0.25         # step (section 7.3)
const STEP_D := 0.4
# Navigation bake volume: x +-40, z from -90 to 60 (reaches the back of Elysia's room),
# y from -0.5 to 1.5 m (the floor is at 0; steps above 1.5 m and everything high are left out).
const NAV_AABB := AABB(Vector3(-40, -0.5, -90), Vector3(80, 2.0, 150))

# --- Plan of each level --------------------------------------------------------------------
# shape: "rect" (size = interior width x depth) or "oct" (size.x = distance between faces).
# The interior = combat area of section 6.3 + a camera margin of 3-4 m per side.
const LEVELS := {
	"arena_1": {
		"title": "Catacomb (Bone Dragon)",
		"shape": "rect", "size": Vector2(40, 40), "height": 8.0, "ceiling": true,
		"output": "gridmap", "wall_rows": [["wall", "wall", "wall_skull"], ["wall"]],
		"floor_tex": "Floor512_indexed", "wall_tex": "concrete_512_indexed_dark",
		"tint": Color(0.85, 0.72, 0.6), "light": Color(1.0, 0.62, 0.35),
		# Pillar: [x, z, width/diameter, height, shape ("box"/"cyl"), tilt in degrees]
		"pillars": [[-9, -9, 2.0, 8.0, "box", 0], [9, -9, 2.0, 8.0, "box", 0],
			[-9, 9, 2.0, 8.0, "box", 0], [9, 9, 2.0, 8.0, "box", 0]],
		# Spawns behind the pillars (seen from the center) and on the east/west walls. The side ones
		# used to be at (+-18, 0), inside the camera cone at the start (only 2 valid points); at (+-18, 7)
		# they sit next to the side wall, outside the cone and > 8 m from PlayerStart (4 valid).
		"spawns": [[-12, -12], [12, -12], [-12, 12], [12, 12], [-18, 7], [18, 7]],
		"player_start": 16.0, "boss_start": Vector3(0, 0, -9),
		"torches": [[-19, -10], [19, -10], [-19, 10], [19, 10], [0, -19], [0, 19]],
		"exit": "stairs",
		"fog_end": 48.0,   # the base fog (30 m) hid the boss from the start
	},
	"arena_2": {
		"title": "Cloister (Blackhorn)",
		"shape": "oct", "size": Vector2(30, 30), "height": 8.0, "ceiling": true,
		"output": "gridmap", "wall_rows": [["wall"], ["wall", "wall_window"]],
		"floor_tex": "concrete_512_indexed", "wall_tex": "concrete_512_indexed",
		"tint": Color(0.82, 0.88, 1.0), "light": Color(0.75, 0.85, 1.0),
		"pillars": "ring6",   # 6 columns of 1.2 m in a ring of radius 8, at 30 deg + k*60 deg
		# Used to be "ring6" (radius 12.5): at the start all 6 were in the camera cone or < 8 m away. Now they go
		# toward the side and back walls (the entrance is to the south, Kaelen faces north).
		"spawns": [[-8, 10], [8, 10], [-12.5, 6], [12.5, 6], [-12.5, -6], [12.5, -6]],
		"player_start": 11.0, "boss_start": Vector3(0, 0, -6),
		"torches": [[-11, -6], [11, -6], [-11, 6], [11, 6], [0, 0]],
		"exit": "stairs",
		"fog_end": 40.0,
	},
	"arena_3": {
		"title": "Ruins (Ghidorah)",
		"shape": "rect", "size": Vector2(48, 48), "height": 12.0, "ceiling": false,
		"output": "gridmap", "wall_rows": [["wall"], ["wall", "wall_window"], ["wall_ruin"]],
		"floor_tex": "TerraCotta_512", "wall_tex": "concrete_512_indexed",
		"tint": Color(0.7, 0.7, 0.72), "light": Color(0.85, 0.85, 0.9),
		"pillars": [[-14, -14, 1.2, 5.0, "cyl", 0], [14, -14, 1.2, 3.0, "cyl", 0],
			[-14, 14, 1.2, 3.5, "cyl", 0], [14, 14, 1.2, 6.0, "cyl", 0],
			[-19, 0, 1.2, 2.0, "cyl", 0], [19, 2, 1.2, 7.0, "cyl", 75]],
		# (+-21, 9) instead of (-21, 0) and (21, -3): those were inside the camera cone at the start.
		"spawns": [[-16, -16], [16, -16], [-16, 16], [16, 16], [-21, 9], [21, 9]],
		"player_start": 20.0, "boss_start": Vector3(0, 0, -12),
		"torches": [[-22, -22], [22, -22], [-22, 22], [22, 22]],
		"exit": "ending",
		"corridor_len": 20.0,                 # corridor behind the locked door
		"ending_room": Vector3(12, 6, 12),    # Elysia's room: width, height, depth
		"fog_end": 70.0,
	},
}

# Exterior: main island (island_main, ~104 m, from float-islands) shifted so the path sits near
# Y=0; the path runs from south to north along x=0 up to the temple facade.
const EXTERIOR := {
	"island": "island_main", "island_pos": Vector3(5, 8, 0),
	# 7 m wide path; the invisible back wall is at path_start_z and Kaelen starts 6 m from it
	# (at 2 m the camera SpringArm hit the wall and ended up 1.7 m from Kaelen, not 4 m).
	"path_half_w": 3.5, "path_start_z": 40.0, "start_back": 6.0,
	# Center line of the path (x, z): straight up to z = 19, curves left around the hole of the
	# skull's nose, and returns to the x = 0 axis before the plaza.
	"path": [Vector2(0, 40), Vector2(0, 19), Vector2(-5.5, 13.5), Vector2(-5.5, 1), Vector2(0, -4.5),
		Vector2(0, -22)],
	"plaza": Rect2(-10, -31, 20, 9),                    # plaza in front of the door (x, z, width, depth)
	# Temple: `temple_z` = south face of the door; the rest of the design is in `_temple`.
	"temple_z": -31.0,
	# Door = opening with the outline of the kit arch (arch.glb, stretched x1.6 vertically): inner
	# width 3.2 m, height 3.2 m (the normal door of section 7.3 is 3 x 2; this is the temple one).
	"door": Vector2(3.2, 3.2),
	# Ponds that cover the holes of the island [center (x, z), half-axes (x, z), water y]: left eye, right
	# eye and nose of the skull (measured with rays against `island_main`; see AGENTS.md, sections 1.2 and 9.1).
	"ponds": [[Vector2(-17.5, -10.0), Vector2(11.0, 14.0), -0.3], [Vector2(27.5, -10.0), Vector2(9.5, 14.0), -0.3],
		[Vector2(6.0, 6.5), Vector2(9.5, 9.5), 1.4]],
	# Distant forest: rings of silhouettes (radius, base y, height) and mist layers [y, density].
	"forest_center": Vector3(5, 0, 0),
	"forest_rings": [
		{"count": 60, "radius": [95.0, 130.0], "base": [-12.0, -2.0], "height": [30.0, 50.0], "fade": [10.0, 230.0]},
		{"count": 70, "radius": [140.0, 190.0], "base": [-24.0, -10.0], "height": [45.0, 75.0], "fade": [10.0, 230.0]},
		{"count": 80, "radius": [200.0, 235.0], "base": [-34.0, -18.0], "height": [60.0, 100.0], "fade": [10.0, 230.0]}],
	"forest_trees": ["res://assets/environment/trees/tree01.fbx", "res://assets/environment/trees/tree02.fbx",
		"res://assets/environment/trees/tree03.fbx", "res://assets/environment/trees/tree05.fbx",
		"res://assets/environment/trees/tree06.fbx", "res://assets/environment/trees/tree07.fbx",
		"res://assets/environment/trees/tree08.fbx"],
	"mist_layers": [[-9.0, 0.45], [-22.0, 0.6], [-40.0, 0.85]],
	"islets": [["islet_round", Vector3(-75, -18, -35), 30.0], ["islet_long", Vector3(65, -28, 15), 70.0],
		["islet_l", Vector3(-60, -6, 55), 120.0], ["islet_small", Vector3(35, 6, -70), 0.0],
		["islet_hole", Vector3(110, -35, -70), 200.0]],
	"fog_end": 110.0,
}

# Alternative output folder (see the header), trailing slash included.
var _out_dir := OUT_DIR
var _mats := {}
var _kit_mat: Material
var _kit_meshes := {}


func _initialize() -> void:
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out_dir = a.substr(4)
		else:
			only.append(a)
	_kit_library()
	for id in LEVELS:
		if only.is_empty() or id in only:
			await _build_level(id, LEVELS[id])
	if only.is_empty() or "exterior" in only:
		await _build_exterior(EXTERIOR)
	quit()


# --- Exterior -------------------------------------------------------------------------------

func _build_exterior(cfg: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Exterior"
	get_root().add_child(root)
	var we := WorldEnvironment.new()
	var env := (load(BASE_ENV) as Environment).duplicate() as Environment
	env.fog_depth_begin = 25.0
	env.fog_depth_end = cfg.fog_end
	# The sky below the horizon was almost black (it looked like a void): the sky "ground" now uses the
	# haze color, which the sea of mist (_mist) and the forest silhouettes (_forest) also cover.
	var sky := env.sky.duplicate() as Sky
	var sky_mat := sky.sky_material.duplicate() as ProceduralSkyMaterial
	sky_mat.ground_horizon_color = Color(0.42, 0.46, 0.55)
	sky_mat.ground_bottom_color = Color(0.3, 0.33, 0.42)
	sky_mat.ground_curve = 0.25
	sky.sky_material = sky_mat
	env.sky = sky
	we.environment = env
	_node(root, we, "WorldEnvironment")
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.85, 0.85, 0.95)
	sun.light_energy = 0.9
	sun.rotation_degrees = Vector3(-40, -30, 0)
	_node(root, sun, "Sun")

	# Island with trimesh collision (~1100 triangles, cheap) on the world layer.
	var island := _node(root, Node3D.new(), "Island") as Node3D
	island.position = cfg.island_pos
	var src := (load("res://assets/environment/island/%s.glb" % cfg.island) as PackedScene).instantiate()
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_node(island, body, "Ground")
	for mi: MeshInstance3D in src.find_children("*", "MeshInstance3D", true, false):
		var m := MeshInstance3D.new()
		m.mesh = mi.mesh
		m.transform = mi.transform
		_node(body, m, "Mesh")
		var col := CollisionShape3D.new()
		col.shape = mi.mesh.create_trimesh_shape()
		col.transform = mi.transform
		_node(body, col, "Shape")
	src.free()
	var islets := _node(root, Node3D.new(), "Islets")
	for it in cfg.islets:
		var isl := (load("res://assets/environment/island/%s.glb" % it[0]) as PackedScene).instantiate() as Node3D
		isl.position = it[1]
		isl.rotation_degrees.y = it[2]
		_node(islets, isl, it[0].to_pascal_case())
	_ponds(root, cfg)
	_forest(root, cfg)
	_mist(root, cfg)

	for i in 3:
		await physics_frame
	var ground := func(x: float, z: float) -> float:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -60, z))
		var r := root.get_world_3d().direct_space_state.intersect_ray(q)
		return r.position.y if r else 0.0

	# Tiered ancient temple with door, columns, roofed wings and ruins (see _temple).
	var geo := _temple(root, cfg, ground)
	var tz: float = cfg.temple_z
	var base_y: float = geo.get_meta("base_y")
	var door: Vector2 = cfg.door

	# Path: polyline `path` (x, z) from south to north with 45 degree bends (the "skull" island has a hole
	# in the nose, x in [-1, 11], z in [2, 12], right on the straight line), low pillars every 8 m on the
	# sides and invisible walls enclosing it.
	var hw: float = cfg.path_half_w
	var z0: float = cfg.path_start_z
	var start_back: float = cfg.start_back
	var plaza: Rect2 = cfg.plaza
	var path: Array = cfg.path
	var deco := _node(root, Node3D.new(), "PathMarkers")
	var n := 0
	var dist := start_back + 2.0
	var path_len := 0.0
	for i in path.size() - 1:
		path_len += (path[i + 1] - path[i]).length()
	while dist < path_len - 6.0:
		var at := _path_at(path, dist)
		for sx in [-1, 1]:
			var q: Vector2 = at[0] + at[1] * sx * (hw + 0.8)
			var m := _kit_mesh("pillar_collapsed")
			m.position = Vector3(q.x, ground.call(q.x, q.y) - 0.3, q.y)
			n += 1
			_node(deco, m, "Marker%d" % n)
		dist += 8.0
	# Walls: one chain on each side of the polyline. At each bend the outer side is lengthened by
	# hw*tan(theta/2) (+0.2 overlap) and the inner side shortened by the same (otherwise it would block the path).
	var chunks := []   # [a, b, ext_a, ext_b]
	var last: int = path.size() - 1
	for i in last:
		var d: Vector2 = (path[i + 1] - path[i]).normalized()
		var nrm := Vector2(-d.y, d.x)
		var cross_a := 0.0
		var ang_a := 0.0
		var cross_b := 0.0
		var ang_b := 0.0
		if i > 0:
			var din: Vector2 = (path[i] - path[i - 1]).normalized()
			cross_a = din.cross(d)
			ang_a = absf(din.angle_to(d))
		if i < last - 1:
			var dout: Vector2 = (path[i + 2] - path[i + 1]).normalized()
			cross_b = d.cross(dout)
			ang_b = absf(d.angle_to(dout))
		for side in [-1, 1]:
			var ea := 0.0
			var eb := 0.0
			if ang_a > 0.001:
				ea = hw * tan(ang_a / 2.0) * (-1.0 if side * cross_a > 0.0 else 1.0)
				ea += 0.2 if ea > 0.0 else 0.0
			if ang_b > 0.001:
				eb = hw * tan(ang_b / 2.0) * (-1.0 if side * cross_b > 0.0 else 1.0)
				eb += 0.2 if eb > 0.0 else 0.0
			chunks.append([path[i] + nrm * side * hw, path[i + 1] + nrm * side * hw, ea, eb])
	var walls := StaticBody3D.new()
	walls.collision_layer = 1
	walls.collision_mask = 0
	_node(root, walls, "InvisibleWalls")
	var boxes := []   # [2D center, length, yaw, ground height]
	for c in chunks:
		var a: Vector2 = c[0]
		var b: Vector2 = c[1]
		var d := (b - a).normalized()
		a -= d * c[2]
		b += d * c[3]
		var total := (b - a).length()
		var pieces := maxi(1, ceili(total / 8.0))
		for k in pieces:
			var p0 := a + d * (total * k / pieces)
			var p1 := a + d * (total * (k + 1) / pieces)
			var mid := (p0 + p1) / 2
			boxes.append([mid, (p1 - p0).length() + 0.1, atan2(-d.y, d.x), ground.call(mid.x, mid.y)])
	# Back wall (perpendicular to the first segment, 6 m behind Kaelen) and plaza in front of the door.
	var pe: Vector2 = path[last]
	var plaza_walls := [[Vector2(-hw, pe.y), Vector2(plaza.position.x, plaza.end.y)],
		[Vector2(plaza.position.x, plaza.end.y), Vector2(plaza.position.x, plaza.position.y)],
		[Vector2(hw, pe.y), Vector2(plaza.end.x, plaza.end.y)],
		[Vector2(plaza.end.x, plaza.end.y), Vector2(plaza.end.x, plaza.position.y)]]
	for pw in plaza_walls:
		var a: Vector2 = pw[0]
		var b: Vector2 = pw[1]
		var mid := (a + b) / 2
		var ang := 0.0 if absf(b.y - a.y) < 0.01 else PI / 2
		boxes.append([mid, maxf(absf(b.x - a.x), absf(b.y - a.y)) + 0.5, 0.0 if ang == 0.0 else PI / 2, ground.call(mid.x, mid.y)])
	boxes.append([Vector2(path[0].x, z0), hw * 2 + 0.5, 0.0, ground.call(path[0].x, z0 - 1.0)])
	for i in boxes.size():
		var bx: Array = boxes[i]
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(bx[1], 30, 0.5)
		col.shape = box
		col.transform = Transform3D(Basis(Vector3.UP, bx[2]), Vector3(bx[0].x, bx[3] + 5, bx[0].y))
		_node(walls, col, "Wall%d" % (i + 1))

	var ps := _node(root, Marker3D.new(), "PlayerStart") as Marker3D
	ps.position = Vector3(0, ground.call(0.0, z0 - start_back), z0 - start_back)
	_node(root, Node3D.new(), "Gameplay")
	print("  path: start z=%.1f y=%.2f, door y=%.2f, length ~ %d m" % [ps.position.z, ps.position.y, base_y,
		int(path_len - start_back + (pe.y - tz))])
	_save(root, _out_dir + "exterior.tscn")
	root.queue_free()
	await process_frame


# Point of the polyline `dist` meters from the start: [position, normal to the left of the direction of travel].
func _path_at(path: Array, dist: float) -> Array:
	var left := dist
	for i in path.size() - 1:
		var seg: Vector2 = path[i + 1] - path[i]
		if left <= seg.length() or i == path.size() - 2:
			var d := seg.normalized()
			return [path[i] + d * minf(left, seg.length()), Vector2(-d.y, d.x)]
		left -= seg.length()
	return [path[0], Vector2.RIGHT]


# --- Exterior environment: ponds, distant forest and mist ----------------------------------

# The eyes and nose of the skull are holes through the island (the void was visible). Each pond is
# a water plane with a shader (per-vertex waves, quantized ripples) at the height of the hole's edge. It
# has no collision or floor: Kaelen never gets there (the invisible walls enclose the path and the plaza),
# so she could not fall there before either; the water only covers the view.
func _ponds(root: Node3D, cfg: Dictionary) -> void:
	var ponds := _node(root, Node3D.new(), "Ponds") as Node3D
	var shader := load("res://shaders/water_psx.gdshader") as Shader
	for i in cfg.ponds.size():
		var pd: Array = cfg.ponds[i]
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("water_tex", load("res://assets/environment/textures/water_sbs_elements12.png"))
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(pd[1].x * 2.0, pd[1].y * 2.0)
		mesh.subdivide_width = 10
		mesh.subdivide_depth = 10
		mesh.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(pd[0].x, pd[2], pd[0].y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("pond_half", pd[1])
		_node(ponds, mi, "Pond%d" % (i + 1))


# Rings of distant trees around the island and below its level, peeking out of the sea of mist: the
# edge looks like it continues into a huge forest. They use the models of the "ps1-style tree pack"
# (assets/environment/trees/). Each ring is a node with `ForestRing`, which builds its MultiMesh on entering
# the tree (with a fixed seed) and darkens and blends them into the haze by distance (shaders/forest_tree.gdshader).
# A MultiMesh is not saved when this generator runs with --headless; that is why only the parameters are saved.
# Kaelen's camera sees up to 300 m, so the rings stay inside that range.
func _forest(root: Node3D, cfg: Dictionary) -> void:
	var forest := _node(root, Node3D.new(), "Forest") as Node3D
	var script := load("res://scripts/environment/forest_ring.gd")
	var center: Vector3 = cfg.forest_center
	for i in cfg.forest_rings.size():
		var rg: Dictionary = cfg.forest_rings[i]
		var ring := Node3D.new()
		ring.set_script(script)
		ring.set("tree_paths", PackedStringArray(cfg.forest_trees))
		ring.set("count", rg.count)
		ring.set("seed_value", 7021 + i * 101)
		ring.set("center", center)
		ring.set("radius_range", Vector2(rg.radius[0], rg.radius[1]))
		ring.set("base_range", Vector2(rg.base[0], rg.base[1]))
		ring.set("height_range", Vector2(rg.height[0], rg.height[1]))
		ring.set("fade_near", rg.fade[0])
		ring.set("fade_far", rg.fade[1])
		_node(forest, ring, "Ring%d" % (i + 1))


# Horizontal mist layers (sea of mist) at different heights under the island.
func _mist(root: Node3D, cfg: Dictionary) -> void:
	var mist := _node(root, Node3D.new(), "Mist") as Node3D
	var shader := load("res://shaders/mist_layer.gdshader") as Shader
	var center: Vector3 = cfg.forest_center
	for i in cfg.mist_layers.size():
		var ml: Array = cfg.mist_layers[i]
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("density", ml[1])
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(700, 700)
		mesh.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(center.x, ml[0], center.z)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_node(mist, mi, "Layer%d" % (i + 1))


# --- Temple (exterior facade) ---------------------------------------------------------
# Tiered ancient temple (reference: tower of decreasing floors over a door with a pediment, columns
# on the sides and wings with sloped roofs). Only the design changes: same kit textures and those of
# `assets/environment/textures/`. Collision comes from the CSG body (door + wings) and a few boxes
# (columns, statues, rubble); the rest are meshes without collision (unreachable or decorative).
# Measures in meters; `f` = z of the south face of the door; the door opening and the `ExitTrigger` do not change.

func _temple(root: Node3D, cfg: Dictionary, ground: Callable) -> Node3D:
	var geo := _node(root, Node3D.new(), "Temple") as Node3D
	var stone := _mat("concrete_512_indexed_dark", Color(0.45, 0.46, 0.5))
	var trim := _mat("concrete_512_indexed", Color(0.58, 0.57, 0.55))
	var moss := _mat("concrete_512_indexed_dark", Color(0.3, 0.5, 0.26))
	var roof := _mat("TerraCotta_512", Color(0.5, 0.5, 0.3))
	var wood := _mat("TerraCotta_512", Color(0.3, 0.19, 0.11))
	var metal := _mat("metal_512", Color(0.55, 0.5, 0.45))
	var f: float = cfg.temple_z
	var b: float = ground.call(0.0, f - 1.0)
	geo.set_meta("base_y", b)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261015
	var dec := _node(geo, Node3D.new(), "Decor") as Node3D

	# Body with collision: door block (12 x 10) and two low wings; sunk 8 m into the terrain.
	var comb := _combiner(geo, "Body")
	_box(comb, "Gate", Vector3(12, 17, 10), Vector3(0, b + 0.5, f - 5), stone)
	for sx in [-1, 1]:
		_box(comb, "Wing%s" % ("E" if sx > 0 else "W"), Vector3(14.5, 13, 7), Vector3(sx * 13.25, b - 1.5, f - 5), stone)
	# Door opening: straight section (0.2 m of the arch x 1.6) + half-ellipse of a = 1.6, b = 1.8 x 1.6 m,
	# equal to the interior of the scaled arch.glb; the arch sits flush with the opening, with no wall strip.
	var door: Vector2 = cfg.door
	var arch_sy := 1.6
	var leg := 0.2 * arch_sy
	_box(comb, "Door", Vector3(door.x, leg, 3), Vector3(0, b + leg / 2, f), stone, CSGShape3D.OPERATION_SUBTRACTION)
	var dome := CSGCylinder3D.new()
	dome.radius = door.x / 2
	dome.height = 3
	dome.sides = 24
	dome.operation = CSGShape3D.OPERATION_SUBTRACTION
	dome.material = stone
	dome.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2).scaled_local(Vector3(1, 1, 1.8 * arch_sy / (door.x / 2))),
		Vector3(0, b + leg, f))
	_node(comb, dome, "DoorTop")

	# Facades with kit walls (stretched ~4 m pieces, 5 cm from the plane; no collision).
	var facade := _node(geo, Node3D.new(), "Facade")
	_facade(facade, "GateS", Vector3(0, b, f), 0.0, 12, 9, Vector2(4, 4), ["wall", "wall_ruin", "wall"])
	for sx in [-1, 1]:
		var tag := "E" if sx > 0 else "W"
		_facade(facade, "Wing%sS" % tag, Vector3(sx * 13.25, b, f - 1.5), 0.0, 14.5, 5, Vector2.ZERO,
			["wall", "wall_window", "wall", "wall_ruin"])
		_facade(facade, "Wing%sEnd" % tag, Vector3(sx * 20.5, b, f - 5), sx * PI / 2, 7, 5, Vector2.ZERO, ["wall", "wall_ruin"])
		_facade(facade, "Gate%sSide" % tag, Vector3(sx * 6.0, b + 5, f - 5.75), sx * PI / 2, 8.5, 4, Vector2.ZERO, ["wall"])
		_facade(facade, "Wing%sBack" % tag, Vector3(sx * 13.25, b, f - 8.5), PI, 14.5, 5, Vector2.ZERO, ["wall"])

	# Door: kit arch flush with the opening, jambs with columns, lintel with a skull frieze, pediment
	# with tympanum and wooden leaves open inward (the opening stays free: ExitTrigger and passage intact).
	var arch := _kit_mesh("arch")
	arch.position = Vector3(0, b, f + 0.5)
	arch.scale = Vector3(1, arch_sy, 1)
	_node(geo, arch, "Arch")
	var col_body := StaticBody3D.new()
	col_body.collision_layer = 1
	col_body.collision_mask = 0
	_node(geo, col_body, "DecorCollision")
	for sx in [-1, 1]:
		for k in 2:
			var tag2 := "%d%s" % [k, "E" if sx > 0 else "W"]
			var px: float = sx * (2.5 + k * 1.3)
			var sc := Vector3(0.8 - k * 0.12, 0.55 - k * 0.04, 0.8 - k * 0.12)
			var pil := _kit_mesh("pillar")
			pil.position = Vector3(px, b - 0.1, f + 1.3)
			pil.scale = sc
			_node(dec, pil, "Column" + tag2)
			_frame_box(col_body, "Column" + tag2, Vector3(1.2 * sc.x, 8.0 * sc.y, 1.2 * sc.z),
				Vector3(px, b + 4.0 * sc.y, f + 1.3))
			_mbox(dec, "Base" + tag2, Vector3(1.2 * sc.x + 0.3, 0.4, 1.2 * sc.z + 0.3), Vector3(px, b + 0.15, f + 1.3), trim)
	_mbox(dec, "Lintel", Vector3(9.2, 0.9, 1.9), Vector3(0, b + 4.75, f + 1.0), trim)
	_mbox(dec, "LintelCap", Vector3(9.6, 0.3, 2.2), Vector3(0, b + 5.35, f + 1.05), stone)
	for k in 3:
		_piece(dec, "Frieze%d" % k, "wall_skull", Vector3((k - 1) * 2.9, b + 4.35, f + 2.05), 0.0, Vector3(0.6, 0.2, 1))
	_mprism(dec, "Pediment", Vector3(9.6, 3.2, 1.6), Vector3(0, b + 5.5 + 1.6, f + 1.0), trim)
	_mprism(dec, "Tympanum", Vector3(7.0, 2.2, 0.6), Vector3(0, b + 5.7 + 1.1, f + 2.0), stone)
	_piece(dec, "TympanumSkull", "wall_skull", Vector3(0, b + 6.3, f + 2.35), 0.0, Vector3(0.55, 0.4, 1))
	for ax in [-4.7, 4.7]:
		_mcyl(dec, "Acroter%s" % ("E" if ax > 0 else "W"), 0.0, 0.4, 1.2, Vector3(ax, b + 5.95, f + 1.0), trim, 4)
	_mcyl(dec, "AcroterTop", 0.0, 0.45, 1.5, Vector3(0, b + 8.95, f + 1.0), trim, 4)
	for sx in [-1, 1]:   # wooden leaves ajar inward, with metal straps
		var leaf := Node3D.new()
		leaf.position = Vector3(sx * door.x / 2, b + 0.1, f - 0.1)
		leaf.rotation_degrees.y = -sx * 78.0
		_node(dec, leaf, "Leaf%s" % ("E" if sx > 0 else "W"))
		var lw := door.x / 2 - 0.05
		_mbox(leaf, "Wood", Vector3(lw, 2.9, 0.16), Vector3(-sx * lw / 2, 1.45, 0), wood)
		for k in 3:
			_mbox(leaf, "Strap%d" % k, Vector3(lw + 0.04, 0.16, 0.2), Vector3(-sx * lw / 2, 0.5 + k * 1.0, 0), metal)
	# Stone guardians beside the door (pedestal + body + head) with simple collision.
	for sx in [-1, 1]:
		var gx: float = sx * 7.6
		_mbox(dec, "Pedestal%d" % sx, Vector3(2.0, 1.3, 2.0), Vector3(gx, b + 0.65, f + 2.2), trim)
		_mbox(dec, "Beast%d" % sx, Vector3(1.2, 1.0, 1.9), Vector3(gx, b + 1.8, f + 2.2), stone)
		_mbox(dec, "BeastHead%d" % sx, Vector3(0.9, 0.85, 0.9), Vector3(gx, b + 2.15, f + 3.0), stone)
		_frame_box(col_body, "Guardian%d" % sx, Vector3(2.0, 2.4, 2.0), Vector3(gx, b + 1.2, f + 2.2))

	# Tiered tower: four decreasing floors with cornice, pediment on the south face and finial.
	_mbox(dec, "GateCornice", Vector3(13.6, 0.6, 11.4), Vector3(0, b + 9.3, f - 5), trim)
	var tiers := [Vector3(10.4, 5.0, 8.4), Vector3(8.4, 4.6, 7.0), Vector3(6.6, 4.2, 5.8), Vector3(4.8, 3.6, 4.4)]
	var ty := b + 9.6
	var zc := f - 5.0
	for i in tiers.size():
		var t: Vector3 = tiers[i]
		_mbox(dec, "Tier%d" % (i + 1), t, Vector3(0, ty + t.y / 2, zc), stone)
		_facade(dec, "Tier%dS" % (i + 1), Vector3(0, ty, zc + t.z / 2), 0.0, t.x, t.y, Vector2.ZERO,
			["wall_window", "wall"] if i % 2 == 0 else ["wall", "wall_skull", "wall"])
		_mbox(dec, "Cornice%d" % (i + 1), Vector3(t.x + 1.2, 0.5, t.z + 1.2), Vector3(0, ty + t.y + 0.25, zc), trim)
		_mprism(dec, "TierPediment%d" % (i + 1), Vector3(t.x * 0.62, t.y * 0.55, 0.9),
			Vector3(0, ty + t.y + 0.5 + t.y * 0.275, zc + t.z / 2 + 0.45), trim)
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				_mcyl(dec, "Acroter%d_%d_%d" % [i, sx, sz], 0.0, 0.32, 1.0,
					Vector3(sx * (t.x / 2 + 0.4), ty + t.y + 1.0, zc + sz * (t.z / 2 + 0.4)), trim, 4)
		ty += t.y + 0.5
	_mcyl(dec, "Finial", 0.0, 1.7, 4.5, Vector3(0, ty + 2.25, zc), trim, 4)
	_mcyl(dec, "FinialSpire", 0.0, 0.18, 2.2, Vector3(0, ty + 5.6, zc), metal, 6)

	# Wings with a gabled roof (ridge along X), broken tiles and moss.
	for sx in [-1, 1]:
		var tag := "E" if sx > 0 else "W"
		_mprism(dec, "Roof" + tag, Vector3(9.0, 3.0, 15.4), Vector3(sx * 13.25, b + 6.5, f - 5), roof, Vector3(0, 90, 0))
		_mbox(dec, "Eave" + tag, Vector3(15.0, 0.4, 0.6), Vector3(sx * 13.25, b + 5.1, f - 1.0), trim)
		for k in 3:
			var south := k % 2 == 0
			_mbox(dec, "RoofMoss%s%d" % [tag, k], Vector3(2.0 + rng.randf() * 2.0, 0.08, 1.4),
				Vector3(sx * (9.0 + rng.randf() * 10.0), b + 6.56, f - 5 + (2.25 if south else -2.25)),
				moss, Vector3(33.7 if south else -33.7, 0, 0))
		for k in 5:   # fallen tiles on the ridge
			_mbox(dec, "Tile%s%d" % [tag, k], Vector3(0.7, 0.12, 0.5),
				Vector3(sx * (8.0 + rng.randf() * 11.0), b + 8.1, f - 5 + rng.randf_range(-0.6, 0.6)), roof,
				Vector3(rng.randf_range(-20, 20), rng.randf() * 180.0, rng.randf_range(-20, 20)))

	# Big tree with roots against the west wing (as in the reference), bushes and rubble.
	var tree := Vector3(-11.0, b, f - 3.0)
	# The tree is a model of the PS1 tree pack (tree02) with the same script as the forest, with little haze.
	var ft := Node3D.new()
	ft.set_script(load("res://scripts/environment/forest_ring.gd"))
	ft.set("tree_paths", PackedStringArray(["res://assets/environment/trees/tree02.fbx"]))
	ft.set("fixed_positions", PackedVector3Array([tree]))
	ft.set("seed_value", 31)
	ft.set("center", tree)
	ft.set("height_range", Vector2(17.0, 17.0))
	ft.set("fade_near", 400.0)
	ft.set("fade_far", 500.0)
	ft.set("base_haze", 0.0)
	ft.set("dark_mul", 0.62)
	_node(dec, ft, "Tree")
	for k in 6:   # keeps the random sequence of the bushes below
		rng.randf()
	for k in 12:
		var bx := rng.randf_range(-19.0, 19.0)
		if absf(bx) < 5.0:
			bx = signf(bx + 0.01) * (5.0 + rng.randf() * 3.0)
		var bz := f + (rng.randf_range(0.2, 1.6) if absf(bx) < 8.0 else rng.randf_range(-1.2, 0.8))
		if bx > -13.0 and bx < -9.0:
			continue
		_msphere(dec, "Bush%d" % k, 0.5 + rng.randf() * 0.5, Vector3(bx, b + 0.3, bz), moss, Vector3(1.3, 0.8, 1.1))
	for k in 9:   # fallen stones with collision (tilted boxes), spread over the plaza
		var rx := rng.randf_range(-9.0, 9.0)
		if absf(rx) < 2.5:
			rx += signf(rx + 0.01) * 3.0
		var rz := f + rng.randf_range(2.8, 8.0)
		var sz := Vector3(rng.randf_range(0.6, 1.5), rng.randf_range(0.35, 0.8), rng.randf_range(0.6, 1.3))
		var gy: float = ground.call(rx, rz)
		var rot := Vector3(rng.randf_range(-10, 10), rng.randf() * 180.0, rng.randf_range(-10, 10))
		_mbox(dec, "Rubble%d" % k, sz, Vector3(rx, gy + sz.y * 0.3, rz), stone if k % 3 else moss, rot)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sz * 0.9
		cs.shape = bs
		cs.transform = Transform3D(Basis.from_euler(rot * PI / 180.0), Vector3(rx, gy + sz.y * 0.3, rz))
		_node(col_body, cs, "Rubble%d" % k)
	for sx in [-1, 1]:   # fallen kit column on each side of the plaza
		var pc := _kit_mesh("pillar_collapsed")
		pc.position = Vector3(sx * 7.6, ground.call(sx * 7.6, f + 6.5) - 0.2, f + 6.5)
		pc.rotation_degrees.y = sx * 35.0
		pc.scale = Vector3(1.2, 1.0, 1.2)
		_node(dec, pc, "FallenPillar%d" % sx)

	_area(root, "ExitTrigger", Vector3(door.x, 3, 1.5), Vector3(0, b + 1.5, f + 0.5)).set_meta("doc", "Kaelen enters the temple → GameState.advance_level() (A)")
	var torch := OmniLight3D.new()
	torch.light_color = Color(1.0, 0.6, 0.3)
	torch.light_energy = 2.0
	torch.omni_range = 10
	torch.position = Vector3(0, b + 5, f + 3)
	_node(geo, torch, "DoorLight")
	return geo


func _mbox(parent: Node, name: String, size: Vector3, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	return _mesh_node(parent, name, m, pos, rot_deg)


# Triangular prism: the base (x) and height (y) are the triangle; `size.z` is the extrusion length.
func _mprism(parent: Node, name: String, size: Vector3, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var m := PrismMesh.new()
	m.size = size
	m.material = mat
	return _mesh_node(parent, name, m, pos, rot_deg)


func _mcyl(parent: Node, name: String, r_top: float, r_bottom: float, height: float, pos: Vector3, mat: Material,
		sides := 8) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = height
	m.radial_segments = sides
	m.rings = 1
	m.material = mat
	var mi := _mesh_node(parent, name, m, pos, Vector3.ZERO)
	if sides == 4:
		mi.rotation_degrees.y = 45.0
	return mi


func _msphere(parent: Node, name: String, radius: float, pos: Vector3, mat: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 8
	m.rings = 4
	m.material = mat
	var mi := _mesh_node(parent, name, m, pos, Vector3.ZERO)
	mi.scale = scl
	return mi


func _mesh_node(parent: Node, name: String, mesh: Mesh, pos: Vector3, rot_deg: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return _node(parent, mi, name) as MeshInstance3D


# Kit wall face: `pos` = bottom center of the face, `yaw` makes +Z face outward. ~4 m pieces
# stretched to fill width x height; `gap` (width, height) leaves a centered opening at the bottom (the door).
func _facade(parent: Node, name: String, pos: Vector3, yaw: float, width: float, height: float, gap: Vector2,
		items: Array = ["wall"]) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var rows := maxi(1, ceili(height / 4.0))
	var sy := height / (4.0 * rows)
	var segs: Array = [[-width / 2, width / 2, 0]]
	if gap.x > 0.0:
		var gr := ceili(gap.y / 4.0)
		segs = [[-width / 2, -gap.x / 2, 0], [gap.x / 2, width / 2, 0], [-gap.x / 2, gap.x / 2, gr]]
	var n := 0
	for sg in segs:
		var t0: float = sg[0]
		var t1: float = sg[1]
		var cols := maxi(1, roundi((t1 - t0) / 4.0))
		var sx := (t1 - t0) / cols / 4.0
		for r in range(sg[2], rows):
			for c in cols:
				var tc := t0 + (c + 0.5) * (t1 - t0) / cols
				n += 1
				_piece(parent, "%s_%d" % [name, n], items[(n - 1) % items.size()],
					pos + basis * Vector3(tc, r * 4.0 * sy, 1.05), yaw, Vector3(sx, sy, 1))


# Copy of a kit mesh with the PSX material as a loose MeshInstance3D (saved in the scene).
func _kit_mesh(name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _kit_mesh_res(name)
	return mi


# --- Level ----------------------------------------------------------------------------------

func _build_level(id: String, cfg: Dictionary) -> void:
	var root := Node3D.new()
	root.name = id.to_pascal_case()
	root.set_meta("title", cfg.title)
	get_root().add_child(root)

	_environment(root, cfg)
	var geo := _node(root, Node3D.new(), "Geometry")
	geo.add_to_group("nav_source", true)
	var w: float = cfg.size.x
	var d: float = cfg.size.y
	var h: float = cfg.height
	var half_d: float = d * 0.5 if cfg.shape == "rect" else w * 0.5

	# Floor, ceiling and walls with the gate openings (south and north).
	var floor_mat := _mat(cfg.floor_tex, cfg.tint)
	var wall_mat := _mat(cfg.wall_tex, cfg.tint)
	var shell := _combiner(geo, "Shell")
	if cfg.get("output", "csg") == "gridmap":
		if cfg.shape == "oct":
			_oct_shell(geo, shell, cfg, wall_mat)
		else:
			_grid_shell(geo, shell, cfg, wall_mat)
	elif cfg.shape == "rect":
		_box(shell, "Floor", Vector3(w + 2 * WALL_T, 1, d + 2 * WALL_T), Vector3(0, -0.5, 0), floor_mat)
		_box(shell, "WallN", Vector3(w + 2 * WALL_T, h, WALL_T), Vector3(0, h / 2, -d / 2 - WALL_T / 2), wall_mat)
		_box(shell, "WallS", Vector3(w + 2 * WALL_T, h, WALL_T), Vector3(0, h / 2, d / 2 + WALL_T / 2), wall_mat)
		_box(shell, "WallE", Vector3(WALL_T, h, d), Vector3(w / 2 + WALL_T / 2, h / 2, 0), wall_mat)
		_box(shell, "WallW", Vector3(WALL_T, h, d), Vector3(-w / 2 - WALL_T / 2, h / 2, 0), wall_mat)
		if cfg.ceiling:
			_box(shell, "Ceiling", Vector3(w + 2 * WALL_T, 1, d + 2 * WALL_T), Vector3(0, h + 0.5, 0), wall_mat)
	else:
		# Octagon with one face looking south: vertex radius = apothem / cos(22.5 deg).
		var apo := w * 0.5
		var r_in := apo / cos(PI / 8)
		var r_out := (apo + WALL_T) / cos(PI / 8)
		_cyl(shell, "Floor", r_out, 1, Vector3(0, -0.5, 0), floor_mat, 8)
		_cyl(shell, "Walls", r_out, h, Vector3(0, h / 2, 0), wall_mat, 8)
		_cyl(shell, "Interior", r_in, h, Vector3(0, h / 2, 0), wall_mat, 8,
			CSGShape3D.OPERATION_SUBTRACTION)
		if cfg.ceiling:
			_cyl(shell, "Ceiling", r_out, 1, Vector3(0, h + 0.5, 0), wall_mat, 8)
	for side in [1, -1] if cfg.get("output", "csg") == "csg" else []:   # 1 = south, -1 = north
		_box(shell, "Cut" + ("S" if side == 1 else "N"), Vector3(GATE_W, GATE_H, WALL_T * 3),
			Vector3(0, GATE_H / 2, side * (half_d + WALL_T / 2)), wall_mat, CSGShape3D.OPERATION_SUBTRACTION)

	_pillars(geo, cfg, wall_mat)
	_entry_hall(geo, half_d, floor_mat, wall_mat)
	var exit_info: Dictionary
	if cfg.exit == "stairs":
		exit_info = _exit_stairs(geo, half_d, floor_mat, wall_mat)
	else:
		exit_info = _exit_ending(root, geo, cfg, half_d, floor_mat, wall_mat)

	_gates(root, half_d)
	_markers(root, cfg)
	_triggers(root, exit_info)
	_torches(root, cfg)
	_node(root, Node3D.new(), "Gameplay")

	# Wait for the CSG to generate its meshes and bake the navigation.
	for i in 3:
		await process_frame
	_navigation(root, "NavigationSmall", 1, 0.5, 2.0, 0.25, 35.0)
	_navigation(root, "NavigationLarge", 2, 2.5, 4.0, 0.5, 25.0)

	_save(root, _out_dir + id + ".tscn")
	root.queue_free()
	await process_frame


func _environment(root: Node3D, cfg: Dictionary) -> void:
	var we := WorldEnvironment.new()
	var env := load(BASE_ENV) as Environment
	if cfg.has("fog_end"):
		env = env.duplicate()
		env.fog_depth_end = cfg.fog_end
	we.environment = env
	_node(root, we, "WorldEnvironment")
	var sun := DirectionalLight3D.new()
	sun.light_color = cfg.light
	sun.light_energy = 0.35 if cfg.ceiling else 0.8
	sun.rotation_degrees = Vector3(-55, 30, 0)
	_node(root, sun, "Sun")


func _pillars(geo: Node3D, cfg: Dictionary, mat: Material) -> void:
	var list: Array = []
	if typeof(cfg.pillars) == TYPE_STRING:   # "ring6"
		for k in 6:
			var a := deg_to_rad(30.0 + 60.0 * k)
			list.append([8.0 * sin(a), 8.0 * cos(a), 1.2, cfg.height, "cyl", 0])
	else:
		list = cfg.pillars
	# Kit pillars (pillar.glb: 1.2 x 8 m, origin at the base) scaled to the width and height of the
	# table, with a cylindrical StaticBody3D on the world layer. The low ones use pillar_collapsed.
	var group := _node(geo, Node3D.new(), "Pillars")
	for i in list.size():
		var p: Array = list[i]
		var wid: float = p[2]
		var hgt: float = p[3]
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = Vector3(p[0], 0, p[1])
		_node(group, body, "Pillar%d" % (i + 1))
		var broken := hgt < 4.0
		var src := _kit_instance("pillar_collapsed" if broken else "pillar")
		var piece := MeshInstance3D.new()   # copy of the mesh (what a .glb instantiates is not saved)
		piece.mesh = _first_mesh(src).mesh
		src.free()
		piece.scale = Vector3(wid / 1.2, hgt / (2.06 if broken else 8.0), wid / 1.2)
		_node(body, piece, "Mesh")
		var col := CollisionShape3D.new()
		if p[4] == "box":
			var bs := BoxShape3D.new()
			bs.size = Vector3(wid, hgt, wid)
			col.shape = bs
		else:
			var cs := CylinderShape3D.new()
			cs.radius = wid / 2
			cs.height = hgt
			col.shape = cs
		col.position.y = hgt / 2
		_node(body, col, "Shape")
		if p[5] != 0:   # fallen pillar: tilts over its base
			body.rotation_degrees.z = p[5]
			body.position.y = 0.6


# South hall: 6 m landing behind the entry gate and a staircase going down (arrival from below).
func _entry_hall(geo: Node3D, half_d: float, floor_mat: Material, wall_mat: Material) -> void:
	var z0 := half_d + WALL_T
	var comb := _combiner(geo, "EntryHall")
	var steps := 8
	_corridor(comb, z0, 6.0 + steps * STEP_D + 1.0, 1, GATE_W, GATE_H + 1, floor_mat, wall_mat)
	var base_d := steps * STEP_D + 1.0   # solid block under the staircase to carve it out of
	_box(comb, "StairBase", Vector3(GATE_W, 3, base_d), Vector3(0, -1.5, z0 + 6.0 + base_d / 2), floor_mat)
	_stairs(comb, Vector3(0, 0, z0 + 6.0), 1, -1, steps, GATE_W, floor_mat)
	_stair_ramp(geo, "EntryRamp", Vector3(0, 0, z0 + 6.0), 1, -1, steps, GATE_W)


# North exit of floors 1 and 2: corridor + staircase climbing 4 m + landing with ExitTrigger.
func _exit_stairs(geo: Node3D, half_d: float, floor_mat: Material, wall_mat: Material) -> Dictionary:
	var z0 := -(half_d + WALL_T)
	var steps := 16
	var run := 3.0 + steps * STEP_D + 4.0
	var comb := _combiner(geo, "ExitHall")
	_corridor(comb, z0, run, -1, GATE_W, GATE_H + 4.5, floor_mat, wall_mat)
	_stairs(comb, Vector3(0, 0, z0 - 3.0), -1, 1, steps, GATE_W, floor_mat)
	_stair_ramp(geo, "ExitRamp", Vector3(0, 0, z0 - 3.0), -1, 1, steps, GATE_W)
	var top := steps * STEP_H
	_box(comb, "Landing", Vector3(GATE_W, top, 4.0), Vector3(0, top / 2, z0 - run + 2.0), floor_mat)
	return {"pos": Vector3(0, top + 1.0, z0 - run + 2.0), "size": Vector3(GATE_W, 2.0, 3.0)}


# North exit of floor 3: locked door (GateExit) -> corridor -> Elysia's room.
func _exit_ending(root: Node3D, geo: Node3D, cfg: Dictionary, half_d: float,
		floor_mat: Material, wall_mat: Material) -> Dictionary:
	var z0 := -(half_d + WALL_T)
	var length: float = cfg.corridor_len
	var room: Vector3 = cfg.ending_room
	var comb := _combiner(geo, "EndingHall")
	_corridor(comb, z0, length, -1, GATE_W, GATE_H + 1, floor_mat, wall_mat)
	# Room: hollow box with an opening toward the corridor.
	var zc := z0 - length - room.z / 2
	var room_mat := wall_mat   # dungeon stone (it used to be golden): the north wall and the altar match the room
	_box(comb, "RoomFloor", Vector3(room.x + 2, 1, room.z + 2), Vector3(0, -0.5, zc), floor_mat)
	_box(comb, "RoomCeiling", Vector3(room.x + 2, 1, room.z + 2), Vector3(0, room.y + 0.5, zc), wall_mat)
	_box(comb, "RoomWallN", Vector3(room.x + 2, room.y, 1), Vector3(0, room.y / 2, zc - room.z / 2 - 0.5), room_mat)
	_box(comb, "RoomWallS", Vector3(room.x + 2, room.y, 1), Vector3(0, room.y / 2, zc + room.z / 2 + 0.5), wall_mat)
	_box(comb, "RoomWallE", Vector3(1, room.y, room.z), Vector3(room.x / 2 + 0.5, room.y / 2, zc), wall_mat)
	_box(comb, "RoomWallW", Vector3(1, room.y, room.z), Vector3(-room.x / 2 - 0.5, room.y / 2, zc), wall_mat)
	_box(comb, "RoomDoor", Vector3(GATE_W, GATE_H, 3), Vector3(0, GATE_H / 2, zc + room.z / 2 + 0.5),
		wall_mat, CSGShape3D.OPERATION_SUBTRACTION)
	_break_room(comb, room, zc, room_mat)
	# Altar (blockout; replaced by the Modular Dungeon altar in the art phase).
	var altar_z := zc - room.z / 2 + 2.0
	_box(comb, "AltarStep", Vector3(6, 0.5, 4), Vector3(0, 0.25, altar_z), room_mat)
	_box(comb, "Altar", Vector3(2.4, 1.0, 1.2), Vector3(0, 1.0, altar_z - 0.6), room_mat)

	var ending := _node(root, Node3D.new(), "Ending")
	var elysia := (load(ELYSIA) as PackedScene).instantiate() as Node3D
	elysia.name = "Elysia"
	elysia.position = Vector3(0, 0.5, altar_z + 1.0)   # on the step, facing south (corridor)
	ending.add_child(elysia)
	var trig := _area(ending, "EndingTrigger", Vector3(room.x - 2, 3, 3), Vector3(0, 1.5, altar_z + 5.0))
	trig.set_meta("doc", "Kaelen in front of Elysia → ending_director.gd (A)")
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.6)
	light.light_energy = 1.6
	light.omni_range = 10
	light.position = Vector3(0, 4, altar_z + 2)
	_node(ending, light, "AltarLight")
	_camera(ending, "EndingCam1", Vector3(3.5, 2.2, altar_z + 6.5), Vector3(0, 1.3, altar_z + 1))
	_camera(ending, "EndingCam2", Vector3(0, 1.6, zc + room.z / 2 + 2), Vector3(0, 1.3, altar_z + 1))
	_node(ending, Marker3D.new(), "KaelenEndPoint").position = Vector3(0, 0, altar_z + 3.0)
	# The floor 3 ExitTrigger does not lead to another floor: it stays in the corridor in case gameplay needs it.
	return {"pos": Vector3(0, 1.5, z0 - 3.0), "size": Vector3(GATE_W, 3.0, 2.0)}


# Broken Elysia room: irregular opening in the north wall (reaches the ceiling) and an open ceiling in
# that corner; the outside, the rubble and the fall come from scenes/props/ending_room.tscn.
func _break_room(comb: CSGCombiner3D, room: Vector3, zc: float, mat: Material) -> void:
	var wz := zc - room.z / 2 - 0.5
	# [name, size, position (x, y, z), Z rotation (degrees), Y rotation (degrees)]
	var cuts := [
		["BreakWallA", Vector3(6.0, 3.6, 3.0), Vector3(0.3, 3.2, wz), 0.0, 0.0],
		["BreakWallB", Vector3(3.2, 2.6, 3.0), Vector3(-1.6, 5.0, wz), 14.0, 0.0],
		["BreakWallC", Vector3(2.6, 2.6, 3.0), Vector3(-3.4, 2.0, wz), 28.0, 0.0],
		["BreakWallD", Vector3(2.0, 3.0, 3.0), Vector3(3.8, 4.6, wz), -22.0, 0.0],
		["BreakCeilA", Vector3(5.0, 3.0, 4.5), Vector3(0.8, 6.5, wz + 2.4), 0.0, 14.0],
		["BreakCeilB", Vector3(2.4, 3.0, 2.6), Vector3(-2.4, 6.5, wz + 3.2), 0.0, -26.0],
	]
	for c in cuts:
		var b := _box(comb, c[0], c[1], c[2], mat, CSGShape3D.OPERATION_SUBTRACTION)
		b.rotation_degrees = Vector3(0, c[4], c[3])


func _corridor(comb: CSGCombiner3D, z0: float, length: float, dir: int, width: float,
		height: float, floor_mat: Material, wall_mat: Material) -> void:
	var zc := z0 + dir * length / 2
	var tag := "S" if dir == 1 else "N"
	_box(comb, "Floor" + tag, Vector3(width + 2, 1, length), Vector3(0, -0.5, zc), floor_mat)
	_box(comb, "Roof" + tag, Vector3(width + 2, 1, length), Vector3(0, height + 0.5, zc), wall_mat)
	_box(comb, "SideE" + tag, Vector3(1, height, length), Vector3(width / 2 + 0.5, height / 2, zc), wall_mat)
	_box(comb, "SideW" + tag, Vector3(1, height, length), Vector3(-width / 2 - 0.5, height / 2, zc), wall_mat)
	_box(comb, "End" + tag, Vector3(width + 2, height, 1), Vector3(0, height / 2, z0 + dir * (length + 0.5)), wall_mat)


# 0.25 m steps: dir = direction along Z (1 south, -1 north); up = 1 climbs, -1 descends.
func _stairs(comb: CSGCombiner3D, start: Vector3, dir: int, up: int, steps: int, width: float,
		mat: Material) -> void:
	for i in steps:
		var top := start.y + up * (i + 1) * STEP_H
		var z := start.z + dir * (i + 0.5) * STEP_D
		if up > 0:
			_box(comb, "Step%d" % i, Vector3(width, top, STEP_D), Vector3(0, top / 2, z), mat)
		else:   # descending: carved out of the floor (arrival stairs are only seen)
			_box(comb, "Step%d" % i, Vector3(width, -top + 0.01, STEP_D),
				Vector3(0, top / 2, z), mat, CSGShape3D.OPERATION_SUBTRACTION)


# Collision ramp of a staircase: the CSG steps are only visual; the player walks on an inclined plane that
# passes 2 cm above the step edges, so a CharacterBody3D climbs and descends it without the abrupt
# jump of a 0.25 m step (it used to depend on `_try_step_up`, which teleports it).
# Convex wedge: `start` = foot of the staircase, `dir` = direction along Z, `up` = 1 climbs / -1 descends.
func _stair_ramp(parent: Node, name: String, start: Vector3, dir: int, up: int, steps: int,
		width: float) -> StaticBody3D:
	var slope := STEP_H / STEP_D
	var total := steps * STEP_H
	var sink := -0.02   # negative = 2 cm above the edges (so the capsule does not graze them)
	var prof: Array = []   # profile (s along the staircase, y) of the top face
	if up > 0:
		prof = [Vector2(-(STEP_H - sink) / slope, 0.0), Vector2((total - STEP_H + sink) / slope, total),
			Vector2(steps * STEP_D + 0.3, total)]
	else:
		prof = [Vector2(-sink / slope, 0.0), Vector2((total - sink) / slope, -total),
			Vector2(steps * STEP_D + 0.3, -total)]
	var pts := PackedVector3Array()
	var low := minf(prof[0].y, prof[2].y) - 0.6
	for p: Vector2 in prof:
		for sx in [-1, 1]:
			pts.append(Vector3(sx * width / 2, start.y + p.y, start.z + dir * p.x))
	for p: Vector2 in [prof[0], prof[2]]:
		for sx in [-1, 1]:
			pts.append(Vector3(sx * width / 2, start.y + low, start.z + dir * p.x))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("doc", "Collision ramp of the staircase (the CSG steps are visual only)")
	_node(parent, body, name)
	var col := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	col.shape = shape
	_node(body, col, "Shape")
	return body


func _gates(root: Node3D, half_d: float) -> void:
	var mat := _mat("metal_512", Color(0.45, 0.42, 0.4))
	for g in [["GateEntry", 1], ["GateExit", -1]]:
		var body := AnimatableBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = Vector3(0, GATE_H / 2, g[1] * (half_d + WALL_T / 2))
		body.set_meta("open_offset", Vector3(0, -GATE_H - 0.1, 0))   # opens by sinking into the floor
		_node(root, body, g[0])
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(GATE_W, GATE_H, 0.3)
		bm.material = mat
		mesh.mesh = bm
		_node(body, mesh, "Mesh")
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = bm.size
		col.shape = shape
		_node(body, col, "Shape")


func _markers(root: Node3D, cfg: Dictionary) -> void:
	var ps := _node(root, Marker3D.new(), "PlayerStart")
	ps.position = Vector3(0, 0, cfg.player_start)   # 4 m from the entrance, facing north
	var bs := _node(root, Marker3D.new(), "BossStart")
	bs.position = cfg.boss_start
	bs.rotation_degrees.y = 180   # faces south, toward Kaelen
	var spawns := _node(root, Node3D.new(), "Spawns")
	var list: Array = []
	if typeof(cfg.spawns) == TYPE_STRING:
		for k in 6:
			var a := deg_to_rad(30.0 + 60.0 * k)
			list.append([12.5 * sin(a), 12.5 * cos(a)])
	else:
		list = cfg.spawns
	for i in list.size():
		var m := Marker3D.new()
		m.position = Vector3(list[i][0], 0, list[i][1])
		_node(spawns, m, "Spawn%d" % (i + 1)).add_to_group("spawn_point", true)


func _triggers(root: Node3D, info: Dictionary) -> void:
	var t := _area(root, "ExitTrigger", info.size, info.pos)
	t.set_meta("doc", "Kaelen crosses it → GameState.advance_level() (A)")


func _torches(root: Node3D, cfg: Dictionary) -> void:
	var lights := _node(root, Node3D.new(), "Torches")
	var i := 0
	for t in cfg.torches:
		var l := OmniLight3D.new()
		l.light_color = cfg.light
		l.light_energy = 1.4
		l.omni_range = 14
		l.position = Vector3(t[0], 4.5, t[1])
		i += 1
		_node(lights, l, "Torch%d" % i)


func _navigation(root: Node3D, name: String, layer: int, radius: float, height: float,
		climb: float, slope: float) -> void:
	var nm := NavigationMesh.new()
	# Floor only: without this the bake generated polygons on the tops of walls, pillars and ceiling
	# (y ~ 8-12 m). The first footprints of the staircases are kept (without them there is nowhere to
	# rest the entry mesh) and everything above the NAV_AABB top is cut.
	nm.filter_baking_aabb = NAV_AABB
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = &"nav_source"
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = radius
	nm.agent_height = height
	nm.agent_max_climb = climb
	nm.agent_max_slope = slope
	var region := NavigationRegion3D.new()
	region.navigation_mesh = nm
	region.navigation_layers = layer
	_node(root, region, name)
	region.bake_navigation_mesh(false)
	print("  %s: %d polygons" % [name, nm.get_polygon_count()])


# --- Kit / GridMap --------------------------------------------------------------------------

# GridMap walls (4 m cells) in the same place as the CSG blockout: each wall goes in the cell
# outside the interior, flush with the edge facing the interior. The gate openings (2 cells = 8 m)
# are closed down to 6 x 6 m with CSG jambs and lintel. The floor is still a CSG block (continuous
# collision and no seams for navigation); the kit tiles are painted on top.
func _grid_shell(geo: Node3D, shell: CSGCombiner3D, cfg: Dictionary, wall_mat: Material) -> void:
	var gm := _new_gridmap(geo)
	var w: float = cfg.size.x
	var d: float = cfg.size.y
	var h: float = cfg.height
	var nx := int(w / 4)
	var nz := int(d / 4)
	var rows: Array = cfg.wall_rows
	var id := func(n: String) -> int: return KIT_ITEMS.find(n)
	var rot := func(deg: float) -> int: return gm.get_orthogonal_index_from_basis(Basis(Vector3.UP, deg_to_rad(deg)))
	var floor_id: int = id.call("floor")
	var ceil_id: int = id.call("ceiling")
	# Interior floor (and ceiling), plus the floor of the gate openings.
	for x in range(-nx / 2, nx / 2):
		for z in range(-nz / 2, nz / 2):
			gm.set_cell_item(Vector3i(x, 0, z), floor_id)
			if cfg.ceiling:
				gm.set_cell_item(Vector3i(x, int(h / 4), z), ceil_id)
		if x == -1 or x == 0:
			gm.set_cell_item(Vector3i(x, 0, -nz / 2 - 1), floor_id)
			gm.set_cell_item(Vector3i(x, 0, nz / 2), floor_id)
	_box(shell, "Floor", Vector3(w + 2 * WALL_T, 1, d + 2 * WALL_T), Vector3(0, -0.55, 0), wall_mat)
	# Walls: [cell, rotation]. The piece occupies the north edge of its cell; the rotation takes it to the edge
	# touching the interior (south -> 0 deg, north -> 180 deg, east -> +90 deg, west -> -90 deg).
	for y in int(h / 4):
		var row: Array = rows[min(y, rows.size() - 1)]
		var n := 0
		for x in range(-nx / 2, nx / 2):
			var gate := (x == -1 or x == 0) and y * 4 < GATE_H
			var item: int = id.call(row[n % row.size()])
			n += 1
			if not gate:
				gm.set_cell_item(Vector3i(x, y, nz / 2), item, rot.call(0))
				gm.set_cell_item(Vector3i(x, y, -nz / 2 - 1), item, rot.call(180))
		for z in range(-nz / 2, nz / 2):
			var item: int = id.call(row[n % row.size()])
			n += 1
			gm.set_cell_item(Vector3i(nx / 2, y, z), item, rot.call(90))
			gm.set_cell_item(Vector3i(-nx / 2 - 1, y, z), item, rot.call(-90))
	# Corners (1 x 1 m that the GridMap leaves free, covered by the walls) and the gate frame.
	var top := float(int(GATE_H / 4) + 1) * 4.0   # height of the opening in the grid (8 m)
	for sx in [1, -1]:
		for sz in [1, -1]:
			_box(shell, "Corner%d%d" % [sx, sz], Vector3(1, h, 1),
				Vector3(sx * (w / 2 + 0.5), h / 2, sz * (d / 2 + 0.5)), wall_mat)
	var frame := StaticBody3D.new()
	frame.collision_layer = 1
	frame.collision_mask = 0
	_node(geo, frame, "GateFrame")
	var pieces := _node(geo, Node3D.new(), "GatePieces")
	for sz in [1, -1]:
		var yaw := 0.0 if sz == 1 else PI
		for sx in [1, -1]:   # jambs: 1 m wide, on both sides of the 6 m opening
			_frame_box(frame, "Jamb%d%d" % [sx, sz], Vector3(1, top, 1),
				Vector3(sx * (GATE_W / 2 + 0.5), top / 2, sz * (d / 2 + 0.5)))
			for r in int(top / 4):
				_piece(pieces, "Jamb%d%d_%d" % [sx, sz, r], "wall",
					Vector3(sx * (GATE_W / 2 + 0.5), r * 4.0, sz * (d / 2 + 2.0)), yaw, Vector3(0.25, 1, 1))
		_frame_box(frame, "Lintel%d" % sz, Vector3(GATE_W, top - GATE_H, 1),
			Vector3(0, GATE_H + (top - GATE_H) / 2, sz * (d / 2 + 0.5)))
		_piece(pieces, "Lintel%d" % sz, "wall", Vector3(0, GATE_H, sz * (d / 2 + 2.0)), yaw,
			Vector3(GATE_W / 4.0, (top - GATE_H) / 4.0, 1))


# Collision box (no mesh) for jambs and lintels: the look comes from the kit pieces.
func _frame_box(body: StaticBody3D, name: String, size: Vector3, pos: Vector3) -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = pos
	_node(body, col, name)


# Kit piece as a loose MeshInstance3D (origin at the center of the 4 m face; the inner face of the
# wall is at local z = -2, so `pos` goes 2 m outward from the inner plane of the wall).
func _piece(parent: Node, name: String, item: String, pos: Vector3, yaw: float, scl: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = _kit_mesh_res(item)
	m.transform = Transform3D(Basis(Vector3.UP, yaw).scaled_local(scl), pos)
	return _node(parent, m, name) as MeshInstance3D


func _new_gridmap(geo: Node3D) -> GridMap:
	var gm := GridMap.new()
	gm.mesh_library = load(KIT_LIB)
	gm.cell_size = Vector3(4, 4, 4)
	gm.cell_center_y = false
	gm.collision_layer = 1
	gm.collision_mask = 0
	_node(geo, gm, "GridMap")
	return gm


# Octagon (cfg.size.x = distance between faces, e.g. 30 m = 24 of combat + 3 m of margin per side)
# with kit pieces. It does not fit the 4 m grid, so:
# - floor and ceiling: GridMap tiles in the cells touching the octagon (those sticking out at the
#   corners end up outside the 1 m thick wall, which reaches the grid edge); below, an 8-sided
#   CSG cylinder closes the collision and the navigation without seams;
# - walls: 3 pieces per face and row, rotated k x 45 deg and stretched to the face length (12.43 / 3 m);
#   on the south and north faces only the side pieces and the CSG lintel over the gate remain;
# - wall collision: one box per face (two on the gate faces).
func _oct_shell(geo: Node3D, shell: CSGCombiner3D, cfg: Dictionary, wall_mat: Material) -> void:
	var apo: float = cfg.size.x * 0.5
	var h: float = cfg.height
	var rows: Array = cfg.wall_rows
	var gm := _new_gridmap(geo)
	var floor_id := KIT_ITEMS.find("floor")
	var ceil_id := KIT_ITEMS.find("ceiling")
	var n := int(ceil(apo / 4.0))
	for x in range(-n, n):
		for z in range(-n, n):
			var near_x := maxf(absf((x + 0.5) * 4.0) - 2.0, 0.0)
			var near_z := maxf(absf((z + 0.5) * 4.0) - 2.0, 0.0)
			if near_x + near_z >= apo * sqrt(2.0) - 0.1:   # outside the diagonal faces
				continue
			gm.set_cell_item(Vector3i(x, 0, z), floor_id)
			if cfg.ceiling:
				gm.set_cell_item(Vector3i(x, int(h / 4), z), ceil_id)
	_cyl(shell, "Floor", (apo + WALL_T) / cos(PI / 8), 1, Vector3(0, -0.55, 0), wall_mat, 8)

	var face_len := 2.0 * apo * tan(PI / 8)           # inner length of the face
	var half_out := (apo + WALL_T) * tan(PI / 8) + 0.1   # outer half-length + overlap with the neighbor
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_node(geo, body, "WallBodies")
	var walls := _node(geo, Node3D.new(), "WallPieces")
	for k in 8:
		var a := k * PI / 4.0                       # 0 = south face; the rotation takes +Z (outward) to o
		var o := Vector3(sin(a), 0, cos(a))
		var tangent := Vector3(cos(a), 0, -sin(a))
		var gate := k == 0 or k == 4
		# Spans of the face [t0, t1] (along the tangent) that carry wall: pieces on the inside
		# (exact face length) and collision boxes on the outside (with the corner overlap).
		var hole := GATE_W / 2
		var spans: Array = [[-face_len / 2, face_len / 2]]
		var col_spans: Array = [[-half_out, half_out]]
		if gate:
			spans = [[-face_len / 2, -hole], [hole, face_len / 2]]
			col_spans = [[-half_out, -hole], [hole, half_out]]
		for si in spans.size():
			var t0: float = spans[si][0]
			var t1: float = spans[si][1]
			var pieces := maxi(1, roundi((t1 - t0) / 4.0))
			var width := (t1 - t0) / pieces
			for r in int(h / 4):
				var row: Array = rows[min(r, rows.size() - 1)]
				for j in pieces:
					var piece := MeshInstance3D.new()
					piece.mesh = _kit_mesh_res(row[(j + si) % row.size()])
					var tc := t0 + (j + 0.5) * width
					piece.transform = Transform3D(Basis(Vector3.UP, a).scaled_local(Vector3(width / 4.0, 1, 1)),
						o * (apo + 2.0) + tangent * tc + Vector3(0, r * 4.0, 0))
					_node(walls, piece, "F%d_S%d_R%d_%d" % [k, si, r, j])
			var lo: float = col_spans[si][0]
			var hi: float = col_spans[si][1]
			var col := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(hi - lo, h, WALL_T)
			col.shape = box
			col.transform = Transform3D(Basis(Vector3.UP, a),
				o * (apo + WALL_T / 2) + tangent * ((lo + hi) / 2) + Vector3(0, h / 2, 0))
			_node(body, col, "Wall%d_%d" % [k, si])
		if gate:   # lintel over the gate: from 6 m to h (flattened wall piece; collision in the body)
			var lcol := CollisionShape3D.new()
			var lbox := BoxShape3D.new()
			lbox.size = Vector3(GATE_W, h - GATE_H, WALL_T)
			lcol.shape = lbox
			lcol.transform = Transform3D(Basis(Vector3.UP, a),
				o * (apo + WALL_T / 2) + Vector3(0, GATE_H + (h - GATE_H) / 2, 0))
			_node(body, lcol, "Lintel%d" % k)
			_piece(walls, "Lintel%d" % k, "wall", o * (apo + 2.0) + Vector3(0, GATE_H, 0), a,
				Vector3(GATE_W / 4.0, (h - GATE_H) / 4.0, 1))
	print("  octagon: apothem %.1f m, face %.2f m, %d tiles" % [apo, face_len, gm.get_used_cells().size()])


# MeshLibrary with the pieces exported from Blender, PSX material with the atlas and simple collision.
func _kit_library() -> void:
	var lib := MeshLibrary.new()
	for i in KIT_ITEMS.size():
		var name: String = KIT_ITEMS[i]
		var src := _kit_instance(name)
		var mi := _first_mesh(src)
		lib.create_item(i)
		lib.set_item_name(i, name)
		lib.set_item_mesh(i, mi.mesh)
		lib.set_item_mesh_transform(i, mi.transform)
		var shapes := []
		match name:
			"floor":
				shapes = [[Vector3(4, 0.2, 4), Vector3(0, -0.1, 0)]]
			"ceiling":
				shapes = [[Vector3(4, 0.2, 4), Vector3(0, 0.1, 0)]]
			"wall_corner":
				shapes = [[Vector3(4, 4, 1), Vector3(0, 2, -1.5)], [Vector3(1, 4, 4), Vector3(-1.5, 2, 0)]]
			_:
				shapes = [[Vector3(4, 4, 1), Vector3(0, 2, -1.5)]]
		var arr := []
		for sh in shapes:
			var box := BoxShape3D.new()
			box.size = sh[0]
			arr.append(box)
			arr.append(Transform3D(Basis(), sh[1]))
		lib.set_item_shapes(i, arr)
		src.free()
	print("MeshLibrary → %s (%s)" % [KIT_LIB, error_string(ResourceSaver.save(lib, KIT_LIB))])


# Instantiates a kit piece with the Dungeon_Map atlas. Standard material (nearest, per-vertex lighting,
# no culling) like the rest of the level, NOT the psx_lit shader: its vertex snapping to a grid
# made the 4 m tiles with a vertex behind the camera disappear (a hole in the floor next to
# Kaelen). The PSX look comes from the low-resolution post-process.
func _kit_instance(name: String) -> Node3D:
	var node := (load(KIT + name + ".glb") as PackedScene).instantiate() as Node3D
	var mi := _first_mesh(node)
	if _kit_mat == null:
		var src := mi.mesh.surface_get_material(0) as BaseMaterial3D
		var m := StandardMaterial3D.new()
		m.albedo_texture = src.albedo_texture
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		ResourceSaver.save(m, KIT + "kit_std.tres")
		_kit_mat = load(KIT + "kit_std.tres")
	var mesh := mi.mesh.duplicate() as Mesh
	for s in mesh.get_surface_count():
		mesh.surface_set_material(s, _kit_mat)
	mi.mesh = mesh
	return node


# Mesh of a kit piece with the standard material, a single one per name (the scenes share the resource).
func _kit_mesh_res(name: String) -> Mesh:
	if not _kit_meshes.has(name):
		var src := _kit_instance(name)
		_kit_meshes[name] = _first_mesh(src).mesh
		src.free()
	return _kit_meshes[name]


func _first_mesh(n: Node) -> MeshInstance3D:
	return n if n is MeshInstance3D else n.find_children("*", "MeshInstance3D", true, false)[0]


# --- Utilities -----------------------------------------------------------------------------

func _node(parent: Node, n: Node, name: String) -> Node:
	n.name = name
	parent.add_child(n)
	return n


func _combiner(parent: Node, name: String) -> CSGCombiner3D:
	var c := CSGCombiner3D.new()
	c.use_collision = true
	c.collision_layer = 1
	c.collision_mask = 0
	return _node(parent, c, name)


func _box(parent: Node, name: String, size: Vector3, pos: Vector3, mat: Material,
		op := CSGShape3D.OPERATION_UNION) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.material = mat
	b.operation = op
	return _node(parent, b, name)


func _cyl(parent: Node, name: String, radius: float, height: float, pos: Vector3, mat: Material,
		sides: int, op := CSGShape3D.OPERATION_UNION) -> CSGCylinder3D:
	var c := CSGCylinder3D.new()
	c.radius = radius
	c.height = height
	c.sides = sides
	c.position = pos
	c.material = mat
	c.operation = op
	if sides == 8:
		c.rotation_degrees.y = 22.5   # one face looking south
	return _node(parent, c, name)


func _area(parent: Node, name: String, size: Vector3, pos: Vector3) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = 2   # player only (section 7.7)
	a.monitorable = false
	a.position = pos
	_node(parent, a, name)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	_node(a, col, "Shape")
	return a


func _camera(parent: Node, name: String, pos: Vector3, target: Vector3) -> void:
	var cam := Camera3D.new()
	cam.fov = 60
	_node(parent, cam, name)
	cam.look_at_from_position(pos, target)
	# The first Camera3D that enters the tree (the generator's) becomes current and would be saved with
	# `current = true`, hijacking Kaelen's camera. The ending activates them from code.
	cam.clear_current(false)


# Blockout material: kit texture with triplanar projection in world coordinates
# (CSG shapes have no useful UVs; section 6.4 allows it temporarily). Nearest filter, no mipmaps.
func _mat(tex_name: String, tint: Color) -> Material:
	var key := tex_name + str(tint)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + tex_name + ".png")
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.25, 0.25, 0.25)   # one repeat every 4 m (one module)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_mats[key] = m
	return m


func _save(root: Node, path: String) -> void:
	# The *_gameplay.tscn scenes are hand-maintained: the generator never touches them.
	assert(not path.ends_with("_gameplay.tscn"), "level_builder must not write " + path)
	_set_owner(root, root)
	for cam: Camera3D in root.find_children("*", "Camera3D", true, false):
		cam.clear_current(false)   # no level camera is saved as current
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		err = ResourceSaver.save(ps, path)
	print("%s → %s (%s)" % [root.name, path, error_string(err)])


func _set_owner(node: Node, owner: Node) -> void:
	for c in node.get_children():
		if c is MultiMeshInstance3D:   # ForestRing builds them on entering the tree; they are not saved in the scene
			continue
		c.owner = owner
		if c.scene_file_path.is_empty():   # do not enter instanced scenes (Elysia)
			_set_owner(c, owner)
