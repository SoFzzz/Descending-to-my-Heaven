extends Node
## Autoload "AudioManager" (Tarea 17): música con fundido, efectos 3D con variación de tono, sonidos
## de interfaz y atenuación de la música durante la pausa.
##
## Buses (default_bus_layout.tres): Master → Music / SFX / UI. Sigue procesando en pausa
## (PROCESS_MODE_ALWAYS): la música baja PAUSE_MUSIC_DROP_DB y los efectos 3D en curso se congelan.
## Cualquier cambio de foco de la interfaz (flechas, D-pad, stick, Tab) suena como "mover" y los
## botones (BaseButton) que entran al árbol reciben solos los sonidos de confirmar/volver;
## `set_meta(&"ui_sound", &"back")` o `&"none"` en un botón cambia o anula el de pulsar.

const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"
const BUS_UI := &"UI"

const DEFAULT_PITCH_VARIATION := 0.1   # ±10 % (spec §11)
const SFX_POOL_SIZE := 12
const SFX_UNIT_SIZE := 8.0             # m a los que un efecto 3D suena a volumen pleno
const SILENT_DB := -60.0
const PAUSE_MUSIC_DROP_DB := -10.0
const PAUSE_FADE_SPEED := 60.0         # dB/s con que la música baja o sube al pausar
## Un botón no suena al recibir foco hasta pasado este tiempo desde que entró al árbol (el foco inicial
## de un menú no debe sonar).
const UI_FOCUS_GRACE_MS := 300
## Tras confirmar/volver no suena "mover" durante este tiempo (el foco salta al abrir otro panel y
## taparia el sonido de confirmar).
const UI_CONFIRM_QUIET_MS := 180
const UI_POOL_SIZE := 4
## Los sonidos de interfaz se recortan y normalizan a -6 dBFS de pico (scripts/tools/make_ui_sounds.py).
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
var _ui_players: Array[AudioStreamPlayer] = []
var _ui_last_confirm_ms := -100000
var _pause_drop_db := 0.0
var _duck_db := 0.0
var _duck_tween: Tween
var _rng := RandomNumberGenerator.new()


# --- Lógica pura (con pruebas) ------------------------------------------------------------------

## Factor de tono para `variation` (0.1 = ±10 %) y un número `roll` en [-1, 1].
static func pitch_for(variation: float, roll: float) -> float:
	return 1.0 + clampf(roll, -1.0, 1.0) * maxf(variation, 0.0)


## Atenuación (dB) de la música: PAUSE_MUSIC_DROP_DB en pausa, 0 en juego.
static func pause_target_db(paused: bool) -> float:
	return PAUSE_MUSIC_DROP_DB if paused else 0.0


## Índice del siguiente reproductor del pool: uno libre si lo hay; si todos suenan, el más antiguo
## (round-robin desde `cursor`). `busy` dice si cada reproductor está sonando.
static func pick_pool_slot(busy: Array[bool], cursor: int) -> int:
	var count := busy.size()
	if count == 0:
		return -1
	for i in count:
		var idx := (cursor + i) % count
		if not busy[idx]:
			return idx
	return cursor % count


## Índice de bus por nombre; -1 si no existe (pruebas, o un layout sin ese bus).
static func bus_index(bus: StringName) -> int:
	return AudioServer.get_bus_index(bus)


# --- Ciclo de vida ------------------------------------------------------------------------------

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
	# Los botones que ya estaban en el árbol (si este nodo se crea tarde) también se enganchan.
	_hook_existing(get_tree().root)


func _process(delta: float) -> void:
	var paused := get_tree().paused
	var target := pause_target_db(paused)
	if not is_equal_approx(_pause_drop_db, target):
		_pause_drop_db = move_toward(_pause_drop_db, target, PAUSE_FADE_SPEED * delta)
		_apply_music_bus()
	for player in _sfx_pool:
		if player.stream_paused != paused:
			player.stream_paused = paused


## El volumen de la música es el elegido en opciones (UserSettings) más el descuento de la pausa.
func _apply_music_bus() -> void:
	var idx := bus_index(BUS_MUSIC)
	if idx < 0:
		return
	var settings := get_node_or_null(^"/root/UserSettings")
	var base_db: float = settings.call(&"volume_db", BUS_MUSIC) if settings else 0.0
	AudioServer.set_bus_volume_db(idx, base_db + _pause_drop_db + _duck_db)


## Baja la música `db` dB (negativo; 0 la devuelve) en `time` s, p. ej. mientras suenan los blips del
## final. Se suma al volumen de opciones y al descuento de la pausa.
func duck_music(db: float, time: float = 1.0) -> void:
	if _duck_tween and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	_duck_tween.tween_method(_set_duck, _duck_db, minf(db, 0.0), maxf(time, 0.01))


func _set_duck(db: float) -> void:
	_duck_db = db
	_apply_music_bus()


func get_duck_db() -> float:
	return _duck_db


# --- Música -------------------------------------------------------------------------------------

## Cambia la música con un fundido cruzado de `fade_time` s. Si `stream` ya suena no hace nada;
## con null equivale a stop_music(fade_time).
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


## Baja la música actual hasta el silencio en `fade_time` s y la detiene.
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


## Cuántos reproductores de música suenan ahora (1 en reposo, 2 solo durante un fundido cruzado).
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


# --- Efectos ------------------------------------------------------------------------------------

## Efecto 3D en `position` con tono aleatorio ±`pitch_variation`. Usa un pool fijo de reproductores
## (si todos suenan, reutiliza el más antiguo). `volume_db` y `unit_size` son opcionales.
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


## Da foco a un botón sin que suene el "mover selección" (foco inicial de un menú).
func grab_focus_silent(button: Control) -> void:
	button.set_meta(&"ui_added_ms", Time.get_ticks_msec())
	button.grab_focus()


## Sonido de interfaz (sigue sonando en pausa).
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


## true si algun reproductor de interfaz suena (pruebas y diagnostico).
func is_ui_playing() -> bool:
	for player in _ui_players:
		if player.playing:
			return true
	return false


# --- Botones ------------------------------------------------------------------------------------

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


## Un solo punto para el sonido de foco: el viewport avisa de todo cambio de foco (teclado, mando o
## código) sea cual sea el control, sin depender de cuándo se enganchó cada botón.
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
