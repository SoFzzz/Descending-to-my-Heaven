extends TestCase
# Pruebas de Hitbox/Hurtbox (un golpe por objetivo y activación, multiplicador de daño).


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
