extends TestCase
# Tests for Kaelen's roll (invulnerability window, stamina cost and flags).


func test_iframes_window() -> void:
	assert_true(not Player.iframes_active_at(0.0), "t = 0.0")
	assert_true(Player.iframes_active_at(0.05), "t = 0.05")
	assert_true(Player.iframes_active_at(0.30), "t = 0.30")
	assert_true(not Player.iframes_active_at(0.45), "t = 0.45")


func test_roll_needs_stamina() -> void:
	var p := Player.new()
	var s := Stamina.new()
	p.stamina = s
	s.current = 0.0
	assert_true(not p.try_roll(), "try_roll with 0 stamina")
	assert_eq(p.state, Player.State.MOVE)
	p.free()
	s.free()


# Review focus 4: after boss_defeated, finishing a roll must not remove invulnerability.
func test_invulnerable_combines_flags() -> void:
	var p := Player.new()
	var s := Stamina.new()
	var h := Health.new()
	p.stamina = s
	p.health = h
	assert_true(p.try_roll(), "try_roll with full stamina")
	assert_eq(p.state, Player.State.ROLL)
	p._advance_roll(0.1)                 # within the i-frames window
	assert_true(p.is_invulnerable(), "i-frames active")
	p._on_boss_defeated(null)            # victory in the middle of the roll
	p._advance_roll(Player.ROLL_DURATION) # the roll ends
	assert_eq(p.state, Player.State.MOVE)
	assert_true(p.is_invulnerable(), "victory keeps invulnerability")
	assert_true(h.invulnerable, "Health also becomes invulnerable")
	p.free()
	s.free()
	h.free()
