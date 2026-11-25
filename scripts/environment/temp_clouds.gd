class_name TempClouds
extends Node3D
## TEMPORARY. Soft clouds high in the sky and low around the island. To remove them, delete the
## "TempClouds" node from scenes/levels/exterior_gameplay.tscn (and this script if wanted): nothing else
## refers to it.
##
## One MultiMesh of camera-facing quads (1 draw call) with a procedural cloud sprite. Sky clouds sit far
## away and high, so they read as a backdrop; island clouds are lower, smaller and more transparent, in a
## ring outside the island so none drifts onto the path or in front of the camera. The whole layer turns
## very slowly around the island. The material ignores fog (it would hide them in the haze).

const SKY_COUNT := 30
const NEAR_COUNT := 18
const SEED := 4417
const TEXTURE_SIZE := 64
const SPIN := 0.0015   # rad/s

@export var center := Vector3(5.0, 0.0, 0.0)


func _ready() -> void:
	global_position = center
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var items: Array[Array] = []   # [position, width, height, alpha]
	for i in SKY_COUNT:
		var a := (i + rng.randf_range(-0.4, 0.4)) * TAU / SKY_COUNT
		var r := rng.randf_range(130.0, 280.0)
		var w := rng.randf_range(70.0, 150.0)
		items.append([Vector3(cos(a) * r, rng.randf_range(45.0, 120.0), sin(a) * r), w, w * rng.randf_range(0.28, 0.42),
				rng.randf_range(0.75, 0.95)])
	for i in NEAR_COUNT:
		var a := (i + rng.randf_range(-0.35, 0.35)) * TAU / NEAR_COUNT
		var r := rng.randf_range(72.0, 112.0)
		var w := rng.randf_range(26.0, 52.0)
		items.append([Vector3(cos(a) * r, rng.randf_range(-8.0, 14.0), sin(a) * r), w, w * rng.randf_range(0.3, 0.45),
				rng.randf_range(0.45, 0.7)])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _material()
	mm.mesh = quad
	mm.instance_count = items.size()
	for i in items.size():
		var it: Array = items[i]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(it[1], it[2], 1.0)), it[0]))
		mm.set_instance_color(i, Color(1.0, 1.0, 1.0, it[3]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-320, -40, -320), Vector3(640, 200, 640))
	add_child(mmi)


func _process(delta: float) -> void:
	rotate_y(SPIN * delta)


func _material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = _sprite()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return mat


## A soft puff: noisy blob that fades to nothing at its edge, brighter on top and lilac underneath.
func _sprite() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.07
	noise.fractal_octaves = 3
	var img := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var nx := (x + 0.5) / TEXTURE_SIZE * 2.0 - 1.0
			var ny := (y + 0.5) / TEXTURE_SIZE * 2.0 - 1.0
			var r := Vector2(nx, ny * 1.25).length()
			var body := clampf(1.0 - r, 0.0, 1.0)
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf(body * 1.7 + (n - 0.5) * 0.7 * body, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			var shade := clampf(0.5 - ny * 0.5, 0.0, 1.0)   # top (y < 0) bright, bottom lilac
			var col := Color(0.78, 0.74, 0.88).lerp(Color(1.0, 0.96, 0.95), shade)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)
