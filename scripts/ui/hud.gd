class_name Hud
extends CanvasLayer
## Kaelen's HUD (spec §9): health and stamina bars at the top left, boss bar at the bottom
## (hidden until show_boss) and a marker over the locked target's LockOnPoint.
## It is a child of kaelen.tscn, so it exists in any playable scene.

const BAR_WIDTH := 120.0
const BOSS_BAR_WIDTH := 300.0
const MARKER_SIZE := 4.0   # half-width of the diamond, in pixels of the 640×360 view

var _player: Player
var _health: Health
var _stamina: Stamina
var _boss_health: Health

@onready var _health_fill: ColorRect = $Bars/HealthBack/HealthFill
@onready var _stamina_fill: ColorRect = $Bars/StaminaBack/StaminaFill
@onready var _boss_bar: Control = $BossBar
@onready var _boss_name: Label = $BossBar/BossName
@onready var _boss_fill: ColorRect = $BossBar/Back/Fill
@onready var _marker: Control = $LockOnMarker


func _ready() -> void:
	_boss_bar.visible = false
	_marker.visible = false
	_marker.draw.connect(_draw_marker)
	var player := get_parent() as Player
	if player:
		bind_player(player)


## Connects the bars to Kaelen's Health and Stamina and reads their current values (Health does not
## emit changed in its _ready).
func bind_player(player: Player) -> void:
	_player = player
	_health = player.get_node_or_null(^"Health") as Health
	_stamina = player.get_node_or_null(^"Stamina") as Stamina
	if _health:
		_health.changed.connect(_on_health_changed)
		_on_health_changed(_health.current, _health.max_value)
	if _stamina:
		_stamina.changed.connect(_on_stamina_changed)
		_on_stamina_changed(_stamina.current, _stamina.max_value)


func show_boss(boss_name: String, health: Health) -> void:
	hide_boss()
	_boss_health = health
	_boss_name.text = boss_name
	if health:
		health.changed.connect(_on_boss_changed)
		_on_boss_changed(health.current, health.max_value)
	_boss_bar.visible = true


func hide_boss() -> void:
	if is_instance_valid(_boss_health) and _boss_health.changed.is_connected(_on_boss_changed):
		_boss_health.changed.disconnect(_on_boss_changed)
	_boss_health = null
	_boss_bar.visible = false


func _process(_delta: float) -> void:
	_update_marker()


func _update_marker() -> void:
	var target: Node3D = _player.get_lock_target() if is_instance_valid(_player) else null
	var camera := get_viewport().get_camera_3d()
	if target == null or camera == null:
		_marker.visible = false
		return
	var point := LockOn.aim_point(target)
	if camera.is_position_behind(point):
		_marker.visible = false
		return
	_marker.position = camera.unproject_position(point) - _marker.size * 0.5
	_marker.visible = true


func _draw_marker() -> void:
	var c := _marker.size * 0.5
	var s := MARKER_SIZE
	var outer := PackedVector2Array([c + Vector2(0, -s - 1), c + Vector2(s + 1, 0), c + Vector2(0, s + 1), c + Vector2(-s - 1, 0)])
	var inner := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)])
	_marker.draw_colored_polygon(outer, Color(0, 0, 0, 0.8))
	_marker.draw_colored_polygon(inner, Color(1.0, 0.95, 0.8))


static func _ratio(current: float, max_value: float) -> float:
	return clampf(current / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0


func _on_health_changed(current: int, max_value: int) -> void:
	_health_fill.size.x = BAR_WIDTH * _ratio(current, max_value)


func _on_stamina_changed(current: float, max_value: float) -> void:
	_stamina_fill.size.x = BAR_WIDTH * _ratio(current, max_value)


func _on_boss_changed(current: int, max_value: int) -> void:
	_boss_fill.size.x = BOSS_BAR_WIDTH * _ratio(current, max_value)
