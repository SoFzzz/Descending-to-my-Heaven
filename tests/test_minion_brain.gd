extends TestCase
# MinionBrain tests (pure minion state machine and vision cone).

const S := MinionBrain.State


## Base context: Kaelen is far away and nothing happened. Each test overrides only its own keys.
func _ctx(overrides: Dictionary = {}) -> Dictionary:
	var ctx := {
		distance = 20.0,
		sees_player = false,
		has_token = false,
		attack_finished = false,
		recover_finished = false,
		stun_finished = false,
		was_hit = false,
		is_dead = false,
	}
	ctx.merge(overrides, true)
	return ctx


func test_idle_to_chase_when_seen() -> void:
	var b := MinionBrain.new()
	assert_eq(b.next_state(S.IDLE, _ctx({distance = 10.0})), S.IDLE, "sin verla sigue quieto")
	assert_eq(b.next_state(S.IDLE, _ctx({distance = 10.0, sees_player = true})), S.CHASE)


func test_chase_to_circle_without_token() -> void:
	var b := MinionBrain.new()
	assert_eq(b.next_state(S.CHASE, _ctx({distance = 4.0, sees_player = true})), S.CIRCLE)
	assert_eq(b.next_state(S.CHASE, _ctx({distance = 1.0, sees_player = true})), S.CIRCLE, "sin ficha no ataca aunque esté pegado")
	assert_eq(b.next_state(S.CHASE, _ctx({distance = 6.0, sees_player = true})), S.CHASE)


func test_chase_to_attack_with_token() -> void:
	var b := MinionBrain.new()
	assert_eq(b.next_state(S.CHASE, _ctx({distance = 1.5, sees_player = true, has_token = true})), S.ATTACK)
	assert_eq(b.next_state(S.CHASE, _ctx({distance = 3.0, sees_player = true, has_token = true})), S.CHASE, "con ficha se acerca hasta el rango")


func test_attack_to_recover() -> void:
	var b := MinionBrain.new()
	assert_eq(b.next_state(S.ATTACK, _ctx({distance = 1.0, has_token = true})), S.ATTACK)
	assert_eq(b.next_state(S.ATTACK, _ctx({distance = 1.0, has_token = true, attack_finished = true})), S.RECOVER)
	assert_eq(b.next_state(S.RECOVER, _ctx({distance = 1.0})), S.RECOVER)
	assert_eq(b.next_state(S.RECOVER, _ctx({distance = 1.0, recover_finished = true})), S.CHASE)


func test_hit_interrupts_to_stunned() -> void:
	var b := MinionBrain.new()
	for s in [S.IDLE, S.CHASE, S.CIRCLE, S.ATTACK, S.RECOVER, S.STUNNED]:
		assert_eq(b.next_state(s, _ctx({distance = 1.0, has_token = true, was_hit = true})), S.STUNNED, "desde %d" % s)
	assert_eq(b.next_state(S.STUNNED, _ctx({distance = 1.0})), S.STUNNED)
	assert_eq(b.next_state(S.STUNNED, _ctx({distance = 1.0, stun_finished = true})), S.CHASE)


func test_dead_is_terminal() -> void:
	var b := MinionBrain.new()
	for s in [S.IDLE, S.CHASE, S.CIRCLE, S.ATTACK, S.RECOVER, S.STUNNED, S.DEAD]:
		assert_eq(b.next_state(s, _ctx({is_dead = true, was_hit = true})), S.DEAD, "desde %d" % s)
	# It never leaves DEAD, even if the context says it is alive and sees the player.
	var alive := _ctx({distance = 1.0, sees_player = true, has_token = true, recover_finished = true, stun_finished = true})
	assert_eq(b.next_state(S.DEAD, alive), S.DEAD)


func test_circle_to_attack_when_token_granted() -> void:
	var b := MinionBrain.new()
	assert_eq(b.next_state(S.CIRCLE, _ctx({distance = 3.5, sees_player = true})), S.CIRCLE)
	assert_eq(b.next_state(S.CIRCLE, _ctx({distance = 1.2, sees_player = true, has_token = true})), S.ATTACK)
	# Has a token but is out of range: it closes in (CHASE) and attacks on arrival.
	assert_eq(b.next_state(S.CIRCLE, _ctx({distance = 3.5, sees_player = true, has_token = true})), S.CHASE)


func test_lose_sight_returns_to_idle() -> void:
	var b := MinionBrain.new()
	# Behind a pillar but close: the trail is not lost.
	assert_eq(b.next_state(S.CHASE, _ctx({distance = 8.0})), S.CHASE)
	assert_eq(b.next_state(S.CIRCLE, _ctx({distance = 3.5})), S.CIRCLE)
	# Not seen and farther than the detection radius: returns to IDLE.
	assert_eq(b.next_state(S.CHASE, _ctx({distance = 13.0})), S.IDLE)
	assert_eq(b.next_state(S.CIRCLE, _ctx({distance = 13.0})), S.IDLE)


func test_can_see_cone() -> void:
	var from := Vector3.ZERO
	var fwd := Vector3.FORWARD  # -Z
	assert_true(MinionBrain.can_see(from, fwd, Vector3(0, 0, -5)), "5 m al frente")
	assert_true(not MinionBrain.can_see(from, fwd, Vector3(0, 0, 5)), "5 m detrás")
	assert_true(not MinionBrain.can_see(from, fwd, Vector3(0, 0, -13)), "13 m al frente")
	var at_50 := Vector3(sin(deg_to_rad(50.0)), 0.0, -cos(deg_to_rad(50.0))) * 5.0
	var at_60 := Vector3(sin(deg_to_rad(60.0)), 0.0, -cos(deg_to_rad(60.0))) * 5.0
	assert_true(MinionBrain.can_see(from, fwd, at_50), "5 m a 50°")
	assert_true(not MinionBrain.can_see(from, fwd, at_60), "5 m a 60°")
