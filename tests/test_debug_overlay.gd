extends TestCase
# Overlay F3: lineas de la meta del jefe y del comportamiento de Kaelen.

const OverlayScript := preload("res://scripts/ai/debug_overlay.gd")


func test_format_info_without_boss_goal_has_no_extra_lines() -> void:
	var text: String = OverlayScript.format_info({"phase": 0, "cycle": 1})
	assert_true(not text.contains("Meta del jefe"))


func test_format_info_shows_goal_and_kaelen_behavior() -> void:
	var text: String = OverlayScript.format_info({"phase": 1, "cycle": 1, "boss_goal": "PINZA", "kaelen": "CON ESBIRROS", "distracted": true})
	assert_true(text.contains("Meta del jefe: PINZA"), text)
	assert_true(text.contains("Kaelen: CON ESBIRROS (distraída)"), text)
