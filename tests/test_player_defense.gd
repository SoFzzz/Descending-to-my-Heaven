extends TestCase
# Pruebas de la defensa de Kaelen: i-frames tras recibir un golpe, armadura durante el ataque y
# ventanas de daño que empiezan pronto.


func _make_player() -> Array:
	var p := Player.new()
	var s := Stamina.new()
	var h := Health.new()
	h.reset(100)
	var hb := Hurtbox.new()
	hb.health = h
	p.stamina = s
	p.health = h
	p.hurtbox = hb
	p._connect_components()
	return [p, s, h, hb]


func _free_all(nodes: Array) -> void:
	for n in nodes:
		(n as Node).free()


# Tras un golpe en MOVE: HURT y HURT_IFRAMES s de invulnerabilidad, que siguen al terminar HURT.
func test_hurt_grants_iframes() -> void:
	var n := _make_player()
	var p: Player = n[0]
	var h: Health = n[2]
	h.take_damage(20)
	assert_eq(p.state, Player.State.HURT)
	assert_true(p.is_invulnerable(), "invulnerable al entrar en HURT")
	assert_true(h.invulnerable, "Health también queda invulnerable")
	h.take_damage(20)
	assert_eq(h.current, 80, "un segundo golpe durante los i-frames no resta")
	p._advance_hurt(Player.HURT_DURATION + 0.01)
	p._tick_hurt_iframes(Player.HURT_DURATION + 0.01)
	assert_eq(p.state, Player.State.MOVE, "al terminar HURT ya puede actuar")
	assert_true(p.is_invulnerable(), "sigue invulnerable después de HURT")
	assert_true(p.try_roll(), "puede rodar aunque siga invulnerable")
	p._tick_hurt_iframes(Player.HURT_IFRAMES - Player.HURT_DURATION - 0.05)
	assert_true(p.is_invulnerable(), "todavía dentro de HURT_IFRAMES")
	p._advance_roll(Player.ROLL_DURATION)
	p._tick_hurt_iframes(0.1)
	assert_true(not p.is_invulnerable(), "pasado HURT_IFRAMES vuelve a ser vulnerable")
	assert_true(not h.invulnerable, "Health vuelve a ser vulnerable")
	_free_all(n)


# Las cuatro fuentes (rodada, i-frames de golpe, victoria, god) se combinan sin apagarse entre sí.
func test_hurt_iframes_combine_with_other_sources() -> void:
	var n := _make_player()
	var p: Player = n[0]
	var h: Health = n[2]
	h.take_damage(20)
	p._advance_hurt(Player.HURT_DURATION + 0.01)
	p._tick_hurt_iframes(Player.HURT_DURATION + 0.01)
	assert_true(p.try_roll(), "rueda durante los i-frames de golpe")
	p._advance_roll(0.1)
	p._advance_roll(Player.ROLL_DURATION)   # la rodada termina y apaga sus i-frames
	assert_eq(p.state, Player.State.MOVE)
	assert_true(p.is_invulnerable(), "terminar la rodada no apaga los i-frames de golpe")
	p._on_boss_defeated(null)
	p._tick_hurt_iframes(Player.HURT_IFRAMES)   # los i-frames de golpe terminan
	assert_true(p.is_invulnerable(), "terminar los i-frames de golpe no apaga la victoria")
	assert_true(h.invulnerable, "Health sigue invulnerable por la victoria")
	_free_all(n)


func test_hurt_iframes_do_not_cancel_god() -> void:
	var n := _make_player()
	var p: Player = n[0]
	var h: Health = n[2]
	h.take_damage(20)
	p._god = true
	p._tick_hurt_iframes(Player.HURT_IFRAMES + 0.1)
	assert_true(p.is_invulnerable(), "god sigue activo al terminar los i-frames de golpe")
	assert_true(h.invulnerable)
	_free_all(n)


# Armadura: un golpe durante ATTACK no lo interrumpe y resta ATTACK_DAMAGE_TAKEN_MULT del daño.
func test_attack_hyper_armor() -> void:
	var n := _make_player()
	var p: Player = n[0]
	var h: Health = n[2]
	var hb: Hurtbox = n[3]
	assert_true(p.try_attack())
	assert_almost(hb.damage_multiplier, Player.ATTACK_DAMAGE_TAKEN_MULT, 0.001, "multiplicador en ATTACK")
	hb.receive_hit(20, null)
	assert_eq(h.current, 90, "resta la mitad")
	assert_eq(p.state, Player.State.ATTACK, "el golpe no interrumpe el ataque")
	assert_true(p.is_invulnerable(), "el golpe en ATTACK también da i-frames")
	p._advance_attack(Player.HIT_END[0] + Player.COMBO_WINDOW + 0.01)
	assert_eq(p.state, Player.State.MOVE, "el ataque termina normalmente")
	assert_almost(hb.damage_multiplier, 1.0, 0.001, "al salir de ATTACK vuelve a 1.0")
	_free_all(n)


func test_attack_hyper_armor_still_dies() -> void:
	var n := _make_player()
	var p: Player = n[0]
	var h: Health = n[2]
	var hb: Hurtbox = n[3]
	h.current = 8
	p._last_hp = 8
	assert_true(p.try_attack())
	hb.receive_hit(20, null)
	assert_eq(h.current, 0)
	assert_eq(p.state, Player.State.DEAD, "si el golpe la mata, muere igual")
	assert_almost(hb.damage_multiplier, 1.0, 0.001, "al morir vuelve a 1.0")
	assert_true(not p.is_invulnerable(), "el golpe mortal no da i-frames")
	_free_all(n)


# La ventana de daño de cada golpe empieza pronto en tiempo de juego y se deriva del tiempo de clip.
func test_attack_windows_start_early() -> void:
	var limits: Array[float] = [0.35, 0.40, 0.40]
	for i in 3:
		assert_true(Player.HIT_START[i] <= limits[i], "golpe %d empieza en %.3f s" % [i + 1, Player.HIT_START[i]])
		var expected: float = (Player.CLIP_HIT_START[i] - Player.ATTACK_CLIP_START[i]) / Player.ATTACK_ANIM_SPEED[i]
		assert_almost(Player.HIT_START[i], expected, 0.0001, "HIT_START %d derivado del clip" % i)
		expected = (Player.CLIP_HIT_END[i] - Player.ATTACK_CLIP_START[i]) / Player.ATTACK_ANIM_SPEED[i]
		assert_almost(Player.HIT_END[i], expected, 0.0001, "HIT_END %d derivado del clip" % i)
		assert_true(Player.HIT_END[i] > Player.HIT_START[i], "ventana %d no vacía" % i)
