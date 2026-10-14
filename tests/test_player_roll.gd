extends TestCase
# Pruebas de la rodada de Kaelen (ventana de invulnerabilidad, costo de estamina y banderas).


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
	assert_true(not p.try_roll(), "try_roll con estamina 0")
	assert_eq(p.state, Player.State.MOVE)
	p.free()
	s.free()


# Foco de revisión 4: tras boss_defeated, terminar una rodada no debe quitar la invulnerabilidad.
func test_invulnerable_combines_flags() -> void:
	var p := Player.new()
	var s := Stamina.new()
	var h := Health.new()
	p.stamina = s
	p.health = h
	assert_true(p.try_roll(), "try_roll con estamina llena")
	assert_eq(p.state, Player.State.ROLL)
	p._advance_roll(0.1)                 # dentro de la ventana de i-frames
	assert_true(p.is_invulnerable(), "i-frames activos")
	p._on_boss_defeated(null)            # victoria a mitad de la rodada
	p._advance_roll(Player.ROLL_DURATION) # la rodada termina
	assert_eq(p.state, Player.State.MOVE)
	assert_true(p.is_invulnerable(), "la victoria mantiene la invulnerabilidad")
	assert_true(h.invulnerable, "Health también queda invulnerable")
	p.free()
	s.free()
	h.free()
