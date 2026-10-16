extends Node
## Autoload "AudioManager": music with crossfades, 3D sound effects with pitch variation, UI sounds
## and music attenuation while paused.
##
## Buses (default_bus_layout.tres): Master -> Music / SFX / UI. It keeps processing while paused
## (PROCESS_MODE_ALWAYS): the music drops by PAUSE_MUSIC_DROP_DB and running 3D effects freeze.
## Any UI focus change (arrows, D-pad, stick, Tab) plays the "move" sound, and buttons (BaseButton)
## entering the tree get the confirm/back sounds automatically; `set_meta(&"ui_sound", &"back")` or
## `&"none"` on a button changes or mutes its press sound.

const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"
const BUS_UI := &"UI"

const DEFAULT_PITCH_VARIATION := 0.1   # ±10 % (spec §11)
const SFX_POOL_SIZE := 12
const SFX_UNIT_SIZE := 8.0             # metres at which a 3D effect plays at full volume
const SILENT_DB := -60.0
const PAUSE_MUSIC_DROP_DB := -10.0
const PAUSE_FADE_SPEED := 60.0         # dB/s at which the music drops or recovers when pausing
## A button does not sound on focus until this long after entering the tree (a menu's initial focus
## must stay silent).
const UI_FOCUS_GRACE_MS := 300
## After confirm/back the "move" sound is muted for this long (focus jumps when another panel opens
## and would cover the confirm sound).
const UI_CONFIRM_QUIET_MS := 180
const UI_POOL_SIZE := 4
## UI sounds are trimmed and normalised to a -6 dBFS peak (scripts/tools/make_ui_sounds.py).
const UI_VOLUME_DB := 0.0

const UI_MOVE := preload("res://assets/audio/sfx/ui/ui_move.wav")
const UI_CONFIRM := preload("res://assets/audio/sfx/ui/ui_confirm.wav")
const UI_BACK := preload("res://assets/audio/sfx/ui/ui_back.wav")
const UI_PAUSE_OPEN := preload("res://assets/audio/sfx/ui/pause_open.wav")
const UI_PAUSE_CLOSE := preload("res://assets/audio/sfx/ui/pause_close.wav")

var _music_players: Array[AudioStreamPlayer] = []
var _music_current: AudioStreamPlayer
var _music_tween: Tween
var _music_stopping := false
var _sfx_pool: Array[AudioStreamPlayer3D] = []
var _sfx_next := 0
var _sfx_paused := false
var _ui_players: Array[AudioStreamPlayer] = []
var _ui_last_confirm_ms := -100000
var _pause_drop_db := 0.0
var _duck_db := 0.0
var _duck_tween: Tween
var _rng := RandomNumberGenerator.new()


# --- Pure logic (unit-tested) -------------------------------------------------------------------

## Pitch factor for `variation` (0.1 = ±10 %) and a `roll` number in [-1, 1].
static func pitch_for(variation: float, roll: float) -> float:
	return 1.0 + clampf(roll, -1.0, 1.0) * maxf(variation, 0.0)


## Music attenuation (dB): PAUSE_MUSIC_DROP_DB while paused, 0 in play.
static func pause_target_db(paused: bool) -> float:
	return PAUSE_MUSIC_DROP_DB if paused else 0.0


## Index of the next pool player: a free one if any; if all are playing, the oldest one
## (round-robin from `cursor`). `busy` tells whether each player is playing.
static func pick_pool_slot(busy: Array[bool], cursor: int) -> int:
	var count := busy.size()
	if count == 0:
		return -1
	for i in count:
		var idx := (cursor + i) % count
		if not busy[idx]:
			return idx
	return cursor % count


## Bus index by name; -1 if it does not exist (tests, or a layout without that bus).
static func bus_index(bus: StringName) -> int:
	return AudioServer.get_bus_index(bus)


# --- Lifecycle ----------------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_MUSIC
		player.volume_db = SILENT_DB
		add_child(player)
		_music_players.append(player)
	_music_current = _music_players[0]
	for i in SFX_POOL_SIZE:
		var player3d := AudioStreamPlayer3D.new()
		player3d.bus = BUS_SFX
		player3d.unit_size = SFX_UNIT_SIZE
		add_child(player3d)
		_sfx_pool.append(player3d)
	for i in UI_POOL_SIZE:
		var ui_player := AudioStreamPlayer.new()
		ui_player.bus = BUS_UI
		ui_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(ui_player)
		_ui_players.append(ui_player)
	get_tree().node_added.connect(_on_node_added)
	get_viewport().gui_focus_changed.connect(_on_gui_focus_changed)
	# Buttons that were already in the tree (if this node is created late) get hooked too.
	_hook_existing(get_tree().root)


func _process(delta: float) -> void:
	var paused := get_tree().paused
	var target := pause_target_db(paused)
	if not is_equal_approx(_pause_drop_db, target):
		_pause_drop_db = move_toward(_pause_drop_db, target, PAUSE_FADE_SPEED * delta)
		refresh_music_bus()
	if paused != _sfx_paused:
		_sfx_paused = paused
		for player in _sfx_pool:
			player.stream_paused = paused


## The music volume is the one chosen in the options (UserSettings) plus the pause and duck offsets.
## Also called by UserSettings when the music slider moves, so those offsets are not lost.
func refresh_music_bus() -> void:
	var idx := bus_index(BUS_MUSIC)
	if idx < 0:
		return
	var settings := get_node_or_null(^"/root/UserSettings") if is_inside_tree() else null
	var base_db: float = settings.call(&"volume_db", BUS_MUSIC) if settings else 0.0
	AudioServer.set_bus_volume_db(idx, base_db + _pause_drop_db + _duck_db)


## Lowers the music by `db` dB (negative; 0 restores it) over `time` s, e.g. while the ending's blips
## play. It adds to the options volume and the pause offset.
func duck_music(db: float, time: float = 1.0) -> void:
	if _duck_tween and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	_duck_tween.tween_method(_set_duck, _duck_db, minf(db, 0.0), maxf(time, 0.01))


func _set_duck(db: float) -> void:
	_duck_db = db
	refresh_music_bus()


func get_duck_db() -> float:
	return _duck_db


## Drops any duck immediately (the scene that requested it is gone).
func clear_duck() -> void:
	if _duck_tween and _duck_tween.is_valid():
		_duck_tween.kill()
	_set_duck(0.0)


# --- Music --------------------------------------------------------------------------------------

## Switches the music with a crossfade of `fade_time` s. Does nothing if `stream` is already playing;
## with null it is the same as stop_music(fade_time).
func play_music(stream: AudioStream, fade_time: float = 1.0) -> void:
	if stream == null:
		stop_music(fade_time)
		return
	if _music_current.stream == stream and _music_current.playing and not _music_stopping:
		return
	_kill_music_tween()
	_music_stopping = false
	var outgoing := _music_current
	var incoming := _music_players[1] if outgoing == _music_players[0] else _music_players[0]
	incoming.stop()   # may still be fading out from an earlier change
	incoming.stream = stream
	incoming.volume_db = SILENT_DB if fade_time > 0.0 else 0.0
	incoming.play()
	_music_current = incoming
	if fade_time <= 0.0:
		outgoing.stop()
		return
	_music_tween = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	_music_tween.tween_property(incoming, "volume_db", 0.0, fade_time)
	if outgoing.playing:
		_music_tween.tween_property(outgoing, "volume_db", SILENT_DB, fade_time)
		_music_tween.chain().tween_callback(outgoing.stop)


## Fades the current music to silence over `fade_time` s and stops it.
func stop_music(fade_time: float = 1.0) -> void:
	_kill_music_tween()
	for player in _music_players:
		if player != _music_current:
			player.stop()
	if not _music_current.playing:
		return
	if fade_time <= 0.0:
		_music_current.stop()
		return
	_music_stopping = true
	_music_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	_music_tween.tween_property(_music_current, "volume_db", SILENT_DB, fade_time)
	_music_tween.tween_callback(_music_current.stop)


## How many music players are playing now (1 at rest, 2 only during a crossfade).
func playing_music_count() -> int:
	var count := 0
	for player in _music_players:
		if player.playing:
			count += 1
	return count


func get_current_music() -> AudioStream:
	return _music_current.stream if _music_current.playing and not _music_stopping else null


func _kill_music_tween() -> void:
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = null


# --- Effects ------------------------------------------------------------------------------------

## 3D effect at `position` with a random pitch of ±`pitch_variation`. Uses a fixed player pool
## (if all are playing it reuses the oldest). `volume_db` and `unit_size` are optional.
func play_sfx_3d(stream: AudioStream, position: Vector3, pitch_variation: float = DEFAULT_PITCH_VARIATION, \
		volume_db: float = 0.0, unit_size: float = SFX_UNIT_SIZE) -> void:
	if stream == null or _sfx_pool.is_empty():
		return
	var busy: Array[bool] = []
	for p in _sfx_pool:
		busy.append(p.playing)
	var slot := pick_pool_slot(busy, _sfx_next)
	_sfx_next = (slot + 1) % _sfx_pool.size()
	var player := _sfx_pool[slot]
	player.stop()
	player.stream = stream
	player.global_position = position
	player.pitch_scale = pitch_for(pitch_variation, _rng.randf_range(-1.0, 1.0))
	player.volume_db = volume_db
	player.unit_size = unit_size
	player.stream_paused = get_tree().paused
	player.play()


## Gives a button focus without the "move selection" sound (a menu's initial focus).
func grab_focus_silent(button: Control) -> void:
	button.set_meta(&"ui_added_ms", Time.get_ticks_msec())
	button.grab_focus()


## UI sound (keeps playing while paused).
func play_ui(stream: AudioStream) -> void:
	if stream == null:
		return
	var player := _ui_players[0]
	for candidate in _ui_players:
		if not candidate.playing:
			player = candidate
			break
	player.stream = stream
	player.volume_db = UI_VOLUME_DB
	player.play()


## true if any UI player is playing (tests and diagnostics).
func is_ui_playing() -> bool:
	for player in _ui_players:
		if player.playing:
			return true
	return false


# --- Buttons ------------------------------------------------------------------------------------

func _on_node_added(node: Node) -> void:
	var control := node as Control
	if control == null:
		return
	control.set_meta(&"ui_added_ms", Time.get_ticks_msec())
	if control is BaseButton:
		_hook_button(control as BaseButton)


func _hook_existing(node: Node) -> void:
	for child in node.get_children():
		if child is BaseButton:
			_hook_button(child as BaseButton)
		_hook_existing(child)


func _hook_button(button: BaseButton) -> void:
	if button.has_meta(&"ui_hooked"):
		return
	button.set_meta(&"ui_hooked", true)
	button.pressed.connect(_on_button_pressed.bind(button))
	button.mouse_entered.connect(_on_button_focus.bind(button))


## Single place for the focus sound: the viewport reports every focus change (keyboard, gamepad or
## code) whatever the control, regardless of when each button was hooked.
func _on_gui_focus_changed(control: Control) -> void:
	_on_button_focus(control)


func _on_button_pressed(button: BaseButton) -> void:
	if button.get_meta(&"ui_sound", &"confirm") != &"none":
		_ui_last_confirm_ms = Time.get_ticks_msec()
	match button.get_meta(&"ui_sound", &"confirm"):
		&"back":
			play_ui(UI_BACK)
		&"none":
			pass
		_:
			play_ui(UI_CONFIRM)


func _on_button_focus(control: Control) -> void:
	if control is BaseButton and (control as BaseButton).disabled:
		return
	if control.get_meta(&"ui_sound", &"") == &"silent_focus":
		return
	if Time.get_ticks_msec() - int(control.get_meta(&"ui_added_ms", 0)) < UI_FOCUS_GRACE_MS:
		return
	if Time.get_ticks_msec() - _ui_last_confirm_ms < UI_CONFIRM_QUIET_MS:
		return
	play_ui(UI_MOVE)
