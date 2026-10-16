extends TestCase
# Kaelen's set_cutscene: invulnerable while it lasts and cancels an ongoing roll/attack.


func test_cutscene_makes_invulnerable() -> void:
	var p := Player.new()
	var h := Health.new()
	p.health = h
	assert_true(not p.is_invulnerable(), "before")
	p.set_cutscene(true)
	assert_true(p.is_cutscene(), "flag")
	assert_true(p.is_invulnerable(), "invulnerable during the sequence")
	assert_true(h.invulnerable, "Health reflects it")
	p.set_cutscene(false)
	assert_true(not p.is_invulnerable(), "after")
	p.free()
	h.free()


func test_cutscene_cancels_roll() -> void:
	var p := Player.new()
	var s := Stamina.new()
	p.stamina = s
	assert_true(p.try_roll(), "rolls")
	assert_eq(p.state, Player.State.ROLL)
	p.set_cutscene(true)
	assert_eq(p.state, Player.State.MOVE, "the roll is cancelled")
	p.free()
	s.free()
