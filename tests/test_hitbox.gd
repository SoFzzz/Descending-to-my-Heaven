extends TestCase
# Tests for Hitbox/Hurtbox (one hit per target and activation, damage multiplier).


func test_hitbox_hits_each_target_once_per_activation() -> void:
	var hb := Hitbox.new()
	var hurt := Hurtbox.new()
	hb.activate()
	assert_true(hb.register_hit(hurt))
	assert_true(not hb.register_hit(hurt))
	hb.deactivate()
	hb.activate()
	assert_true(hb.register_hit(hurt))
	hb.free()
	hurt.free()


func test_hurtbox_applies_multiplier() -> void:
	var health := Health.new()
	health.reset()
	var hurt := Hurtbox.new()
	hurt.health = health
	hurt.damage_multiplier = 1.25
	hurt.receive_hit(20, null)
	assert_eq(health.current, 75)
	hurt.free()
	health.free()


func test_inactive_hitbox_does_not_register() -> void:
	var hb := Hitbox.new()
	var hurt := Hurtbox.new()
	assert_true(not hb.register_hit(hurt))
	hb.free()
	hurt.free()


func test_invulnerable_hurtbox_cannot_be_hit() -> void:
	var health := Health.new()
	health.max_value = 100
	health.reset()
	var hurt := Hurtbox.new()
	hurt.health = health
	health.invulnerable = true
	assert_true(not hurt.can_be_hit())
	health.invulnerable = false
	assert_true(hurt.can_be_hit())
	health.take_damage(100)  # dead
	assert_true(not hurt.can_be_hit())
	var no_health := Hurtbox.new()  # no Health: the hit always counts
	assert_true(no_health.can_be_hit())
	no_health.free()
	hurt.free()
	health.free()
