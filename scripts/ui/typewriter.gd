class_name Typewriter
extends Node
## Revela el texto de un Label letra a letra (visible_characters) con voz por hablante, estilo Undertale.
##
## - Velocidad base CHARS_PER_SECOND, con pausas cortas tras la puntuación (, ; : y . ! ? …).
## - Suena un blip cada BLIP_EVERY letras "habladas" (se saltan espacios, puntuación y comillas).
## - El hablante sale del prefijo de cada línea ("Kaelen:" / "Elysia:"); sin prefijo es narrador y no suena.
## - El prefijo ("Kaelen:") se muestra de golpe y sin blips.
## - Dos AudioStreamPlayer que se alternan: cada blip nuevo corta el anterior sin chasquido.
## - Entrada: `attack` (clic / botón de ataque), `ui_accept` (Enter, Espacio, A del mando). Mientras se
##   revela completa la línea al instante; con la línea completa emite `advanced` (el que espera, por
##   ejemplo el EndingDirector, pasa al siguiente texto). Nada avanza solo por tiempo.
## - Anti doble salto: tras empezar o completar una línea se ignoran (y se consumen) las pulsaciones
##   durante ADVANCE_LOCK_MS, y una pulsación solo emite `advanced` una vez.
## Toda la planificación (qué letras suenan, pausas, hablante) son funciones estáticas puras.

signal finished   ## el texto quedó completo (por tiempo o por skip)
signal advanced   ## con el texto ya completo, el jugador pulsó avanzar
signal blip_played(speaker: StringName)

const CHARS_PER_SECOND := 30.0
const BLIP_EVERY := 2
const PAUSE_SHORT := 0.12   ## , ; :
const PAUSE_LONG := 0.28    ## . ! ? …
const ADVANCE_ACTIONS: Array[StringName] = [&"attack", &"ui_accept"]
const ADVANCE_LOCK_MS := 150
const BLIP_BUS := &"UI"
## Valor de `speaker` que significa "detectar el hablante por el prefijo del texto".
const AUTO := &"auto"

const SPEAKERS: Array[String] = ["Kaelen", "Elysia"]
const SHORT_PAUSE_CHARS := ",;:"
const LONG_PAUSE_CHARS := ".!?…"
const QUOTE_CHARS := "\"'“”«»¿¡"

## Voces: Kaelen grave (~300-400 Hz), Elysia aguda (~700-800 Hz). Los blips son del pack de dmochas,
## normalizados a -3 dBFS de pico con scripts/tools/make_dialogue_blips.py (ver assets/credits.txt).
## Los originales llegaban a -23 dBFS y con -12/-15 dB de volumen quedaban 22 dB por debajo de los
## sonidos de interfaz (pico medido en el bus UI: -33 dB frente a -10 dB), es decir, inaudibles.
const VOICE_DEFS := {
	&"kaelen": {
		"files": ["kaelen_1", "kaelen_2", "kaelen_3"],
		"pitch": 0.9, "random_pitch": 1.06, "volume_db": -4.0,
	},
	&"elysia": {
		"files": ["elysia_1", "elysia_2", "elysia_3"],
		"pitch": 1.12, "random_pitch": 1.06, "volume_db": -7.0,
	},
}
const VOICE_DIR := "res://assets/audio/sfx/dialogue/"

## speaker (StringName) -> {stream: AudioStream, pitch: float, volume_db: float}
var voices: Dictionary = {}

var _label: Label
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _unlock_at_ms := 0
var _speaker: StringName = AUTO
var _schedule: Dictionary = {}
var _elapsed := 0.0
var _blip_cursor := 0
var _revealing := false
var _complete := false


# --- Lógica pura ---------------------------------------------------------------------------

## Hablante de una línea según su prefijo; &"" si es narrador.
static func speaker_of(line: String) -> StringName:
	for speaker_name in SPEAKERS:
		if line.begins_with(speaker_name + ":"):
			return StringName(speaker_name.to_lower())
	return &""


## Caracteres del prefijo "Nombre:" más los espacios que lo siguen (0 si no hay hablante).
static func prefix_length(line: String) -> int:
	for speaker_name in SPEAKERS:
		if line.begins_with(speaker_name + ":"):
			var n := speaker_name.length() + 1
			while n < line.length() and line[n] == " ":
				n += 1
			return n
	return 0


## true si el carácter puede disparar blip: letra o dígito (no espacio, puntuación ni comillas).
static func is_voiced(c: String) -> bool:
	if c.is_empty() or c.strip_edges().is_empty():
		return false
	if SHORT_PAUSE_CHARS.contains(c) or LONG_PAUSE_CHARS.contains(c) or QUOTE_CHARS.contains(c):
		return false
	var code := c.unicode_at(0)
	# Letras (incluye acentos) y dígitos; el resto de símbolos no suenan.
	return (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code >= 192


## true si la letra número `voiced_index` (0, 1, 2…) de una línea debe sonar: la 1ª, 3ª, 5ª...
static func should_blip(voiced_index: int) -> bool:
	return voiced_index % BLIP_EVERY == 0


## Pausa (s) tras el carácter `i`: solo al final de una racha de puntuación ("..." pausa una vez).
static func pause_after(text: String, i: int) -> float:
	var c := text[i]
	var pause := 0.0
	if LONG_PAUSE_CHARS.contains(c):
		pause = PAUSE_LONG
	elif SHORT_PAUSE_CHARS.contains(c):
		pause = PAUSE_SHORT
	if pause == 0.0:
		return 0.0
	var j := i + 1
	while j < text.length() and QUOTE_CHARS.contains(text[j]):
		j += 1
	if j < text.length() and (LONG_PAUSE_CHARS.contains(text[j]) or SHORT_PAUSE_CHARS.contains(text[j])):
		return 0.0
	return pause


## Planifica la revelación: {times: PackedFloat32Array (instante en que cada carácter pasa a ser
## visible), blips: Array[{time, index, speaker}], duration: float}.
## Con `forced_speaker` distinto de AUTO todo el texto es cuerpo de ese hablante (&"" = narrador).
static func build_schedule(text: String, forced_speaker: StringName = AUTO) -> Dictionary:
	var times := PackedFloat32Array()
	var blips: Array[Dictionary] = []
	var t := 0.0
	var speaker: StringName = &""
	var body_start := 0
	var voiced := 0
	for i in text.length():
		if i == 0 or text[i - 1] == "\n":
			var end := text.find("\n", i)
			var line := text.substr(i) if end < 0 else text.substr(i, end - i)
			if forced_speaker == AUTO:
				speaker = speaker_of(line)
				body_start = i + prefix_length(line)
			else:
				speaker = forced_speaker
				body_start = i
			voiced = 0
		var c := text[i]
		var in_body := i >= body_start and c != "\n"
		if in_body:
			t += 1.0 / CHARS_PER_SECOND
		times.append(t)
		if in_body and is_voiced(c):
			if speaker != &"" and should_blip(voiced):
				blips.append({"time": t, "index": i, "speaker": speaker})
			voiced += 1
		if in_body:
			t += pause_after(text, i)
	return {"times": times, "blips": blips, "duration": t}


## Duración (s) de la revelación completa de un texto.
static func reveal_duration(text: String) -> float:
	return float(build_schedule(text)["duration"])


## Cuántos caracteres son visibles al cabo de `elapsed` s según el plan.
static func visible_count(times: PackedFloat32Array, elapsed: float) -> int:
	var n := 0
	while n < times.size() and times[n] <= elapsed:
		n += 1
	return n


## Voces por defecto: un AudioStreamRandomizer por hablante con sus blips y pitch aleatorio leve.
static func default_voices() -> Dictionary:
	var out := {}
	for speaker in VOICE_DEFS:
		var def: Dictionary = VOICE_DEFS[speaker]
		var randomizer := AudioStreamRandomizer.new()
		randomizer.random_pitch = def["random_pitch"]
		randomizer.random_volume_offset_db = 1.5
		var count := 0
		for file_name in def["files"]:
			var stream := load(VOICE_DIR + file_name + ".ogg") as AudioStream
			if stream:
				randomizer.add_stream(-1, stream, 1.0)
				count += 1
		if count > 0:
			out[speaker] = {"stream": randomizer, "pitch": def["pitch"], "volume_db": def["volume_db"]}
	return out


# --- Runtime -------------------------------------------------------------------------------

func _ready() -> void:
	set_process(false)
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = BLIP_BUS
		add_child(player)
		_players.append(player)
	if voices.is_empty():
		voices = default_voices()


## Empieza a revelar `text` en `label` (visible_characters = 0). `speaker` fija la voz (&"" = narrador);
## con AUTO se detecta por el prefijo "Kaelen:" / "Elysia:".
func start(label: Label, text: String, speaker: StringName = AUTO) -> void:
	_label = label
	_label.text = text
	_label.visible_characters = 0
	_speaker = speaker
	_schedule = build_schedule(text, speaker)
	_lock_input()
	_elapsed = 0.0
	_blip_cursor = 0
	_complete = false
	_revealing = true
	set_process(true)
	_apply_progress()


func is_revealing() -> bool:
	return _revealing


## true con la línea completa esperando a que el jugador avance.
func is_waiting() -> bool:
	return _complete


## true si el evento es una pulsación de avanzar (ataque, aceptar o clic izquierdo; sin eco).
static func is_advance_event(event: InputEvent) -> bool:
	if event.is_echo() or not event.is_pressed():
		return false
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	for action in ADVANCE_ACTIONS:
		if event.is_action_pressed(action):
			return true
	return false


## true si ya pasó el bloqueo de entrada (`now_ms` >= `unlock_at_ms`).
static func input_open(now_ms: int, unlock_at_ms: int) -> bool:
	return now_ms >= unlock_at_ms


func _lock_input() -> void:
	_unlock_at_ms = Time.get_ticks_msec() + ADVANCE_LOCK_MS


## Procesa una pulsación de avanzar (también la usan las pruebas): completa, pasa o ignora.
## Devuelve true si hizo algo.
func press_advance() -> bool:
	if not (_revealing or _complete) or not input_open(Time.get_ticks_msec(), _unlock_at_ms):
		return false
	if _revealing:
		_complete_text()
	else:
		_complete = false
		_lock_input()
		advanced.emit()
	return true


## Completa el texto al instante, sin blips.
func skip() -> void:
	if _revealing:
		_complete_text()


func _process(delta: float) -> void:
	if not _revealing:
		return
	_elapsed += delta
	_apply_progress()


func _apply_progress() -> void:
	var times: PackedFloat32Array = _schedule["times"]
	var shown := visible_count(times, _elapsed)
	if _label:
		_label.visible_characters = shown
	var blips: Array = _schedule["blips"]
	var last_due := -1
	while _blip_cursor < blips.size() and float(blips[_blip_cursor]["time"]) <= _elapsed:
		last_due = _blip_cursor
		_blip_cursor += 1
	if last_due >= 0:
		_play_blip(blips[last_due]["speaker"])   # si se acumuló más de uno solo suena el último
	if shown >= times.size():
		_complete_text()


func _complete_text() -> void:
	_revealing = false
	_complete = true
	_lock_input()
	set_process(false)
	if _label:
		_label.visible_characters = -1
	finished.emit()


func _play_blip(speaker: StringName) -> void:
	var voice: Dictionary = voices.get(speaker, {})
	if voice.is_empty() or _players.is_empty():
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = voice["stream"]
	player.pitch_scale = voice["pitch"]
	player.volume_db = voice["volume_db"]
	player.play()   # el otro reproductor termina su cola sin cortarse en seco
	blip_played.emit(speaker)


func _input(event: InputEvent) -> void:
	if not (_revealing or _complete) or not is_advance_event(event):
		return
	get_viewport().set_input_as_handled()   # una pulsación nunca llega a nadie más ni salta dos líneas
	press_advance()
