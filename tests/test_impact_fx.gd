extends TestCase
# Impact effects (ImpactFx) with Storm & Wind 3D Free and Magic Circles 3D Free: they exist, they
# instantiate without errors and the emitter pools are shared out without creating new nodes.


func test_packs_are_installed() -> void:
	assert_true(MagicArea.presets().has("fire_circle"), "Magic Circles: fire circle")
	assert_true(MagicArea.presets().has("blood_circle"), "Magic Circles: blood circle")
	assert_true(StormFX.presets().has("air_gust"), "Storm & Wind: air gust")
	assert_true(FileAccess.file_exists("res://addons/storm_wind/LICENSE.txt"), "Storm & Wind license")
	assert_true(FileAccess.file_exists("res://addons/magic_circles/LICENSE.txt"), "Magic Circles license")


func test_pools_are_built_with_the_pack_shader() -> void:
	var fx := ImpactFx.new()
	fx._build()
	assert_eq(fx._sparks.size(), ImpactFx.SPARK_POOL, "spark pool")
	assert_eq(fx._dust.size(), ImpactFx.DUST_POOL, "dust pool")
	for p in fx._sparks + fx._dust:
		var mat := p.material_override as ShaderMaterial
		assert_true(mat != null and mat.shader.resource_path == ImpactFx.SPARK_SHADER, "uses the pack's spark.gdshader")
		assert_true(p.one_shot and not p.emitting, "one shot and off")
	fx.free()


func test_emitters_are_reused_not_created() -> void:
	var fx := ImpactFx.new()
	fx._build()
	var children := fx.get_child_count()
	fx._next_spark = 0
	for i in ImpactFx.SPARK_POOL + 3:
		fx._emit_sparks(Vector3.ZERO, 1.0, true)   # outside the tree: it does not emit, but does not fail
	assert_eq(fx.get_child_count(), children, "creates no nodes")
	fx.free()


func test_warmup_samples_cover_every_effect() -> void:
	var samples := ImpactFx.warmup_samples()
	var kinds := []
	for s in samples:
		kinds.append(s.get_class() if not (s is MagicArea or s is StormFX) else s.kind)
	assert_true(kinds.count("CPUParticles3D") == 2, "sparks and dust")
	assert_true(kinds.has("circle") and kinds.has("gust"), "circle and gust")
	for s in samples:
		s.free()


func test_ground_attacks_are_listed() -> void:
	assert_true(&"slam" in ImpactFx.GROUND_ATTACKS and &"stomp" in ImpactFx.GROUND_ATTACKS, "ground hits")
	assert_true(not (&"beam" in ImpactFx.GROUND_ATTACKS), "the beam raises no dust")


func test_ending_room_uses_storm_gust() -> void:
	var room := (load("res://scenes/props/ending_room.tscn") as PackedScene).instantiate()
	room._ready()
	var gust := room.get_node_or_null(^"Outside/WindStreaks") as StormFX
	assert_true(gust != null and gust.kind == "gust", "Storm & Wind gust in the exterior")
	if gust:
		assert_true(not gust.visible, "off until the fall starts")
	room.start_fall()
	if gust:
		assert_true(gust.visible, "visible when falling")
	room.free()


func test_every_enemy_surface_has_a_strong_hit_effect() -> void:
	# Floors 2 and 3 used to fall back to faint sparks ("flesh" had no effect of its own).
	var strong := [&"bone", &"metal"] + ImpactFx.ORGANIC.keys()
	for path in ["res://scenes/enemies/minion_skeleton.tscn", "res://scenes/enemies/minion_knight_elite.tscn",
			"res://scenes/enemies/minion_plague.tscn", "res://scenes/enemies/minion_plague_elite.tscn",
			"res://scenes/enemies/minion_wrapper.tscn", "res://scenes/enemies/minion_reaper_elite.tscn",
			"res://scenes/bosses/boss_bonedragon.tscn", "res://scenes/bosses/boss_blackhorn.tscn",
			"res://scenes/bosses/boss_ghidorah.tscn"]:
		var node := (load(path) as PackedScene).instantiate()
		for hb in node.find_children("*", "Hurtbox", true, false):
			assert_true((hb as Hurtbox).surface in strong, "%s: %s has a strong hit effect" % [path, (hb as Hurtbox).surface])
		node.free()
	assert_true(ImpactFx.ORGANIC.has(&"ichor") and ImpactFx.ORGANIC.has(&"straw"), "creature colours")
