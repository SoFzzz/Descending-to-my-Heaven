extends CanvasLayer
## Debug overlay (spec 8.3). F3 (action "debug_overlay") shows / hides it: intensity,
## phase, budget of the last wave, live minions and attack tokens. F5 ("debug_skip")
## jumps to the next level with GameState.advance_level(). F6 (god mode) is handled by Kaelen.
## Child of the GameState autoload; it only shows and acts if there is a "player" in the scene, so it
## does not appear in the main menu.

const TokensScript := preload("res://scripts/ai/attack_tokens.gd")
const PHASE_NAMES: Array[String] = ["BUILD-UP", "PEAK", "RELAX"]
## Order of OrchestratorModel.Cycle.
const CYCLE_NAMES: Array[String] = ["FIRST WAVE in", "WAVE in progress", "BOSS WINDOW"]

@onready var _panel: Control = $Panel
@onready var _label: Label = $Panel/Label

var _enabled := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _in_gameplay():
		return
	if event.is_action_pressed(&"debug_overlay"):
		_enabled = not _enabled
		_panel.visible = _enabled
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"debug_skip"):
		var game_state := get_node_or_null(^"/root/GameState")
		if game_state and game_state.has_method(&"advance_level"):
			game_state.call_deferred(&"advance_level")
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _enabled:
		return
	var in_game := _in_gameplay()
	_panel.visible = in_game
	if in_game:
		_label.text = format_info(_info())


func is_shown() -> bool:
	return _panel.visible


static func format_info(info: Dictionary) -> String:
	var phase := int(info.get("phase", 0))
	var cycle := int(info.get("cycle", 0))
	var cycle_text: String = CYCLE_NAMES[clampi(cycle, 0, CYCLE_NAMES.size() - 1)]
	if cycle != 1:   # outside the wave there is a countdown
		cycle_text += " %.1f s" % float(info.get("cycle_time", 0.0))
	return "Intensity: %d / 100
Phase: %s
Cycle: %s
Budget: %d
Live minions: %d
Tokens: %d / %d%s" % [
		roundi(float(info.get("intensity", 0.0))),
		PHASE_NAMES[clampi(phase, 0, PHASE_NAMES.size() - 1)],
		cycle_text,
		int(info.get("budget", 0)),
		int(info.get("alive", 0)),
		int(info.get("tokens", 0)),
		TokensScript.MAX_TOKENS,
		_boss_lines(info),
	]


## Tactical goal of the boss and detected behaviour of Kaelen (if the boss has tactics).
static func _boss_lines(info: Dictionary) -> String:
	if not info.has("boss_goal"):
		return ""
	return "
Boss goal: %s
Kaelen: %s%s" % [
		str(info.get("boss_goal", "")),
		str(info.get("kaelen", "")),
		" (distracted)" if info.get("distracted", false) else "",
	]


func _info() -> Dictionary:
	var orchestrator := get_node_or_null(^"/root/Orchestrator")
	var info: Dictionary = orchestrator.call(&"get_debug_info") if orchestrator else {}
	var tokens := get_node_or_null(^"/root/AttackTokens")
	if tokens:
		info["tokens"] = tokens.call(&"holders_count")
	return info


func _in_gameplay() -> bool:
	var tree := get_tree()
	return tree != null and tree.get_first_node_in_group(&"player") != null
