extends TestCase
# Rayo de Ghidorah: apertura del efecto, recta boca -> suelo y que efecto, hitbox y aviso coincidan.

const MOUTH := Vector3(0.0, 5.5, -3.5)   # boca de la cabeza central en `beam` (a ojo, jefe en el origen)


func test_open_progress() -> void:
	assert_almost(BeamVfx.open_progress(0.0), 0.0)
	assert_almost(BeamVfx.open_progress(BeamVfx.OPEN_TIME * 0.5), 0.5)
	assert_almost(BeamVfx.open_progress(5.0), 1.0, 0.0001, "no pasa de 1")
	assert_almost(BeamVfx.open_progress(1.0, 0.0), 1.0, 0.0001, "duracion 0 = abierto")


func test_scene_wiring() -> void:
	var scene := load("res://scenes/bosses/boss_ghidorah.tscn") as PackedScene
	var boss := scene.instantiate()
	var attack := load("res://resources/attacks/ghidorah_beam.tres") as BossAttack
	var visual := boss.get_node_or_null(attack.visual_path) as BeamVfx
	assert_true(visual != null, "BeamVisual es un BeamVfx")
	assert_true(not visual.visible, "oculto fuera de ACTIVE")
	assert_true(boss.get_node_or_null(attack.hitbox_path) is Hitbox, "BeamHitbox")
	assert_true(boss.get_node_or_null(^"BeamAim") is GhidorahBeamAim, "BeamAim apunta el rayo")
	assert_true(boss.get_node_or_null(^"Telegraphs/beam/HitZone") != null, "tramo de daño del aviso")
	assert_eq(boss.get_node(^"BeamAim").get_index(), boss.get_child_count() - 1, "BeamAim es el ultimo hijo")
	boss.free()


func test_solve_reaches_ground_at_target() -> void:
	var target := Vector3(0.0, 0.0, -12.0)
	var beam = GhidorahBeamAim.solve(MOUTH, target, 0.35)
	var end: Vector3 = beam.end
	assert_almost(end.distance_to(target + Vector3.UP * 0.35), 0.0, 0.0001, "termina sobre el impacto")
	assert_almost(beam.length, MOUTH.distance_to(target + Vector3.UP * 0.35), 0.0001, "largo")
	assert_true((beam.direction as Vector3).y < -0.3, "baja en diagonal")
	assert_true(end.y >= 0.0, "no atraviesa el suelo")
	# El eje -Z de la base apunta a lo largo de la recta (como el efecto del pack).
	assert_almost((-(beam.basis as Basis).z).dot(beam.direction), 1.0, 0.0001, "base mira al impacto")


func test_clamp_target_range() -> void:
	var boss := Vector3(2.0, 0.0, 3.0)
	var near = GhidorahBeamAim.clamp_target(boss, Vector3(2.0, 0.0, 1.0), 8.0, 20.0)
	assert_almost(Vector2(near.x - boss.x, near.z - boss.z).length(), 8.0, 0.0001, "minimo 8")
	var far = GhidorahBeamAim.clamp_target(boss, Vector3(2.0, 0.0, -60.0), 8.0, 20.0)
	assert_almost(Vector2(far.x - boss.x, far.z - boss.z).length(), 20.0, 0.0001, "maximo 20")
	var mid = GhidorahBeamAim.clamp_target(boss, Vector3(2.0, 0.5, -9.0), 8.0, 20.0)
	assert_almost(mid.z, -9.0, 0.0001, "dentro del rango no se mueve")
	assert_almost(mid.y, 0.5, 0.0001, "altura de Kaelen")


## Distancia de `point` a la caja de la hitbox (centro `center`, base `basis`, tamaño local `size`).
func _dist_to_box(point: Vector3, center: Vector3, basis: Basis, size: Vector3) -> float:
	var local := basis.inverse() * (point - center)
	var outside := Vector3(maxf(absf(local.x) - size.x * 0.5, 0.0), maxf(absf(local.y) - size.y * 0.5, 0.0), maxf(absf(local.z) - size.z * 0.5, 0.0))
	return outside.length()


## True si la capsula de Kaelen (r 0.30, alto 1.50, centro a 0.85 m de sus pies) toca la caja.
func _kaelen_hit(feet: Vector3, beam: Dictionary) -> bool:
	var size := Vector3(1.5, 1.5, beam.length)
	for i in 10:
		var y := lerpf(0.4, 1.3, i / 9.0)   # eje de la capsula (sin los casquetes)
		if _dist_to_box(feet + Vector3(0.0, y, 0.0), beam.center, beam.basis, size) <= 0.3:
			return true
	return false


func test_beam_hits_kaelen_on_path_only() -> void:
	for dist in [8.0, 12.0, 20.0]:
		var target := Vector3(0.0, 0.0, -dist)
		var beam = GhidorahBeamAim.solve(MOUTH, target, 0.35)
		assert_true(_kaelen_hit(target, beam), "Kaelen de pie en el impacto (%s m)" % dist)
		# Dentro del tramo de daño sobre la trayectoria tambien la alcanza.
		var slope := asin(-(beam.direction as Vector3).y)
		var run = GhidorahBeamAim.danger_run(slope, 0.75, 0.35)
		var inside := target + Vector3(0.0, 0.0, run * 0.6)
		assert_true(_kaelen_hit(inside, beam), "Kaelen dentro del tramo de daño (%s m)" % dist)
		# 2.5 m a un lado, o claramente detras del impacto, no la toca.
		assert_true(not _kaelen_hit(target + Vector3(2.5, 0.0, 0.0), beam), "2.5 m al lado (%s m)" % dist)
		assert_true(not _kaelen_hit(target + Vector3(0.0, 0.0, -3.0), beam), "pasado el impacto (%s m)" % dist)
		# Bajo el tramo alto del rayo (cerca de la boca) puede caminar sin recibir daño.
		var under := Vector3(0.0, 0.0, MOUTH.z - 1.0)
		if dist >= 12.0:
			assert_true(not _kaelen_hit(under, beam), "bajo el tramo alto (%s m)" % dist)


func test_danger_run() -> void:
	# Mas inclinado = tramo de daño en el suelo mas corto.
	var steep = GhidorahBeamAim.danger_run(deg_to_rad(50.0), 0.75, 0.35)
	var shallow = GhidorahBeamAim.danger_run(deg_to_rad(15.0), 0.75, 0.35)
	assert_true(shallow > steep * 3.0, "rayo rasante, tramo largo")
	assert_true(steep > 1.0 and steep < 3.0, "tramo corto con el rayo empinado")
