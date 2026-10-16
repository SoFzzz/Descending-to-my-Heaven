extends TestCase
# HUD tests: bar value mapping, heart beat and boss bar skins per boss.
# The bars-in-a-tree checks live in tests/flow/ui_flow.tscn (they need a real SceneTree).


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


func test_every_boss_has_a_bar_skin() -> void:
	for boss_name in ["Bone Dragon", "Blackhorn", "Mecha King Ghidorah"]:
		assert_true(Hud.BOSS_BAR_STYLES.has(boss_name), boss_name)


func test_all_boss_bars_use_the_thin_dragon_style() -> void:
	for boss_name in Hud.BOSS_BAR_STYLES:
		var style: Dictionary = Hud.BOSS_BAR_STYLES[boss_name]
		var height: float = (style[&"full"] as Rect2).size.y * style[&"scale"]
		assert_true(height <= 16.0, boss_name + " bar is thin")
	var dragon: Dictionary = Hud.BOSS_BAR_STYLES["Bone Dragon"]
	assert_almost((dragon[&"full"] as Rect2).size.y * dragon[&"scale"], 16.0)
	for boss_name in Hud.BOSS_BAR_STYLES:
		assert_eq(Hud.BOSS_BAR_STYLES[boss_name], dragon, boss_name + " uses the dragon bar")
