extends TestCase
# Minion.alert(): pone al esbirro en CHASE y le quita el radio de pérdida (sin necesitar la escena).


func test_alert_sets_chase_and_unlimited_lose_radius() -> void:
	var minion := Minion.new()
	assert_eq(minion.state, MinionBrain.State.IDLE)
	minion.alert()
	assert_eq(minion.state, MinionBrain.State.CHASE)
	assert_true(is_inf(minion.brain.lose_radius), "sin radio de pérdida")
	minion.free()


func test_alert_does_not_revive_a_dead_minion() -> void:
	var minion := Minion.new()
	minion.state = MinionBrain.State.DEAD
	minion.alert()
	assert_eq(minion.state, MinionBrain.State.DEAD)
	minion.free()
