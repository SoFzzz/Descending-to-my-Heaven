extends TestCase
# HUD tests: bar value mapping, heart beat and boss bar skins per boss.


func test_fill_width_maps_ratio_between_the_insets() -> void:
	assert_almost(Hud.fill_width(0.0, 12.0, 8.0, 304.0), 12.0)
	assert_almost(Hud.fill_width(1.0, 12.0, 8.0, 304.0), 296.0)
	assert_almost(Hud.fill_width(2.0, 12.0, 8.0, 304.0), 296.0, 0.001, "ratio is clamped")


func test_heart_beats_faster_with_low_health() -> void:
	assert_true(Hud.beat_period(0.1) < Hud.beat_period(1.0))
	assert_almost(Hud.beat_period(1.0), Hud.BEAT_SLOW)
	assert_almost(Hud.beat_period(-1.0), Hud.BEAT_FAST)


func test_beat_frame_holds_at_the_start_of_the_period() -> void:
	assert_eq(Hud.beat_frame(0.0, 1.0), 1)
	assert_eq(Hud.beat_frame(0.5, 1.0), 0)
	assert_eq(Hud.beat_frame(1.05, 1.0), 1)


func test_hud_bars_follow_health_stamina_and_boss() -> void:
	var hud: Hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	var boss_health := Health.new()
	boss_health.max_value = 200
	boss_health.current = 200
	Engine.get_main_loop().root.add_child(hud)
	hud._on_health_changed(25, 100)
	hud._on_stamina_changed(50.0, 100.0)
	assert_almost(hud.get_node(^"Bars/Frame/HealthBar").value, 0.25)
	assert_almost(hud.get_node(^"Bars/Frame/StaminaBar").value, 0.5)
	hud.show_boss("Blackhorn", boss_health)
	boss_health.current = 100
	boss_health.changed.emit(100, 200)
	var style: Dictionary = Hud.BOSS_BAR_STYLES["Blackhorn"]
	assert_almost(hud.get_node(^"BossBar/Bar/Clip").size.x, Hud.fill_width(0.5, style[&"fill"].x, style[&"fill"].y, Hud.BOSS_BAR_WIDTH / style[&"scale"]))
	assert_almost(hud.get_node(^"BossBar/Bar").size.x * hud.get_node(^"BossBar/Bar").scale.x, Hud.BOSS_BAR_WIDTH)
	assert_true(hud.get_node(^"BossBar").visible)
	hud.hide_boss()
	assert_true(not hud.get_node(^"BossBar").visible)
	hud.free()
	boss_health.free()


func test_every_boss_has_a_bar_skin() -> void:
	for boss_name in ["Bone Dragon", "Blackhorn", "Mecha King Ghidorah"]:
		assert_true(Hud.BOSS_BAR_STYLES.has(boss_name), boss_name)


func test_all_boss_bars_share_the_original_length_and_stay_thin() -> void:
	for boss_name in Hud.BOSS_BAR_STYLES:
		var style: Dictionary = Hud.BOSS_BAR_STYLES[boss_name]
		var height: float = (style[&"full"] as Rect2).size.y * style[&"scale"]
		assert_true(height <= 16.0, boss_name + " bar is thin")
	var blackhorn: Dictionary = Hud.BOSS_BAR_STYLES["Blackhorn"]
	assert_almost((blackhorn[&"full"] as Rect2).size.y * blackhorn[&"scale"], 8.0)
	var dragon: Dictionary = Hud.BOSS_BAR_STYLES["Bone Dragon"]
	assert_almost((dragon[&"full"] as Rect2).size.y * dragon[&"scale"], 16.0)
