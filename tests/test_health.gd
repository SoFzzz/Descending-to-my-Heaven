extends TestCase
# Tests for Health (health with signals and invulnerability).


func test_damage_reduces_and_clamps_at_zero() -> void:
	var h := Health.new()
	h.reset()
	h.take_damage(30)
	assert_eq(h.current, 70)
	h.take_damage(500)
	assert_eq(h.current, 0)
	assert_true(h.is_dead())
	h.free()


func test_died_emits_once() -> void:
	var h := Health.new()
	h.reset()
	var count: Array[int] = [0]
	h.died.connect(func() -> void: count[0] += 1)
	h.take_damage(500)
	h.take_damage(500)
	assert_eq(count[0], 1)
	h.free()


func test_invulnerable_ignores_damage() -> void:
	var h := Health.new()
	h.reset()
	h.invulnerable = true
	h.take_damage(50)
	assert_eq(h.current, 100)
	h.free()


func test_reset_with_new_max() -> void:
	var h := Health.new()
	h.reset(70)
	assert_eq(h.current, 70)
	assert_eq(h.max_value, 70)
	h.free()
