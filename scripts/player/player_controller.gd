class_name Player
extends CharacterBody3D
## Kaelen (Tarea 3). Por ahora solo el estado MOVE: caminar relativo a la cámara, gravedad y giro
## suave. ROLL, ATTACK, HURT y DEAD quedan para las Tareas 3 (rodada) y 6 (combate).

enum State { MOVE, ROLL, ATTACK, HURT, DEAD }

const WALK_SPEED := 5.0          # m/s (Tarea 3)
const ACCELERATION := 30.0       # m/s² al arrancar
const DECELERATION := 40.0       # m/s² al frenar
const TURN_SPEED := 12.0         # rapidez del giro hacia la dirección de avance
const MAX_STEP := 0.35           # escalón más alto que sube sola (los del mapa miden 0.25 m)
const STEP_PROBE := 0.2          # cuánto se adelanta para buscar la huella del escalón
const ROLL_DURATION := 0.6
const ROLL_IFRAME_START := 0.05
const ROLL_IFRAME_END := 0.40
const ROLL_COST := 25.0

# Velocidad del suelo a la que cada clip se ve sin patinar (medida a ojo con capturas; ver
# docs/asset-status.md). Por encima de RUN_ANIM_SPEED se acelera el clip `run`.
const WALK_ANIM_SPEED := 1.4
const RUN_ANIM_SPEED := 4.2

var state: State = State.MOVE

@onready var _model: Node3D = $Model
@onready var _camera_rig: CameraRig = $CameraRig
var _anim_tree: AnimationTree
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("player")
	_build_animation_tree()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Vector3.ZERO
	if state == State.MOVE and input != Vector2.ZERO:
		# Relativo a la cámara: solo importa su giro horizontal.
		dir = Basis(Vector3.UP, _camera_rig.yaw) * Vector3(input.x, 0.0, input.y)
		dir = dir.normalized() * minf(input.length(), 1.0)

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var goal := dir * WALK_SPEED
	var rate := ACCELERATION if goal.length() > horizontal.length() else DECELERATION
	horizontal = horizontal.move_toward(goal, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	var was_on_floor := is_on_floor()
	move_and_slide()
	if was_on_floor and is_on_wall() and dir != Vector3.ZERO:
		_try_step_up(dir * WALK_SPEED * delta)

	if dir != Vector3.ZERO:
		# El modelo de Mixamo mira a +Z: se gira para que su frente apunte hacia `dir`.
		var target_yaw := atan2(dir.x, dir.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, minf(1.0, TURN_SPEED * delta))
	_update_animation(horizontal.length())


# CharacterBody3D no sube escalones solo: si choca con algo de hasta MAX_STEP de alto, se prueba
# subirla, avanzar un poco y bajar hasta tocar el escalón; si hay apoyo, se eleva a esa altura y
# el siguiente move_and_slide la hace avanzar.
func _try_step_up(motion: Vector3) -> void:
	var probe := motion.normalized() * STEP_PROBE
	var from := global_transform
	if test_move(from, Vector3.UP * MAX_STEP):
		return   # techo encima
	var raised := from.translated(Vector3.UP * MAX_STEP)
	if test_move(raised, probe):
		return   # sigue siendo pared: no es un escalón
	var col := KinematicCollision3D.new()
	if not test_move(raised.translated(probe), Vector3.DOWN * MAX_STEP, col):
		return   # no hay suelo donde apoyarse
	var rise := MAX_STEP + col.get_travel().y
	if rise <= 0.01:
		return
	global_position.y += rise
	velocity.y = 0.0


func get_facing() -> Vector3:
	return _model.global_basis.z


## Coloca a Kaelen en un punto (Marker3D) del nivel y alinea la cámara detrás de ella.
func spawn_at(marker: Node3D) -> void:
	global_position = marker.global_position
	velocity = Vector3.ZERO
	var forward := -marker.global_basis.z   # los Marker3D miran a -Z
	_model.rotation.y = atan2(forward.x, forward.z)
	_camera_rig.yaw = atan2(-forward.x, -forward.z)
	_camera_rig.rotate_view(0.0, 0.0)
	_camera_rig.global_position = global_position + Vector3.UP * CameraRig.PIVOT_HEIGHT


# --- Animación --------------------------------------------------------------------------------
# AnimationTree simple: BlendSpace1D idle/walk/run según la velocidad y un TimeScale que acelera
# el clip cuando se va más rápido de lo que muestra (evita que los pies patinen).

func _build_animation_tree() -> void:
	var player := _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	space.max_space = WALK_SPEED
	for p in [["idle", 0.0], ["walk", WALK_ANIM_SPEED], ["run", RUN_ANIM_SPEED]]:
		var clip := AnimationNodeAnimation.new()
		clip.animation = p[0]
		space.add_blend_point(clip, p[1], -1, p[0])
	var tree := AnimationNodeBlendTree.new()
	tree.add_node(&"locomotion", space)
	tree.add_node(&"speed", AnimationNodeTimeScale.new())
	tree.connect_node(&"speed", 0, &"locomotion")
	tree.connect_node(&"output", 0, &"speed")
	_anim_tree = AnimationTree.new()
	_anim_tree.name = "AnimationTree"
	_anim_tree.tree_root = tree
	add_child(_anim_tree)
	_anim_tree.anim_player = _anim_tree.get_path_to(player)
	_anim_tree.active = true


func _update_animation(speed: float) -> void:
	_anim_tree.set("parameters/locomotion/blend_position", speed)
	var scale := 1.0
	if speed > RUN_ANIM_SPEED:
		scale = speed / RUN_ANIM_SPEED
	elif speed > 0.05 and speed < WALK_ANIM_SPEED:
		scale = maxf(0.6, speed / WALK_ANIM_SPEED)
	_anim_tree.set("parameters/speed/scale", scale)
