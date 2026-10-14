extends TestCase
# Pruebas de Stamina (gasto permitido con current > 0 y regeneración con espera).


func test_spend_requires_positive_stamina() -> void:
	var s := Stamina.new()
	s.current = 10.0
	assert_true(s.try_spend(25.0))
	assert_almost(s.current, 0.0)
	assert_true(not s.try_spend(20.0))
	s.free()


func test_no_regen_before_delay() -> void:
	var s := Stamina.new()
	s.try_spend(50.0)
	s.tick(0.5)
	assert_almost(s.current, 50.0)
	s.free()


func test_regen_rate_after_delay() -> void:
	var s := Stamina.new()
	s.try_spend(100.0)
	s.tick(0.6)
	assert_almost(s.current, 0.0)
	s.tick(1.0)
	assert_almost(s.current, 30.0)
	s.free()


func test_regen_clamps_at_max() -> void:
	var s := Stamina.new()
	s.try_spend(10.0)
	s.tick(0.6)
	s.tick(100.0)
	assert_almost(s.current, s.max_value)
	s.free()
