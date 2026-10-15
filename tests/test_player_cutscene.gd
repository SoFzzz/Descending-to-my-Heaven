extends TestCase
# set_cutscene de Kaelen: invulnerable mientras dura y cancela rodada/ataque en curso.


func test_cutscene_makes_invulnerable() -> void:
	var p := Player.new()
	var h := Health.new()
	p.health = h
	assert_true(not p.is_invulnerable(), "antes")
	p.set_cutscene(true)
	assert_true(p.is_cutscene(), "bandera")
	assert_true(p.is_invulnerable(), "invulnerable en la secuencia")
	assert_true(h.invulnerable, "Health lo refleja")
	p.set_cutscene(false)
	assert_true(not p.is_invulnerable(), "después")
	p.free()
	h.free()


func test_cutscene_cancels_roll() -> void:
	var p := Player.new()
	var s := Stamina.new()
	p.stamina = s
	assert_true(p.try_roll(), "rueda")
	assert_eq(p.state, Player.State.ROLL)
	p.set_cutscene(true)
	assert_eq(p.state, Player.State.MOVE, "la rodada se cancela")
	p.free()
	s.free()
