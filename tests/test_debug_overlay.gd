extends TestCase
# F3 overlay: lines for the boss goal and the detected behaviour of Kaelen.

const OverlayScript := preload("res://scripts/ai/debug_overlay.gd")


func test_format_info_without_boss_goal_has_no_extra_lines() -> void:
	var text: String = OverlayScript.format_info({"phase": 0, "cycle": 1})
	assert_true(not text.contains("Boss goal"))


func test_format_info_shows_goal_and_kaelen_behavior() -> void:
	var text: String = OverlayScript.format_info({"phase": 1, "cycle": 1, "boss_goal": "PINCER", "kaelen": "WITH MINIONS", "distracted": true})
	assert_true(text.contains("Boss goal: PINCER"), text)
	assert_true(text.contains("Kaelen: WITH MINIONS (distracted)"), text)
