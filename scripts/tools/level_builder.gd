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
# Salida alternativa para probar sin tocar las escenas del juego: `-- out=C:/ruta/` (con barra final).
var _out_dir := OUT_DIR
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
# Volumen de horneado de la navegación: x ±40, z de −90 a 60 (llega al fondo de la sala de Elysia),
# y de −0.5 a 1.5 m (el suelo está en 0; los escalones de más de 1.5 m y todo lo alto quedan fuera).
const NAV_AABB := AABB(Vector3(-40, -0.5, -90), Vector3(80, 2.0, 150))

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
		# Spawns detrás de los pilares (vistos desde el centro) y en los muros este/oeste. Los laterales
		# estaban en (±18, 0), dentro del cono de la cámara al inicio (solo 2 puntos válidos); en (±18, 7)
		# quedan junto a la pared lateral, fuera del cono y a > 8 m de PlayerStart (4 válidos).
		"spawns": [[-12, -12], [12, -12], [-12, 12], [12, 12], [-18, 7], [18, 7]],
		"player_start": 16.0, "boss_start": Vector3(0, 0, -9),
		"torches": [[-19, -10], [19, -10], [-19, 10], [19, 10], [0, -19], [0, 19]],
		"exit": "stairs",
		"fog_end": 48.0,   # la niebla base (30 m) tapaba al jefe desde el inicio
	},
	"arena_2": {
		"title": "Claustro (Blackhorn)",
		"shape": "oct", "size": Vector2(30, 30), "height": 8.0, "ceiling": true,
		"output": "gridmap", "wall_rows": [["wall"], ["wall", "wall_window"]],
		"floor_tex": "concrete_512_indexed", "wall_tex": "concrete_512_indexed",
		"tint": Color(0.82, 0.88, 1.0), "light": Color(0.75, 0.85, 1.0),
		"pillars": "ring6",   # 6 columnas de 1.2 m en anillo de radio 8, a 30° + k·60°
		# Antes "ring6" (radio 12.5): al inicio los 6 estaban en el cono de la cámara o a < 8 m. Ahora van
		# hacia las paredes laterales y traseras (la entrada está al sur, Kaelen mira al norte).
		"spawns": [[-8, 10], [8, 10], [-12.5, 6], [12.5, 6], [-12.5, -6], [12.5, -6]],
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
		# (±21, 9) en vez de (-21, 0) y (21, -3): esos quedaban dentro del cono de la cámara al inicio.
		"spawns": [[-16, -16], [16, -16], [-16, 16], [16, 16], [-21, 9], [21, 9]],
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
	# Sendero de 7 m; la pared invisible del fondo está en path_start_z y Kaelen empieza a 6 m de ella
	# (a 2 m el SpringArm de la cámara chocaba con la pared y quedaba a 1.7 m de Kaelen, no a 4 m).
	"path_half_w": 3.5, "path_start_z": 40.0, "start_back": 6.0,
	# Línea central del sendero (x, z): recto hasta z = 19, curva a la izquierda para rodear el hueco
	# de la nariz de la calavera, y vuelve al eje x = 0 antes de la explanada.
	"path": [Vector2(0, 40), Vector2(0, 19), Vector2(-5.5, 13.5), Vector2(-5.5, 1), Vector2(0, -4.5),
		Vector2(0, -22)],
	"plaza": Rect2(-10, -31, 20, 9),                    # explanada ante la puerta (x, z, ancho, fondo)
	# Templo: `temple_z` = cara sur de la puerta; el resto del diseño está en `_temple`.
	"temple_z": -31.0,
	# Puerta = hueco con el contorno del arco del kit (arch.glb, estirado ×1.6 en vertical): ancho
	# interior 3.2 m, alto 3.2 m (la puerta normal de §7.3 mide 3 × 2; esta es la del templo).
	"door": Vector2(3.2, 3.2),
	# Estanques que tapan los huecos de la isla [centro (x, z), semiejes (x, z), y del agua]: ojo izquierdo, ojo
	# derecho y nariz de la calavera (medidos con rayos contra `island_main`; ver docs/problemas-mapa.md).
	"ponds": [[Vector2(-17.5, -10.0), Vector2(11.0, 14.0), -0.3], [Vector2(27.5, -10.0), Vector2(9.5, 14.0), -0.3],
		[Vector2(6.0, 6.5), Vector2(9.5, 9.5), 1.4]],
	# Bosque lejano: anillos de siluetas (radio, base y, alto) y capas de niebla [y, densidad].
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

var _mats := {}


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
	# El cielo bajo el horizonte era casi negro (se veía como un vacío): el "suelo" del cielo pasa a la
	# bruma, que además cubren el mar de niebla (_mist) y las siluetas del bosque (_forest).
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
	_ponds(root, cfg)
	_forest(root, cfg)
	_mist(root, cfg)

	for i in 3:
		await physics_frame
	var ground := func(x: float, z: float) -> float:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -60, z))
		var r := root.get_world_3d().direct_space_state.intersect_ray(q)
		return r.position.y if r else 0.0

	# Templo antiguo escalonado con puerta, columnas, alas con tejado y ruinas (ver _temple).
	var geo := _temple(root, cfg, ground)
	var tz: float = cfg.temple_z
	var base_y: float = geo.get_meta("base_y")
	var door: Vector2 = cfg.door

	# Sendero: polilínea `path` (x, z) de sur a norte con curvas a 45° (la isla "calavera" tiene un hueco
	# en la nariz, x ∈ [-1, 11], z ∈ [2, 12], justo en la línea recta), pilares bajos cada 8 m a los
	# lados y paredes invisibles que lo encierran.
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
	# Paredes: una cadena a cada lado de la polilínea. En cada curva el lado exterior se alarga
	# hw·tan(θ/2) (+0.2 de solape) y el interior se acorta lo mismo (si no, taparía el sendero).
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
	var boxes := []   # [centro 2D, largo, yaw, alto de suelo]
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
	# Pared del fondo (perpendicular al primer tramo, 6 m detrás de Kaelen) y explanada ante la puerta.
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
	print("  sendero: inicio z=%.1f y=%.2f, puerta y=%.2f, recorrido ≈ %d m" % [ps.position.z, ps.position.y, base_y,
		int(path_len - start_back + (pe.y - tz))])
	_save(root, _out_dir + "exterior.tscn")
	root.queue_free()
	await process_frame


# Punto de la polilínea a `dist` metros del inicio: [posición, normal a la izquierda del avance].
func _path_at(path: Array, dist: float) -> Array:
	var left := dist
	for i in path.size() - 1:
		var seg: Vector2 = path[i + 1] - path[i]
		if left <= seg.length() or i == path.size() - 2:
			var d := seg.normalized()
			return [path[i] + d * minf(left, seg.length()), Vector2(-d.y, d.x)]
		left -= seg.length()
	return [path[0], Vector2.RIGHT]


# --- Entorno del exterior: estanques, bosque lejano y niebla ----------------------------------

# Los ojos y la nariz de la calavera son huecos que atraviesan la isla (se veía el vacío). Cada estanque es
# un plano de agua con shader (olas por vértice, ondas cuantizadas) a la altura del borde del hueco. No
# lleva colisión ni suelo: Kaelen nunca llega (las paredes invisibles encierran el sendero y la explanada),
# así que antes tampoco podía caer ahí; el agua solo tapa la vista.
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


# Anillos de árboles lejanos alrededor de la isla y por debajo de su nivel, asomando del mar de niebla: el
# borde parece seguir en un bosque enorme. Usan los modelos del pack "ps1-style tree pack"
# (assets/environment/trees/). Cada anillo es un nodo con `ForestRing`, que arma sus MultiMesh al entrar al
# árbol (con semilla fija) y los oscurece y funde con la bruma por distancia (shaders/forest_tree.gdshader).
# Un MultiMesh no se guarda si este generador corre con --headless; por eso solo se guardan los parámetros.
# La cámara de Kaelen ve hasta 300 m, así que los anillos quedan dentro de ese rango.
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


# Capas horizontales de niebla (mar de niebla) a distintas alturas bajo la isla.
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


# --- Templo (fachada del exterior) ---------------------------------------------------------
# Templo antiguo escalonado (referencia: torre de pisos decrecientes sobre una puerta con frontón, columnas
# a los lados y alas con tejado inclinado). Solo cambia el diseño: mismas texturas del kit y de
# `assets/environment/textures/`. La colisión la dan el cuerpo CSG (puerta + alas) y unas cajas
# (columnas, estatuas, escombros); el resto son mallas sin colisión (inalcanzables o decorativas).
# Medidas en metros; `f` = z de la cara sur de la puerta; el hueco de la puerta y el `ExitTrigger` no cambian.

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

	# Cuerpo con colisión: bloque de la puerta (12 × 10) y dos alas bajas; se hunde 8 m en el terreno.
	var comb := _combiner(geo, "Body")
	_box(comb, "Gate", Vector3(12, 17, 10), Vector3(0, b + 0.5, f - 5), stone)
	for sx in [-1, 1]:
		_box(comb, "Wing%s" % ("E" if sx > 0 else "W"), Vector3(14.5, 13, 7), Vector3(sx * 13.25, b - 1.5, f - 5), stone)
	# Hueco de la puerta: tramo recto (0.2 m del arco × 1.6) + semielipse de a = 1.6, b = 1.8 × 1.6 m,
	# igual al interior de arch.glb escalado; el arco queda pegado al hueco sin franja de muro.
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

	# Fachadas con muros del kit (piezas de ~4 m estiradas, a 5 cm del plano; sin colisión).
	var facade := _node(geo, Node3D.new(), "Facade")
	_facade(facade, "GateS", Vector3(0, b, f), 0.0, 12, 9, Vector2(4, 4), ["wall", "wall_ruin", "wall"])
	for sx in [-1, 1]:
		var tag := "E" if sx > 0 else "W"
		_facade(facade, "Wing%sS" % tag, Vector3(sx * 13.25, b, f - 1.5), 0.0, 14.5, 5, Vector2.ZERO,
			["wall", "wall_window", "wall", "wall_ruin"])
		_facade(facade, "Wing%sEnd" % tag, Vector3(sx * 20.5, b, f - 5), sx * PI / 2, 7, 5, Vector2.ZERO, ["wall", "wall_ruin"])
		_facade(facade, "Gate%sSide" % tag, Vector3(sx * 6.0, b + 5, f - 5.75), sx * PI / 2, 8.5, 4, Vector2.ZERO, ["wall"])
		_facade(facade, "Wing%sBack" % tag, Vector3(sx * 13.25, b, f - 8.5), PI, 14.5, 5, Vector2.ZERO, ["wall"])

	# Puerta: arco del kit pegado al hueco, jambas con columnas, dintel con friso de calaveras, frontón
	# con tímpano y hojas de madera abiertas hacia dentro (el hueco queda libre: ExitTrigger y paso intactos).
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
	for sx in [-1, 1]:   # hojas de madera entreabiertas hacia dentro, con refuerzos de metal
		var leaf := Node3D.new()
		leaf.position = Vector3(sx * door.x / 2, b + 0.1, f - 0.1)
		leaf.rotation_degrees.y = -sx * 78.0
		_node(dec, leaf, "Leaf%s" % ("E" if sx > 0 else "W"))
		var lw := door.x / 2 - 0.05
		_mbox(leaf, "Wood", Vector3(lw, 2.9, 0.16), Vector3(-sx * lw / 2, 1.45, 0), wood)
		for k in 3:
			_mbox(leaf, "Strap%d" % k, Vector3(lw + 0.04, 0.16, 0.2), Vector3(-sx * lw / 2, 0.5 + k * 1.0, 0), metal)
	# Guardianes de piedra a los lados de la puerta (pedestal + cuerpo + cabeza) con colisión simple.
	for sx in [-1, 1]:
		var gx: float = sx * 7.6
		_mbox(dec, "Pedestal%d" % sx, Vector3(2.0, 1.3, 2.0), Vector3(gx, b + 0.65, f + 2.2), trim)
		_mbox(dec, "Beast%d" % sx, Vector3(1.2, 1.0, 1.9), Vector3(gx, b + 1.8, f + 2.2), stone)
		_mbox(dec, "BeastHead%d" % sx, Vector3(0.9, 0.85, 0.9), Vector3(gx, b + 2.15, f + 3.0), stone)
		_frame_box(col_body, "Guardian%d" % sx, Vector3(2.0, 2.4, 2.0), Vector3(gx, b + 1.2, f + 2.2))

	# Torre escalonada: cuatro pisos decrecientes con cornisa, frontón en la cara sur y remate.
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

	# Alas con tejado inclinado a dos aguas (caballete a lo largo de X), tejas rotas y musgo.
	for sx in [-1, 1]:
		var tag := "E" if sx > 0 else "W"
		_mprism(dec, "Roof" + tag, Vector3(9.0, 3.0, 15.4), Vector3(sx * 13.25, b + 6.5, f - 5), roof, Vector3(0, 90, 0))
		_mbox(dec, "Eave" + tag, Vector3(15.0, 0.4, 0.6), Vector3(sx * 13.25, b + 5.1, f - 1.0), trim)
		for k in 3:
			var south := k % 2 == 0
			_mbox(dec, "RoofMoss%s%d" % [tag, k], Vector3(2.0 + rng.randf() * 2.0, 0.08, 1.4),
				Vector3(sx * (9.0 + rng.randf() * 10.0), b + 6.56, f - 5 + (2.25 if south else -2.25)),
				moss, Vector3(33.7 if south else -33.7, 0, 0))
		for k in 5:   # tejas caídas sobre el caballete
			_mbox(dec, "Tile%s%d" % [tag, k], Vector3(0.7, 0.12, 0.5),
				Vector3(sx * (8.0 + rng.randf() * 11.0), b + 8.1, f - 5 + rng.randf_range(-0.6, 0.6)), roof,
				Vector3(rng.randf_range(-20, 20), rng.randf() * 180.0, rng.randf_range(-20, 20)))

	# Árbol grande con raíces contra el ala oeste (como la referencia), arbustos y escombros.
	var tree := Vector3(-11.0, b, f - 3.0)
	# El árbol es un modelo del pack de árboles PS1 (tree02) con el mismo script del bosque, con poca bruma.
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
	for k in 6:   # mantiene la secuencia aleatoria de los arbustos de abajo
		rng.randf()
	for k in 12:
		var bx := rng.randf_range(-19.0, 19.0)
		if absf(bx) < 5.0:
			bx = signf(bx + 0.01) * (5.0 + rng.randf() * 3.0)
		var bz := f + (rng.randf_range(0.2, 1.6) if absf(bx) < 8.0 else rng.randf_range(-1.2, 0.8))
		if bx > -13.0 and bx < -9.0:
			continue
		_msphere(dec, "Bush%d" % k, 0.5 + rng.randf() * 0.5, Vector3(bx, b + 0.3, bz), moss, Vector3(1.3, 0.8, 1.1))
	for k in 9:   # piedras caídas con colisión (cajas inclinadas), repartidas por la explanada
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
	for sx in [-1, 1]:   # columna caída del kit junto a cada lado de la explanada
		var pc := _kit_mesh("pillar_collapsed")
		pc.position = Vector3(sx * 7.6, ground.call(sx * 7.6, f + 6.5) - 0.2, f + 6.5)
		pc.rotation_degrees.y = sx * 35.0
		pc.scale = Vector3(1.2, 1.0, 1.2)
		_node(dec, pc, "FallenPillar%d" % sx)

	_area(root, "ExitTrigger", Vector3(door.x, 3, 1.5), Vector3(0, b + 1.5, f + 0.5)).set_meta("doc", "Kaelen entra al templo → GameState.advance_level() (A)")
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


# Prisma triangular: la base (x) y la altura (y) son el triángulo; `size.z` es la longitud de la extrusión.
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


# Cara de muro del kit: `pos` = centro inferior de la cara, `yaw` hace que +Z mire hacia fuera. Piezas de
# ~4 m estiradas para llenar ancho × alto; `gap` (ancho, alto) deja un hueco centrado abajo (la puerta).
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


# Copia de una malla del kit con material PSX como MeshInstance3D suelto (se guarda en la escena).
func _kit_mesh(name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _kit_mesh_res(name)
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
	_stair_ramp(geo, "EntryRamp", Vector3(0, 0, z0 + 6.0), 1, -1, steps, GATE_W)


# Salida norte de los pisos 1 y 2: pasillo + escalera que sube 4 m + rellano con ExitTrigger.
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
	var room_mat := wall_mat   # piedra de la mazmorra (antes dorada): el muro norte y el altar casan con la sala
	_box(comb, "RoomFloor", Vector3(room.x + 2, 1, room.z + 2), Vector3(0, -0.5, zc), floor_mat)
	_box(comb, "RoomCeiling", Vector3(room.x + 2, 1, room.z + 2), Vector3(0, room.y + 0.5, zc), wall_mat)
	_box(comb, "RoomWallN", Vector3(room.x + 2, room.y, 1), Vector3(0, room.y / 2, zc - room.z / 2 - 0.5), room_mat)
	_box(comb, "RoomWallS", Vector3(room.x + 2, room.y, 1), Vector3(0, room.y / 2, zc + room.z / 2 + 0.5), wall_mat)
	_box(comb, "RoomWallE", Vector3(1, room.y, room.z), Vector3(room.x / 2 + 0.5, room.y / 2, zc), wall_mat)
	_box(comb, "RoomWallW", Vector3(1, room.y, room.z), Vector3(-room.x / 2 - 0.5, room.y / 2, zc), wall_mat)
	_box(comb, "RoomDoor", Vector3(GATE_W, GATE_H, 3), Vector3(0, GATE_H / 2, zc + room.z / 2 + 0.5),
		wall_mat, CSGShape3D.OPERATION_SUBTRACTION)
	_break_room(comb, room, zc, room_mat)
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


# Sala de Elysia rota: hueco irregular en el muro norte (sube hasta el techo) y techo abierto en
# esa esquina; el exterior, los escombros y la caída los pone scenes/props/ending_room.tscn.
func _break_room(comb: CSGCombiner3D, room: Vector3, zc: float, mat: Material) -> void:
	var wz := zc - room.z / 2 - 0.5
	# [nombre, tamaño, posición (x, y, z), giro en Z (grados), giro en Y (grados)]
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


# Rampa de colisión de una escalera: los peldaños CSG solo se ven; el jugador pisa un plano inclinado que
# pasa a 2 cm por encima de los cantos de los peldaños, así que un CharacterBody3D la sube y la baja sin
# el salto brusco de un escalón de 0.25 m (antes dependía de `_try_step_up`, que lo teletransporta).
# Cuña convexa: `start` = pie de la escalera, `dir` = sentido en Z, `up` = 1 sube / -1 baja.
func _stair_ramp(parent: Node, name: String, start: Vector3, dir: int, up: int, steps: int,
		width: float) -> StaticBody3D:
	var slope := STEP_H / STEP_D
	var total := steps * STEP_H
	var sink := -0.02   # negativo = 2 cm por encima de los cantos (que no los roce la cápsula)
	var prof: Array = []   # perfil (s a lo largo de la escalera, y) de la cara superior
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
	body.set_meta("doc", "Rampa de colisión de la escalera (los peldaños CSG son visuales)")
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
	# Solo el suelo: sin esto el horneado generaba polígonos en las cimas de muros, pilares y techo
	# (y ≈ 8–12 m). Se conservan las primeras huellas de las escaleras (sin ellas no hay sitio donde
	# apoyar la malla de la entrada) y se corta todo lo que pasa de NAV_MAX_Y.
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
	print("  %s: %d polígonos" % [name, nm.get_polygon_count()])


# --- Kit / GridMap --------------------------------------------------------------------------

# Muros en GridMap (celdas de 4 m) en el mismo lugar que el bloqueo CSG: cada muro va en la celda
# de fuera del interior, pegado al borde que da al interior. Los huecos de las rejas (2 celdas = 8 m)
# se cierran a 6 × 6 m con jambas y dintel CSG. El suelo sigue siendo un bloque CSG (colisión
# continua y sin juntas para la navegación); encima se pintan las baldosas del kit.
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
	# Esquinas (1 × 1 m que el GridMap deja libres, tapadas por los muros) y marco de las rejas.
	var top := float(int(GATE_H / 4) + 1) * 4.0   # alto del hueco en la grilla (8 m)
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
		for sx in [1, -1]:   # jambas: 1 m de ancho, a ambos lados del hueco de 6 m
			_frame_box(frame, "Jamb%d%d" % [sx, sz], Vector3(1, top, 1),
				Vector3(sx * (GATE_W / 2 + 0.5), top / 2, sz * (d / 2 + 0.5)))
			for r in int(top / 4):
				_piece(pieces, "Jamb%d%d_%d" % [sx, sz, r], "wall",
					Vector3(sx * (GATE_W / 2 + 0.5), r * 4.0, sz * (d / 2 + 2.0)), yaw, Vector3(0.25, 1, 1))
		_frame_box(frame, "Lintel%d" % sz, Vector3(GATE_W, top - GATE_H, 1),
			Vector3(0, GATE_H + (top - GATE_H) / 2, sz * (d / 2 + 0.5)))
		_piece(pieces, "Lintel%d" % sz, "wall", Vector3(0, GATE_H, sz * (d / 2 + 2.0)), yaw,
			Vector3(GATE_W / 4.0, (top - GATE_H) / 4.0, 1))


# Caja de colisión (sin malla) para jambas y dinteles: el aspecto lo dan las piezas del kit.
func _frame_box(body: StaticBody3D, name: String, size: Vector3, pos: Vector3) -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = pos
	_node(body, col, name)


# Pieza del kit como MeshInstance3D suelta (origen en el centro de la cara de 4 m; la cara interior
# del muro está en z local = −2, así que `pos` va 2 m hacia fuera del plano interior del muro).
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


# Octógono (cfg.size.x = distancia entre caras, p. ej. 30 m = 24 de combate + 3 m de margen por lado)
# con piezas del kit. No encaja en la grilla de 4 m, así que:
# - suelo y techo: baldosas de GridMap en las celdas que tocan el octágono (las que sobresalen por las
#   esquinas quedan fuera del muro, de 1 m de grosor, que llega al borde de la grilla); debajo, un
#   cilindro CSG de 8 lados cierra la colisión y la navegación sin juntas;
# - muros: 3 piezas por cara y fila, giradas k × 45° y estiradas al largo de la cara (12.43 / 3 m);
#   en las caras sur y norte quedan solo las piezas de los lados y el dintel CSG sobre la reja;
# - colisión de los muros: una caja por cara (dos en las caras de las rejas).
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
			if near_x + near_z >= apo * sqrt(2.0) - 0.1:   # fuera de las caras diagonales
				continue
			gm.set_cell_item(Vector3i(x, 0, z), floor_id)
			if cfg.ceiling:
				gm.set_cell_item(Vector3i(x, int(h / 4), z), ceil_id)
	_cyl(shell, "Floor", (apo + WALL_T) / cos(PI / 8), 1, Vector3(0, -0.55, 0), wall_mat, 8)

	var face_len := 2.0 * apo * tan(PI / 8)           # largo de la cara por dentro
	var half_out := (apo + WALL_T) * tan(PI / 8) + 0.1   # semilargo por fuera + solape con la vecina
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_node(geo, body, "WallBodies")
	var walls := _node(geo, Node3D.new(), "WallPieces")
	for k in 8:
		var a := k * PI / 4.0                       # 0 = cara sur; el giro lleva +Z (hacia fuera) a o
		var o := Vector3(sin(a), 0, cos(a))
		var tangent := Vector3(cos(a), 0, -sin(a))
		var gate := k == 0 or k == 4
		# Tramos de la cara [t0, t1] (a lo largo de la tangente) que llevan muro: piezas por dentro
		# (largo exacto de la cara) y cajas de colisión por fuera (con el solape de las esquinas).
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
		if gate:   # dintel sobre la reja: de 6 m a h (pieza de muro achatada; colisión en el cuerpo)
			var lcol := CollisionShape3D.new()
			var lbox := BoxShape3D.new()
			lbox.size = Vector3(GATE_W, h - GATE_H, WALL_T)
			lcol.shape = lbox
			lcol.transform = Transform3D(Basis(Vector3.UP, a),
				o * (apo + WALL_T / 2) + Vector3(0, GATE_H + (h - GATE_H) / 2, 0))
			_node(body, lcol, "Lintel%d" % k)
			_piece(walls, "Lintel%d" % k, "wall", o * (apo + 2.0) + Vector3(0, GATE_H, 0), a,
				Vector3(GATE_W / 4.0, (h - GATE_H) / 4.0, 1))
	print("  octógono: apotema %.1f m, cara %.2f m, %d baldosas" % [apo, face_len, gm.get_used_cells().size()])


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


var _kit_mat: Material

# Instancia una pieza del kit con el atlas Dungeon_Map. Material estándar (nearest, luz por vértice,
# sin culling) como el del resto del nivel, NO el shader psx_lit: su ajuste de vértices a rejilla
# hacía desaparecer las baldosas de 4 m con algún vértice detrás de la cámara (un hueco en el suelo
# junto a Kaelen). El aspecto PSX lo da el postproceso de baja resolución.
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


var _kit_meshes := {}

# Malla de una pieza del kit con material estándar, una sola por nombre (las escenas comparten el recurso).
func _kit_mesh_res(name: String) -> Mesh:
	if not _kit_meshes.has(name):
		var src := _kit_instance(name)
		_kit_meshes[name] = _first_mesh(src).mesh
		src.free()
	return _kit_meshes[name]


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
	# La primera Camera3D que entra al árbol (el del generador) queda como actual y se guardaría con
	# `current = true`, secuestrando la cámara de Kaelen. El final (Tarea 15) las activa por código.
	cam.clear_current(false)


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
	for cam: Camera3D in root.find_children("*", "Camera3D", true, false):
		cam.clear_current(false)   # ninguna cámara del nivel se guarda como actual
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		err = ResourceSaver.save(ps, path)
	print("%s → %s (%s)" % [root.name, path, error_string(err)])


func _set_owner(node: Node, owner: Node) -> void:
	for c in node.get_children():
		if c is MultiMeshInstance3D:   # los arma ForestRing al entrar al árbol; no se guardan en la escena
			continue
		c.owner = owner
		if c.scene_file_path.is_empty():   # no entrar en escenas instanciadas (Elysia)
			_set_owner(c, owner)
