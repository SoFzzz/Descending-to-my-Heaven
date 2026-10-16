extends CanvasLayer
## Overlay de depuración (spec §8.3). F3 (acción "debug_overlay") lo muestra/oculta: intensidad,
## fase, presupuesto de la última oleada, esbirros vivos y fichas de ataque. F5 ("debug_skip")
## salta al siguiente nivel con GameState.advance_level(). F6 (modo dios) lo gestiona Kaelen.
## Hijo del autoload GameState; solo se ve y actúa si hay un "player" en la escena, así que no
## aparece en el menú principal.

const TokensScript := preload("res://scripts/ai/attack_tokens.gd")
const PHASE_NAMES: Array[String] = ["CRECIMIENTO", "PICO", "RESPIRO"]
## Orden de OrchestratorModel.Cycle.
const CYCLE_NAMES: Array[String] = ["PRIMERA OLEADA en", "OLEADA en curso", "VENTANA DEL JEFE"]

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
	if cycle != 1:   # fuera de la oleada hay cuenta atrás
		cycle_text += " %.1f s" % float(info.get("cycle_time", 0.0))
	return "Intensidad: %d / 100
Fase: %s
Ciclo: %s
Presupuesto: %d
Esbirros vivos: %d
Fichas: %d / %d%s" % [
		roundi(float(info.get("intensity", 0.0))),
		PHASE_NAMES[clampi(phase, 0, PHASE_NAMES.size() - 1)],
		cycle_text,
		int(info.get("budget", 0)),
		int(info.get("alive", 0)),
		int(info.get("tokens", 0)),
		TokensScript.MAX_TOKENS,
		_boss_lines(info),
	]


## Meta táctica del jefe y comportamiento detectado de Kaelen (si el jefe tiene tácticas).
static func _boss_lines(info: Dictionary) -> String:
	if not info.has("boss_goal"):
		return ""
	return "
Meta del jefe: %s
Kaelen: %s%s" % [
		str(info.get("boss_goal", "")),
		str(info.get("kaelen", "")),
		" (distraída)" if info.get("distracted", false) else "",
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
