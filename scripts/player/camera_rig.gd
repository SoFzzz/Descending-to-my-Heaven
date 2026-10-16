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
## With a boss locked far away (huge bosses) the arm lengthens so it fits entirely on screen:
## +ARM_PER_METER m for every meter of horizontal distance above ARM_FAR_FROM, up to ARM_EXTRA_MAX.
const ARM_FAR_FROM := 8.0
const ARM_PER_METER := 0.4
const ARM_EXTRA_MAX := 3.0
const LOCK_TURN_SPEED := 8.0        # how fast the rotation reaches the locked target
const LOCK_PITCH_OFFSET := deg_to_rad(-12.0)  # looks slightly above the shoulder, downward
const ZOOM_SPEED := 4.0             # interpolation speed for pivot, arm and FOV

var yaw: float = 0.0
var pitch: float = deg_to_rad(-15.0)

var pivot_height := PIVOT_HEIGHT

var _shake_amplitude := 0.0
var _shake_total := 0.0
var _shake_left := 0.0

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
		var k := MOUSE_SENSITIVITY * look_sensitivity()
		rotate_view(-event.relative.x * k, -event.relative.y * k)
	# "pause" is handled by the pause menu (GameState). A click recaptures the mouse if it was
	# released (e.g. after alt-tab), never while the game is paused.
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


## Right stick response: the dead zone is already applied by Input.get_vector (0.2 in the InputMap);
## here it is smoothed with a quadratic curve for fine aiming with little travel and fast turning at full tilt.
static func stick_look(raw: Vector2) -> Vector2:
	return raw * raw.length()


## Sensitivity multiplier chosen in the options (mouse and stick); 1.0 if there are no settings.
func look_sensitivity() -> float:
	var settings := get_node_or_null(^"/root/UserSettings") if is_inside_tree() else null
	return float(settings.get("look_sensitivity")) if settings else 1.0


func rotate_view(d_yaw: float, d_pitch: float) -> void:
	yaw = wrapf(yaw + d_yaw, -PI, PI)
	pitch = clampf(pitch + d_pitch, PITCH_MIN, PITCH_MAX)
	_apply_rotation()


## Camera shake of `amplitude` m that fades out linearly over `duration` s (boss repel).
func shake(amplitude: float, duration: float) -> void:
	_shake_amplitude = maxf(_shake_amplitude * _shake_left / maxf(_shake_total, 0.001), amplitude)
	_shake_total = duration
	_shake_left = duration


func _apply_shake(delta: float) -> void:
	if _camera == null:
		return
	if _shake_left <= 0.0:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		return
	_shake_left = maxf(0.0, _shake_left - delta)
	var k := _shake_amplitude * _shake_left / maxf(_shake_total, 0.001)
	_camera.h_offset = randf_range(-k, k)
	_camera.v_offset = randf_range(-k, k)


func _process(delta: float) -> void:
	_apply_shake(delta)
	var stick := stick_look(Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down"))
	if stick != Vector2.ZERO:
		var speed := STICK_SPEED * look_sensitivity()
		rotate_view(-stick.x * speed * delta, -stick.y * speed * delta)
	var lock_target := _lock_target()
	var boss := lock_target != null and lock_target.is_in_group(&"boss")
	var t := minf(1.0, ZOOM_SPEED * delta)
	pivot_height = lerpf(pivot_height, PIVOT_HEIGHT_BOSS if boss else PIVOT_HEIGHT, t)
	var arm_goal := ARM_LENGTH_BOSS + boss_arm_extra(_flat_distance(lock_target)) if boss else ARM_LENGTH
	_arm.spring_length = lerpf(_arm.spring_length, arm_goal, t)
	if _camera:
		_camera.fov = lerpf(_camera.fov, FOV_BOSS if boss else FOV, t)
	var goal := _target.global_position + Vector3.UP * pivot_height
	global_position = global_position.lerp(goal, minf(1.0, FOLLOW_SPEED * delta))
	if lock_target:
		_face_point(LockOn.aim_point(lock_target), delta)


## Extra arm meters for a boss locked at `distance` m (horizontally) from the camera.
static func boss_arm_extra(distance: float) -> float:
	return clampf((distance - ARM_FAR_FROM) * ARM_PER_METER, 0.0, ARM_EXTRA_MAX)


func _flat_distance(node: Node3D) -> float:
	if node == null:
		return 0.0
	var d := node.global_position - _target.global_position
	return Vector2(d.x, d.z).length()


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
