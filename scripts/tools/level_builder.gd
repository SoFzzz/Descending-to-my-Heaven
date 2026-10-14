extends SceneTree
## Generador paramétrico y determinista de los niveles (§6 del diseño). NO es procedural:
## el plano de cada escena está en las tablas de abajo (LEVELS); para cambiar el mapa se edita
## un número y se vuelve a ejecutar. Sobrescribe las escenas de salida.
##
## Ejecutar desde la raíz del proyecto:
##   godot --headless --path . -s res://scripts/tools/level_builder.gd            (todas)
##   godot --headless --path . -s res://scripts/tools/level_builder.gd -- arena_2 (una)
##
## Convenciones: 1 unidad = 1 m; el sur es +Z y el norte es -Z (los Marker3D miran a -Z, o sea
## al norte, salvo que se indique). Toda la geometría es CSG con colisión en la capa 1 (`world`).
## Nombres fijos que usan A y B: PlayerStart, BossStart, Spawns/Spawn1..6 (grupo "spawn_point"),
## GateEntry, GateExit (AnimatableBody3D; meta "open_offset" = desplazamiento para abrirlas),
## ExitTrigger, Gameplay y, en la arena 3, Ending/EndingTrigger, Ending/EndingCam1..2.

const OUT_DIR := "res://scenes/levels/"
const TEX := "res://assets/environment/textures/"
const BASE_ENV := "res://assets/environment/base_env.tres"
const ELYSIA := "res://assets/characters/elysia/elysia.glb"
const KIT := "res://assets/environment/kit/"
const KIT_LIB := KIT + "dungeon_kit.meshlib"
const PSX_BASE := "res://assets/materials/psx_base.tres"
# Piezas de la MeshLibrary (ids = orden). Ver _source/tools/export_dungeon_kit.py para su forma.
const KIT_ITEMS := ["floor", "ceiling", "wall", "wall_skull", "wall_window", "wall_ruin", "wall_corner"]

const WALL_T := 1.0          # grosor de muro
const GATE_W := 6.0          # reja de arena: 6 × 6 m (§7.3)
const GATE_H := 6.0
const STEP_H := 0.25         # escalón (§7.3)
const STEP_D := 0.4

# --- Plano de cada nivel --------------------------------------------------------------------
# shape: "rect" (size = ancho x fondo interior) u "oct" (size.x = distancia entre caras).
# El interior = área de combate de §6.3 + margen de cámara de 3-4 m por lado.
const LEVELS := {
	"arena_1": {
		"title": "Catacumba (Bone Dragon)",
		"shape": "rect", "size": Vector2(40, 40), "height": 8.0, "ceiling": true,
		"output": "gridmap", "wall_rows": [["wall", "wall", "wall_skull"], ["wall"]],
		"floor_tex": "Floor512_indexed", "wall_tex": "concrete_512_indexed_dark",
		"tint": Color(0.85, 0.72, 0.6), "light": Color(1.0, 0.62, 0.35),
		# Pilar: [x, z, ancho/diámetro, alto, forma ("box"/"cyl"), inclinación en grados]
		"pillars": [[-9, -9, 2.0, 8.0, "box", 0], [9, -9, 2.0, 8.0, "box", 0],
			[-9, 9, 2.0, 8.0, "box", 0], [9, 9, 2.0, 8.0, "box", 0]],
		# Spawns detrás de los pilares (vistos desde el centro) y en los muros este/oeste.
		"spawns": [[-12, -12], [12, -12], [-12, 12], [12, 12], [-18, 0], [18, 0]],
		"player_start": 16.0, "boss_start": Vector3(0, 0, -9),
		"torches": [[-19, -10], [19, -10], [-19, 10], [19, 10], [0, -19], [0, 19]],
		"exit": "stairs",
		"fog_end": 48.0,   # la niebla base (30 m) tapaba al jefe desde el inicio
	},
	"arena_2": {
		"title": "Claustro (Blackhorn)",
		"shape": "oct", "size": Vector2(30, 30), "height": 8.0, "ceiling": true,
		"floor_tex": "concrete_512_indexed", "wall_tex": "concrete_512_indexed",
		"tint": Color(0.82, 0.88, 1.0), "light": Color(0.75, 0.85, 1.0),
		"pillars": "ring6",   # 6 columnas de 1.2 m en anillo de radio 8, a 30° + k·60°
		"spawns": "ring6",    # detrás de cada columna, radio 12.5
		"player_start": 11.0, "boss_start": Vector3(0, 0, -6),
		"torches": [[-11, -6], [11, -6], [-11, 6], [11, 6], [0, 0]],
		"exit": "stairs",
		"fog_end": 40.0,
	},
	"arena_3": {
		"title": "Ruinas (Ghidorah)",
		"shape": "rect", "size": Vector2(48, 48), "height": 12.0, "ceiling": false,
		"output": "gridmap", "wall_rows": [["wall"], ["wall", "wall_window"], ["wall_ruin"]],
		"floor_tex": "TerraCotta_512", "wall_tex": "concrete_512_indexed",
		"tint": Color(0.7, 0.7, 0.72), "light": Color(0.85, 0.85, 0.9),
		"pillars": [[-14, -14, 1.2, 5.0, "cyl", 0], [14, -14, 1.2, 3.0, "cyl", 0],
			[-14, 14, 1.2, 3.5, "cyl", 0], [14, 14, 1.2, 6.0, "cyl", 0],
			[-19, 0, 1.2, 2.0, "cyl", 0], [19, 2, 1.2, 7.0, "cyl", 75]],
		"spawns": [[-16, -16], [16, -16], [-16, 16], [16, 16], [-21, 0], [21, -3]],
		"player_start": 20.0, "boss_start": Vector3(0, 0, -12),
		"torches": [[-22, -22], [22, -22], [-22, 22], [22, 22]],
		"exit": "ending",
		"corridor_len": 20.0,                 # pasillo tras la puerta bloqueada
		"ending_room": Vector3(12, 6, 12),    # sala de Elysia: ancho, alto, fondo
		"fog_end": 70.0,
	},
}

# Exterior: isla principal (island_main, ≈ 104 m, de float-islands) desplazada para que el sendero
# quede cerca de Y=0; el sendero va de sur a norte por x=0 hasta la fachada del templo.
const EXTERIOR := {
	"island": "island_main", "island_pos": Vector3(5, 8, 0),
	"path_half_w": 2.5, "path_start_z": 36.0,          # ancho del sendero 5 m
	"plaza": Rect2(-10, -31, 20, 9),                    # explanada ante la puerta (x, z, ancho, fondo)
	# Templo: cuerpos apilados [ancho, alto, fondo]; la cara sur del primero está en temple_z.
	"temple_z": -31.0, "temple": [Vector3(22, 12, 20), Vector3(16, 10, 15), Vector3(10, 8, 10)],
	"door": Vector2(3, 4),                              # puerta normal 3 × 2 m (§7.3) agrandada a 3 × 4
	"islets": [["islet_round", Vector3(-75, -18, -35), 30.0], ["islet_long", Vector3(65, -28, 15), 70.0],
		["islet_l", Vector3(-60, -6, 55), 120.0], ["islet_small", Vector3(35, 6, -70), 0.0],
		["islet_hole", Vector3(110, -35, -70), 200.0]],
	"fog_end": 110.0,
}

var _mats := {}


func _initialize() -> void:
	var only := OS.get_cmdline_user_args()
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
	we.environment = env
	_node(root, we, "WorldEnvironment")
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.85, 0.85, 0.95)
	sun.light_energy = 0.9
	sun.rotation_degrees = Vector3(-40, -30, 0)
	_node(root, sun, "Sun")

	# Isla con colisión trimesh (≈ 1100 triángulos, barata) en la capa world.
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

	for i in 3:
		await physics_frame
	var ground := func(x: float, z: float) -> float:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -60, z))
		var r := root.get_world_3d().direct_space_state.intersect_ray(q)
		return r.position.y if r else 0.0

	# Templo: cuerpos apilados con textura de muro, puerta al sur, arco y pilares del kit.
	var geo := _node(root, Node3D.new(), "Temple")
	var wall_mat := _mat("concrete_512_indexed_dark", Color(0.75, 0.72, 0.7))
	var tz: float = cfg.temple_z
	var base_y: float = ground.call(0.0, tz - 1.0)
	var comb := _combiner(geo, "Body")
	var y := base_y - 8.0   # el primer cuerpo se hunde en el terreno
	var parts: Array = cfg.temple
	for i in parts.size():
		var sz: Vector3 = parts[i]
		var hh := sz.y + (8.0 if i == 0 else 0.0)
		_box(comb, "Tier%d" % (i + 1), Vector3(sz.x, hh, sz.z), Vector3(0, y + hh / 2, tz - parts[0].z / 2), wall_mat)
		y += hh
	var door: Vector2 = cfg.door
	_box(comb, "Door", Vector3(door.x, door.y, 3), Vector3(0, base_y + door.y / 2, tz), wall_mat,
		CSGShape3D.OPERATION_SUBTRACTION)
	var arch := _kit_mesh("arch")
	arch.position = Vector3(0, base_y + door.y - 0.4, tz + 0.5)
	_node(geo, arch, "Arch")
	for sx in [-1, 1]:
		var pil := _kit_mesh("pillar")
		pil.position = Vector3(sx * 4.0, base_y - 1.0, tz + 1.0)
		pil.scale = Vector3(1.4, 1.6, 1.4)
		_node(geo, pil, "DoorPillar%s" % ("W" if sx < 0 else "E"))
	_area(root, "ExitTrigger", Vector3(door.x, 3, 1.5), Vector3(0, base_y + 1.5, tz + 0.5)) 		.set_meta("doc", "Kaelen entra al templo → GameState.advance_level() (A)")
	var torch := OmniLight3D.new()
	torch.light_color = Color(1.0, 0.6, 0.3)
	torch.light_energy = 2.0
	torch.omni_range = 10
	torch.position = Vector3(0, base_y + 5, tz + 3)
	_node(geo, torch, "DoorLight")

	# Sendero: pilares bajos cada 8 m a los lados y paredes invisibles que lo encierran.
	var hw: float = cfg.path_half_w
	var z0: float = cfg.path_start_z
	var plaza: Rect2 = cfg.plaza
	var deco := _node(root, Node3D.new(), "PathMarkers")
	var z := z0 - 4.0
	var n := 0
	while z > plaza.end.y:
		for sx in [-1, 1]:
			var m := _kit_mesh("pillar_collapsed")
			m.position = Vector3(sx * (hw + 0.8), ground.call(sx * (hw + 0.8), z) - 0.3, z)
			n += 1
			_node(deco, m, "Marker%d" % n)
		z -= 8.0
	var walls := StaticBody3D.new()
	walls.collision_layer = 1
	walls.collision_mask = 0
	_node(root, walls, "InvisibleWalls")
	var pts_w := [Vector2(-hw, z0), Vector2(-hw, plaza.end.y), Vector2(plaza.position.x, plaza.end.y),
		Vector2(plaza.position.x, plaza.position.y)]
	var pts_e := pts_w.map(func(p: Vector2) -> Vector2: return Vector2(-p.x, p.y))
	var segs := []
	for i in pts_w.size() - 1:
		segs.append([pts_w[i], pts_w[i + 1]])
		segs.append([pts_e[i], pts_e[i + 1]])
	segs.append([pts_w[0], pts_e[0]])
	for i in segs.size():
		var a: Vector2 = segs[i][0]
		var b: Vector2 = segs[i][1]
		var mid := (a + b) / 2
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(max(abs(b.x - a.x), 0.5), 30, max(abs(b.y - a.y), 0.5))
		col.shape = box
		col.position = Vector3(mid.x, ground.call(mid.x, mid.y) + 5, mid.y)
		_node(walls, col, "Wall%d" % (i + 1))

	var ps := _node(root, Marker3D.new(), "PlayerStart") as Marker3D
	ps.position = Vector3(0, ground.call(0.0, z0 - 2.0), z0 - 2.0)
	_node(root, Node3D.new(), "Gameplay")
	print("  sendero: inicio y=%.2f, puerta y=%.2f, %d m" % [ps.position.y, base_y, int(z0 - tz)])
	_save(root, OUT_DIR + "exterior.tscn")
	root.queue_free()
	await process_frame


# Copia de una malla del kit con material PSX como MeshInstance3D suelto (se guarda en la escena).
func _kit_mesh(name: String) -> MeshInstance3D:
	var src := _kit_instance(name)
	var mi := MeshInstance3D.new()
	mi.mesh = _first_mesh(src).mesh
	src.free()
	return mi


# --- Nivel ----------------------------------------------------------------------------------

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

	# Suelo, techo y muros con los huecos de las rejas (sur y norte).
	var floor_mat := _mat(cfg.floor_tex, cfg.tint)
	var wall_mat := _mat(cfg.wall_tex, cfg.tint)
	var shell := _combiner(geo, "Shell")
	if cfg.get("output", "csg") == "gridmap":
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
		# Octógono con una cara mirando al sur: radio al vértice = apotema / cos(22.5°).
		var apo := w * 0.5
		var r_in := apo / cos(PI / 8)
		var r_out := (apo + WALL_T) / cos(PI / 8)
		_cyl(shell, "Floor", r_out, 1, Vector3(0, -0.5, 0), floor_mat, 8)
		_cyl(shell, "Walls", r_out, h, Vector3(0, h / 2, 0), wall_mat, 8)
		_cyl(shell, "Interior", r_in, h, Vector3(0, h / 2, 0), wall_mat, 8,
			CSGShape3D.OPERATION_SUBTRACTION)
		if cfg.ceiling:
			_cyl(shell, "Ceiling", r_out, 1, Vector3(0, h + 0.5, 0), wall_mat, 8)
	for side in [1, -1] if cfg.get("output", "csg") == "csg" else []:   # 1 = sur, -1 = norte
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
	_markers(root, cfg, half_d)
	_triggers(root, exit_info)
	_torches(root, cfg)
	_node(root, Node3D.new(), "Gameplay")

	# Esperar a que el CSG genere sus mallas y hornear la navegación.
	for i in 3:
		await process_frame
	_navigation(root, "NavigationSmall", 1, 0.5, 2.0, 0.3, 35.0)
	_navigation(root, "NavigationLarge", 2, 2.5, 4.0, 0.5, 25.0)

	_save(root, OUT_DIR + id + ".tscn")
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
	# Pilares del kit (pillar.glb: 1.2 × 8 m, origen en la base) escalados al ancho y alto de la
	# tabla, con un StaticBody3D cilíndrico en la capa world. Los bajos usan pillar_collapsed.
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
		var piece := MeshInstance3D.new()   # copia de la malla (lo instanciado de un .glb no se guarda)
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
		if p[5] != 0:   # pilar caído: se inclina sobre su base
			body.rotation_degrees.z = p[5]
			body.position.y = 0.6


# Vestíbulo sur: rellano de 6 m tras la reja de entrada y escalera que baja (llegada desde abajo).
func _entry_hall(geo: Node3D, half_d: float, floor_mat: Material, wall_mat: Material) -> void:
	var z0 := half_d + WALL_T
	var comb := _combiner(geo, "EntryHall")
	var steps := 8
	_corridor(comb, z0, 6.0 + steps * STEP_D + 1.0, 1, GATE_W, GATE_H + 1, floor_mat, wall_mat)
	var base_d := steps * STEP_D + 1.0   # bloque macizo bajo la escalera para recortarla
	_box(comb, "StairBase", Vector3(GATE_W, 3, base_d), Vector3(0, -1.5, z0 + 6.0 + base_d / 2), floor_mat)
	_stairs(comb, Vector3(0, 0, z0 + 6.0), 1, -1, steps, GATE_W, floor_mat)


# Salida norte de los pisos 1 y 2: pasillo + escalera que sube 4 m + rellano con ExitTrigger.
func _exit_stairs(geo: Node3D, half_d: float, floor_mat: Material, wall_mat: Material) -> Dictionary:
	var z0 := -(half_d + WALL_T)
	var steps := 16
	var run := 3.0 + steps * STEP_D + 4.0
	var comb := _combiner(geo, "ExitHall")
	_corridor(comb, z0, run, -1, GATE_W, GATE_H + 4.5, floor_mat, wall_mat)
	_stairs(comb, Vector3(0, 0, z0 - 3.0), -1, 1, steps, GATE_W, floor_mat)
	var top := steps * STEP_H
	_box(comb, "Landing", Vector3(GATE_W, top, 4.0), Vector3(0, top / 2, z0 - run + 2.0), floor_mat)
	return {"pos": Vector3(0, top + 1.0, z0 - run + 2.0), "size": Vector3(GATE_W, 2.0, 3.0)}


# Salida norte del piso 3: puerta bloqueada (GateExit) → pasillo → sala de Elysia.
func _exit_ending(root: Node3D, geo: Node3D, cfg: Dictionary, half_d: float,
		floor_mat: Material, wall_mat: Material) -> Dictionary:
	var z0 := -(half_d + WALL_T)
	var length: float = cfg.corridor_len
	var room: Vector3 = cfg.ending_room
	var comb := _combiner(geo, "EndingHall")
	_corridor(comb, z0, length, -1, GATE_W, GATE_H + 1, floor_mat, wall_mat)
	# Sala: caja hueca con hueco hacia el pasillo.
	var zc := z0 - length - room.z / 2
	var room_mat := _mat("gold512", Color(0.75, 0.7, 0.6))
	_box(comb, "RoomFloor", Vector3(room.x + 2, 1, room.z + 2), Vector3(0, -0.5, zc), floor_mat)
	_box(comb, "RoomCeiling", Vector3(room.x + 2, 1, room.z + 2), Vector3(0, room.y + 0.5, zc), wall_mat)
	_box(comb, "RoomWallN", Vector3(room.x + 2, room.y, 1), Vector3(0, room.y / 2, zc - room.z / 2 - 0.5), room_mat)
	_box(comb, "RoomWallS", Vector3(room.x + 2, room.y, 1), Vector3(0, room.y / 2, zc + room.z / 2 + 0.5), wall_mat)
	_box(comb, "RoomWallE", Vector3(1, room.y, room.z), Vector3(room.x / 2 + 0.5, room.y / 2, zc), wall_mat)
	_box(comb, "RoomWallW", Vector3(1, room.y, room.z), Vector3(-room.x / 2 - 0.5, room.y / 2, zc), wall_mat)
	_box(comb, "RoomDoor", Vector3(GATE_W, GATE_H, 3), Vector3(0, GATE_H / 2, zc + room.z / 2 + 0.5),
		wall_mat, CSGShape3D.OPERATION_SUBTRACTION)
	# Altar (bloqueo; se reemplaza por el Altar de Modular Dungeon en la fase de arte).
	var altar_z := zc - room.z / 2 + 2.0
	_box(comb, "AltarStep", Vector3(6, 0.5, 4), Vector3(0, 0.25, altar_z), room_mat)
	_box(comb, "Altar", Vector3(2.4, 1.0, 1.2), Vector3(0, 1.0, altar_z - 0.6), room_mat)

	var ending := _node(root, Node3D.new(), "Ending")
	var elysia := (load(ELYSIA) as PackedScene).instantiate() as Node3D
	elysia.name = "Elysia"
	elysia.position = Vector3(0, 0.5, altar_z + 1.0)   # sobre el escalón, mirando al sur (pasillo)
	ending.add_child(elysia)
	var trig := _area(ending, "EndingTrigger", Vector3(room.x - 2, 3, 3), Vector3(0, 1.5, altar_z + 5.0))
	trig.set_meta("doc", "Kaelen frente a Elysia → ending_director.gd (A)")
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.6)
	light.light_energy = 1.6
	light.omni_range = 10
	light.position = Vector3(0, 4, altar_z + 2)
	_node(ending, light, "AltarLight")
	_camera(ending, "EndingCam1", Vector3(3.5, 2.2, altar_z + 6.5), Vector3(0, 1.3, altar_z + 1))
	_camera(ending, "EndingCam2", Vector3(0, 1.6, zc + room.z / 2 + 2), Vector3(0, 1.3, altar_z + 1))
	_node(ending, Marker3D.new(), "KaelenEndPoint").position = Vector3(0, 0, altar_z + 3.0)
	# ExitTrigger del piso 3 no lleva a otro piso: se deja en el pasillo por si A lo necesita.
	return {"pos": Vector3(0, 1.5, z0 - 3.0), "size": Vector3(GATE_W, 3.0, 2.0)}


func _corridor(comb: CSGCombiner3D, z0: float, length: float, dir: int, width: float,
		height: float, floor_mat: Material, wall_mat: Material) -> void:
	var zc := z0 + dir * length / 2
	var tag := "S" if dir == 1 else "N"
	_box(comb, "Floor" + tag, Vector3(width + 2, 1, length), Vector3(0, -0.5, zc), floor_mat)
	_box(comb, "Roof" + tag, Vector3(width + 2, 1, length), Vector3(0, height + 0.5, zc), wall_mat)
	_box(comb, "SideE" + tag, Vector3(1, height, length), Vector3(width / 2 + 0.5, height / 2, zc), wall_mat)
	_box(comb, "SideW" + tag, Vector3(1, height, length), Vector3(-width / 2 - 0.5, height / 2, zc), wall_mat)
	_box(comb, "End" + tag, Vector3(width + 2, height, 1), Vector3(0, height / 2, z0 + dir * (length + 0.5)), wall_mat)


# Escalones de 0.25 m: dir = sentido en Z (1 sur, -1 norte); up = 1 sube, -1 baja.
func _stairs(comb: CSGCombiner3D, start: Vector3, dir: int, up: int, steps: int, width: float,
		mat: Material) -> void:
	for i in steps:
		var top := start.y + up * (i + 1) * STEP_H
		var z := start.z + dir * (i + 0.5) * STEP_D
		if up > 0:
			_box(comb, "Step%d" % i, Vector3(width, top, STEP_D), Vector3(0, top / 2, z), mat)
		else:   # baja: se recorta del suelo (las escaleras de llegada solo se ven)
			_box(comb, "Step%d" % i, Vector3(width, -top + 0.01, STEP_D),
				Vector3(0, top / 2, z), mat, CSGShape3D.OPERATION_SUBTRACTION)


func _gates(root: Node3D, half_d: float) -> void:
	var mat := _mat("metal_512", Color(0.45, 0.42, 0.4))
	for g in [["GateEntry", 1], ["GateExit", -1]]:
		var body := AnimatableBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = Vector3(0, GATE_H / 2, g[1] * (half_d + WALL_T / 2))
		body.set_meta("open_offset", Vector3(0, -GATE_H - 0.1, 0))   # se abre bajando al suelo
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


func _markers(root: Node3D, cfg: Dictionary, half_d: float) -> void:
	var ps := _node(root, Marker3D.new(), "PlayerStart")
	ps.position = Vector3(0, 0, cfg.player_start)   # a 4 m de la entrada, mirando al norte
	var bs := _node(root, Marker3D.new(), "BossStart")
	bs.position = cfg.boss_start
	bs.rotation_degrees.y = 180   # mira al sur, hacia Kaelen
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
	t.set_meta("doc", "Kaelen la cruza → GameState.advance_level() (A)")


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
	print("  %s: %d polígonos" % [name, nm.get_polygon_count()])


# --- Kit / GridMap --------------------------------------------------------------------------

# Muros en GridMap (celdas de 4 m) en el mismo lugar que el bloqueo CSG: cada muro va en la celda
# de fuera del interior, pegado al borde que da al interior. Los huecos de las rejas (2 celdas = 8 m)
# se cierran a 6 × 6 m con jambas y dintel CSG. El suelo sigue siendo un bloque CSG (colisión
# continua y sin juntas para la navegación); encima se pintan las baldosas del kit.
func _grid_shell(geo: Node3D, shell: CSGCombiner3D, cfg: Dictionary, wall_mat: Material) -> void:
	var gm := GridMap.new()
	gm.mesh_library = load(KIT_LIB)
	gm.cell_size = Vector3(4, 4, 4)
	gm.cell_center_y = false
	gm.collision_layer = 1
	gm.collision_mask = 0
	_node(geo, gm, "GridMap")
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
	# Suelo (y techo) del interior, más el suelo de los huecos de las rejas.
	for x in range(-nx / 2, nx / 2):
		for z in range(-nz / 2, nz / 2):
			gm.set_cell_item(Vector3i(x, 0, z), floor_id)
			if cfg.ceiling:
				gm.set_cell_item(Vector3i(x, int(h / 4), z), ceil_id)
		if x == -1 or x == 0:
			gm.set_cell_item(Vector3i(x, 0, -nz / 2 - 1), floor_id)
			gm.set_cell_item(Vector3i(x, 0, nz / 2), floor_id)
	_box(shell, "Floor", Vector3(w + 2 * WALL_T, 1, d + 2 * WALL_T), Vector3(0, -0.55, 0), wall_mat)
	# Muros: [celda, giro]. La pieza ocupa el borde norte de su celda; el giro la lleva al borde
	# que toca el interior (sur → 0°, norte → 180°, este → +90°, oeste → -90°).
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
	# Esquinas (1 × 1 m que el GridMap deja libres) y marco de las rejas.
	var top := float(int(GATE_H / 4) + 1) * 4.0   # alto del hueco en la grilla (8 m)
	for sx in [1, -1]:
		for sz in [1, -1]:
			_box(shell, "Corner%d%d" % [sx, sz], Vector3(1, h, 1),
				Vector3(sx * (w / 2 + 0.5), h / 2, sz * (d / 2 + 0.5)), wall_mat)
		for sz in [1, -1]:
			_box(shell, "Jamb%d%d" % [sx, sz], Vector3(1, top, 1),
				Vector3(sx * (GATE_W / 2 + 0.5), top / 2, sz * (d / 2 + 0.5)), wall_mat)
	for sz in [1, -1]:
		_box(shell, "Lintel%d" % sz, Vector3(GATE_W, top - GATE_H, 1),
			Vector3(0, GATE_H + (top - GATE_H) / 2, sz * (d / 2 + 0.5)), wall_mat)


# MeshLibrary con las piezas exportadas por Blender, material PSX con el atlas y colisión simple.
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


var _kit_mat: ShaderMaterial

# Instancia una pieza del kit con el material PSX (atlas Dungeon_Map).
func _kit_instance(name: String) -> Node3D:
	var node := (load(KIT + name + ".glb") as PackedScene).instantiate() as Node3D
	var mi := _first_mesh(node)
	if _kit_mat == null:
		_kit_mat = (load(PSX_BASE) as ShaderMaterial).duplicate()
		var src := mi.mesh.surface_get_material(0) as BaseMaterial3D
		_kit_mat.set_shader_parameter("albedoTex", src.albedo_texture)
		ResourceSaver.save(_kit_mat, KIT + "kit_psx.tres")
		_kit_mat = load(KIT + "kit_psx.tres")
	var mesh := mi.mesh.duplicate() as Mesh
	for s in mesh.get_surface_count():
		mesh.surface_set_material(s, _kit_mat)
	mi.mesh = mesh
	return node


func _first_mesh(n: Node) -> MeshInstance3D:
	return n if n is MeshInstance3D else n.find_children("*", "MeshInstance3D", true, false)[0]


# --- Utilidades -----------------------------------------------------------------------------

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
		c.rotation_degrees.y = 22.5   # una cara mirando al sur
	return _node(parent, c, name)


func _area(parent: Node, name: String, size: Vector3, pos: Vector3) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = 2   # solo el jugador (§7.7)
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


# Material de bloqueo: textura del kit con proyección triplanar en coordenadas de mundo
# (los CSG no tienen UV útiles; §6.4 lo permite temporalmente). Filtro nearest, sin mipmaps.
func _mat(tex_name: String, tint: Color) -> Material:
	var key := tex_name + str(tint)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + tex_name + ".png")
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.25, 0.25, 0.25)   # una repetición cada 4 m (un módulo)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_mats[key] = m
	return m


func _save(root: Node, path: String) -> void:
	# Las escenas *_gameplay.tscn son de A y B: el generador nunca las toca.
	assert(not path.ends_with("_gameplay.tscn"), "level_builder no debe escribir " + path)
	_set_owner(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		err = ResourceSaver.save(ps, path)
	print("%s → %s (%s)" % [root.name, path, error_string(err)])


func _set_owner(node: Node, owner: Node) -> void:
	for c in node.get_children():
		c.owner = owner
		if c.scene_file_path.is_empty():   # no entrar en escenas instanciadas (Elysia)
			_set_owner(c, owner)
