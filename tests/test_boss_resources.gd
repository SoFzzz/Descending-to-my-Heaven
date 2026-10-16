extends TestCase
# Tarea 13: ataques y escenas de Blackhorn y Ghidorah (§7.4, §8.2). El avance, las aperturas y las hurtboxes
# expuestas viven en Boss / BossAttack (ver test_boss_attack.gd).
# Solo estructura y datos: el comportamiento en ejecución se comprueba con el arnés de verificación.

const ATTACK_DIR := "res://resources/attacks/"
const BLACKHORN := "res://scenes/bosses/boss_blackhorn.tscn"
const GHIDORAH := "res://scenes/bosses/boss_ghidorah.tscn"


func _attack(file: String) -> BossAttack:
	return load(ATTACK_DIR + file) as BossAttack


func _scene(path: String) -> Boss:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Boss


func _shape(boss: Node, path: String) -> Shape3D:
	var node := boss.get_node_or_null(NodePath(path + "/CollisionShape3D")) as CollisionShape3D
	return node.shape if node else null


# --- Recursos de ataque ---------------------------------------------------------------------------

func test_blackhorn_attack_ranges() -> void:
	var slam := _attack("blackhorn_slam.tres")
	var pounce := _attack("blackhorn_pounce.tres")
	var charge := _attack("blackhorn_charge.tres")
	assert_true(slam != null and pounce != null and charge != null, "los 3 recursos cargan como BossAttack")
	if slam == null or pounce == null or charge == null:
		return
	assert_eq(slam.id, &"slam")
	assert_almost(slam.min_range, 0.0)
	assert_almost(slam.max_range, 4.0)
	assert_eq(pounce.id, &"pounce")
	assert_almost(pounce.min_range, 2.0)
	assert_almost(pounce.max_range, 7.0)
	assert_eq(charge.id, &"charge")
	assert_almost(charge.min_range, 8.0)
	assert_almost(charge.max_range, 16.0)
	assert_eq(slam.phase_min, 1)
	assert_eq(pounce.phase_min, 1)
	assert_eq(charge.phase_min, 2, "la embestida solo en fase 2")


func test_ghidorah_attack_ranges() -> void:
	var bite := _attack("ghidorah_bite.tres")
	var tail := _attack("ghidorah_tail_sweep.tres")
	var beam := _attack("ghidorah_beam.tres")
	assert_true(bite != null and tail != null and beam != null, "los 3 recursos cargan como BossAttack")
	if bite == null or tail == null or beam == null:
		return
	assert_eq(bite.id, &"bite")
	assert_almost(bite.min_range, 0.0)
	assert_almost(bite.max_range, 5.0)
	assert_eq(tail.id, &"tail_sweep")
	assert_almost(tail.max_range, 8.0)
	assert_true(tail.lateral, "el barrido cubre los costados")
	assert_true(tail.spin_degrees > 0.0, "el barrido gira el cuerpo")
	assert_eq(beam.id, &"beam")
	assert_almost(beam.min_range, 8.0)
	assert_almost(beam.max_range, 20.0)


func test_attack_timings_are_sane() -> void:
	for file in ["blackhorn_slam", "blackhorn_pounce", "blackhorn_charge", "ghidorah_bite", "ghidorah_tail_sweep", "ghidorah_beam"]:
		var a := _attack(file + ".tres")
		assert_true(a != null, file)
		if a == null:
			continue
		assert_true(a.telegraph_time >= 0.9, file + ": aviso legible (>= 0.9 s)")
		assert_true(a.active_time > 0.0 and a.recovery_time > 0.0, file + ": ventanas positivas")
		assert_true(a.damage > 0, file + ": hace daño")
		assert_true(a.base_weight > 0.0, file)
		assert_true(not a.hitbox_path.is_empty(), file + ": hitbox_path")
		assert_true(a.animation != &"", file + ": animación")


# --- Escenas ----------------------------------------------------------------------------------------

func _check_attack_wiring(boss: Boss, label: String) -> void:
	assert_eq(boss.attacks.size(), 3, label + ": 3 ataques")
	var anim := boss.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_true(anim != null, label + ": AnimationPlayer en el modelo")
	for attack in boss.attacks:
		var hb := boss.get_node_or_null(attack.hitbox_path) as Hitbox
		assert_true(hb != null, "%s: hitbox de %s" % [label, attack.id])
		if hb:
			assert_eq(hb.damage, attack.damage, "%s: daño de la hitbox = daño del ataque (%s)" % [label, attack.id])
			assert_eq(hb.collision_layer, 32, "%s: capa enemy_hitbox" % label)
			assert_eq(hb.collision_mask, 64, "%s: detecta player_hurtbox" % label)
			assert_true(not hb.monitoring, "%s: %s empieza inactiva" % [label, attack.id])
		assert_true(boss.get_node_or_null(NodePath("Telegraphs/" + String(attack.id))) is Node3D, "%s: aviso de %s" % [label, attack.id])
		if anim:
			assert_true(anim.has_animation(attack.animation), "%s: clip %s existe" % [label, attack.animation])
	if anim:
		for clip in [boss.idle_animation, boss.roar_animation, boss.death_animation]:
			assert_true(anim.has_animation(clip), "%s: clip %s" % [label, clip])


func test_blackhorn_scene() -> void:
	var boss := _scene(BLACKHORN)
	assert_true(boss != null, "boss_blackhorn.tscn carga como Boss")
	if boss == null:
		return
	assert_eq(boss.max_health, 625)
	assert_eq(boss.display_name, "Blackhorn")
	var nav := boss.get_node(^"NavigationAgent3D") as NavigationAgent3D
	assert_eq(nav.navigation_layers, 2, "navegación capa grande")
	_check_attack_wiring(boss, "blackhorn")
	assert_eq(boss.collision_layer, 8, "capa boss")
	var cap := (boss.get_node(^"CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	assert_almost(cap.radius, 0.7)
	assert_almost(cap.height, 3.2)
	var hurt := _shape(boss, "BodyHurtbox") as CapsuleShape3D
	assert_true(hurt != null, "hurtbox del cuerpo (cápsula)")
	if hurt:
		assert_almost(hurt.radius, 1.0)
		assert_almost(hurt.height, 3.2)
	assert_almost((_shape(boss, "SlamHitbox") as SphereShape3D).radius, 3.8, 0.001, "golpe al suelo: esfera r 3.8 (cubre hasta su max_range)")
	assert_almost((_shape(boss, "PounceHitbox") as BoxShape3D).size.x, 3.2)
	assert_almost((_shape(boss, "PounceHitbox") as BoxShape3D).size.y, 2.4)
	assert_almost((_shape(boss, "PounceHitbox") as BoxShape3D).size.z, 5.0, 0.001, "zarpazo 3.2 x 2.4 x 5 (desde pegado al cuerpo)")
	var charge := (_shape(boss, "ChargeHitbox") as BoxShape3D).size
	assert_almost(charge.x, 2.4)
	assert_almost(charge.y, 2.5)
	assert_almost(charge.z, 4.0, 0.001, "embestida 2.4 x 2.5 x 4")
	for claw in ["ClawLHitbox", "ClawRHitbox"]:
		var s := _shape(boss, claw) as SphereShape3D
		assert_true(s != null, claw)
		if s:
			assert_almost(s.radius, 0.6, 0.001, "garras r 0.6")
	assert_true(boss.get_node_or_null(^"LockOnPoint") is Marker3D)
	assert_eq(boss.walk_animation, &"run", "Blackhorn solo corre (nunca walk)")
	assert_true(boss.settle_on_death, "apoya el cuerpo en el suelo al morir")
	assert_eq(boss.collision_mask & 2, 2, "no atraviesa a Kaelen (capa player en la máscara)")
	assert_true(boss.get_node_or_null(^"AttackDriver") == null, "el AttackDriver ya no existe")
	boss.free()


func test_ghidorah_scene() -> void:
	var boss := _scene(GHIDORAH)
	assert_true(boss != null, "boss_ghidorah.tscn carga como Boss")
	if boss == null:
		return
	assert_eq(boss.max_health, 750)
	assert_eq(boss.display_name, "Mecha King Ghidorah")
	assert_eq((boss.get_node(^"NavigationAgent3D") as NavigationAgent3D).navigation_layers, 2)
	_check_attack_wiring(boss, "ghidorah")
	var cap := (boss.get_node(^"CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	assert_almost(cap.radius, 1.4, 0.001, "cápsula del torso (el cuerpo real mide ~1.2 m de radio)")
	assert_almost(cap.height, 5.0)
	var model := boss.get_node(^"Model") as Node3D
	assert_almost(model.scale.y, 1.95, 0.001, "escala del modelo x1.95 (8.1 m de alto, ~14 m con la cola)")
	assert_almost((_shape(boss, "BiteHitbox") as BoxShape3D).size.z, 7.0, 0.001, "mordida: zona fija de 7 m de fondo (de pegado al cuerpo a 5 m)")
	assert_almost((_shape(boss, "BeamHitbox") as BoxShape3D).size.z, 2.0, 0.001, "rayo: zona corta que viaja con el impacto")
	assert_almost((_shape(boss, "BeamHitbox") as BoxShape3D).size.x, 1.5)
	assert_almost((_shape(boss, "TailSweepHitbox") as BoxShape3D).size.z, 9.6, 0.001, "cola de 9.6 m: del cuerpo al borde del aviso, sin hueco")
	# Cabezas: solo hurtbox (esfera r 1.0), cerradas hasta que baje la cabeza.
	for head in ["HeadCHurtbox", "HeadLHurtbox", "HeadRHurtbox"]:
		var hurt := boss.get_node_or_null(NodePath(head)) as Hurtbox
		assert_true(hurt != null, head)
		if hurt == null:
			continue
		assert_almost((_shape(boss, head) as SphereShape3D).radius, 1.0, 0.001, head + " r 1.0")
		assert_true(not hurt.monitorable, head + " cerrada al inicio")
		assert_true(boss.get_node_or_null(NodePath(head + "/CollisionShape3D")).get_parent() == hurt)
	assert_true(boss.get_node_or_null(^"TorsoHurtbox") is Hurtbox, "torso siempre alcanzable")
	assert_true((boss.get_node(^"TorsoHurtbox") as Hurtbox).monitorable)
	for leg in ["LegLHurtbox", "LegRHurtbox"]:
		assert_true(boss.get_node_or_null(NodePath(leg)) is Hurtbox, leg)
		assert_true((boss.get_node(NodePath(leg)) as Hurtbox).monitorable)
	assert_true(boss.get_node_or_null(^"AttackDriver") == null, "el AttackDriver ya no existe")
	assert_eq(boss.gated_hurtboxes.size(), 3, "las 3 cabezas solo se golpean durante la mordida")
	for path in boss.gated_hurtboxes:
		assert_true(boss.get_node_or_null(path) is Hurtbox, str(path))
	var lock := boss.get_node(^"LockOnPoint") as Marker3D
	assert_true(lock.position.y > 2.0 and lock.position.y < 5.0, "LockOnPoint en el torso, a media altura")
	boss.free()
