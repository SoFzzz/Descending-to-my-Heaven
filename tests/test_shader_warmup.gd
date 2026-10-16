extends TestCase
# Boss effects warm-up (ShaderWarmup): without a window it does nothing.


func test_warmup_is_skipped_without_window() -> void:
	var boss := (load("res://scenes/bosses/boss_ghidorah.tscn") as PackedScene).instantiate() as Boss
	assert_true(ShaderWarmup.start(boss) == null, "without a window (--headless) the SubViewport is not created")
	boss.free()


func test_warmup_covers_every_attack_effect() -> void:
	# Each Ghidorah attack with a visual effect (the beam) or telegraph has a node to warm up.
	var boss := (load("res://scenes/bosses/boss_ghidorah.tscn") as PackedScene).instantiate() as Boss
	var beam: BossAttack
	for a in boss.attacks:
		assert_true(boss.get_node_or_null(NodePath("Telegraphs/%s" % a.id)) != null, "telegraph of %s" % a.id)
		if a.id == &"beam":
			beam = a
	assert_true(beam != null and boss.get_node_or_null(beam.visual_path) is BeamVfx, "the beam has its effect")
	boss.free()
