extends Node
## Director del final (Tarea 15). Hijo de `Arena3Gameplay` (arena_3_gameplay.tscn). Usa los nodos
## `Level/Ending/*` de arena_3.tscn: Elysia, EndingTrigger, EndingCam1, EndingCam2 y KaelenEndPoint.
##
## - Al iniciar hace respirar a Elysia (sube y baja unos 2 cm en bucle) y escucha el EndingTrigger.
## - Cuando Kaelen entra al EndingTrigger con la arena despejada ejecuta `play()` una sola vez:
##   bloquea a Kaelen, oculta su HUD, la coloca frente a Elysia, gira a Elysia hacia ella, muestra
##   dos cámaras con un texto cada una, resuelve el abrazo con un fundido a negro y pide
##   GameState.advance_level() (que desde la arena 3 lleva a los créditos).
## Si falta algún nodo avisa con push_warning y sigue; nunca se queda esperando.

## Respiración de Elysia: amplitud (m) y duración de cada medio ciclo (s).
const BREATH_AMPLITUDE := 0.02
const BREATH_HALF_CYCLE := 1.6
## Giro de Elysia hacia Kaelen (s) y corrección de yaw si su modelo no mira hacia +Z (rad).
const ELYSIA_TURN_TIME := 0.8
const ELYSIA_FRONT_YAW_OFFSET := 0.0

## Pausa inicial antes del primer plano y duración de los textos.
const LEAD_IN_TIME := 0.5
const TEXT_FADE_IN := 1.0
const TEXT_FADE_OUT := 1.0
## Tiempo que el texto queda completo tras revelarse (el jugador puede saltarlo con el ataque).
const SHOT_1_HOLD := 1.5
const SHOT_2_HOLD := 1.5
## Fundido a negro que resuelve el abrazo y pausa en negro antes de pasar a los créditos.
const EMBRACE_FADE_TIME := 1.8
const EMBRACE_BLACK_HOLD := 0.6

## Fundido de salida del viento de la caída al pasar a créditos (s).
const WIND_FADE_OUT := 1.2

const TEXT_LAYER := 20
const TEXT_FONT_SIZE := 14
const TEXT_BOTTOM_MARGIN := 24.0

## Claves de traducción (localization/translations.csv); el prefijo "Kaelen:" / "Elysia:" se mantiene en ambos idiomas.
const SHOT_1_TEXT := "ENDING_SHOT_1"
const SHOT_2_TEXT := "ENDING_SHOT_2"

## Música del encuentro con Elysia (también suena en los créditos).
@export var music: AudioStream
@export var music_fade := 2.0

var _played := false
var _breath_tween: Tween
var _ending: Node3D
var _elysia: Node3D
var _trigger: Area3D
var _cam_1: Camera3D
var _cam_2: Camera3D
var _end_point: Node3D
var _text_layer: CanvasLayer
var _label: Label
var _overlay: ColorRect
var _typewriter: Typewriter

signal hold_over   ## fin de la pausa con el texto completo (por tiempo o por avanzar)


## Texto de un plano en el idioma actual.
static func localized(key: String) -> String:
	return TranslationServer.translate(StringName(key))


## Duración total aproximada de la secuencia (s), sin contar el fundido propio de GameState.
static func total_duration() -> float:
	var shot_1 := Typewriter.reveal_duration(localized(SHOT_1_TEXT)) + SHOT_1_HOLD + TEXT_FADE_OUT
	var shot_2 := Typewriter.reveal_duration(localized(SHOT_2_TEXT)) + SHOT_2_HOLD + TEXT_FADE_OUT
	return LEAD_IN_TIME + shot_1 + shot_2 + EMBRACE_FADE_TIME + EMBRACE_BLACK_HOLD


## true si la secuencia debe arrancar: no se ha reproducido, entró Kaelen y la arena está despejada.
static func can_start(already_played: bool, is_player: bool, arena_cleared: bool) -> bool:
	return not already_played and is_player and arena_cleared


## Yaw (rad) para que un nodo cuyo frente es +Z mire de `from` hacia `to` (solo plano horizontal).
## Si ambos puntos coinciden en el plano devuelve `fallback`.
static func yaw_toward(from: Vector3, to: Vector3, fallback := 0.0) -> float:
	var dir := to - from
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return fallback
	return atan2(dir.x, dir.z)


func _ready() -> void:
	_ending = get_node_or_null(^"../Level/Ending") as Node3D
	if _ending == null:
		push_warning("EndingDirector: no se encontró Level/Ending")
		return
	_elysia = _ending.get_node_or_null(^"Elysia") as Node3D
	_trigger = _ending.get_node_or_null(^"EndingTrigger") as Area3D
	_cam_1 = _ending.get_node_or_null(^"EndingCam1") as Camera3D
	_cam_2 = _ending.get_node_or_null(^"EndingCam2") as Camera3D
	_end_point = _ending.get_node_or_null(^"KaelenEndPoint") as Node3D
	_start_breathing()
	if _trigger:
		_trigger.body_entered.connect(_on_trigger_body_entered)
	else:
		push_warning("EndingDirector: falta Ending/EndingTrigger; el final no arrancará solo")


func _start_breathing() -> void:
	if _elysia == null:
		push_warning("EndingDirector: falta Ending/Elysia")
		return
	var base_y := _elysia.position.y
	_breath_tween = create_tween().set_loops()
	_breath_tween.tween_property(_elysia, "position:y", base_y + BREATH_AMPLITUDE, BREATH_HALF_CYCLE) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_breath_tween.tween_property(_elysia, "position:y", base_y, BREATH_HALF_CYCLE) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_trigger_body_entered(body: Node3D) -> void:
	if not can_start(_played, body is Player, _arena_cleared()):
		return
	play.call_deferred()   # deferred: we are inside a physics signal and play() moves Kaelen


func _arena_cleared() -> bool:
	var gameplay := get_parent()
	return gameplay != null and bool(gameplay.get(&"arena_cleared"))


func _player() -> Player:
	var gameplay := get_parent()
	if gameplay != null:
		var player := gameplay.get(&"player") as Player
		if player:
			return player
	if is_inside_tree():
		return get_tree().get_first_node_in_group(&"player") as Player
	return null


## Ejecuta el final. Solo actúa la primera vez que se llama.
func play() -> void:
	if _played:
		return
	_played = true
	var game_state := _game_state()
	if game_state:
		game_state.set(&"cutscene_active", true)
	_start_music()
	_start_fall()
	var player := _player()
	if player == null:
		push_warning("EndingDirector: no hay Kaelen; se salta el final")
		_finish()
		return
	_prepare_actors(player)
	_build_text_layer()
	if not await _wait(LEAD_IN_TIME):
		return

	# Plano 1: cámara lejana, primer texto.
	_activate_camera(_cam_1)
	if not await _show_text(localized(SHOT_1_TEXT), SHOT_1_HOLD):
		return
	# Plano 2: cámara cercana, segundo texto.
	_activate_camera(_cam_2)
	if not await _show_text(localized(SHOT_2_TEXT), SHOT_2_HOLD):
		return
	# Abrazo: se resuelve con un fundido a negro.
	_tween_alpha(_overlay, 1.0, EMBRACE_FADE_TIME)
	if not await _wait(EMBRACE_FADE_TIME + EMBRACE_BLACK_HOLD):
		return
	_finish()


func _start_music() -> void:
	var audio := get_node_or_null(^"/root/AudioManager") if is_inside_tree() else null
	if audio and music:
		audio.play_music(music, music_fade)


## Bloquea a Kaelen, oculta su HUD y coloca a ambas frente a frente.
func _prepare_actors(player: Player) -> void:
	player.set_cutscene(true)
	var hud := player.get_node_or_null(^"HUD") as CanvasLayer
	if hud:
		hud.visible = false
	var elysia_pos := _elysia.global_position if _elysia else Vector3.ZERO
	if _end_point:
		player.global_position = _end_point.global_position
		player.velocity = Vector3.ZERO
	else:
		push_warning("EndingDirector: falta Ending/KaelenEndPoint; Kaelen se queda donde está")
	if _elysia:
		player.face_point(elysia_pos)
		_turn_elysia_toward(player.global_position)
	else:
		push_warning("EndingDirector: falta Ending/Elysia")


func _turn_elysia_toward(target: Vector3) -> void:
	var desired := yaw_toward(_elysia.global_position, target, _elysia.rotation.y) + ELYSIA_FRONT_YAW_OFFSET
	var goal := _elysia.rotation.y + angle_difference(_elysia.rotation.y, desired)
	create_tween().tween_property(_elysia, "rotation:y", goal, ELYSIA_TURN_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _activate_camera(cam: Camera3D) -> void:
	if cam == null:
		push_warning("EndingDirector: falta una cámara del final; se mantiene la actual")
		return
	cam.make_current()


## Fundido de entrada con el texto revelándose letra a letra (con voz), pausa de `hold` s con el texto
## completo y fundido de salida. El ataque completa la línea y, ya completa, pasa a la siguiente.
## Devuelve false si el árbol cambió.
func _show_text(text: String, hold: float) -> bool:
	_tween_alpha(_label, 1.0, TEXT_FADE_IN)
	_typewriter.start(_label, text)
	if _typewriter.is_revealing():
		await _typewriter.finished
	if not is_inside_tree():
		return false
	if not await _hold(hold):
		return false
	_tween_alpha(_label, 0.0, TEXT_FADE_OUT)
	return await _wait(TEXT_FADE_OUT)


## Espera `seconds` s con el texto completo o hasta que el jugador pulse avanzar.
func _hold(seconds: float) -> bool:
	if not is_inside_tree():
		return false
	var timer := get_tree().create_timer(seconds)
	timer.timeout.connect(hold_over.emit)
	_typewriter.advanced.connect(hold_over.emit)
	await hold_over
	if timer.timeout.is_connected(hold_over.emit):
		timer.timeout.disconnect(hold_over.emit)
	if _typewriter.advanced.is_connected(hold_over.emit):
		_typewriter.advanced.disconnect(hold_over.emit)
	return is_inside_tree()


func _tween_alpha(item: CanvasItem, alpha: float, time: float) -> void:
	if item == null:
		return
	item.create_tween().tween_property(item, "modulate:a", alpha, time)


## Espera `seconds` s. Devuelve false (y la secuencia se corta) si el nodo salió del árbol.
func _wait(seconds: float) -> bool:
	if not is_inside_tree():
		return false
	await get_tree().create_timer(seconds).timeout
	return is_inside_tree()


## Capa con el fundido a negro y la línea de texto, creada por código (sobre el HUD y la pausa).
func _build_text_layer() -> void:
	_text_layer = CanvasLayer.new()
	_text_layer.layer = TEXT_LAYER
	_overlay = ColorRect.new()
	_overlay.color = Color.BLACK
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.modulate.a = 0.0
	_text_layer.add_child(_overlay)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.offset_bottom = -TEXT_BOTTOM_MARGIN
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override(&"font_size", TEXT_FONT_SIZE)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 4)
	_label.modulate.a = 0.0
	_text_layer.add_child(_label)
	_typewriter = Typewriter.new()
	_text_layer.add_child(_typewriter)
	add_child(_text_layer)


func _game_state() -> Node:
	return get_node_or_null(^"/root/GameState") if is_inside_tree() else null


## Cierra la secuencia: pide el siguiente paso (créditos) con el fundido propio de GameState.
func _finish() -> void:
	if is_inside_tree():
		get_tree().call_group(EndingRoom.GROUP, &"stop_wind", WIND_FADE_OUT)
	var game_state := _game_state()
	if game_state and game_state.has_method(&"advance_level"):
		game_state.advance_level()
	else:
		push_warning("EndingDirector: no hay GameState; no se puede avanzar al final")


## Avisa a la sala de Elysia rota (grupo `ending_room`) de que empieza el final: la isla cae.
func _start_fall() -> void:
	if is_inside_tree():
		get_tree().call_group(EndingRoom.GROUP, &"start_fall")
