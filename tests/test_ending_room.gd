extends TestCase
# Sala de Elysia rota: hueco en el nivel generado, barrera de seguridad y activación de la caída.

const Room := preload("res://scripts/game/ending_room.gd")


func test_speed_ramp() -> void:
	assert_almost(Room.speed_for(0.0), Room.IDLE_SPEED, 0.001, "quieta: deriva lenta")
	assert_almost(Room.speed_for(1.0), 1.0, 0.001, "caída completa")
	assert_almost(Room.speed_for(5.0), 1.0, 0.001, "se limita a 1")
	assert_true(Room.speed_for(0.5) > Room.speed_for(0.2), "crece con la intensidad")


func test_wrap_height() -> void:
	assert_almost(Room.wrap_height(10.0), 10.0, 0.001, "dentro del rango no cambia")
	var wrapped: float = Room.wrap_height(Room.ROCK_TOP + 1.0)
	assert_true(wrapped < Room.ROCK_BOTTOM + 2.0, "pasado el tope reaparece abajo")


func test_room_has_safety_barrier() -> void:
	var room := (load("res://scenes/props/ending_room.tscn") as PackedScene).instantiate()
	room._ready()
	var barrier := room.get_node_or_null(^"SafetyBarrier") as StaticBody3D
	assert_true(barrier != null, "falta SafetyBarrier")
	if barrier:
		assert_eq(barrier.collision_layer, 1, "la barrera colisiona con el mundo")
		var shape := barrier.get_child(0) as CollisionShape3D
		assert_true(shape != null and shape.shape is BoxShape3D, "la barrera tiene forma")
		if shape:
			assert_true((shape.shape as BoxShape3D).size.x >= 9.0, "cubre el hueco de lado a lado")
	assert_true(room.is_in_group(Room.GROUP), "grupo ending_room (lo busca EndingDirector)")
	assert_true(room.get_node_or_null(^"Outside/Clouds") != null, "nubes del exterior")
	assert_true(room.get_node_or_null(^"Rubble") != null, "escombros")
	room.free()


func test_fall_starts_only_when_asked() -> void:
	var room := (load("res://scenes/props/ending_room.tscn") as PackedScene).instantiate()
	room._ready()
	assert_true(not room.falling, "no cae durante el combate")
	assert_true(not (room.get_node(^"CeilingDust") as CPUParticles3D).emitting, "sin polvo antes del final")
	room.start_fall()
	assert_true(room.falling, "cae al empezar el final")
	assert_true((room.get_node(^"CeilingDust") as CPUParticles3D).emitting, "polvo del techo")
	assert_almost(room.intensity, 1.0, 0.001, "fuera del árbol salta a máxima intensidad")
	room.free()


func test_generated_arena_has_hole() -> void:
	var level := (load("res://scenes/levels/arena_3.tscn") as PackedScene).instantiate()
	var hall := level.get_node(^"Geometry/EndingHall")
	var cuts := 0
	for n in hall.get_children():
		if String(n.name).begins_with("Break") and (n as CSGShape3D).operation == CSGShape3D.OPERATION_SUBTRACTION:
			cuts += 1
	assert_true(cuts >= 4, "hueco irregular en el muro y el techo (%d cortes)" % cuts)
	var wall := hall.get_node(^"RoomWallN") as Node3D
	var cut := hall.get_node(^"BreakWallA") as Node3D
	assert_almost(cut.position.z, wall.position.z, 0.01, "el corte está en el muro norte")
	level.free()


func test_gameplay_places_room_at_north_wall() -> void:
	var gp := (load("res://scenes/levels/arena_3_gameplay.tscn") as PackedScene).instantiate()
	var room := gp.get_node(^"EndingRoom") as Node3D
	var wall := gp.get_node(^"Level/Geometry/EndingHall/RoomWallN") as Node3D
	assert_almost(room.position.z, wall.position.z, 0.01, "origen en el centro del muro norte")
	assert_almost(room.position.x, 0.0, 0.01, "centrada")
	gp.free()
