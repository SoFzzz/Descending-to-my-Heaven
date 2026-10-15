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


const HIT_SIZE := Vector3(1.5, 2.4, 2.0)   # ancho, alto y largo de la zona de daño que viaja con el impacto


## True si la capsula de Kaelen (r 0.30, alto 1.50, centro a 0.85 m de sus pies) toca la zona de
## daño cuando el impacto esta en `impact` y el rayo va en la direccion `dir`.
func _kaelen_hit(feet: Vector3, impact: Vector3, dir: Vector3) -> bool:
	var basis := Basis.looking_at(dir, Vector3.UP)
	var center := impact + Vector3.UP * HIT_SIZE.y * 0.5
	for i in 10:
		var y := lerpf(0.4, 1.3, i / 9.0)   # eje de la capsula (sin los casquetes)
		if _dist_to_box(feet + Vector3(0.0, y, 0.0), center, basis, HIT_SIZE) <= 0.3:
			return true
	return false


## Pasos de 1/60 s del recorrido (0,9 s) en los que Kaelen en `feet` recibe el rayo.
func _hit_steps(line: Dictionary, feet: Vector3, steps := 54) -> int:
	var n := 0
	for i in steps + 1:
		if _kaelen_hit(feet, GhidorahBeamAim.sweep_point(line, float(i) / steps), line.dir):
			n += 1
	return n


func test_sweep_line_runs_from_boss_through_target() -> void:
	var boss := Vector3(2.0, 0.0, 3.0)
	var target := Vector3(2.0, 0.5, -9.0)   # a 12 m, recto delante
	var line = GhidorahBeamAim.sweep_line(boss, target, 2.5, 2.0)
	assert_almost((line.from as Vector3).distance_to(Vector3(2.0, 0.5, 0.5)), 0.0, 0.0001, "empieza a 2.5 m del jefe")
	assert_almost((line.to as Vector3).distance_to(Vector3(2.0, 0.5, -11.0)), 0.0, 0.0001, "termina 2 m despues de Kaelen")
	assert_almost(line.length, 11.5, 0.0001)
	assert_almost((line.dir as Vector3).distance_to(Vector3(0.0, 0.0, -1.0)), 0.0, 0.0001)


func test_sweep_point_interpolates() -> void:
	var line = GhidorahBeamAim.sweep_line(Vector3.ZERO, Vector3(0.0, 0.0, -10.0), 2.0, 2.0)
	assert_almost((GhidorahBeamAim.sweep_point(line, 0.0) as Vector3).z, -2.0, 0.0001)
	assert_almost((GhidorahBeamAim.sweep_point(line, 0.5) as Vector3).z, -7.0, 0.0001)
	assert_almost((GhidorahBeamAim.sweep_point(line, 1.0) as Vector3).z, -12.0, 0.0001)
	assert_almost((GhidorahBeamAim.sweep_point(line, 2.0) as Vector3).z, -12.0, 0.0001, "no pasa del final")


func test_beam_hits_only_where_impact_passes() -> void:
	for dist in [8.0, 12.0, 20.0]:
		var target := Vector3(0.0, 0.0, -dist)
		var line = GhidorahBeamAim.sweep_line(Vector3.ZERO, target, 2.5, 2.0)
		var on_target := _hit_steps(line, target)
		assert_true(on_target >= 3, "Kaelen quieta en el punto fijado recibe el rayo (%s m)" % dist)
		assert_true(on_target <= 24, "...pero solo mientras pasa el impacto, no todo el recorrido (%s m: %d pasos)" % [dist, on_target])
		# Cerca del jefe, antes de que el impacto llegue a Kaelen, no hay dano en su sitio.
		assert_true(not _kaelen_hit(target, GhidorahBeamAim.sweep_point(line, 0.0), line.dir), "al inicio el impacto esta lejos (%s m)" % dist)
		assert_true(not _kaelen_hit(target, GhidorahBeamAim.sweep_point(line, 1.0), line.dir), "al final ya paso de largo (%s m)" % dist)
		# Fuera de la linea (2.5 m al lado) nunca la toca.
		assert_eq(_hit_steps(line, target + Vector3(2.5, 0.0, 0.0)), 0, "a un lado no recibe dano (%s m)" % dist)
		# Un poco antes del punto fijado tambien la alcanza (el impacto pasa por ahi).
		assert_true(_hit_steps(line, target + Vector3(0.0, 0.0, 3.0)) > 0, "el impacto recorre la linea hacia ella (%s m)" % dist)


func test_beam_sweep_speed_is_dodgeable() -> void:
	# Con 0.9 s de recorrido, un impacto que va de 2.5 m a (distancia + 2) m del jefe.
	var attack := load("res://resources/attacks/ghidorah_beam.tres") as BossAttack
	assert_true(attack.active_time >= 0.6 and attack.active_time <= 1.0, "recorrido de 0.6 a 1.0 s")
	var line = GhidorahBeamAim.sweep_line(Vector3.ZERO, Vector3(0.0, 0.0, -20.0), 2.5, 2.0)
	var speed: float = line.length / attack.active_time
	assert_true(speed < 22.0, "en el peor caso (20 m) avanza a %.1f m/s" % speed)
