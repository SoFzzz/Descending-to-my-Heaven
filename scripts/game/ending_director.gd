extends Node
## Ending director. Child of `Arena3Gameplay` (arena_3_gameplay.tscn). Uses the `Level/Ending/*`
## nodes of arena_3.tscn: Elysia, EndingTrigger, EndingCam1, EndingCam2 and KaelenEndPoint.
##
## - On start it makes Elysia breathe (about 2 cm up and down in a loop) and listens to the EndingTrigger.
## - When Kaelen enters the EndingTrigger with the arena cleared it runs `play()` only once: it locks
##   Kaelen, hides her HUD, places her in front of Elysia, turns Elysia towards her, alternates two
##   cameras following the script (ENDING_LINES), shows the dialogue in a box (DialogueBox) that
##   advances ONLY when the player presses, resolves the embrace with a fade to black and calls
##   GameState.advance_level() (which from arena 3 leads to the credits).
## If a node is missing it warns with push_warning and carries on; it never waits forever.

## Elysia's breathing: amplitude (m) and duration of each half cycle (s).
const BREATH_AMPLITUDE := 0.02
const BREATH_HALF_CYCLE := 1.6
## Elysia's turn towards Kaelen (s) and yaw correction if her model does not face +Z (rad).
const ELYSIA_TURN_TIME := 0.8
const ELYSIA_FRONT_YAW_OFFSET := 0.0

## Cut to the meeting: fade to black (Kaelen is moved to her mark while the screen is black), then
## fade in on the first shot. The player never sees Kaelen travel to the mark.
const CUT_FADE_OUT := 0.5
const CUT_FADE_IN := 0.6

## Pause after the screen is clear and before the first line, and fades of the dialogue box.
const LEAD_IN_TIME := 0.4
const BOX_FADE_IN := 0.8
const BOX_FADE_OUT := 0.8
## Fade to black that resolves the embrace, and the hold on black before the credits.
const EMBRACE_FADE_TIME := 1.8
const EMBRACE_BLACK_HOLD := 0.6

## Fade-out of the falling wind when moving on to the credits (s).
const WIND_FADE_OUT := 1.2

## During the dialogue the music drops by this level (dB) so the blips can be heard.
const MUSIC_DUCK_DB := -7.0
const MUSIC_DUCK_TIME := 1.0

const TEXT_LAYER := 20
## Frames each ending camera is shown during the warm-up (under the arena's title card).
const WARMUP_FRAMES := 3

## Staging of the ending (procedural: Elysia's model has no rig, so she moves as a whole body; Kaelen
## uses her own clips). Beat applied when the line of that index (in ENDING_LINES) starts:
## - &"quake": the room shakes, both stagger, dust falls (ENDING_04, the floor trembles);
## - &"look_out": both turn to the broken wall while a tower breaks away (ENDING_12);
## - &"come_down": Elysia turns back and steps down from the altar step to stand in front of Kaelen
##   (ENDING_13); she stops ELYSIA_EMBRACE_GAP m from her, so the bodies never overlap;
## - &"embrace": both lean in (EMBRACE_LEAN) under a last strong tremor (ENDING_17).
const BEATS := {3: &"quake", 11: &"look_out", 12: &"come_down", 16: &"embrace"}
const QUAKE_KICK := 0.12
const QUAKE_TIME := 1.2
const STAGGER_TILT := 0.09     # rad Elysia sways on a tremor
const STAGGER_TIME := 0.35
## Elysia stepping down: final distance to Kaelen (horizontal, between origins), duration and hop.
const ELYSIA_EMBRACE_GAP := 0.7
const STEP_DOWN_TIME := 1.1
const STEP_DOWN_HOP := 0.12
## She walks at the step's height until STEP_DOWN_LEDGE m before her mark (already past the step's
## edge: the mark is 0.3 m beyond it), and only then drops to the floor: her feet never cut into it.
const STEP_DOWN_LEDGE := 0.25
const STEP_DOWN_SPLIT := 0.6
const EMBRACE_LEAN := 0.14     # rad each one leans toward the other (about 8 deg)
const EMBRACE_TIME := 1.4
## Idle life: Elysia sways slightly while she talks (besides breathing).
const SWAY_ANGLE := 0.02
const SWAY_HALF_CYCLE := 2.4

## Ending script: translation key (localization/translations.csv; the "Kaelen:" / "Elysia:" prefix is
## kept in both languages and only tells who is speaking) and camera shot of each line:
## 1 = EndingCam1 (far, with the island falling), 2 = EndingCam2 (close, the two together).
const ENDING_LINES: Array[Array] = [
	["ENDING_01", 1], ["ENDING_02", 1], ["ENDING_03", 1], ["ENDING_04", 1],
	["ENDING_05", 2], ["ENDING_06", 2], ["ENDING_07", 2], ["ENDING_08", 2], ["ENDING_09", 2],
	["ENDING_10", 1], ["ENDING_11", 1], ["ENDING_12", 1],
	["ENDING_13", 2], ["ENDING_14", 2], ["ENDING_15", 2], ["ENDING_16", 2],
	["ENDING_17", 2], ["ENDING_18", 2], ["ENDING_19", 1],
]

## Music of the meeting with Elysia (it also plays in the credits).
@export var music: AudioStream
@export var music_fade := 2.0

## Emitted while the screen is fully black, right after Kaelen was placed at her mark and the first
## shot was set (tests use it to check nothing is seen in between).
signal actors_placed

var _played := false
var _breath_tween: Tween
var _ending: Node3D
var _elysia: Node3D
var _trigger: Area3D
var _cam_1: Camera3D
var _cam_2: Camera3D
var _end_point: Node3D
var _text_layer: CanvasLayer
var _overlay: ColorRect
var _box: DialogueBox
var _sway_tween: Tween
var _beat_tween: Tween


## Text of a line in the current language.
static func localized(key: String) -> String:
	return TranslationServer.translate(StringName(key))


## Minimum duration of the sequence (s): reveal of every line, the lead-in and the embrace. It does not
## include the time the player takes to press between lines (the dialogue no longer advances by itself).
static func total_duration() -> float:
	var total := LEAD_IN_TIME + BOX_FADE_OUT + EMBRACE_FADE_TIME + EMBRACE_BLACK_HOLD
	for entry in ENDING_LINES:
		total += Typewriter.reveal_duration(DialogueBox.parse_line(localized(entry[0]))["body"])
	return total


## Number of script lines.
static func line_count() -> int:
	return ENDING_LINES.size()


## true if the sequence must start: not played yet, Kaelen entered and the arena is cleared.
static func can_start(already_played: bool, is_player: bool, arena_cleared: bool) -> bool:
	return not already_played and is_player and arena_cleared


## Yaw (rad) for a node whose front is +Z to look from `from` towards `to` (horizontal plane only).
## If both points coincide on the plane it returns `fallback`.
static func yaw_toward(from: Vector3, to: Vector3, fallback := 0.0) -> float:
	var dir := to - from
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return fallback
	return atan2(dir.x, dir.z)


func _ready() -> void:
	_ending = get_node_or_null(^"../Level/Ending") as Node3D
	if _ending == null:
		push_warning("EndingDirector: Level/Ending not found")
		return
	_elysia = _ending.get_node_or_null(^"Elysia") as Node3D
	_trigger = _ending.get_node_or_null(^"EndingTrigger") as Area3D
	_cam_1 = _ending.get_node_or_null(^"EndingCam1") as Camera3D
	_cam_2 = _ending.get_node_or_null(^"EndingCam2") as Camera3D
	_end_point = _ending.get_node_or_null(^"KaelenEndPoint") as Node3D
	_start_breathing()
	_start_sway()
	_build_text_layer()   # now, not when the ending starts: the box and its fonts cost a frame
	_warm_up.call_deferred()
	if _trigger:
		_trigger.body_entered.connect(_on_trigger_body_entered)
	else:
		push_warning("EndingDirector: missing Ending/EndingTrigger; the ending will not start by itself")


func _start_breathing() -> void:
	if _elysia == null:
		push_warning("EndingDirector: missing Ending/Elysia")
		return
	var base_y := _elysia.position.y
	_breath_tween = create_tween().set_loops()
	_breath_tween.tween_property(_elysia, "position:y", base_y + BREATH_AMPLITUDE, BREATH_HALF_CYCLE) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_breath_tween.tween_property(_elysia, "position:y", base_y, BREATH_HALF_CYCLE) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Slow whole-body sway (rotation z) so Elysia never stands like a statue.
func _start_sway() -> void:
	if _elysia == null:
		return
	_sway_tween = create_tween().set_loops()
	_sway_tween.tween_property(_elysia, "rotation:z", SWAY_ANGLE, SWAY_HALF_CYCLE) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sway_tween.tween_property(_elysia, "rotation:z", -SWAY_ANGLE, SWAY_HALF_CYCLE) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Where Elysia ends when she steps down: on the line from her to Kaelen, ELYSIA_EMBRACE_GAP m from
## Kaelen, on Kaelen's floor height.
static func step_down_target(elysia: Vector3, kaelen: Vector3, gap: float) -> Vector3:
	var flat := Vector3(kaelen.x - elysia.x, 0.0, kaelen.z - elysia.z)
	if flat.length() <= gap:
		return Vector3(elysia.x, kaelen.y, elysia.z)
	var stop := kaelen - flat.normalized() * gap
	return Vector3(stop.x, kaelen.y, stop.z)


func _beat(index: int, player: Player) -> void:
	var beat: StringName = BEATS.get(index, &"")
	if beat == &"" or player == null or not is_inside_tree():
		return
	match beat:
		&"quake":
			_quake(player, 1.0)
		&"look_out":
			_quake(player, 0.6)
			var hole := _hole_point()
			player.face_point(hole)
			if _elysia:
				_turn_elysia_toward(hole)
		&"come_down":
			player.face_point(_elysia.global_position if _elysia else player.global_position)
			_come_down(player)
		&"embrace":
			_quake(player, 1.3)
			_lean_in(player)


## A tremor: camera kick and dust (EndingRoom.kick), Kaelen's hurt stagger, Elysia's sway.
func _quake(player: Player, strength: float) -> void:
	get_tree().call_group(EndingRoom.GROUP, &"kick", QUAKE_KICK * strength, QUAKE_TIME)
	player.call(&"_play_action", &"hurt")
	if _elysia:
		var tilt := create_tween()
		tilt.tween_property(_elysia, "rotation:x", -STAGGER_TILT * strength, STAGGER_TIME * 0.4) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tilt.tween_property(_elysia, "rotation:x", 0.0, STAGGER_TIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## The broken north wall of the room (where the sky opens): EndingCam1 looks across the room toward
## the altar, so the hole is beyond the altar from Kaelen's mark.
func _hole_point() -> Vector3:
	var from := _end_point.global_position if _end_point else Vector3.ZERO
	var altar := _elysia.global_position if _elysia else from + Vector3.FORWARD
	var dir := altar - from
	dir.y = 0.0
	return altar + dir.normalized() * 6.0 + Vector3.UP * 3.0


func _come_down(player: Player) -> void:
	if _elysia == null:
		return
	if _breath_tween and _breath_tween.is_valid():
		_breath_tween.kill()
	_turn_elysia_toward(player.global_position)
	var from := _elysia.global_position
	var to := step_down_target(from, player.global_position, ELYSIA_EMBRACE_GAP)
	_beat_tween = create_tween()
	_beat_tween.tween_method(_place_on_arc.bind(from, to), 0.0, 1.0, STEP_DOWN_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_beat_tween.tween_callback(_start_breathing)   # breathing again from her new height


func _place_on_arc(t: float, from: Vector3, to: Vector3) -> void:
	if _elysia and is_instance_valid(_elysia):
		_elysia.global_position = step_down_point(t, from, to)


## Position of the step down at `t` (0..1): walk at the step's height to the ledge point, then drop.
static func step_down_point(t: float, from: Vector3, to: Vector3) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var ledge := Vector3(to.x, from.y, to.z) - flat.normalized() * minf(STEP_DOWN_LEDGE, flat.length())
	if t < STEP_DOWN_SPLIT:
		var k := t / STEP_DOWN_SPLIT
		return from.lerp(ledge, k) + Vector3.UP * STEP_DOWN_HOP * sin(PI * k)
	var k2 := (t - STEP_DOWN_SPLIT) / (1.0 - STEP_DOWN_SPLIT)
	return ledge.lerp(to, k2)


func _lean_in(player: Player) -> void:
	var model := player.get_node_or_null(^"Model") as Node3D
	var lean := create_tween().set_parallel(true)
	if model:
		lean.tween_property(model, "rotation:x", EMBRACE_LEAN, EMBRACE_TIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _elysia:
		if _sway_tween and _sway_tween.is_valid():
			_sway_tween.kill()
		lean.tween_property(_elysia, "rotation:x", EMBRACE_LEAN, EMBRACE_TIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		lean.tween_property(_elysia, "rotation:z", 0.0, EMBRACE_TIME)


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


## Runs the ending. It only acts the first time it is called.
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
		push_warning("EndingDirector: no Kaelen; skipping the ending")
		_finish()
		return
	# Lock Kaelen where she stands (she is in the trigger, running at most), cut to black, and only
	# then move everything: the island starts falling under the black so the clouds and the wind
	# are already moving when the picture comes back.
	player.set_cutscene(true)
	if _text_layer == null:
		_build_text_layer()
	_tween_alpha(_overlay, 1.0, CUT_FADE_OUT)
	if not await _wait(CUT_FADE_OUT):
		return
	_prepare_actors(player)
	var shot := 1
	_activate_camera(_cam_1)
	await get_tree().process_frame   # let the new transform and the idle pose reach the renderer
	await get_tree().process_frame
	actors_placed.emit()
	_tween_alpha(_overlay, 0.0, CUT_FADE_IN)
	if not await _wait(CUT_FADE_IN + LEAD_IN_TIME):
		return

	# Dialogue: each line is revealed by the typewriter and waits for the player to press; the camera
	# shot changes when the next line belongs to another shot.
	_duck_music(MUSIC_DUCK_DB)
	_box.fade(1.0, BOX_FADE_IN)
	for i in ENDING_LINES.size():
		var entry: Array = ENDING_LINES[i]
		if int(entry[1]) != shot:
			shot = int(entry[1])
			_activate_camera(_cam_1 if shot == 1 else _cam_2)
		_beat(i, player)
		if not await _say(localized(entry[0])):
			return
	_box.fade(0.0, BOX_FADE_OUT)
	_duck_music(0.0)
	# Embrace: resolved with a fade to black.
	_tween_alpha(_overlay, 1.0, EMBRACE_FADE_TIME)
	if not await _wait(EMBRACE_FADE_TIME + EMBRACE_BLACK_HOLD):
		return
	_finish()


func _start_music() -> void:
	var audio := get_node_or_null(^"/root/AudioManager") if is_inside_tree() else null
	if audio and music:
		audio.play_music(music, music_fade)


## Hides her HUD and places both face to face. Call it only with the screen black.
func _prepare_actors(player: Player) -> void:
	var hud := player.get_node_or_null(^"HUD") as CanvasLayer
	if hud:
		hud.visible = false
	var elysia_pos := _elysia.global_position if _elysia else Vector3.ZERO
	if _end_point:
		player.global_position = _end_point.global_position
		player.velocity = Vector3.ZERO
	else:
		push_warning("EndingDirector: missing Ending/KaelenEndPoint; Kaelen stays where she is")
	if _elysia:
		player.face_point(elysia_pos)
		_turn_elysia_toward(player.global_position)
	else:
		push_warning("EndingDirector: missing Ending/Elysia")


func _turn_elysia_toward(target: Vector3) -> void:
	var desired := yaw_toward(_elysia.global_position, target, _elysia.rotation.y) + ELYSIA_FRONT_YAW_OFFSET
	var goal := _elysia.rotation.y + angle_difference(_elysia.rotation.y, desired)
	create_tween().tween_property(_elysia, "rotation:y", goal, ELYSIA_TURN_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _activate_camera(cam: Camera3D) -> void:
	if cam == null:
		push_warning("EndingDirector: missing an ending camera; keeping the current one")
		return
	cam.make_current()


## Shows a line and waits for the player to complete it and press again to move on.
## Returns false if the tree changed.
func _say(line: String) -> bool:
	_box.show_line(line)
	await _box.advanced
	return is_inside_tree()


## Lowers the music (or returns it to 0) while the blips play.
func _duck_music(db: float) -> void:
	var audio := get_node_or_null(^"/root/AudioManager") if is_inside_tree() else null
	if audio and audio.has_method(&"duck_music"):
		audio.duck_music(db, MUSIC_DUCK_TIME)


func _tween_alpha(item: CanvasItem, alpha: float, time: float) -> void:
	if item == null:
		return
	item.create_tween().tween_property(item, "modulate:a", alpha, time)


## Waits `seconds` s. Returns false (and the sequence is cut short) if the node left the tree.
func _wait(seconds: float) -> bool:
	if not is_inside_tree():
		return false
	await get_tree().create_timer(seconds).timeout
	return is_inside_tree()


## Layer with the fade to black and the dialogue box, built in code (above the HUD and the pause).
func _build_text_layer() -> void:
	_text_layer = CanvasLayer.new()
	_text_layer.layer = TEXT_LAYER
	_box = DialogueBox.new()
	_text_layer.add_child(_box)
	_overlay = ColorRect.new()
	_overlay.color = Color.BLACK
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.modulate.a = 0.0
	_text_layer.add_child(_overlay)
	add_child(_text_layer)


func _game_state() -> Node:
	return get_node_or_null(^"/root/GameState") if is_inside_tree() else null


## gl_compatibility compiles a shader the first time it is drawn, so the ending's first frame (sky,
## clouds, wind streaks, dust, the room) stalled. While the arena's title card still covers the screen
## each ending camera is made current for a few frames with the fall's effects on, then Kaelen's
## camera comes back. Skipped without a window or without a transition covering the screen.
func _warm_up() -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree() or _played:
		return
	# Only while the transition covers the screen (a scene opened straight from the editor would
	# flash the ending's shots instead).
	var game_state := _game_state()
	var transition: Node = game_state.get(&"transition") if game_state else null
	if transition == null or not transition.call(&"is_busy"):
		return
	var previous := get_viewport().get_camera_3d()
	get_tree().call_group(EndingRoom.GROUP, &"warm_up", true)
	for cam in [_cam_1, _cam_2]:
		if cam == null:
			continue
		cam.make_current()
		for i in WARMUP_FRAMES:
			await get_tree().process_frame
			if not is_inside_tree() or _played:
				return
	if is_inside_tree():
		get_tree().call_group(EndingRoom.GROUP, &"warm_up", false)
	if previous and is_instance_valid(previous) and not _played:
		previous.make_current()


## Closes the sequence: requests the next step (credits) with GameState's own fade.
func _finish() -> void:
	if is_inside_tree():
		get_tree().call_group(EndingRoom.GROUP, &"stop_wind", WIND_FADE_OUT)
	var game_state := _game_state()
	if game_state and game_state.has_method(&"advance_level"):
		_advance_when_free(game_state)
	else:
		push_warning("EndingDirector: no GameState; cannot move on from the ending")


## GameState ignores advance_level() while a fade is running, which would leave the ending hanging
## on a black screen: wait until the transition is free, then advance. Gives up if the director
## leaves the tree (a scene change already took over).
func _advance_when_free(game_state: Node) -> void:
	while _transition_busy(game_state):
		if not is_inside_tree():
			return
		await get_tree().process_frame
	game_state.call(&"advance_level")


static func _transition_busy(game_state: Node) -> bool:
	var transition := game_state.get(&"transition") as Node
	return transition != null and transition.has_method(&"is_busy") and transition.call(&"is_busy")


## Tells the broken Elysia room (group `ending_room`) that the ending begins: the island falls.
func _start_fall() -> void:
	if is_inside_tree():
		get_tree().call_group(EndingRoom.GROUP, &"start_fall")
