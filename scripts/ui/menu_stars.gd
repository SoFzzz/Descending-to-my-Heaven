class_name MenuStars
extends Control
## Menu background stars: fixed points that twinkle with sines of different phase and period.
## Cheap to draw (a few dozen rectangles); placed over the sky and under the island.

@export var count := 70
@export var seed_value := 11
@export var area := Rect2(0.0, 0.0, 640.0, 250.0)
@export var base_color := Color(0.94, 0.94, 0.97)

var _stars: Array[Dictionary] = []
var _time := 0.0


## Alpha (0..1) of a star at time `t`: oscillates between `low` and 1 with period `period`.
static func twinkle(t: float, phase: float, period: float, low: float = 0.25) -> float:
	var wave := 0.5 + 0.5 * sin(TAU * (t / period) + phase)
	return lerpf(low, 1.0, wave)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in count:
		_stars.append({
			&"pos": Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y)).floor(),
			&"phase": rng.randf() * TAU,
			&"period": rng.randf_range(1.6, 4.5),
			&"size": 2.0 if rng.randf() < 0.22 else 1.0,
			&"low": rng.randf_range(0.1, 0.4),
		})


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	for star in _stars:
		var alpha := twinkle(_time, star[&"phase"], star[&"period"], star[&"low"])
		var size: float = star[&"size"]
		draw_rect(Rect2(star[&"pos"], Vector2(size, size)), Color(base_color, alpha * 0.95))
