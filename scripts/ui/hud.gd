class_name Hud
extends CanvasLayer
## Kaelen's HUD (spec §9): the Pulsing Heart panel at the top left (health = red bar with a beating
## heart, stamina = the blue bar of the same frame), boss bar at the bottom (hidden until show_boss)
## and a reticle over the locked target's LockOnPoint.
## It is a child of kaelen.tscn, so it exists in any playable scene.

const MARKER_SIZE := 48.0   # reticle sprite size, in pixels of the 640×360 view
const BOSS_NAME_HEIGHT := 14.0
const BOSS_BAR_AREA := Vector2(304.0, 78.0)

## Heart: frame 1 of the sheet is held for BEAT_HOLD of every period; the period shortens as
## health drops (BEAT_SLOW at full health, BEAT_FAST near death).
const BEAT_SLOW := 1.1
const BEAT_FAST := 0.38
const BEAT_HOLD := 0.3

const DRAGON_BAR := preload("res://assets/ui/dragonhpbar/dragonhpbar.png")
const PIXEL_BAR := preload("res://assets/ui/pixel_ui_pack_3/05_boss_bar.png")

## Boss bar skins: texture, full and empty frame regions inside it, the horizontal range (in pixels
## of a frame) the fill travels over, and the integer scale. To give a boss another bar change its
## entry in BOSS_BAR_STYLES (key = Boss.display_name); bosses not listed use DEFAULT_BOSS_BAR.
const DRAGON_STYLE := {
	&"texture": DRAGON_BAR,
	&"full": Rect2(0, 0, 112, 32),
	&"empty": Rect2(784, 0, 112, 32),
	&"fill": Vector2(25.0, 96.0),
	&"scale": 2.0,
	&"name_overlap": 4.0,
}
const BLACKHORN_STYLE := {
	&"texture": PIXEL_BAR,
	&"full": Rect2(0, 21, 48, 6),
	&"empty": Rect2(240, 21, 48, 6),
	&"fill": Vector2(2.0, 46.0),
	&"scale": 5.0,
	&"name_overlap": 0.0,
}
const BOSS_BAR_STYLES := {
	"Bone Dragon": DRAGON_STYLE,
	"Blackhorn": BLACKHORN_STYLE,
	"Mecha King Ghidorah": DRAGON_STYLE,
}
const DEFAULT_BOSS_BAR := DRAGON_STYLE

var _player: Player
var _health: Health
var _stamina: Stamina
var _boss_health: Health
var _boss_style: Dictionary = DEFAULT_BOSS_BAR
var _beat_time := 0.0
var _health_ratio := 1.0

@onready var _health_bar: TextureProgressBar = $Bars/Frame/HealthBar
@onready var _stamina_bar: TextureProgressBar = $Bars/Frame/StaminaBar
@onready var _heart: TextureRect = $Bars/Frame/Heart
@onready var _boss_bar: Control = $BossBar
@onready var _boss_name: Label = $BossBar/BossName
@onready var _boss_fill: TextureProgressBar = $BossBar/Bar
@onready var _marker: TextureRect = $LockOnMarker


func _ready() -> void:
	_boss_bar.visible = false
	_marker.visible = false
	_marker.size = Vector2(MARKER_SIZE, MARKER_SIZE)
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
	_apply_boss_style(BOSS_BAR_STYLES.get(boss_name, DEFAULT_BOSS_BAR))
	if health:
		health.changed.connect(_on_boss_changed)
		_on_boss_changed(health.current, health.max_value)
	_boss_bar.visible = true


func hide_boss() -> void:
	if is_instance_valid(_boss_health) and _boss_health.changed.is_connected(_on_boss_changed):
		_boss_health.changed.disconnect(_on_boss_changed)
	_boss_health = null
	_boss_bar.visible = false


func _process(delta: float) -> void:
	_update_marker()
	_update_heart(delta)


func _update_heart(delta: float) -> void:
	_beat_time += delta
	var frame := beat_frame(_beat_time, beat_period(_health_ratio))
	(_heart.texture as AtlasTexture).region = Rect2(90.0 * frame, 0.0, 90.0, 28.0)


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
	_marker.position = (camera.unproject_position(point) - _marker.size * 0.5).round()
	_marker.visible = true


func _apply_boss_style(style: Dictionary) -> void:
	_boss_style = style
	var tex := style[&"texture"] as Texture2D
	var full: Rect2 = style[&"full"]
	var scale_f: float = style[&"scale"]
	var under := AtlasTexture.new()
	under.atlas = tex
	under.region = style[&"empty"]
	var over := AtlasTexture.new()
	over.atlas = tex
	over.region = full
	_boss_fill.texture_under = under
	_boss_fill.texture_progress = over
	_boss_fill.size = full.size
	_boss_fill.scale = Vector2(scale_f, scale_f)
	var bar_y := BOSS_BAR_AREA.y - full.size.y * scale_f
	_boss_fill.position = Vector2(roundf((BOSS_BAR_AREA.x - full.size.x * scale_f) * 0.5), bar_y)
	_boss_name.position.y = maxf(0.0, bar_y - BOSS_NAME_HEIGHT + float(style[&"name_overlap"]))


## Seconds between heart beats for a health ratio (0–1).
static func beat_period(health_ratio: float) -> float:
	return lerpf(BEAT_FAST, BEAT_SLOW, clampf(health_ratio, 0.0, 1.0))


## Heart sheet frame (1 = beat, 0 = rest) at a time inside a beat period.
static func beat_frame(time: float, period: float) -> int:
	return 1 if fposmod(time, period) < period * BEAT_HOLD else 0


## Value (0–1) a TextureProgressBar needs so that the fill covers `ratio` of the bar part, which
## spans [fill_lo, fill_hi] pixels of a frame that is `width` pixels wide.
static func bar_value(ratio: float, fill_lo: float, fill_hi: float, width: float) -> float:
	return (fill_lo + (fill_hi - fill_lo) * clampf(ratio, 0.0, 1.0)) / width


static func _ratio(current: float, max_value: float) -> float:
	return clampf(current / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0


func _on_health_changed(current: int, max_value: int) -> void:
	_health_ratio = _ratio(current, max_value)
	_health_bar.value = _health_ratio


func _on_stamina_changed(current: float, max_value: float) -> void:
	_stamina_bar.value = _ratio(current, max_value)


func _on_boss_changed(current: int, max_value: int) -> void:
	var fill: Vector2 = _boss_style[&"fill"]
	var width: float = (_boss_style[&"full"] as Rect2).size.x
	_boss_fill.value = bar_value(_ratio(current, max_value), fill.x, fill.y, width)
