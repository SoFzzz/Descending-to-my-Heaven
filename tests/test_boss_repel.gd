extends TestCase
# Reacción de repulsión de los jefes (BossRepel + Boss + Player.apply_shove).


func _repel() -> BossRepel:
	var r := BossRepel.new()
	r.threshold_fraction = 0.10
	r.window = 4.0
	r.cooldown = 7.0
	r.burst_hits = 3
	r.burst_window = 3.0
	r.glue_time = 7.0
	return r


func test_fires_when_threshold_reached() -> void:
	var r := _repel()   # 10 % de 600 = 60
	assert_true(not r.register_damage(20, 600), "20 no llega")
	r.tick(1.5)
	assert_true(not r.register_damage(20, 600), "40 no llega")
	r.tick(1.4)   # el primer golpe sale de la ventana de 3 s de golpes seguidos
	assert_true(r.register_damage(36, 600), "76 dentro de la ventana de daño dispara")


func test_fires_on_three_quick_hits() -> void:
	var r := _repel()
	assert_true(not r.register_damage(10, 2000))
	r.tick(1.0)
	assert_true(not r.register_damage(10, 2000), "dos golpes no bastan")
	r.tick(1.0)
	assert_true(r.register_damage(10, 2000), "tres golpes en 3 s disparan aunque hagan poco daño")


func test_slow_hits_do_not_count_as_burst() -> void:
	var r := _repel()
	for i in 4:
		assert_true(not r.register_damage(5, 2000), "golpes espaciados 1.6 s no disparan")
		r.tick(1.6)


func test_fires_when_glued_to_the_boss() -> void:
	var r := _repel()
	var fired := false
	for i in 13:
		fired = r.register_proximity(0.5, true)
	assert_true(not fired, "6.5 s pegada aún no")
	assert_true(r.register_proximity(0.5, true), "7 s pegada dispara")
	r.trigger()
	assert_almost(r.glue_seconds(), 0.0)


func test_glue_drains_when_away() -> void:
	var r := _repel()
	for i in 50:
		r.register_proximity(0.1, true)   # 5 s
	for i in 20:
		r.register_proximity(0.1, false)  # 2 s lejos = -4 s
	assert_almost(r.glue_seconds(), 1.0, 0.001, "alejarse la vacía al doble de velocidad")
	for i in 80:
		r.register_proximity(0.1, true)
	assert_true(not r.register_proximity(0.1, true, true), "bloqueado no dispara")
	assert_true(r.is_due(2000), "pero queda pendiente")


func test_window_forgets_old_hits() -> void:
	var r := _repel()
	r.register_damage(30, 400)
	r.tick(4.5)
	assert_eq(r.recent_damage(), 0, "el golpe salió de la ventana")
	assert_true(not r.register_damage(36, 400), "36 solos no llegan al 10 % de 400")


func test_no_fire_during_cooldown() -> void:
	var r := _repel()
	assert_true(r.register_damage(80, 400))
	r.trigger()
	assert_true(r.on_cooldown())
	assert_true(not r.register_damage(200, 400), "en enfriamiento no dispara")
	assert_true(not r.register_proximity(20.0, true), "ni por estar pegada")
	r.tick(7.1)
	assert_true(not r.on_cooldown())
	assert_eq(r.recent_damage(), 0, "lo recibido en enfriamiento no cuenta")
	assert_true(r.register_damage(40, 400), "tras el enfriamiento vuelve a disparar (10 % de 400)")


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
	boss.health.reset(500)
	return boss


func test_boss_queues_repel_on_burst() -> void:
	var boss := _boss()
	boss._register_repel_damage(20)
	assert_true(not boss._pending_repel)
	boss._register_repel_damage(36)
	assert_true(boss._pending_repel, "56 ≥ 50 (10 % de 500): reacción pendiente")
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
	assert_true(boss.can_repel(), "puede cortar la recuperación: es lo que frena el encadenado")
	boss.state = Boss.State.TELEGRAPH
	assert_true(boss.can_repel(), "y el aviso de un ataque")
	boss.free()


func test_boss_repel_is_invulnerable() -> void:
	var boss := _boss()
	boss.state = Boss.State.CHASE
	boss.start_repel()
	assert_true(boss.repelling and boss.state == Boss.State.ROAR, "ruge")
	assert_eq(boss.phase, 1, "no cambia de fase")
	assert_eq(boss.repel_count, 1)
	boss._on_hurt(50, null)
	assert_eq(boss.health.current, 500, "invulnerable mientras ruge")
	boss.free()


func test_shove_pushes_player_away() -> void:
	var p := Player.new()
	assert_true(p.apply_shove(Vector3(10.0, 0.0, 0.0), 0.4))
	assert_eq(p.state, Player.State.HURT, "sin control durante el empuje")
	assert_true(p.velocity.x > 9.0, "sale despedida hacia fuera")
	assert_true(p.apply_shove(Vector3(10.0, 0.0, 0.0), 0.4, 3.0))
	assert_almost(p.velocity.y, 3.0, 0.001, "con un pequeño salto hacia arriba")
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


func test_shove_travels_about_four_and_a_half_metres() -> void:
	var boss := _boss()
	var travelled := boss.repel_force * boss.repel_push_time * 0.5
	assert_true(travelled >= 4.0 and travelled <= 5.0, "empuje de ~4.5 m, no 2 m: %s" % travelled)
	assert_true(boss.repel_radius >= 6.5, "alcanza a Kaelen aunque esté a golpe de espada")
	boss.free()


func test_repel_shockwave_comes_after_a_warning() -> void:
	var boss := _boss()
	boss.state = Boss.State.CHASE
	boss.start_repel()
	assert_true(boss.repel_push_delay >= 0.25 and boss.repel_push_delay <= 0.5, "aviso corto antes de la onda")
	assert_almost(boss._repel_push_left, boss.repel_push_delay, 0.001, "la onda espera al aviso")
	boss.free()


func test_roll_must_be_timed_for_the_shockwave() -> void:
	# La onda sale repel_push_delay s después del rugido: la rodada solo la esquiva si sus i-frames
	# (0.05-0.40 s) cubren ese instante.
	var p := Player.new()
	var s := Stamina.new()
	p.stamina = s
	assert_true(p.try_roll())
	p._advance_roll(0.3)
	assert_true(not p.apply_shove(Vector3(10.0, 0.0, 0.0), 0.5), "a 0.3 s de rodada: esquiva")
	p._advance_roll(0.2)   # 0.5 s: fuera de los i-frames
	assert_true(p.apply_shove(Vector3(10.0, 0.0, 0.0), 0.5), "rodada tardía: la onda la empuja")
	p.free()
	s.free()
