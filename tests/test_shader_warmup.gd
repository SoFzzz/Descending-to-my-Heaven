extends TestCase
# Precalentamiento de efectos de los jefes (ShaderWarmup): sin ventana no hace nada.


func test_warmup_is_skipped_without_window() -> void:
	var boss := (load("res://scenes/bosses/boss_ghidorah.tscn") as PackedScene).instantiate() as Boss
	assert_true(ShaderWarmup.start(boss) == null, "sin ventana (--headless) no se crea el SubViewport")
	boss.free()


func test_warmup_covers_every_attack_effect() -> void:
	# Cada ataque de Ghidorah con efecto visual (el rayo) o aviso tiene nodo que precalentar.
	var boss := (load("res://scenes/bosses/boss_ghidorah.tscn") as PackedScene).instantiate() as Boss
	var beam: BossAttack
	for a in boss.attacks:
		assert_true(boss.get_node_or_null(NodePath("Telegraphs/%s" % a.id)) != null, "aviso de %s" % a.id)
		if a.id == &"beam":
			beam = a
	assert_true(beam != null and boss.get_node_or_null(beam.visual_path) is BeamVfx, "el rayo tiene su efecto")
	boss.free()
