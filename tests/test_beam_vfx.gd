extends TestCase
# Ghidorah beam: effect opening, mouth -> ground line, and effect, hitbox and telegraph matching.

const MOUTH := Vector3(0.0, 5.5, -3.5)   # mouth of the central head in `beam` (by eye, boss at the origin)


func test_open_progress() -> void:
	assert_almost(BeamVfx.open_progress(0.0), 0.0)
	assert_almost(BeamVfx.open_progress(BeamVfx.OPEN_TIME * 0.5), 0.5)
	assert_almost(BeamVfx.open_progress(5.0), 1.0, 0.0001, "does not exceed 1")
	assert_almost(BeamVfx.open_progress(1.0, 0.0), 1.0, 0.0001, "duration 0 = open")


func test_scene_wiring() -> void:
	var scene := load("res://scenes/bosses/boss_ghidorah.tscn") as PackedScene
	var boss := scene.instantiate()
	var attack := load("res://resources/attacks/ghidorah_beam.tres") as BossAttack
	var visual := boss.get_node_or_null(attack.visual_path) as BeamVfx
	assert_true(visual != null, "BeamVisual is a BeamVfx")
	assert_true(not visual.visible, "hidden outside ACTIVE")
	assert_true(boss.get_node_or_null(attack.hitbox_path) is Hitbox, "BeamHitbox")
	assert_true(boss.get_node_or_null(^"BeamAim") is GhidorahBeamAim, "BeamAim aims the beam")
	assert_true(boss.get_node_or_null(^"Telegraphs/beam/HitZone") != null, "damage section of the telegraph")
	assert_eq(boss.get_node(^"BeamAim").get_index(), boss.get_child_count() - 1, "BeamAim is the last child")
	boss.free()


func test_solve_reaches_ground_at_target() -> void:
	var target := Vector3(0.0, 0.0, -12.0)
	var beam = GhidorahBeamAim.solve(MOUTH, target, 0.35)
	var end: Vector3 = beam.end
	assert_almost(end.distance_to(target + Vector3.UP * 0.35), 0.0, 0.0001, "ends on the impact")
	assert_almost(beam.length, MOUTH.distance_to(target + Vector3.UP * 0.35), 0.0001, "length")
	assert_true((beam.direction as Vector3).y < -0.3, "goes down diagonally")
	assert_true(end.y >= 0.0, "does not go through the floor")
	# The base -Z axis points along the line (like the pack effect).
	assert_almost((-(beam.basis as Basis).z).dot(beam.direction), 1.0, 0.0001, "base faces the impact")


func test_clamp_target_range() -> void:
	var boss := Vector3(2.0, 0.0, 3.0)
	var near = GhidorahBeamAim.clamp_target(boss, Vector3(2.0, 0.0, 1.0), 8.0, 20.0)
	assert_almost(Vector2(near.x - boss.x, near.z - boss.z).length(), 8.0, 0.0001, "minimum 8")
	var far = GhidorahBeamAim.clamp_target(boss, Vector3(2.0, 0.0, -60.0), 8.0, 20.0)
	assert_almost(Vector2(far.x - boss.x, far.z - boss.z).length(), 20.0, 0.0001, "maximum 20")
	var mid = GhidorahBeamAim.clamp_target(boss, Vector3(2.0, 0.5, -9.0), 8.0, 20.0)
	assert_almost(mid.z, -9.0, 0.0001, "within range it does not move")
	assert_almost(mid.y, 0.5, 0.0001, "Kaelen's height")


## Distance from `point` to the hitbox box (center `center`, basis `basis`, local size `size`).
func _dist_to_box(point: Vector3, center: Vector3, basis: Basis, size: Vector3) -> float:
	var local := basis.inverse() * (point - center)
	var outside := Vector3(maxf(absf(local.x) - size.x * 0.5, 0.0), maxf(absf(local.y) - size.y * 0.5, 0.0), maxf(absf(local.z) - size.z * 0.5, 0.0))
	return outside.length()


const HIT_SIZE := Vector3(1.5, 2.4, 2.0)   # width, height and length of the damage zone that travels with the impact


## True if Kaelen's capsule (r 0.30, height 1.50, center 0.85 m above her feet) touches the damage zone
## when the impact is at `impact` and the beam goes in direction `dir`.
func _kaelen_hit(feet: Vector3, impact: Vector3, dir: Vector3) -> bool:
	var basis := Basis.looking_at(dir, Vector3.UP)
	var center := impact + Vector3.UP * HIT_SIZE.y * 0.5
	for i in 10:
		var y := lerpf(0.4, 1.3, i / 9.0)   # capsule axis (without the end caps)
		if _dist_to_box(feet + Vector3(0.0, y, 0.0), center, basis, HIT_SIZE) <= 0.3:
			return true
	return false


## 1/60 s steps of the sweep (0.9 s) in which Kaelen at `feet` is hit by the beam.
func _hit_steps(line: Dictionary, feet: Vector3, steps := 54) -> int:
	var n := 0
	for i in steps + 1:
		if _kaelen_hit(feet, GhidorahBeamAim.sweep_point(line, float(i) / steps), line.dir):
			n += 1
	return n


func test_sweep_line_runs_from_boss_through_target() -> void:
	var boss := Vector3(2.0, 0.0, 3.0)
	var target := Vector3(2.0, 0.5, -9.0)   # at 12 m, straight ahead
	var line = GhidorahBeamAim.sweep_line(boss, target, 2.5, 2.0)
	assert_almost((line.from as Vector3).distance_to(Vector3(2.0, 0.5, 0.5)), 0.0, 0.0001, "starts 2.5 m from the boss")
	assert_almost((line.to as Vector3).distance_to(Vector3(2.0, 0.5, -11.0)), 0.0, 0.0001, "ends 2 m past Kaelen")
	assert_almost(line.length, 11.5, 0.0001)
	assert_almost((line.dir as Vector3).distance_to(Vector3(0.0, 0.0, -1.0)), 0.0, 0.0001)


func test_sweep_point_interpolates() -> void:
	var line = GhidorahBeamAim.sweep_line(Vector3.ZERO, Vector3(0.0, 0.0, -10.0), 2.0, 2.0)
	assert_almost((GhidorahBeamAim.sweep_point(line, 0.0) as Vector3).z, -2.0, 0.0001)
	assert_almost((GhidorahBeamAim.sweep_point(line, 0.5) as Vector3).z, -7.0, 0.0001)
	assert_almost((GhidorahBeamAim.sweep_point(line, 1.0) as Vector3).z, -12.0, 0.0001)
	assert_almost((GhidorahBeamAim.sweep_point(line, 2.0) as Vector3).z, -12.0, 0.0001, "does not go past the end")


func test_beam_hits_only_where_impact_passes() -> void:
	for dist in [8.0, 12.0, 20.0]:
		var target := Vector3(0.0, 0.0, -dist)
		var line = GhidorahBeamAim.sweep_line(Vector3.ZERO, target, 2.5, 2.0)
		var on_target := _hit_steps(line, target)
		assert_true(on_target >= 3, "Kaelen standing still at the fixed point is hit by the beam (%s m)" % dist)
		assert_true(on_target <= 24, "...but only while the impact passes, not the whole sweep (%s m: %d steps)" % [dist, on_target])
		# Near the boss, before the impact reaches Kaelen, there is no damage at her spot.
		assert_true(not _kaelen_hit(target, GhidorahBeamAim.sweep_point(line, 0.0), line.dir), "at the start the impact is far away (%s m)" % dist)
		assert_true(not _kaelen_hit(target, GhidorahBeamAim.sweep_point(line, 1.0), line.dir), "at the end it has already gone past (%s m)" % dist)
		# Off the line (2.5 m to the side) it never touches her.
		assert_eq(_hit_steps(line, target + Vector3(2.5, 0.0, 0.0)), 0, "to one side takes no damage (%s m)" % dist)
		# A little before the fixed point it also reaches her (the impact passes through there).
		assert_true(_hit_steps(line, target + Vector3(0.0, 0.0, 3.0)) > 0, "the impact travels the line toward her (%s m)" % dist)


func test_beam_sweep_speed_is_dodgeable() -> void:
	# With a 0.9 s sweep, an impact going from 2.5 m to (distance + 2) m from the boss.
	var attack := load("res://resources/attacks/ghidorah_beam.tres") as BossAttack
	assert_true(attack.active_time >= 0.6 and attack.active_time <= 1.0, "sweep of 0.6 to 1.0 s")
	var line = GhidorahBeamAim.sweep_line(Vector3.ZERO, Vector3(0.0, 0.0, -20.0), 2.5, 2.0)
	var speed: float = line.length / attack.active_time
	assert_true(speed < 22.0, "in the worst case (20 m) it advances at %.1f m/s" % speed)
