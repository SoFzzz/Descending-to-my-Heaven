class_name IslandSilhouette
extends SubViewportContainer
## Silueta negra de la isla flotante para el menú principal: un SubViewport 3D con fondo transparente
## donde la isla del juego y algunos islotes se dibujan en negro sin sombreado. La isla flota arriba y
## abajo y gira despacio sobre su eje vertical; los islotes flotan con desfase y orbitan.
## `distance_scale` (>1 aleja la cámara) y `pitch_degrees` se pueden animar con un Tween.

const ISLAND_DIR := "res://assets/environment/island/"
const MAIN_ISLAND := "island_main"
## Islotes: modelo, escala, radio y altura de la órbita, fase inicial (rad), velocidad orbital (rad/s).
const ISLETS := [
	{&"model": "islet_round", &"scale": 0.34, &"radius": 62.0, &"height": 30.0, &"phase": 0.6, &"speed": 0.16},
	{&"model": "islet_small", &"scale": 0.9, &"radius": 58.0, &"height": -30.0, &"phase": 2.6, &"speed": -0.2},
	{&"model": "islet_long", &"scale": 0.3, &"radius": 64.0, &"height": -4.0, &"phase": 4.4, &"speed": 0.12},
]
const SPIN_SPEED := 0.22          # rad/s sobre el eje vertical
const BOB_AMPLITUDE := 3.0        # unidades de mundo
const BOB_PERIOD := 5.0           # s
const CAMERA_DISTANCE := 275.0
const CAMERA_FOV := 28.0
const MAIN_CENTER_Y := -16.0      # centro vertical del modelo (cuelga bajo y = 0)

var distance_scale := 1.0
var pitch_degrees := 17.0

var _time := 0.0
var _viewport: SubViewport
var _camera: Camera3D
var _island: Node3D
var _islets: Array[Node3D] = []


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.fov = CAMERA_FOV
	_camera.far = 1000.0
	_viewport.add_child(_camera)
	var black := silhouette_material()
	_island = _spawn(MAIN_ISLAND, 1.0, black)
	for data: Dictionary in ISLETS:
		_islets.append(_spawn(data[&"model"], data[&"scale"], black))
	_update(0.0)


func _process(delta: float) -> void:
	_time += delta
	_update(_time)


func _spawn(model: String, model_scale: float, material: Material) -> Node3D:
	var holder := Node3D.new()
	holder.name = model.to_pascal_case()
	var scene := load(ISLAND_DIR + model + ".glb") as PackedScene
	if scene:
		var inst := scene.instantiate() as Node3D
		holder.add_child(inst)
		for node in inst.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).material_override = material
	holder.scale = Vector3.ONE * model_scale
	_viewport.add_child(holder)
	return holder


func _update(t: float) -> void:
	_island.position = Vector3(0.0, -MAIN_CENTER_Y + bob_offset(t), 0.0)
	_island.rotation.y = spin_angle(t)
	for i in _islets.size():
		var data: Dictionary = ISLETS[i]
		var angle: float = data[&"phase"] + t * float(data[&"speed"])
		var radius: float = data[&"radius"]
		var lift := sin(t * TAU / (BOB_PERIOD * (0.8 + 0.2 * i)) + float(i) * 1.9) * BOB_AMPLITUDE * 1.4
		_islets[i].position = Vector3(cos(angle) * radius, float(data[&"height"]) + lift, sin(angle) * radius * 0.6)
		_islets[i].rotation.y = -t * SPIN_SPEED * 0.6 + i
	var pitch := deg_to_rad(pitch_degrees)
	var dist := CAMERA_DISTANCE * distance_scale
	_camera.position = Vector3(0.0, sin(pitch) * dist, cos(pitch) * dist)
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)


## Material negro puro sin sombreado: la isla se lee como silueta.
static func silhouette_material() -> StandardMaterial3D:
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	return black


## Desplazamiento vertical de la isla (flotar) en el instante `t`.
static func bob_offset(t: float) -> float:
	return sin(t * TAU / BOB_PERIOD) * BOB_AMPLITUDE


## Giro de la isla sobre su eje vertical en el instante `t`.
static func spin_angle(t: float) -> float:
	return fposmod(t * SPIN_SPEED, TAU)


func island_node() -> Node3D:
	return _island


func islet_count() -> int:
	return _islets.size()
