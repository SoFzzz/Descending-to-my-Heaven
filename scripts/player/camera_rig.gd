class_name CameraRig
extends Node3D
## Cámara orbital de Kaelen (spec §7.5). Va como hijo de Kaelen con top_level = true, así sigue
## su posición pero no su giro. Estructura: CameraRig (pivote a 1.5 m) → SpringArm3D → Camera3D.
## El SpringArm3D solo choca con la capa `world`: al tocar una pared se acerca en vez de atravesarla.

const PIVOT_HEIGHT := 1.5
const MOUSE_SENSITIVITY := 0.0025   # radianes por píxel
const STICK_SPEED := 2.5            # radianes por segundo con el stick derecho
const PITCH_MIN := deg_to_rad(-60.0)
const PITCH_MAX := deg_to_rad(35.0)
const FOLLOW_SPEED := 12.0

var yaw: float = 0.0
var pitch: float = deg_to_rad(-15.0)

@onready var _target: Node3D = get_parent()
@onready var _arm: SpringArm3D = $SpringArm3D


func _ready() -> void:
	top_level = true
	snap_to_target()
	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Coloca la cámara detrás del objetivo sin interpolar (al aparecer o reaparecer).
func snap_to_target() -> void:
	yaw = _target.global_rotation.y
	global_position = _target.global_position + Vector3.UP * PIVOT_HEIGHT
	_apply_rotation()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_view(-event.relative.x * MOUSE_SENSITIVITY, -event.relative.y * MOUSE_SENSITIVITY)
	elif event.is_action_pressed("pause"):
		# Hasta que exista el menú de pausa (Tarea 10), Esc solo libera el cursor.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func rotate_view(d_yaw: float, d_pitch: float) -> void:
	yaw = wrapf(yaw + d_yaw, -PI, PI)
	pitch = clampf(pitch + d_pitch, PITCH_MIN, PITCH_MAX)
	_apply_rotation()


func _process(delta: float) -> void:
	var stick := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if stick != Vector2.ZERO:
		rotate_view(-stick.x * STICK_SPEED * delta, -stick.y * STICK_SPEED * delta)
	var goal := _target.global_position + Vector3.UP * PIVOT_HEIGHT
	global_position = global_position.lerp(goal, minf(1.0, FOLLOW_SPEED * delta))


func _apply_rotation() -> void:
	rotation = Vector3(pitch, yaw, 0.0)
