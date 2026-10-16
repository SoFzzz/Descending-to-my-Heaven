extends TestCase
# SquadTactics (pincer and shared threats) and their use in AttackTokens.

const TokensScript := preload("res://scripts/ai/attack_tokens.gd")


func test_pincer_points_are_opposite_the_boss() -> void:
	var player := Vector3(2, 0, 3)
	var boss := Vector3(2, 0, 11)
	var pts := SquadTactics.pincer_points(player, boss, 1)
	assert_eq(pts.size(), 1)
	var to_boss := (boss - player).normalized()
	var to_pt := (pts[0] - player).normalized()
	assert_almost(to_boss.dot(to_pt), -1.0, 0.001, "justo al lado contrario")
	assert_almost(pts[0].distance_to(player), SquadTactics.PINCER_RADIUS, 0.001)


func test_pincer_points_all_on_the_far_side_and_on_the_ring() -> void:
	var player := Vector3.ZERO
	var boss := Vector3(7, 0, -4)
	var pts := SquadTactics.pincer_points(player, boss, 3)
	assert_eq(pts.size(), 3)
	var to_boss := boss.normalized()
	for p in pts:
		assert_almost(p.distance_to(player), SquadTactics.PINCER_RADIUS, 0.001)
		assert_true(p.normalized().dot(to_boss) < -0.4, "en el hemisferio opuesto al jefe")
	# The fan is symmetric: the centre point is at 180°.
	assert_almost(pts[1].normalized().dot(to_boss), -1.0, 0.001)
	assert_true(pts[0].distance_to(pts[2]) > pts[0].distance_to(pts[1]), "separados")


func test_pincer_points_zero_minions() -> void:
	assert_eq(SquadTactics.pincer_points(Vector3.ZERO, Vector3.FORWARD * 5.0, 0).size(), 0)


func test_boss_pincer_point_keeps_the_boss_side() -> void:
	var p := SquadTactics.boss_pincer_point(Vector3.ZERO, Vector3(0, 1, 15))
	assert_almost(p.z, SquadTactics.BOSS_PINCER_DISTANCE, 0.001)
	assert_almost(p.x, 0.0, 0.001)
	assert_almost(p.y, 1.0)


func test_assign_points_is_a_one_to_one_matching() -> void:
	var from: Array[Vector3] = [Vector3(-5, 0, 0), Vector3(5, 0, 0)]
	var to: Array[Vector3] = [Vector3(4, 0, 1), Vector3(-4, 0, 1)]
	var a := SquadTactics.assign_points(from, to)
	assert_eq(a[0], 1, "el de la izquierda va al punto de la izquierda")
	assert_eq(a[1], 0)


func test_assign_points_with_more_minions_than_points() -> void:
	var from: Array[Vector3] = [Vector3.ZERO, Vector3(10, 0, 0), Vector3(20, 0, 0)]
	var to: Array[Vector3] = [Vector3(1, 0, 0)]
	var a := SquadTactics.assign_points(from, to)
	assert_eq(a.count(-1), 2)
	assert_eq(a[0], 0)


func test_token_slots() -> void:
	assert_eq(SquadTactics.token_slots(false, false, 2), 2)
	assert_eq(SquadTactics.token_slots(true, true, 2), 0, "amenaza cerca: nadie inicia ataque")
	assert_eq(SquadTactics.token_slots(true, false, 2), 1, "amenaza lejos (rayo): una ficha menos")
	assert_eq(SquadTactics.token_slots(true, false, 0), 0)


func test_may_start_attack() -> void:
	assert_true(SquadTactics.may_start_attack(true, false, false))
	assert_true(not SquadTactics.may_start_attack(false, false, false), "sin ficha no")
	assert_true(not SquadTactics.may_start_attack(true, true, true))
	assert_true(SquadTactics.may_start_attack(true, true, false))


func test_attack_tokens_respect_boss_threat() -> void:
	var t: Node = TokensScript.new()
	var a := Node.new()
	var b := Node.new()
	t.set_boss_threat(true, true)
	assert_true(not t.request(a), "el jefe amenaza cerca de Kaelen")
	t.set_boss_threat(true, false)
	assert_true(t.request(a))
	assert_true(not t.request(b), "con amenaza lejana solo una ficha")
	t.set_boss_threat(false, false)
	assert_true(t.request(b))
	assert_eq(t.holders_count(), 2)
	t.reset()
	assert_eq(t.slots(), 2)
	for n in [t, a, b]:
		n.free()
