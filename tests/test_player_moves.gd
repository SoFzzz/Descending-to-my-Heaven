extends TestCase
# Kaelen's heavy attack timeline and the lock-on strafe animation scales (pure logic; the real
# behaviour in a level is in tests/flow/kaelen_moves_flow.tscn).


func test_heavy_timeline_is_ordered() -> void:
	assert_true(Player.HEAVY_LEAP_START < Player.HEAVY_LEAP_END, "the leap has a duration")
	assert_true(Player.HEAVY_HIT_START < Player.HEAVY_HIT_END, "the hit window has a duration")
	assert_true(Player.HEAVY_IMPACT >= Player.HEAVY_HIT_START and Player.HEAVY_IMPACT < Player.HEAVY_HIT_END, "impact inside the window")
	assert_true(Player.HEAVY_HIT_END < Player.HEAVY_END, "it hits before returning to MOVE")
	assert_true(Player.HEAVY_LEAP_END <= Player.HEAVY_HIT_START + 0.1, "it does not keep sliding through the slam")


func test_heavy_costs_more_and_hits_harder_than_one_slash() -> void:
	assert_true(Player.HEAVY_COST > Player.ATTACK_COST)
	assert_true(Player.HEAVY_DAMAGE > Player.COMBO_DAMAGE.max())
	var leap := Player.HEAVY_LEAP_SPEED * (Player.HEAVY_LEAP_END - Player.HEAVY_LEAP_START)
	assert_true(leap > 1.5 and leap < 2.5, "leap of about 2 m (%.2f)" % leap)


func test_heavy_clip_is_in_the_animation_tree_states() -> void:
	assert_true(Player.ACTION_STATES.has(Player.HEAVY_ANIM))
	assert_true(Player.SCALED_STATES.has(Player.HEAVY_ANIM))


func test_free_anim_scale() -> void:
	assert_almost(Player.free_anim_scale(0.0), 1.0)
	assert_almost(Player.free_anim_scale(Player.WALK_ANIM_SPEED), 1.0)
	assert_almost(Player.free_anim_scale(Player.RUN_ANIM_SPEED * 1.5), 1.5)
	assert_almost(Player.free_anim_scale(0.3), 0.6, 0.001, "very slow walk is clamped")


func test_strafe_anim_scale_by_direction() -> void:
	assert_almost(Player.strafe_anim_scale(Vector2.ZERO), 1.0)
	var side := Vector2(Player.LOCK_MOVE_SPEED, 0.0)
	assert_almost(Player.strafe_anim_scale(side), Player.LOCK_MOVE_SPEED / Player.STRAFE_ANIM_SPEED)
	var back := Vector2(0.0, -Player.LOCK_MOVE_SPEED)
	assert_almost(Player.strafe_anim_scale(back), Player.LOCK_MOVE_SPEED / Player.STRAFE_ANIM_SPEED)
	var fwd := Vector2(0.0, Player.LOCK_MOVE_SPEED)
	assert_almost(Player.strafe_anim_scale(fwd), Player.free_anim_scale(Player.LOCK_MOVE_SPEED), 0.001, "forward uses walk/run")


func test_lock_speed_is_slower_than_running() -> void:
	assert_true(Player.LOCK_MOVE_SPEED < Player.WALK_SPEED)
	assert_true(Player.LOCK_MOVE_SPEED <= Player.STRAFE_ANIM_SPEED * 1.8, "strafe clips are not sped up absurdly")


func test_heavy_attack_is_remappable() -> void:
	assert_true(GameSettings.REMAP_ACTIONS.has(&"heavy_attack"))
	assert_true(InputMap.has_action(&"heavy_attack"))


func _trigger(value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_TRIGGER_RIGHT
	e.axis_value = value
	return e


func test_trigger_counts_one_press_per_pull() -> void:
	var p := Player.new()
	for v in [0.3, 0.6, 1.0, 0.9]:
		p._unhandled_input(_trigger(v))
	assert_true(p._heavy_pressed, "pulling RT presses the heavy attack")
	p._heavy_pressed = false
	p._unhandled_input(_trigger(1.0))
	assert_true(not p._heavy_pressed, "holding RT does not press it again")
	p._unhandled_input(_trigger(0.0))
	p._unhandled_input(_trigger(0.7))
	assert_true(p._heavy_pressed, "releasing and pulling again presses it again")
	p.free()
