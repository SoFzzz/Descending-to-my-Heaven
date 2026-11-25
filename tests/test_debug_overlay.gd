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


# F3 / F5 only in debug builds (OS.is_debug_build()); `shortcuts_enabled` = false is the release build.
const OVERLAY_SCENE := "res://scenes/ui/debug_overlay.tscn"


func _press(action: StringName) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev


func _overlay() -> Node:
	var overlay := (load(OVERLAY_SCENE) as PackedScene).instantiate()
	# Outside the scene tree @onready does not run: bind the panel by hand.
	overlay._panel = overlay.get_node("Panel")
	overlay._label = overlay.get_node("Panel/Label")
	overlay._panel.visible = false
	return overlay


func test_shortcuts_follow_the_build_type() -> void:
	var overlay := _overlay()
	assert_eq(overlay.shortcuts_enabled, OS.is_debug_build(), "default comes from OS.is_debug_build()")
	overlay.free()


func test_debug_build_recognises_f3_and_f5() -> void:
	var overlay := _overlay()
	overlay.shortcuts_enabled = true
	assert_eq(overlay.shortcut_for(_press(&"debug_overlay")), &"debug_overlay", "F3")
	assert_eq(overlay.shortcut_for(_press(&"debug_skip")), &"debug_skip", "F5")
	assert_eq(overlay.shortcut_for(_press(&"attack")), &"", "other actions are not shortcuts")
	overlay.apply_shortcut(&"debug_overlay")
	assert_true(overlay.is_shown(), "F3 shows the panel")
	overlay.apply_shortcut(&"debug_overlay")
	assert_true(not overlay.is_shown(), "F3 again hides it")
	overlay.free()


func test_release_build_ignores_f3_and_f5() -> void:
	var overlay := _overlay()
	overlay.shortcuts_enabled = false
	assert_eq(overlay.shortcut_for(_press(&"debug_overlay")), &"", "F3 ignored")
	assert_eq(overlay.shortcut_for(_press(&"debug_skip")), &"", "F5 ignored")
	overlay.apply_shortcut(&"debug_overlay")
	assert_true(not overlay.is_shown(), "the panel never opens")
	overlay.free()
