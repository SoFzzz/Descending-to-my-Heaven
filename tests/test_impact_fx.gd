extends TestCase
# Efectos de impacto (ImpactFx) con Storm & Wind 3D Free y Magic Circles 3D Free: existen, se
# instancian sin errores y las reservas de emisores se reparten sin crear nodos nuevos.


func test_packs_are_installed() -> void:
	assert_true(MagicArea.presets().has("fire_circle"), "Magic Circles: círculo de fuego")
	assert_true(MagicArea.presets().has("blood_circle"), "Magic Circles: círculo de sangre")
	assert_true(StormFX.presets().has("air_gust"), "Storm & Wind: racha de aire")
	assert_true(FileAccess.file_exists("res://addons/storm_wind/LICENSE.txt"), "licencia Storm & Wind")
	assert_true(FileAccess.file_exists("res://addons/magic_circles/LICENSE.txt"), "licencia Magic Circles")


func test_pools_are_built_with_the_pack_shader() -> void:
	var fx := ImpactFx.new()
	fx._build()
	assert_eq(fx._sparks.size(), ImpactFx.SPARK_POOL, "reserva de chispas")
	assert_eq(fx._dust.size(), ImpactFx.DUST_POOL, "reserva de polvo")
	for p in fx._sparks + fx._dust:
		var mat := p.material_override as ShaderMaterial
		assert_true(mat != null and mat.shader.resource_path == ImpactFx.SPARK_SHADER, "usa spark.gdshader del pack")
		assert_true(p.one_shot and not p.emitting, "un disparo y apagado")
	fx.free()


func test_emitters_are_reused_not_created() -> void:
	var fx := ImpactFx.new()
	fx._build()
	var children := fx.get_child_count()
	fx._next_spark = 0
	for i in ImpactFx.SPARK_POOL + 3:
		fx._emit_sparks(Vector3.ZERO, 1.0, true)   # fuera del árbol: no emite, pero no falla
	assert_eq(fx.get_child_count(), children, "no crea nodos")
	fx.free()


func test_warmup_samples_cover_every_effect() -> void:
	var samples := ImpactFx.warmup_samples()
	var kinds := []
	for s in samples:
		kinds.append(s.get_class() if not (s is MagicArea or s is StormFX) else s.kind)
	assert_true(kinds.count("CPUParticles3D") == 2, "chispas y polvo")
	assert_true(kinds.has("circle") and kinds.has("gust"), "sello y racha")
	for s in samples:
		s.free()


func test_ground_attacks_are_listed() -> void:
	assert_true(&"slam" in ImpactFx.GROUND_ATTACKS and &"stomp" in ImpactFx.GROUND_ATTACKS, "golpes al suelo")
	assert_true(not (&"beam" in ImpactFx.GROUND_ATTACKS), "el rayo no levanta polvo")


func test_ending_room_uses_storm_gust() -> void:
	var room := (load("res://scenes/props/ending_room.tscn") as PackedScene).instantiate()
	room._ready()
	var gust := room.get_node_or_null(^"Outside/WindStreaks") as StormFX
	assert_true(gust != null and gust.kind == "gust", "racha de Storm & Wind en el exterior")
	if gust:
		assert_true(not gust.visible, "apagada hasta que empieza la caída")
	room.start_fall()
	if gust:
		assert_true(gust.visible, "visible al caer")
	room.free()
