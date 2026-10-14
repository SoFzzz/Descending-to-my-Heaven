class_name CameraRig
extends Node3D
## Kaelen's orbital camera (spec §7.5). Child of Kaelen with top_level = true, so it follows
## her position but not her rotation. Structure: CameraRig (pivot at 1.5 m) → SpringArm3D → Camera3D.
## The SpringArm3D only collides with the `world` layer: when touching a wall it moves closer instead of going through it.
## With a locked target (Kaelen's LockOn) the rotation follows the LockOnPoint, smoothly; if the
## target is a boss (group "boss") the pivot rises to 2.5 m, the arm extends to 6.5 m and the FOV
## changes to 75° (spec §7.5).

const PIVOT_HEIGHT := 1.5
const MOUSE_SENSITIVITY := 0.0025   # radians per pixel
const STICK_SPEED := 2.5            # radians per second with the right stick
const PITCH_MIN := deg_to_rad(-60.0)
const PITCH_MAX := deg_to_rad(35.0)
const FOLLOW_SPEED := 12.0
const PIVOT_HEIGHT_BOSS := 2.5
const ARM_LENGTH := 4.0
const ARM_LENGTH_BOSS := 6.5
const FOV := 70.0
const FOV_BOSS := 75.0
const LOCK_TURN_SPEED := 8.0        # how fast the rotation reaches the locked target
const LOCK_PITCH_OFFSET := deg_to_rad(-12.0)  # looks slightly above the shoulder, downward
const ZOOM_SPEED := 4.0             # interpolation speed for pivot, arm and FOV

var yaw: float = 0.0
var pitch: float = deg_to_rad(-15.0)

var pivot_height := PIVOT_HEIGHT

@onready var _target: Node3D = get_parent()
@onready var _arm: SpringArm3D = $SpringArm3D
@onready var _camera: Camera3D = get_node_or_null(^"SpringArm3D/Camera3D") as Camera3D


func _ready() -> void:
	top_level = true
	snap_to_target()
	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Places the camera behind the target without interpolating (on spawn or respawn).
func snap_to_target() -> void:
	yaw = _target.global_rotation.y
	global_position = _target.global_position + Vector3.UP * pivot_height
	_apply_rotation()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_view(-event.relative.x * MOUSE_SENSITIVITY, -event.relative.y * MOUSE_SENSITIVITY)
	elif event.is_action_pressed("pause"):
		# Until the pause menu exists (Task 10), Esc only releases the cursor.
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
	var lock_target := _lock_target()
	var boss := lock_target != null and lock_target.is_in_group(&"boss")
	var t := minf(1.0, ZOOM_SPEED * delta)
	pivot_height = lerpf(pivot_height, PIVOT_HEIGHT_BOSS if boss else PIVOT_HEIGHT, t)
	_arm.spring_length = lerpf(_arm.spring_length, ARM_LENGTH_BOSS if boss else ARM_LENGTH, t)
	if _camera:
		_camera.fov = lerpf(_camera.fov, FOV_BOSS if boss else FOV, t)
	var goal := _target.global_position + Vector3.UP * pivot_height
	global_position = global_position.lerp(goal, minf(1.0, FOLLOW_SPEED * delta))
	if lock_target:
		_face_point(LockOn.aim_point(lock_target), delta)


func _lock_target() -> Node3D:
	if _target is Player:
		return (_target as Player).get_lock_target()
	return null


## Turns (smoothly) so the point ends up centered: yaw toward the point and a slightly lower pitch.
func _face_point(point: Vector3, delta: float) -> void:
	var to_point := point - global_position
	var flat := Vector2(to_point.x, to_point.z).length()
	if flat < 0.3:
		return   # directly above the target: do not spin wildly
	var goal_yaw := atan2(-to_point.x, -to_point.z)
	var goal_pitch := clampf(atan2(to_point.y, flat) + LOCK_PITCH_OFFSET, PITCH_MIN, PITCH_MAX)
	var k := minf(1.0, LOCK_TURN_SPEED * delta)
	yaw = wrapf(lerp_angle(yaw, goal_yaw, k), -PI, PI)
	pitch = lerpf(pitch, goal_pitch, k)
	_apply_rotation()


func _apply_rotation() -> void:
	rotation = Vector3(pitch, yaw, 0.0)
