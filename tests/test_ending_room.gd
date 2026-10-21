extends TestCase
# Broken Elysia room: hole in the generated level, safety barrier and fall activation.

const Room := preload("res://scripts/game/ending_room.gd")


func test_speed_ramp() -> void:
	assert_almost(Room.speed_for(0.0), Room.IDLE_SPEED, 0.001, "idle: slow drift")
	assert_almost(Room.speed_for(1.0), 1.0, 0.001, "full fall")
	assert_almost(Room.speed_for(5.0), 1.0, 0.001, "capped at 1")
	assert_true(Room.speed_for(0.5) > Room.speed_for(0.2), "grows with intensity")


func test_wrap_height() -> void:
	assert_almost(Room.wrap_height(10.0), 10.0, 0.001, "within range it does not change")
	var wrapped: float = Room.wrap_height(Room.ROCK_TOP + 1.0)
	assert_true(wrapped < Room.ROCK_BOTTOM + 2.0, "past the top it reappears at the bottom")


func test_room_has_safety_barrier() -> void:
	var room := (load("res://scenes/props/ending_room.tscn") as PackedScene).instantiate()
	room._ready()
	var barrier := room.get_node_or_null(^"SafetyBarrier") as StaticBody3D
	assert_true(barrier != null, "SafetyBarrier missing")
	if barrier:
		assert_eq(barrier.collision_layer, 1, "the barrier collides with the world")
		var shape := barrier.get_child(0) as CollisionShape3D
		assert_true(shape != null and shape.shape is BoxShape3D, "the barrier has a shape")
		if shape:
			assert_true((shape.shape as BoxShape3D).size.x >= 9.0, "covers the hole from side to side")
	assert_true(room.is_in_group(Room.GROUP), "ending_room group (EndingDirector looks it up)")
	assert_true(room.get_node_or_null(^"Outside/Clouds") != null, "outside clouds")
	assert_true(room.get_node_or_null(^"Rubble") != null, "rubble")
	room.free()


func test_fall_starts_only_when_asked() -> void:
	var room := (load("res://scenes/props/ending_room.tscn") as PackedScene).instantiate()
	room._ready()
	assert_true(not room.falling, "it does not fall during combat")
	assert_true(not (room.get_node(^"CeilingDust") as CPUParticles3D).emitting, "no dust before the ending")
	room.start_fall()
	assert_true(room.falling, "it falls when the ending starts")
	assert_true((room.get_node(^"CeilingDust") as CPUParticles3D).emitting, "ceiling dust")
	assert_almost(room.intensity, 1.0, 0.001, "outside the tree it jumps to maximum intensity")
	room.free()


func test_wind_is_prepared_when_fall_starts() -> void:
	var room := (load("res://scenes/props/ending_room.tscn") as PackedScene).instantiate()
	room._ready()
	# Prepared on load (loading the mp3 at the fall stalled the ending's first frame) but silent.
	var idle := room.get_node_or_null(^"WindFall") as AudioStreamPlayer
	assert_true(idle == null or not idle.playing, "no wind during combat")
	room.start_fall()
	var wind := room.get_node_or_null(^"WindFall") as AudioStreamPlayer
	assert_true(wind != null, "the wind is created when the fall starts")
	if wind:
		assert_true(wind.stream is AudioStreamMP3 and (wind.stream as AudioStreamMP3).loop, "looped")
		assert_true(wind.stream.resource_path == "" or wind.stream.resource_path.ends_with("wind_fall.mp3"), "stream")
		assert_true(Room.WIND_VOLUME_DB < 0.0, "below the dialogues and the music")
	room.stop_wind(0.1)   # outside the tree: does not fail
	room.free()


func test_generated_arena_has_hole() -> void:
	var level := (load("res://scenes/levels/arena_3.tscn") as PackedScene).instantiate()
	var hall := level.get_node(^"Geometry/EndingHall")
	var cuts := 0
	for n in hall.get_children():
		if String(n.name).begins_with("Break") and (n as CSGShape3D).operation == CSGShape3D.OPERATION_SUBTRACTION:
			cuts += 1
	assert_true(cuts >= 4, "irregular hole in the wall and ceiling (%d cuts)" % cuts)
	var wall := hall.get_node(^"RoomWallN") as Node3D
	var cut := hall.get_node(^"BreakWallA") as Node3D
	assert_almost(cut.position.z, wall.position.z, 0.01, "the cut is on the north wall")
	level.free()


func test_gameplay_places_room_at_north_wall() -> void:
	var gp := (load("res://scenes/levels/arena_3_gameplay.tscn") as PackedScene).instantiate()
	var room := gp.get_node(^"EndingRoom") as Node3D
	var wall := gp.get_node(^"Level/Geometry/EndingHall/RoomWallN") as Node3D
	assert_almost(room.position.z, wall.position.z, 0.01, "origin at the center of the north wall")
	assert_almost(room.position.x, 0.0, 0.01, "centered")
	gp.free()


func test_wind_effect_only_outside_the_room() -> void:
	var room := (load("res://scenes/props/ending_room.tscn") as PackedScene).instantiate()
	room._ready()
	var streaks := room.get_node(^"Outside/WindStreaks") as Node3D
	assert_true(streaks != null, "the streaks exist, inside Outside")
	if streaks:
		# Its whole extent (local Z; the north wall is z = 0 and +Z enters the room) stays behind the hole.
		var extent: float = Room.GUST_DEPTH + Room.GUST_RADIUS
		assert_true(streaks.position.z + extent < Room.GUST_MAX_Z, "wind behind the barrier")
	# No visible air particle inside the room: the only things that fall inside are dust and pebbles.
	var inside := ["CeilingDust", "FallingPebbles"]
	for n in room.get_children():
		if n is CPUParticles3D or n is StormFX:
			assert_true(String(n.name) in inside, "particles inside the room: %s" % n.name)
	var dust := room.get_node(^"CeilingDust") as CPUParticles3D
	assert_true(dust.amount <= 20, "subtle dust")
	room.free()


func test_stone_not_gold() -> void:
	var level := (load("res://scenes/levels/arena_3.tscn") as PackedScene).instantiate()
	var wall := level.get_node(^"Geometry/EndingHall/RoomWallN") as CSGBox3D
	var mat := wall.material as BaseMaterial3D
	assert_true(mat != null and mat.albedo_texture != null
			and not mat.albedo_texture.resource_path.contains("gold512"), "stone north wall")
	level.free()
	var room := (load("res://scenes/props/ending_room.tscn") as PackedScene).instantiate()
	room._ready()
	var bad := 0
	for mi in room.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var bm := m.mesh.surface_get_material(0) if m.mesh and m.mesh.get_surface_count() > 0 else null
		var tex := (bm as BaseMaterial3D).albedo_texture if bm is BaseMaterial3D else null
		if tex and tex.resource_path.contains("gold512"):
			bad += 1
	assert_eq(bad, 0, "no block uses gold512")
	room.free()
