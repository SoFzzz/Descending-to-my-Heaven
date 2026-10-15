extends TestCase
# HUD tests: bar value mapping, heart beat and boss bar skins per boss.


func test_bar_value_maps_ratio_into_the_bar_part() -> void:
	assert_almost(Hud.bar_value(0.0, 25.0, 96.0, 112.0), 25.0 / 112.0)
	assert_almost(Hud.bar_value(1.0, 25.0, 96.0, 112.0), 96.0 / 112.0)
	assert_almost(Hud.bar_value(2.0, 25.0, 96.0, 112.0), 96.0 / 112.0, 0.001, "ratio is clamped")


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
	assert_almost(hud.get_node(^"BossBar/Bar").value, Hud.bar_value(0.5, style[&"fill"].x, style[&"fill"].y, 48.0))
	assert_true(hud.get_node(^"BossBar").visible)
	hud.hide_boss()
	assert_true(not hud.get_node(^"BossBar").visible)
	hud.free()
	boss_health.free()


func test_every_boss_has_a_bar_skin() -> void:
	for boss_name in ["Bone Dragon", "Blackhorn", "Mecha King Ghidorah"]:
		assert_true(Hud.BOSS_BAR_STYLES.has(boss_name), boss_name)
