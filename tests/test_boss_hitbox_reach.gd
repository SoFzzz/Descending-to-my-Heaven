extends TestCase
# Zonas de daño de los jefes: cubren lo que muestra el ataque y no dejan huecos pegado al cuerpo
# (comprobado con la geometria de las escenas; el mapa con animacion esta en scripts/tools/boss_hitbox_map.gd).

const KAELEN_RADIUS := 0.3


func _boss(path: String) -> Node3D:
	return (load(path) as PackedScene).instantiate() as Node3D


## True si la capsula de Kaelen en `feet` (suelo, marco del jefe) toca la forma del hitbox `name`.
func _reaches(boss: Node3D, hitbox: String, feet: Vector3) -> bool:
	var hb := boss.get_node(hitbox) as Node3D
	var cs := hb.get_node(^"CollisionShape3D") as CollisionShape3D
	var xf := hb.transform * cs.transform
	for i in 5:
		var l := xf.affine_inverse() * (feet + Vector3(0.0, lerpf(0.4, 1.3, i / 4.0), 0.0))
		var d := INF
		if cs.shape is SphereShape3D:
			d = maxf(l.length() - (cs.shape as SphereShape3D).radius, 0.0)
		elif cs.shape is BoxShape3D:
			var h := (cs.shape as BoxShape3D).size * 0.5
			d = Vector3(maxf(absf(l.x) - h.x, 0.0), maxf(absf(l.y) - h.y, 0.0), maxf(absf(l.z) - h.z, 0.0)).length()
		if d <= KAELEN_RADIUS:
			return true
	return false


func test_blackhorn_slam_reaches_its_whole_range() -> void:
	var boss := _boss("res://scenes/bosses/boss_blackhorn.tscn")
	var slam := load("res://resources/attacks/blackhorn_slam.tres") as BossAttack
	for angle in [0.0, 60.0, 120.0, 180.0, 270.0]:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(angle))
		assert_true(_reaches(boss, "SlamHitbox", dir * slam.max_range), "golpe al suelo alcanza a %s m (%s grados)" % [slam.max_range, angle])
	boss.free()


func test_blackhorn_pounce_starts_beside_the_body() -> void:
	var boss := _boss("res://scenes/bosses/boss_blackhorn.tscn")
	assert_true(_reaches(boss, "PounceHitbox", Vector3(0.0, 0.0, -0.8)), "pegada de frente")
	assert_true(_reaches(boss, "PounceHitbox", Vector3(1.5, 0.0, -0.5)), "pegada al costado")
	assert_true(_reaches(boss, "PounceHitbox", Vector3(1.4, 0.0, -3.5)), "carril de 3.2 m, no 2")
	assert_true(_reaches(boss, "ChargeHitbox", Vector3(1.0, 0.0, -0.3)), "la embestida arranca pegada al jefe")
	boss.free()


func test_bonedragon_has_no_safe_spot_under_its_attacks() -> void:
	var boss := _boss("res://scenes/bosses/boss_bonedragon.tscn")
	var stomp := load("res://resources/attacks/bonedragon_stomp.tres") as BossAttack
	var tail := load("res://resources/attacks/bonedragon_tail_sweep.tres") as BossAttack
	assert_true(_reaches(boss, "StompHitbox", Vector3(0.0, 0.0, -stomp.max_range)), "pisoton alcanza su max_range")
	assert_true(_reaches(boss, "StompHitbox", Vector3(2.7, 0.0, 0.0)), "y el costado")
	# La cola empieza en el cuerpo (z 0) y llega al borde del aviso; el barrido de 360 grados cubre el resto.
	assert_true(_reaches(boss, "TailSweepHitbox", Vector3(0.0, 0.0, 0.3)), "cola: pegada al cuerpo")
	assert_true(_reaches(boss, "TailSweepHitbox", Vector3(0.0, 0.0, tail.max_range)), "cola: hasta su max_range")
	var bite := boss.get_node(^"Model/metarig/Skeleton3D/SkullAttach/BiteHitbox/CollisionShape3D") as CollisionShape3D
	assert_true((bite.shape as SphereShape3D).radius >= 1.6, "la mordida cubre +-2 m, no solo la linea del hocico")
	boss.free()


func test_ghidorah_tail_has_no_hole_at_the_body() -> void:
	var boss := _boss("res://scenes/bosses/boss_ghidorah.tscn")
	var tail := load("res://resources/attacks/ghidorah_tail_sweep.tres") as BossAttack
	for z in [0.4, 1.5, 3.0, 5.0, tail.max_range]:
		assert_true(_reaches(boss, "TailSweepHitbox", Vector3(0.0, 0.0, z)), "cola alcanza a %s m" % z)
	boss.free()


func test_bosses_are_tougher_than_before() -> void:
	# Cifras de dificultad (ver docs/): mas vida, avisos y recuperaciones mas cortos, poco tiempo muerto.
	var expected := {
		"res://scenes/bosses/boss_bonedragon.tscn": 500,
		"res://scenes/bosses/boss_blackhorn.tscn": 625,
		"res://scenes/bosses/boss_ghidorah.tscn": 750,
	}
	for path in expected:
		var boss := (load(path) as PackedScene).instantiate() as Boss
		assert_eq(boss.max_health, expected[path], path)
		assert_true(boss.attack_cooldown <= 0.35, "poco tiempo muerto entre ataques")
		for a in boss.attacks:
			assert_true(a.recovery_time <= 1.1 and a.telegraph_time <= 1.5, "%s: aviso y recuperacion acotados" % a.id)
		boss.free()
