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
## Elysia's turn towards Kaelen (s) and yaw correction if her model does not face +Z (rad).
const ELYSIA_TURN_TIME := 1.2
const ELYSIA_LOOK_TIME := 2.6     # s she takes to turn toward the hole in the wall (slowly)
const ELYSIA_FRONT_YAW_OFFSET := 0.0

## Cut to the meeting: fade to black (Kaelen is moved to her mark while the screen is black), then
## fade in on the first shot. The player never sees Kaelen travel to the mark.
const CUT_FADE_OUT := 0.5
const CUT_FADE_IN := 0.6

## Pause after the screen is clear and before the first line, and fades of the dialogue box.
const LEAD_IN_TIME := 0.4
const BOX_FADE_IN := 0.8
const BOX_FADE_OUT := 0.8
## After the last line they stay in the embrace for HOLD_TIME s while the camera slowly pulls back and
## the island keeps falling; only then comes the fade to black that resolves it and the hold on black
## before the credits.
const HOLD_TIME := 8.0
const HOLD_PULL_BACK := 1.2     # m the camera backs away from the couple during the hold
const HOLD_RISE := 0.5          # m it rises
const EMBRACE_FADE_TIME := 2.4
const EMBRACE_BLACK_HOLD := 0.8

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
##   (ENDING_13); she stops ELYSIA_REACH_GAP m from her (body to body) and opens her arms;
## - &"embrace": both lean in (EMBRACE_LEAN) under a last strong tremor (ENDING_17).
const BEATS := {3: &"quake", 11: &"look_out", 12: &"come_down", 16: &"embrace"}
const QUAKE_KICK := 0.12
const QUAKE_TIME := 1.2
const STAGGER_TILT := 0.09     # rad Elysia sways on a tremor
const STAGGER_TIME := 0.35
## Elysia's walk to Kaelen: the distance she stops at (horizontal, her body to Kaelen) and its duration. Her feet
## stay at the step's height until they pass the step's edge, then come down over STEP_DROP_LENGTH m.
const ELYSIA_REACH_GAP := 1.35
const STEP_DOWN_TIME := 6.0     # s she takes to walk to Kaelen (slowly)
const STEP_DROP_LENGTH := 0.3
const EMBRACE_LEAN := 0.04     # rad each one leans toward the other (about 2 deg: more made their heads and chests cross)
const EMBRACE_TIME := 1.4
## The embrace itself (ENDING_17): Elysia steps in until she is HUG_GAP m from Kaelen (bodies about
## 0.3 m deep each, so they touch), Kaelen's arms (HugArms) close around her over HUG_ARMS_TIME s, and
## her greatsword leaves her hand HUG_DROP_DELAY s after the beat starts.
## HUG_BODY_GAP is measured to the middle of her body (see _elysia_center_local), not to her origin.
const HUG_BODY_GAP := 0.55
const HUG_HEAD_OFFSET := 0.12   # m she stands to one side, so the heads pass each other like in a real hug
const HUG_MOVE_TIME := 1.4
const HUG_ARMS_TIME := 1.6
const STANCE_IDLE_SCALE := 0.2   # her idle clip plays at this speed: she stands almost still, not on the lookout
const STANCE_TIME := 1.4         # s Kaelen takes to lower her sword when the dialogue begins
const HUG_ARMS_DELAY := 0.3
const HUG_DROP_DELAY := 0.35
const SWORD_GRIP := ^"Model/Armature/Skeleton3D/RightHand/SwordGrip"
## Idle life: Elysia sways slightly while she talks (besides breathing).

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

## Camera shot of each line (same order as ENDING_LINES). The speaker is found from the line's prefix:
## face = in front of the speaker, over = over the listener's shoulder, low = low angle on the speaker,
## side = three-quarter from the other side, profile = both from the side, wide = the room from far away.
## Every shot drifts slowly (SHOT_DRIFT_TIME) so the picture is never still.
const SHOT_KINDS: Array[StringName] = [
	&"wide", &"face", &"side", &"wide",
	&"over", &"low", &"over", &"side", &"profile",
	&"low", &"face", &"wide",
	&"face", &"over", &"side", &"low",
	&"profile", &"face", &"wide_high",
]
const SHOT_DRIFT_TIME := 9.0
const KAELEN_HEAD := 1.55
const ELYSIA_HEAD := 1.42

## Music of the meeting with Elysia (it also plays in the credits).
@export var music: AudioStream
@export var music_fade := 2.0

## Emitted while the screen is fully black, right after Kaelen was placed at her mark and the first
## shot was set (tests use it to check nothing is seen in between).
signal actors_placed

var _played := false
var _ending: Node3D
var _elysia: Node3D
var _trigger: Area3D
var _cam_1: Camera3D
var _cam_2: Camera3D
var _end_point: Node3D
var _text_layer: CanvasLayer
var _overlay: ColorRect
var _box: DialogueBox
var _beat_tween: Tween
var _hug: HugArms
var _elysia_origin := Vector3.ZERO   # where her origin is with no lean (the lean pivots about her feet)
var _entrance_fog: Node3D
var _elysia_anim: AnimationPlayer   # her rig's clips: idle (loop), appear (once), hug (holds)
var _elysia_center_local := Vector3.ZERO   # middle of her meshes in her local space (her origin is not her body)
var _hold_tween: Tween
var _turn_tween: Tween
var _dyn_cam: Camera3D          # the dialogue's moving camera (see SHOT_KINDS)
var _shot_kind: StringName = &"wide"
var _shot_speaker: StringName = &""
var _shot_time := 0.0
var _shot_active := false
var _kaelen: Player
var _elysia_busy := false       # she walks / reaches / hugs: the speaking clips stop


## Text of a line in the current language.
static func localized(key: String) -> String:
	return TranslationServer.translate(StringName(key))


## Minimum duration of the sequence (s): reveal of every line, the lead-in and the embrace. It does not
## include the time the player takes to press between lines (the dialogue no longer advances by itself).
static func total_duration() -> float:
	var total := LEAD_IN_TIME + BOX_FADE_OUT + HOLD_TIME + EMBRACE_FADE_TIME + EMBRACE_BLACK_HOLD
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
	_dyn_cam = Camera3D.new()
	_dyn_cam.name = "EndingDynCam"
	if _cam_1:
		_dyn_cam.fov = _cam_1.fov
		_dyn_cam.near = _cam_1.near
		_dyn_cam.far = _cam_1.far
	add_child(_dyn_cam)
	_elysia_center_local = _mesh_center_local(_elysia)
	if _elysia:
		_elysia_origin = _elysia.global_position
	_setup_elysia_animations()
	_build_text_layer()   # now, not when the ending starts: the box and its fonts cost a frame
	_warm_up.call_deferred()
	if _trigger:
		_trigger.body_entered.connect(_on_trigger_body_entered)
	else:
		push_warning("EndingDirector: missing Ending/EndingTrigger; the ending will not start by itself")


## Elysia's rig (tools/rig_elysia.py) brings three clips: she idles from the start (arms relaxed: the static
## model was posed with its arms out), `appear` plays once when the ending shows her, `hug` at the embrace.
func _setup_elysia_animations() -> void:
	if _elysia == null:
		return
	_elysia_anim = _elysia.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _elysia_anim == null:
		push_warning("EndingDirector: Elysia has no AnimationPlayer (is she the rigged model?)")
		return
	if _elysia_anim.has_animation(&"idle"):
		_elysia_anim.get_animation(&"idle").loop_mode = Animation.LOOP_LINEAR
		_elysia_anim.play(&"idle")
	for looped in [&"talk", &"walk"]:
		if _elysia_anim.has_animation(looped):
			_elysia_anim.get_animation(looped).loop_mode = Animation.LOOP_LINEAR


## Plays one of her clips; `then_idle` goes back to the idle loop when it ends.
func _play_elysia(clip: StringName, then_idle := false) -> void:
	if _elysia_anim == null or not _elysia_anim.has_animation(clip):
		return
	_elysia_anim.play(clip, 0.25)
	if then_idle and _elysia_anim.has_animation(&"idle"):
		_elysia_anim.queue(&"idle")


## Middle of all the meshes under `node`, in `node`'s local space (Vector3.ZERO if there are none).
static func _mesh_center_local(node: Node3D) -> Vector3:
	if node == null:
		return Vector3.ZERO
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return Vector3.ZERO
	return node.global_transform.affine_inverse() * box.get_center()


## Floor point `gap` m from Kaelen on the line from Kaelen toward `feet` (the same point if she is already closer).
static func feet_stop(feet: Vector3, kaelen: Vector3, gap: float) -> Vector3:
	var flat := Vector3(feet.x - kaelen.x, 0.0, feet.z - kaelen.z)
	if flat.length() <= gap:
		return feet
	var p := kaelen + flat.normalized() * gap
	return Vector3(p.x, feet.y, p.z)


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
				_turn_elysia_toward(hole, ELYSIA_LOOK_TIME)
		&"come_down":
			player.face_point(_elysia.global_position if _elysia else player.global_position)
			_come_down(player)
		&"embrace":
			_quake(player, 1.3)
			_lean_in(player)
			_embrace(player)


## A tremor: camera kick and dust (EndingRoom.kick), Kaelen's hurt stagger, Elysia's sway.
func _quake(player: Player, strength: float) -> void:
	get_tree().call_group(EndingRoom.GROUP, &"kick", QUAKE_KICK * strength, QUAKE_TIME)
	player.call(&"_play_action", &"hurt")
	if _elysia:
		var tilt := create_tween()
		tilt.tween_method(_set_lean, _elysia.rotation.x, -STAGGER_TILT * strength, STAGGER_TIME * 0.4) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tilt.tween_method(_set_lean, -STAGGER_TILT * strength, 0.0, STAGGER_TIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Floor point under the middle of her body, in her local space (the pivot of her turns and leans).
func _pivot_local() -> Vector3:
	return Vector3(_elysia_center_local.x, 0.0, _elysia_center_local.z)


## Puts her origin at `p` (upright); a lean is added so it pivots about her feet, not about her origin
## (which is a metre away from her body: leaning about it would sway the whole body).
func _set_elysia_origin(p: Vector3) -> void:
	if _elysia == null or not is_instance_valid(_elysia):
		return
	_elysia_origin = p
	var pivot := _pivot_local()
	_elysia.global_position = p + Basis(Vector3.UP, _elysia.rotation.y) * pivot - _elysia.basis * pivot


func _set_lean(angle: float) -> void:
	if _elysia and is_instance_valid(_elysia):
		_elysia.rotation.x = angle
		_set_elysia_origin(_elysia_origin)


## Floor point under her body now (where her feet are).
func _body_floor() -> Vector3:
	return _elysia_origin + Basis(Vector3.UP, _elysia.rotation.y) * _pivot_local()


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
	_elysia_busy = true
	_turn_elysia_toward(player.global_position)
	_beat_tween = create_tween()
	_beat_tween.tween_interval(ELYSIA_TURN_TIME)
	_beat_tween.tween_callback(_start_walk.bind(player))


## She walks slowly to Kaelen and, when she gets there, opens her arms to him.
func _start_walk(player: Player) -> void:
	if _elysia == null or not is_inside_tree():
		return
	var from := _body_floor()
	var to := feet_stop(from, player.global_position, ELYSIA_REACH_GAP)
	_play_elysia(&"walk")
	_beat_tween = create_tween()
	_beat_tween.tween_method(_place_on_arc.bind(from, to), 0.0, 1.0, STEP_DOWN_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_beat_tween.tween_callback(_play_elysia.bind(&"reach"))


## Moves her so the floor point under her body goes from `from` to `to` (t = 0..1), at the height of whatever
## she stands on (the altar step or the floor).
func _place_on_arc(t: float, from: Vector3, to: Vector3) -> void:
	if _elysia == null or not is_instance_valid(_elysia):
		return
	var feet := from.lerp(to, t)
	feet.y = _feet_height(feet)
	_set_elysia_origin(feet - Basis(Vector3.UP, _elysia.rotation.y) * _pivot_local())


## Height of the ground under `p`: the altar step's top while inside it, Kaelen's floor beyond it.
func _feet_height(p: Vector3) -> float:
	var floor_y := _kaelen.global_position.y if _kaelen else 0.0
	var step := get_parent().find_child("AltarStep", true, false) as CSGBox3D if get_parent() else null
	if step == null:
		return floor_y
	var half := step.size * 0.5
	var local := p - step.global_position
	var outside := maxf(absf(local.x) - half.x, absf(local.z) - half.z)
	return lerpf(step.global_position.y + half.y, floor_y, clampf(outside / STEP_DROP_LENGTH, 0.0, 1.0))


func _lean_in(player: Player) -> void:
	var model := player.get_node_or_null(^"Model") as Node3D
	var lean := create_tween().set_parallel(true)
	if model:
		lean.tween_property(model, "rotation:x", EMBRACE_LEAN, EMBRACE_TIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _elysia:
		lean.tween_method(_set_lean, _elysia.rotation.x, EMBRACE_LEAN, EMBRACE_TIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## The embrace: Elysia steps in to HUG_GAP, Kaelen's arms close around her (HugArms) and the greatsword
## leaves her hand. Elysia has no rig, so she only leans in and moves; the arms are Kaelen's.
func _embrace(player: Player) -> void:
	if _elysia == null:
		return
	_elysia_busy = true
	if _beat_tween and _beat_tween.is_valid():
		_beat_tween.kill()   # the walk ends here: she steps into his arms from wherever she is
	_play_elysia(&"hug")
	var from := _body_floor()
	var to := feet_stop(from, player.global_position, HUG_BODY_GAP)
	var toward := Vector3(to.x - player.global_position.x, 0.0, to.z - player.global_position.z).normalized()
	to += Vector3.UP.cross(toward) * HUG_HEAD_OFFSET
	var move := create_tween()
	move.tween_method(_place_on_arc.bind(from, to), 0.0, 1.0, HUG_MOVE_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var grip := player.get_node_or_null(SWORD_GRIP) as Node3D
	if grip:
		get_tree().create_timer(HUG_DROP_DELAY).timeout.connect(func() -> void:
			if is_instance_valid(grip):
				grip.visible = false)
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	if _hug == null or not is_instance_valid(_hug):   # (normally made by _relax_kaelen)
		_hug = HugArms.new()
		_hug.name = "HugArms"
		_hug.stance = true
		_hug.influence = 1.0
		skeleton.add_child(_hug)
	_hug.partner = _elysia
	_hug.center_local = _elysia_center_local
	_hug.hug_blend = 0.0
	var arms := create_tween()
	arms.tween_interval(HUG_ARMS_DELAY)
	arms.tween_property(_hug, "hug_blend", 1.0, HUG_ARMS_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## The held embrace after the last line: the camera backs away and rises slowly, looking at the couple.
func _hold_embrace(player: Player) -> void:
	_shot_active = false
	var cam := get_viewport().get_camera_3d()
	if cam == null or _elysia == null:
		return
	var focus := (player.global_position + _elysia.global_position) * 0.5 + Vector3.UP * 1.0
	var from := cam.global_position
	var away := from - focus
	away.y = 0.0
	var to := from + away.normalized() * HOLD_PULL_BACK + Vector3.UP * HOLD_RISE
	_hold_tween = create_tween()
	_hold_tween.tween_method(_pull_back.bind(cam, from, to, focus), 0.0, 1.0, HOLD_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _pull_back(t: float, cam: Camera3D, from: Vector3, to: Vector3, focus: Vector3) -> void:
	if cam and is_instance_valid(cam):
		cam.global_position = from.lerp(to, t)
		cam.look_at(focus, Vector3.UP)


## Kaelen stops being on guard: her arms hang, the greatsword's point rests on the floor beside her and
## she keeps her eyes on Elysia (HugArms in stance mode: it fades in, and at the embrace blends into the hug).
func _relax_kaelen(player: Player) -> void:
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or _elysia == null:
		return
	if _hug == null or not is_instance_valid(_hug):
		_hug = HugArms.new()
		_hug.name = "HugArms"
		_hug.stance = true
		skeleton.add_child(_hug)
	_hug.partner = _elysia
	_hug.center_local = _elysia_center_local
	_hug.hug_blend = 0.0
	_hug.influence = 0.0
	player.idle_anim_scale = STANCE_IDLE_SCALE
	create_tween().tween_property(_hug, "influence", 1.0, STANCE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Thick black fog over the room's door (the corridor behind Kaelen shows the dead boss and the arena): a
## black plug in the opening and soft black layers in front of it, so nothing beyond is ever seen.
func _build_entrance_fog() -> void:
	if _entrance_fog != null or _ending == null:
		return
	var door := get_parent().find_child("RoomDoor", true, false) as Node3D if get_parent() else null
	var size := Vector3(6.0, 4.0, 3.0)
	var center := Vector3.ZERO
	if door != null:
		center = door.global_position
		if door is CSGBox3D:
			size = (door as CSGBox3D).size
	elif _end_point != null:
		center = _end_point.global_position + Vector3(0.0, size.y * 0.5, 7.5)
	else:
		return
	_entrance_fog = Node3D.new()
	_entrance_fog.name = "EntranceFog"
	add_child(_entrance_fog)
	_entrance_fog.global_position = center
	var black := StandardMaterial3D.new()
	black.albedo_color = Color.BLACK
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var plug := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x + 0.6, size.y + 0.6, 0.5)
	plug.mesh = box
	plug.material_override = black
	_entrance_fog.add_child(plug)
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	fade.colors = PackedColorArray([Color(0, 0, 0, 1.0), Color(0, 0, 0, 0.85), Color(0, 0, 0, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = fade
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var soft := StandardMaterial3D.new()
	soft.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	soft.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	soft.albedo_texture = tex
	soft.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 4:
		var quad := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(size.x + 2.5 + i * 0.6, size.y + 2.0 + i * 0.4)
		quad.mesh = q
		quad.material_override = soft
		quad.position = Vector3(0.0, 0.0, -0.4 - i * 0.55)   # toward the room (north)
		_entrance_fog.add_child(quad)


## Starts the shot of line `index`: the camera follows `speaker` (&"" for narration) from now on.
func _begin_shot(index: int, speaker: StringName) -> void:
	if _dyn_cam == null:
		return
	_shot_kind = SHOT_KINDS[index] if index < SHOT_KINDS.size() else &"wide"
	_shot_speaker = speaker
	_shot_time = 0.0
	_shot_active = true
	_dyn_cam.global_transform = shot_transform(_shot_kind, 0.0, _kaelen_head(), _elysia_head(), speaker,
			_cam_1.global_position if _cam_1 else Vector3.ZERO)
	_dyn_cam.make_current()
	# Elysia talks with her hands while she speaks, and stands calmly while Kaelen does (until she walks).
	var appearing := _elysia_anim != null and _elysia_anim.current_animation == &"appear"
	if not _elysia_busy and not appearing:
		_play_elysia(&"talk" if speaker == &"elysia" else &"idle")


func _process(delta: float) -> void:
	if not _shot_active or _dyn_cam == null or _kaelen == null:
		return
	_shot_time += delta
	_dyn_cam.global_transform = shot_transform(_shot_kind, _shot_time, _kaelen_head(), _elysia_head(),
			_shot_speaker, _cam_1.global_position if _cam_1 else Vector3.ZERO)


func _kaelen_head() -> Vector3:
	return _kaelen.global_position + Vector3.UP * KAELEN_HEAD if _kaelen else Vector3.UP * KAELEN_HEAD


## Head of Elysia: above the middle of her body (her model origin is not her body).
func _elysia_head() -> Vector3:
	if _elysia == null:
		return Vector3.UP * ELYSIA_HEAD
	var c := _elysia.global_transform * _elysia_center_local
	return Vector3(c.x, _elysia.global_position.y + ELYSIA_HEAD, c.z)


## Camera transform of a shot `t` s after it began. `k` and `e` are the heads of Kaelen and Elysia;
## `speaker` (&"kaelen", &"elysia" or &"" for narration) decides who is in front of the lens; `wide_from` is where
## the wide shots start. Pure function (tests call it).
static func shot_transform(kind: StringName, t: float, k: Vector3, e: Vector3, speaker: StringName,
		wide_from: Vector3) -> Transform3D:
	var a := e if speaker == &"elysia" else k   # in front of the lens
	var b := k if speaker == &"elysia" else e   # the listener
	var flat := b - a
	flat.y = 0.0
	var d := flat.length()
	var dir := flat.normalized() if d > 0.01 else Vector3.BACK
	var side := dir.cross(Vector3.UP)
	if speaker == &"kaelen":
		side = -side   # her greatsword hangs on the other side: this keeps it out of her face shots
	var mid := (a + b) * 0.5
	var s := smoothstep(0.0, 1.0, clampf(t / SHOT_DRIFT_TIME, 0.0, 1.0))
	var front := clampf(d * 0.45, 0.8, 1.6)
	var pos := wide_from
	var look := mid
	match kind:
		&"face":
			pos = a + dir * (front - 0.3 * s) + side * 0.5 + Vector3.UP * 0.05
			look = a + Vector3.DOWN * 0.04
		&"side":
			pos = a + dir * front * 0.55 - side * (1.05 - 0.2 * s) + Vector3.UP * 0.1
			look = a + Vector3.DOWN * 0.04
		&"over":
			pos = b + dir * (0.8 - 0.1 * s) + side * (0.45 + 0.15 * s) + Vector3.UP * 0.1
			look = a
		&"low":
			pos = a + dir * front * 0.9 + side * (0.3 - 0.3 * s)
			pos.y = a.y - 0.8 + 0.25 * s
			look = a + Vector3.UP * 0.12
		&"profile":
			pos = mid + side * (2.7 - 0.5 * s) + Vector3.DOWN * 0.15
			look = mid + Vector3.DOWN * 0.1
		&"wide_high":
			pos = mid + side * (1.9 + 0.2 * s) + Vector3.UP * (0.55 + 0.15 * s) + dir * 0.3
			look = mid
		_:   # wide: the room from where EndingCam1 stands, creeping toward the couple
			pos = wide_from.lerp(mid + Vector3.UP * 0.9, 0.2 * s)
			look = mid + Vector3.UP * 0.1
	return Transform3D(Basis(), pos).looking_at(look, Vector3.UP)


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
	_build_entrance_fog()
	_kaelen = player
	_activate_camera(_cam_1)
	await get_tree().process_frame   # let the new transform and the idle pose reach the renderer
	await get_tree().process_frame
	actors_placed.emit()
	_play_elysia(&"appear", true)   # she shows up as the picture opens
	_tween_alpha(_overlay, 0.0, CUT_FADE_IN)
	if not await _wait(CUT_FADE_IN + LEAD_IN_TIME):
		return

	# Dialogue: each line is revealed by the typewriter and waits for the player to press. Every line has its
	# own shot (SHOT_KINDS) that follows whoever speaks and drifts slowly.
	_duck_music(MUSIC_DUCK_DB)
	_box.fade(1.0, BOX_FADE_IN)
	_relax_kaelen(player)
	for i in ENDING_LINES.size():
		var entry: Array = ENDING_LINES[i]
		var line := localized(entry[0])
		_begin_shot(i, Typewriter.speaker_of(line))
		_beat(i, player)
		if not await _say(line):
			return
	_box.fade(0.0, BOX_FADE_OUT)
	_duck_music(0.0)
	# They stay in the embrace while the camera pulls back and the island falls; then the fade to black.
	_hold_embrace(player)
	if not await _wait(HOLD_TIME):
		return
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
	if _elysia:
		_elysia_origin = _elysia.global_position   # (the level may have moved since _ready)
	if _end_point:
		player.global_position = _end_point.global_position
		player.velocity = Vector3.ZERO
	else:
		push_warning("EndingDirector: missing Ending/KaelenEndPoint; Kaelen stays where she is")
	if _elysia:
		player.face_point(elysia_pos)
		_turn_elysia_toward(player.global_position, 0.0)
	else:
		push_warning("EndingDirector: missing Ending/Elysia")


## Turns Elysia toward `target` about her own body (not about her origin, which is a metre away from it:
## that swung the whole model along a curve). time 0 turns at once.
func _turn_elysia_toward(target: Vector3, time := ELYSIA_TURN_TIME) -> void:
	var pivot := _body_floor()
	var from_yaw := _elysia.rotation.y
	var desired := yaw_toward(pivot, target, from_yaw) + ELYSIA_FRONT_YAW_OFFSET
	var goal := from_yaw + angle_difference(from_yaw, desired)
	if time <= 0.0:
		_turn_step(goal, pivot)
		return
	if _turn_tween and _turn_tween.is_valid():
		_turn_tween.kill()   # a new turn replaces the one in progress
	_turn_tween = create_tween()
	_turn_tween.tween_method(_turn_step.bind(pivot), from_yaw, goal, time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _turn_step(yaw: float, pivot: Vector3) -> void:
	if _elysia and is_instance_valid(_elysia):
		_elysia.rotation.y = yaw
		_set_elysia_origin(pivot - Basis(Vector3.UP, yaw) * _pivot_local())


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
