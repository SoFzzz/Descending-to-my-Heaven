extends TestCase
# Minion.alert(): puts the minion in CHASE and removes its lose radius (without needing the scene).


func test_alert_sets_chase_and_unlimited_lose_radius() -> void:
	var minion := Minion.new()
	assert_eq(minion.state, MinionBrain.State.IDLE)
	minion.alert()
	assert_eq(minion.state, MinionBrain.State.CHASE)
	assert_true(is_inf(minion.brain.lose_radius), "no loss radius")
	minion.free()


func test_alert_does_not_revive_a_dead_minion() -> void:
	var minion := Minion.new()
	minion.state = MinionBrain.State.DEAD
	minion.alert()
	assert_eq(minion.state, MinionBrain.State.DEAD)
	minion.free()


func test_order_to_sets_and_clears_the_order() -> void:
	var minion := Minion.new()
	assert_true(not minion.has_order())
	minion.order_to(Vector3(4, 0, 2), 1.5)
	assert_true(minion.has_order())
	minion.clear_order()
	assert_true(not minion.has_order())
	assert_true(not minion.is_retreating())
	minion.free()
