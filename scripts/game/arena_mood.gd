class_name ArenaMood
extends Node
## Per-arena lighting (design §6.3) and the colour filter shown after the boss is defeated.
## Lives as the `Mood` child of arena_N_gameplay.tscn: the values are set in the gameplay scene, not in
## the generated arena_N.tscn. On entry it duplicates the level's Environment (the level resource is
## left untouched) and applies ambient light, fog, colour adjustments and the colour/energy of `Sun`.
## On Events.boss_defeated a subtle multiplicative tint fades in over the world (a CanvasLayer
## below the HUD) and stays until the scene changes.

@export_group("Ambient light and fog")
@export var ambient_color := Color(0.45, 0.48, 0.58)
@export var ambient_energy := 0.35
@export var fog_color := Color(0.42, 0.46, 0.55)
@export var fog_begin := 6.0
@export var fog_end := 48.0
@export_group("Sun")
@export var sun_color := Color(1.0, 1.0, 1.0)
@export var sun_energy := 0.35
@export_group("Tone")
@export_range(0.5, 1.5) var brightness := 1.0
@export_range(0.5, 1.5) var contrast := 1.0
@export_range(0.0, 1.5) var saturation := 1.0
@export_group("Boss defeated")
## Multiplicative tint (white = no tint) and fade duration in seconds.
@export var defeat_tint := Color(1.0, 1.0, 1.0)
@export var defeat_fade := 2.5

const TINT_LAYER := -1

var environment: Environment
var _tint_rect: ColorRect


func _ready() -> void:
	var level := get_parent().get_node_or_null(^"Level")
	if level:
		apply_to(level)
	var events := get_node_or_null(^"/root/Events")
	if events:
		events.boss_defeated.connect(_on_boss_defeated)


## Applies the lighting to `level` (children WorldEnvironment and Sun).
func apply_to(level: Node) -> void:
	var world := level.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if world and world.environment:
		environment = world.environment.duplicate() as Environment
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = ambient_color
		environment.ambient_light_energy = ambient_energy
		environment.fog_enabled = true
		environment.fog_light_color = fog_color
		environment.fog_depth_begin = fog_begin
		environment.fog_depth_end = fog_end
		environment.adjustment_enabled = true
		environment.adjustment_brightness = brightness
		environment.adjustment_contrast = contrast
		environment.adjustment_saturation = saturation
		world.environment = environment
	var sun := level.get_node_or_null(^"Sun") as DirectionalLight3D
	if sun:
		sun.light_color = sun_color
		sun.light_energy = sun_energy


func _on_boss_defeated(_boss: Node3D) -> void:
	show_defeat_tint()


## Fades towards the defeated-boss tint.
func show_defeat_tint() -> void:
	if _tint_rect == null:
		var layer := CanvasLayer.new()
		layer.layer = TINT_LAYER
		_tint_rect = ColorRect.new()
		_tint_rect.color = Color.WHITE
		_tint_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tint_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		_tint_rect.material = mat
		layer.add_child(_tint_rect)
		add_child(layer)
	create_tween().set_ignore_time_scale(true).tween_property(_tint_rect, "color", defeat_tint, defeat_fade)
