extends TestCase
# Every staircase of the arenas has a collision ramp (convex wedge) with a walkable slope
# (< Kaelen's floor_max_angle, 45 deg) joining the floor and the landing: Kaelen climbs and descends without steps.

const RAMPS := {"arena_1": ["EntryRamp", "ExitRamp"], "arena_2": ["EntryRamp", "ExitRamp"], "arena_3": ["EntryRamp"]}


func test_every_stair_has_a_walkable_ramp() -> void:
	for id in RAMPS:
		var level := (load("res://scenes/levels/%s.tscn" % id) as PackedScene).instantiate()
		for ramp_name in RAMPS[id]:
			var body := level.get_node_or_null("Geometry/" + ramp_name) as StaticBody3D
			assert_true(body != null, "%s has no %s" % [id, ramp_name])
			if body == null:
				continue
			var shape := body.get_node("Shape").shape as ConvexPolygonShape3D
			assert_true(shape != null, "%s/%s is not convex" % [id, ramp_name])
			var hi := Vector3(0, -99, 0)
			var lo := Vector3(0, 99, 0)
			for p in shape.points:
				if p.y > hi.y:
					hi = p
				if p.y < lo.y:
					lo = p
			# Top face: from the farthest point in Z (landing or bottom) to the foot of the staircase.
			var rise := absf(hi.y) if ramp_name == "ExitRamp" else absf(lo.y + 0.6)
			assert_true(rise > 1.9, "%s/%s height difference %.2f" % [id, ramp_name, rise])
			var slope_deg := rad_to_deg(atan(0.25 / 0.4))
			assert_true(slope_deg < 45.0, "slope %.1f" % slope_deg)
			assert_eq(body.collision_layer, 1, "%s/%s on the world layer" % [id, ramp_name])
		level.free()
