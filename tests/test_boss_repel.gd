extends TestCase
# Reacción de repulsión de los jefes (BossRepel + Boss + Player.apply_shove).


func _repel() -> BossRepel:
	var r := BossRepel.new()
	r.threshold_fraction = 0.15
	r.window = 4.0
	r.cooldown = 9.0
	return r


func test_fires_when_threshold_reached() -> void:
	var r := _repel()   # 15 % de 400 = 60
	assert_true(not r.register_damage(20, 400), "20 no llega")
	r.tick(1.0)
	assert_true(not r.register_damage(20, 400), "40 no llega")
	r.tick(1.0)
	assert_true(r.register_damage(36, 400), "76 dentro de la ventana dispara")


func test_window_forgets_old_hits() -> void:
	var r := _repel()
	r.register_damage(40, 400)
	r.tick(4.5)
	assert_eq(r.recent_damage(), 0, "el golpe salió de la ventana")
	assert_true(not r.register_damage(36, 400), "36 solos no llegan")


func test_no_fire_during_cooldown() -> void:
	var r := _repel()
	assert_true(r.register_damage(80, 400))
	r.trigger()
	assert_true(r.on_cooldown())
	assert_true(not r.register_damage(200, 400), "en enfriamiento no dispara")
	r.tick(9.1)
	assert_true(not r.on_cooldown())
	assert_eq(r.recent_damage(), 0, "lo recibido en enfriamiento no cuenta")
	assert_true(r.register_damage(60, 400), "tras el enfriamiento vuelve a disparar")


func test_blocked_counts_but_does_not_fire() -> void:
	var r := _repel()
	assert_true(not r.register_damage(80, 400, true), "bloqueado no dispara")
	assert_true(r.is_due(400), "pero queda pendiente")


func test_push_velocity_outward_and_radius() -> void:
	var v := BossRepel.push_velocity(Vector3.ZERO, Vector3(3.0, 1.0, 0.0), 6.0, 10.0)
	assert_almost(v.x, 10.0, 0.001, "hacia fuera")
	assert_almost(v.y, 0.0, 0.001, "horizontal")
	assert_eq(BossRepel.push_velocity(Vector3.ZERO, Vector3(7.0, 0.0, 0.0), 6.0, 10.0), Vector3.ZERO, "fuera del radio")
	var f := BossRepel.push_velocity(Vector3.ZERO, Vector3.ZERO, 6.0, 10.0, Vector3(0.0, 0.0, -1.0))
	assert_almost(f.length(), 10.0, 0.001, "encima: usa la dirección de reserva")


func _boss() -> Boss:
	var boss := (load("res://scenes/bosses/boss_bonedragon.tscn") as PackedScene).instantiate() as Boss
	boss.health = boss.get_node(^"Health") as Health
	boss.health.reset(400)
	return boss


func test_boss_queues_repel_on_burst() -> void:
	var boss := _boss()
	boss._register_repel_damage(30)
	assert_true(not boss._pending_repel)
	boss._register_repel_damage(36)
	assert_true(boss._pending_repel, "66 ≥ 60: reacción pendiente")
	boss.free()


func test_boss_no_repel_in_phase_roar_or_dead() -> void:
	var boss := _boss()
	boss.state = Boss.State.ROAR
	assert_true(not boss.can_repel(), "durante el rugido de fase")
	boss._register_repel_damage(100)
	assert_true(not boss._pending_repel, "no se encola durante el rugido")
	boss.state = Boss.State.CHASE
	boss._pending_roar = true
	assert_true(not boss.can_repel(), "con la transición de fase pendiente")
	boss._pending_roar = false
	boss.state = Boss.State.DEAD
	assert_true(not boss.can_repel(), "muerto")
	boss.state = Boss.State.RECOVER
	assert_true(not boss.can_repel(), "espera al final de la ventana de castigo")
	boss.free()


func test_boss_repel_is_invulnerable() -> void:
	var boss := _boss()
	boss.state = Boss.State.CHASE
	boss.start_repel()
	assert_true(boss.repelling and boss.state == Boss.State.ROAR, "ruge")
	assert_eq(boss.phase, 1, "no cambia de fase")
	assert_eq(boss.repel_count, 1)
	boss._on_hurt(50, null)
	assert_eq(boss.health.current, 400, "invulnerable mientras ruge")
	boss.free()


func test_shove_pushes_player_away() -> void:
	var p := Player.new()
	assert_true(p.apply_shove(Vector3(10.0, 0.0, 0.0), 0.4))
	assert_eq(p.state, Player.State.HURT, "sin control durante el empuje")
	assert_true(p.velocity.x > 9.0, "sale despedida hacia fuera")
	var half := Player.shove_velocity_at(Vector3(10.0, 0.0, 0.0), 0.4, 0.2)
	assert_almost(half.x, 5.0, 0.001, "decae linealmente")
	p._advance_hurt(0.39)
	assert_eq(p.state, Player.State.HURT, "dura lo que el empuje")
	p.free()


func test_roll_dodges_shove() -> void:
	var p := Player.new()
	var s := Stamina.new()
	p.stamina = s
	assert_true(p.try_roll())
	p._advance_roll(0.1)
	assert_true(not p.apply_shove(Vector3(10.0, 0.0, 0.0), 0.4), "los i-frames de la rodada lo esquivan")
	assert_eq(p.state, Player.State.ROLL)
	p.free()
	s.free()
