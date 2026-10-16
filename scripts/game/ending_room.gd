class_name EndingRoom
extends Node3D
## Sala de Elysia rota: el muro norte y el techo de arena_3 tienen un hueco (lo abre level_builder.gd,
## `_break_room`) y por él se ve cómo la isla cae en picada. Esta escena (scenes/props/ending_room.tscn)
## se instancia en arena_3_gameplay.tscn con su origen en el centro del muro norte de la sala
## (0, 0, -57.5); +Z entra a la sala y -Z es el exterior.
##
## Ilusión de caída barata (gl_compatibility): la sala no se mueve; hacia arriba se mueven nubes
## (CPUParticles3D), rachas de viento, islotes del kit y fragmentos de la propia isla. Todo lo de fuera
## solo se dibuja y se mueve cuando la cámara está cerca de la sala. Al llegar a Kaelen el final
## (`start_fall()`, llamado por EndingDirector) la velocidad sube de una deriva lenta a la caída, se
## activa el polvo del techo y un leve temblor de la cámara activa.
##
## Colisión: `SafetyBarrier` (invisible) tapa el hueco y los bloques grandes caídos tienen colisión,
## así que Kaelen no puede caer por el hueco.

const GROUP := &"ending_room"
const TEX := "res://assets/environment/textures/"
const KIT := "res://assets/environment/kit/"
const ISLAND := "res://assets/environment/island/"

## Velocidad relativa de lo exterior antes de empezar el final (deriva lenta) y tiempo de aceleración.
const IDLE_SPEED := 0.1
const RAMP_TIME := 2.5
## Temblor de cámara (m de desplazamiento del frustum) y frecuencia del ruido (rad/s).
const SHAKE_AMOUNT := 0.035
const SHAKE_FREQ := 38.0
## Lo exterior se muestra si la cámara está a menos de esta distancia (Z local) del muro norte.
const SHOW_DISTANCE := 24.0
## Rango vertical (m, local) por el que suben las rocas antes de reaparecer abajo.
const ROCK_BOTTOM := -75.0
const ROCK_TOP := 85.0
## Viento de la caída (WIND-FALL): bucle por debajo de la música y los diálogos del final.
const WIND_STREAM := "res://assets/audio/sfx/ambient/wind_fall.mp3"
const WIND_BUS := &"SFX"
const WIND_VOLUME_DB := -9.0
const WIND_SILENT_DB := -60.0
## Racha de aire (StormFX gust): semiancho (m) y fondo (m). Solo se ve FUERA, a través del hueco: su
## centro está a GUST_Z (local; el muro norte es z = 0) y toda su extensión queda por detrás de
## GUST_MAX_Z, más lejos que la barrera de seguridad. Nada de viento visible dentro de la sala.
const GUST_RADIUS := 14.0
const GUST_DEPTH := 12.0
const GUST_Z := -34.0
const GUST_MAX_Z := -6.0

var falling := false
var intensity := 0.0   ## 0 = hueco quieto con deriva lenta, 1 = caída a toda velocidad

var _outside: Node3D
var _clouds: CPUParticles3D
var _streaks: StormFX
var _dust: CPUParticles3D
var _pebbles: CPUParticles3D
var _rocks: Array[Dictionary] = []   # {node, speed, spin}
var _shaken_cam: Camera3D
var _time := 0.0
var _tween: Tween
var _wind: AudioStreamPlayer
var _wind_tween: Tween


## Velocidad relativa de la caída para una intensidad 0..1.
static func speed_for(level: float) -> float:
	return lerpf(IDLE_SPEED, 1.0, clampf(level, 0.0, 1.0))


## Nueva altura de una roca que sube: al pasar el tope reaparece abajo.
static func wrap_height(y: float) -> float:
	return y - (ROCK_TOP - ROCK_BOTTOM) if y > ROCK_TOP else y


func _ready() -> void:
	add_to_group(GROUP)
	_outside = Node3D.new()
	_outside.name = "Outside"
	add_child(_outside)
	_build_backdrop()
	_build_clouds()
	_build_streaks()
	_build_rocks()
	_build_rubble()
	_build_cracks()
	_build_dust()
	_build_light()
	_apply_speed()
	_outside.visible = false


## Empieza la caída de la isla (llamado por EndingDirector al arrancar el final). Solo actúa una vez.
func start_fall() -> void:
	if falling:
		return
	falling = true
	_dust.emitting = true
	_pebbles.emitting = true
	_streaks.visible = true
	_streaks.set_process(true)
	_streaks.play()
	if is_inside_tree():
		_tween = create_tween()
		_tween.tween_property(self, "intensity", 1.0, RAMP_TIME).set_trans(Tween.TRANS_SINE) \
				.set_ease(Tween.EASE_IN)
	else:
		intensity = 1.0
	_apply_speed()
	_start_wind()


## Viento: entra con la misma curva y duración que la aceleración de la caída (RAMP_TIME).
func _start_wind() -> void:
	if _wind == null:
		var stream := load(WIND_STREAM) as AudioStreamMP3
		if stream == null:
			push_warning("EndingRoom: falta %s" % WIND_STREAM)
			return
		stream = stream.duplicate() as AudioStreamMP3
		stream.loop = true   # más corto que el final: se repite
		_wind = AudioStreamPlayer.new()
		_wind.name = "WindFall"
		_wind.stream = stream
		_wind.bus = WIND_BUS if AudioServer.get_bus_index(WIND_BUS) >= 0 else &"Master"
		_wind.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_wind)
	_wind.volume_db = WIND_SILENT_DB
	if is_inside_tree():
		_wind.play()
	if _wind_tween:
		_wind_tween.kill()
	if is_inside_tree():
		_wind_tween = create_tween()
		_wind_tween.tween_property(_wind, "volume_db", WIND_VOLUME_DB, RAMP_TIME) 				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	else:
		_wind.volume_db = WIND_VOLUME_DB


## Fundido de salida del viento (al pasar a créditos).
func stop_wind(fade: float = 1.2) -> void:
	if _wind == null or not _wind.playing:
		return
	if _wind_tween:
		_wind_tween.kill()
	if not is_inside_tree():
		_wind.stop()
		return
	_wind_tween = create_tween()
	_wind_tween.tween_property(_wind, "volume_db", WIND_SILENT_DB, fade)
	_wind_tween.tween_callback(_wind.stop)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var near := cam != null and to_local(cam.global_position).z < SHOW_DISTANCE
	if _outside.visible != near:
		_outside.visible = near
	if not near:
		_release_camera()
		return
	_time += delta
	_apply_speed()
	var speed := speed_for(intensity)
	for r in _rocks:
		var n := r.node as Node3D
		n.position.y = wrap_height(n.position.y + float(r.speed) * speed * delta)
		n.rotation += (r.spin as Vector3) * speed * delta
	_shake(cam)


func _apply_speed() -> void:
	var s := speed_for(intensity)
	_clouds.speed_scale = s
	_streaks.speed = 0.4 + s * 1.4


func _shake(cam: Camera3D) -> void:
	if _shaken_cam != cam:
		_release_camera()
		_shaken_cam = cam
	if not falling or cam == null:
		return
	var a := SHAKE_AMOUNT * intensity
	cam.h_offset = a * (sin(_time * SHAKE_FREQ) * 0.6 + sin(_time * SHAKE_FREQ * 1.7 + 1.3) * 0.4)
	cam.v_offset = a * (sin(_time * SHAKE_FREQ * 1.3 + 2.1) * 0.6 + sin(_time * SHAKE_FREQ * 2.3) * 0.4)


func _release_camera() -> void:
	if _shaken_cam != null and is_instance_valid(_shaken_cam):
		_shaken_cam.h_offset = 0.0
		_shaken_cam.v_offset = 0.0
	_shaken_cam = null


func _exit_tree() -> void:
	_release_camera()


# --- Construcción ---------------------------------------------------------------------------

## Cielo de fondo: atardecer apagado y frío (melancólico), con un resplandor tenue en el horizonte, sin niebla (la niebla de la
## arena lo apagaría a esa distancia).
func _build_backdrop() -> void:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never;
varying vec3 wpos;
void vertex() { wpos = VERTEX; }
void fragment() {
	float t = clamp(wpos.y / 120.0 * 0.5 + 0.5, 0.0, 1.0);
	vec3 low = vec3(0.60, 0.50, 0.54);
	vec3 mid = vec3(0.36, 0.43, 0.58);
	vec3 high = vec3(0.08, 0.10, 0.23);
	vec3 c = t < 0.5 ? mix(low, mid, smoothstep(0.2, 0.5, t)) : mix(mid, high, smoothstep(0.5, 0.95, t));
	float glow = exp(-length(vec2(wpos.x + 40.0, (wpos.y - 8.0) * 1.5)) / 45.0);
	ALBEDO = c + vec3(0.85, 0.75, 0.72) * glow * 0.28;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	var q := QuadMesh.new()
	q.size = Vector2(700, 260)
	q.material = m
	var mi := MeshInstance3D.new()
	mi.name = "SkyBackdrop"
	mi.mesh = q
	mi.position = Vector3(0, 40, -150)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outside.add_child(mi)


func _soft_puff_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t


func _particle_material(tint: Color, tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = tint
	m.albedo_texture = tex
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.disable_fog = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _fade_ramp() -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.85, 1.0])
	return g


## Nubes: manchas verticales que suben desde abajo; con la caída activa cruzan la vista en ~3 s.
func _build_clouds() -> void:
	_clouds = CPUParticles3D.new()
	_clouds.name = "Clouds"
	var q := QuadMesh.new()
	q.size = Vector2(12, 22)
	q.material = _particle_material(Color(0.7, 0.74, 0.84, 0.8), _soft_puff_texture())
	_clouds.mesh = q
	_clouds.amount = 64
	_clouds.lifetime = 3.4
	_clouds.preprocess = 3.4
	_clouds.local_coords = true
	_clouds.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_clouds.emission_box_extents = Vector3(40, 2, 16)
	_clouds.position = Vector3(0, -34, -28)
	_clouds.direction = Vector3.UP
	_clouds.spread = 0.0
	_clouds.gravity = Vector3.ZERO
	_clouds.initial_velocity_min = 26.0
	_clouds.initial_velocity_max = 34.0
	_clouds.scale_amount_min = 0.7
	_clouds.scale_amount_max = 1.6
	_clouds.color_ramp = _fade_ramp()
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outside.add_child(_clouds)


## Rachas de viento (Storm & Wind 3D Free, StormFX "gust" de aire): líneas y motas que suben a toda
## velocidad lejos, por detrás del hueco (visibles solo a través de él). Empieza apagado y se forma durante RAMP_TIME al empezar la caída.
func _build_streaks() -> void:
	StormFX.default_transparency = 1   # tramado (dither): casa con el aspecto PSX
	_streaks = StormFX.new()
	_streaks.name = "WindStreaks"
	_streaks.kind = "gust"
	_streaks.style = "air"
	_streaks.radius = GUST_RADIUS
	_streaks.height = GUST_DEPTH
	_streaks.light = false
	_streaks.autoplay = false
	_streaks.appear = RAMP_TIME
	_streaks.interval = 0.0
	_streaks.seed = 3.0
	_streaks.set_param(&"thickness", 1.6)
	_streaks.position = Vector3(0, 2, GUST_Z)
	_streaks.rotation_degrees = Vector3(90, 0, 0)   # sopla hacia -Z local = hacia arriba
	_streaks.visible = false
	_streaks.set_process(false)   # nada que dibujar ni actualizar hasta que empiece la caída
	_outside.add_child(_streaks)


func _build_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261015
	# Islotes lejanos (parallax: los más lejanos suben más despacio): [glb, x, y, z, escala, velocidad].
	var islets := [
		["islet_round", -38.0, -20.0, -62.0, 0.9, 11.0], ["islet_long", 46.0, 10.0, -85.0, 1.0, 9.0],
		["islet_l", 6.0, 55.0, -105.0, 1.2, 7.0], ["islet_small", 14.0, -45.0, -30.0, 1.0, 17.0],
		["islet_hole", -55.0, 40.0, -125.0, 1.0, 6.0], ["islet_small", -20.0, 20.0, -42.0, 0.8, 14.0],
	]
	for it in islets:
		var scn := load(ISLAND + it[0] + ".glb") as PackedScene
		if scn == null:
			continue
		var n := scn.instantiate() as Node3D
		n.position = Vector3(it[1], it[2], it[3])
		n.scale = Vector3.ONE * float(it[4])
		n.rotation_degrees = Vector3(rng.randf_range(-7, 7), rng.randf_range(0, 360), rng.randf_range(-7, 7))
		_outside.add_child(n)
		_rocks.append({"node": n, "speed": float(it[5]), "spin": Vector3(0.0, rng.randf_range(-0.03, 0.03), 0.0)})
	# Fragmentos de la propia isla que se desprenden (muro del kit, columna caída y bloques).
	var wall_scn := load(KIT + "wall_ruin.glb") as PackedScene
	var pillar_scn := load(KIT + "pillar_collapsed.glb") as PackedScene
	var chunk_mat := _stone_material("concrete_512_indexed", Color(0.7, 0.7, 0.75))
	for i in 12:
		var n: Node3D
		var pick := i % 3
		if pick == 0 and wall_scn:
			n = wall_scn.instantiate() as Node3D
			n.scale = Vector3.ONE * rng.randf_range(0.5, 1.0)
		elif pick == 1 and pillar_scn:
			n = pillar_scn.instantiate() as Node3D
			n.scale = Vector3.ONE * rng.randf_range(0.8, 1.6)
		else:
			var mi := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(rng.randf_range(0.6, 2.0), rng.randf_range(0.4, 1.4), rng.randf_range(0.6, 2.0))
			b.material = chunk_mat
			mi.mesh = b
			n = mi
		n.position = Vector3(rng.randf_range(-11.0, 11.0), rng.randf_range(ROCK_BOTTOM, ROCK_TOP),
				rng.randf_range(-24.0, -4.0))
		n.rotation = Vector3(rng.randf_range(0, TAU), rng.randf_range(0, TAU), rng.randf_range(0, TAU))
		_outside.add_child(n)
		_rocks.append({"node": n, "speed": rng.randf_range(16.0, 30.0),
				"spin": Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2))})


## Material de piedra del kit: textura con proyección triplanar local y filtro nearest (look PSX).
func _stone_material(tex_name: String, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + tex_name + ".png")
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	return m


## Escombros dentro de la sala (estáticos) y barrera de seguridad del hueco.
func _build_rubble() -> void:
	var rubble := Node3D.new()
	rubble.name = "Rubble"
	add_child(rubble)
	var mat := _stone_material("concrete_512_indexed", Color(0.62, 0.6, 0.62))
	var dark := _stone_material("concrete_512_indexed_dark", Color(0.6, 0.58, 0.6))
	# Pieza del kit: muro caído y columna rota.
	_kit_piece(rubble, "wall_ruin", Vector3(-4.1, 0.0, 2.3), Vector3(0, 28, 74), 0.9)
	_kit_piece(rubble, "pillar_collapsed", Vector3(4.3, 0.55, 3.6), Vector3(0, -35, 90), 1.4)
	_kit_piece(rubble, "wall_ruin", Vector3(2.6, 0.0, 0.2), Vector3(0, 8, 28), 0.45)
	# Bloques: [x, z, tamaño, giro Y, con colisión]. Nada en el pasillo central (|x| < 2.5, z > 4.6).
	var blocks := [
		[-4.6, 5.2, Vector3(1.4, 0.9, 1.1), 20.0, true], [-5.2, 7.6, Vector3(0.9, 0.6, 0.8), -40.0, true],
		[4.8, 6.0, Vector3(1.2, 0.8, 1.3), 55.0, true], [5.3, 8.6, Vector3(0.7, 0.5, 0.9), 10.0, false],
		[-3.4, 3.4, Vector3(0.8, 0.5, 0.7), 70.0, false], [3.6, 1.4, Vector3(1.0, 0.7, 0.9), -15.0, true],
		[-2.2, 1.0, Vector3(0.7, 0.45, 0.6), 35.0, false], [-1.2, 5.6, Vector3(0.4, 0.25, 0.35), 5.0, false],
		[1.8, 5.2, Vector3(0.35, 0.22, 0.4), 62.0, false], [0.3, 8.4, Vector3(0.3, 0.2, 0.3), -50.0, false],
		[-5.5, 10.4, Vector3(1.1, 0.7, 0.9), 80.0, true], [5.4, 10.8, Vector3(0.9, 0.55, 1.0), -25.0, false],
	]
	for i in blocks.size():
		var b: Array = blocks[i]
		var size: Vector3 = b[2]
		var body := StaticBody3D.new()
		body.name = "Block%d" % i
		body.collision_layer = 1 if b[4] else 0
		body.collision_mask = 0
		body.position = Vector3(b[0], size.y * 0.5 - 0.05, b[1])
		body.rotation_degrees = Vector3(i * 7 % 11 - 5, b[3], i * 5 % 9 - 4)
		rubble.add_child(body)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = dark if i % 2 == 0 else mat
		mi.mesh = bm
		body.add_child(mi)
		if b[4]:
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = size
			cs.shape = shape
			body.add_child(cs)
	# Trozos rotos sobre el alféizar del hueco (borde irregular).
	for i in 7:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.35 + (i % 3) * 0.2, 0.3 + (i % 2) * 0.25, 0.5)
		bm.material = mat
		mi.mesh = bm
		mi.position = Vector3(-4.0 + i * 1.25, 0.9 + (i % 3) * 0.25, 0.1)
		mi.rotation_degrees = Vector3(i * 13 % 17 - 8, i * 31 % 50, i * 23 % 40 - 20)
		rubble.add_child(mi)
	# Barrera invisible que tapa el hueco del muro (y el alféizar): Kaelen no puede salir ni caer.
	var barrier := StaticBody3D.new()
	barrier.name = "SafetyBarrier"
	barrier.collision_layer = 1
	barrier.collision_mask = 0
	barrier.position = Vector3(0.0, 3.5, -0.1)
	add_child(barrier)
	var bs := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(12.0, 7.0, 0.8)
	bs.shape = bshape
	barrier.add_child(bs)


func _kit_piece(parent: Node3D, item: String, pos: Vector3, rot_deg: Vector3, scl: float) -> void:
	var scn := load(KIT + item + ".glb") as PackedScene
	if scn == null:
		return
	var n := scn.instantiate() as Node3D
	n.position = pos
	n.rotation_degrees = rot_deg
	n.scale = Vector3.ONE * scl
	parent.add_child(n)


## Grietas: tiras oscuras que irradian del hueco por el suelo y suben por los muros laterales.
func _build_cracks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var cracks := Node3D.new()
	cracks.name = "Cracks"
	add_child(cracks)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.02, 0.02, 0.03)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Suelo: ramas en zigzag que parten del muro norte (plano XZ, y = 0.03).
	for i in 7:
		var p := Vector3(-4.5 + i * 1.5, 0.03, 0.8)
		var dir := Vector3(rng.randf_range(-0.5, 0.5), 0.0, 1.0).normalized()
		for s in 7:
			var q := p + dir * rng.randf_range(0.7, 1.4)
			_strip(st, p, q, Vector3.UP, 0.05 + (6 - s) * 0.008)
			dir = (dir + Vector3(rng.randf_range(-0.8, 0.8), 0.0, 0.0)).normalized()
			p = q
	# Muros laterales: grietas que bajan del techo (plano YZ, x = ±5.96).
	for side in [-1.0, 1.0]:
		for i in 3:
			var p := Vector3(side * 5.96, 5.9, 2.0 + i * 3.4)
			for s in 6:
				var q := p + Vector3(0.0, -rng.randf_range(0.6, 1.0), rng.randf_range(-0.5, 0.5))
				_strip(st, p, q, Vector3(-side, 0, 0), 0.05)
				p = q
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cracks.add_child(mi)


## Segmento de grieta como cuadrilátero de ancho `w`, perpendicular a `normal` en el plano del trazo.
func _strip(st: SurfaceTool, a: Vector3, b: Vector3, normal: Vector3, w: float) -> void:
	var side := (b - a).cross(normal).normalized() * w * 0.5
	st.set_normal(normal)
	for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
		st.add_vertex(v)


## Polvo y guijarros que caen del techo roto mientras dura el final.
func _build_dust() -> void:
	_dust = CPUParticles3D.new()
	_dust.name = "CeilingDust"
	var dm := BoxMesh.new()
	dm.size = Vector3(0.06, 0.06, 0.06)
	dm.material = _flat_material(Color(0.42, 0.42, 0.45))
	_dust.mesh = dm
	_dust.emitting = false
	_dust.amount = 14
	_dust.lifetime = 3.0
	_dust.local_coords = true
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(4.0, 0.1, 2.5)   # solo cerca del hueco, sutil
	_dust.position = Vector3(0.0, 5.9, 2.8)
	_dust.direction = Vector3.DOWN
	_dust.spread = 15.0
	_dust.gravity = Vector3(0, -1.2, 0)
	_dust.initial_velocity_min = 0.2
	_dust.initial_velocity_max = 0.6
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dust)
	_pebbles = CPUParticles3D.new()
	_pebbles.name = "FallingPebbles"
	var pm := BoxMesh.new()
	pm.size = Vector3(0.14, 0.1, 0.12)
	pm.material = _stone_material("concrete_512_indexed_dark", Color(0.6, 0.6, 0.62))
	_pebbles.mesh = pm
	_pebbles.emitting = false
	_pebbles.amount = 10
	_pebbles.lifetime = 1.1
	_pebbles.local_coords = true
	_pebbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_pebbles.emission_box_extents = Vector3(4.0, 0.1, 4.0)
	_pebbles.position = Vector3(0.0, 5.9, 4.0)
	_pebbles.direction = Vector3.DOWN
	_pebbles.spread = 8.0
	_pebbles.gravity = Vector3(0, -9.8, 0)
	_pebbles.initial_velocity_min = 0.0
	_pebbles.initial_velocity_max = 0.5
	_pebbles.angular_velocity_min = -200.0
	_pebbles.angular_velocity_max = 200.0
	_pebbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pebbles)


func _flat_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


## Luz fría y tenue de cielo que entra por el hueco; contrasta con la luz cálida del altar sin apagar la escena.
func _build_light() -> void:
	var l := OmniLight3D.new()
	l.name = "SkyLight"
	l.light_color = Color(0.6, 0.7, 0.92)
	l.light_energy = 1.15
	l.omni_range = 14.0
	l.position = Vector3(0.3, 3.6, -1.5)
	add_child(l)
