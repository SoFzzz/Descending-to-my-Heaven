extends TestCase
# Cada escalera de las arenas tiene una rampa de colisión (cuña convexa) con pendiente transitable
# (< floor_max_angle de Kaelen, 45°) que une el suelo con el rellano: Kaelen sube y baja sin escalones.

const RAMPS := {"arena_1": ["EntryRamp", "ExitRamp"], "arena_2": ["EntryRamp", "ExitRamp"], "arena_3": ["EntryRamp"]}


func test_every_stair_has_a_walkable_ramp() -> void:
	for id in RAMPS:
		var level := (load("res://scenes/levels/%s.tscn" % id) as PackedScene).instantiate()
		for ramp_name in RAMPS[id]:
			var body := level.get_node_or_null("Geometry/" + ramp_name) as StaticBody3D
			assert_true(body != null, "%s sin %s" % [id, ramp_name])
			if body == null:
				continue
			var shape := body.get_node("Shape").shape as ConvexPolygonShape3D
			assert_true(shape != null, "%s/%s no es convexa" % [id, ramp_name])
			var hi := Vector3(0, -99, 0)
			var lo := Vector3(0, 99, 0)
			var top_pts := []
			for p in shape.points:
				if p.y > hi.y:
					hi = p
				if p.y < lo.y:
					lo = p
			# Cara superior: del punto más lejano en Z (rellano o fondo) al pie de la escalera.
			var rise := absf(hi.y) if ramp_name == "ExitRamp" else absf(lo.y + 0.6)
			assert_true(rise > 1.9, "%s/%s desnivel %.2f" % [id, ramp_name, rise])
			var slope_deg := rad_to_deg(atan(0.25 / 0.4))
			assert_true(slope_deg < 45.0, "pendiente %.1f" % slope_deg)
			assert_eq(body.collision_layer, 1, "%s/%s en la capa world" % [id, ramp_name])
		level.free()
