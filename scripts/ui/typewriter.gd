class_name Typewriter
extends Node
## Reveals a Label's text letter by letter (visible_characters) with a per-speaker voice, Undertale style.
##
## - Base speed CHARS_PER_SECOND, with short pauses after punctuation (, ; : and . ! ? ...).
## - A blip plays every BLIP_EVERY "spoken" letters (spaces, punctuation and quotes are skipped).
## - The speaker comes from each line's prefix ("Kaelen:" / "Elysia:"); no prefix means narrator, silent.
## - The prefix ("Kaelen:") is shown at once and without blips.
## - Two AudioStreamPlayers alternate: each new blip cuts the previous one without a click.
## - Input: `attack` (click / attack button), `ui_accept` (Enter, Space, gamepad A). While revealing,
##   a press completes the line instantly; with the line complete it emits `advanced` (whoever waits,
##   e.g. the EndingDirector, moves on to the next text). Nothing advances by time alone.
## - Anti double skip: after starting or completing a line, presses are ignored (and consumed) for
##   ADVANCE_LOCK_MS, and one press emits `advanced` only once.
## All the planning (which letters sound, pauses, speaker) is pure static functions.

signal finished   ## the text is complete (by time or by skip)
signal advanced   ## with the text already complete, the player pressed advance
signal blip_played(speaker: StringName)

const CHARS_PER_SECOND := 30.0
const BLIP_EVERY := 2
const PAUSE_SHORT := 0.12   ## , ; :
const PAUSE_LONG := 0.28    ## . ! ? …
const ADVANCE_ACTIONS: Array[StringName] = [&"attack", &"ui_accept"]
const ADVANCE_LOCK_MS := 150
const BLIP_BUS := &"UI"
## `speaker` value meaning "detect the speaker from the text prefix".
const AUTO := &"auto"

const SPEAKERS: Array[String] = ["Kaelen", "Elysia"]
const SHORT_PAUSE_CHARS := ",;:"
const LONG_PAUSE_CHARS := ".!?…"
const QUOTE_CHARS := "\"'“”«»¿¡"

## Voices: Kaelen low (~300-400 Hz), Elysia high (~700-800 Hz). The blips come from the dmochas pack,
## normalised to -3 dBFS peak with scripts/tools/make_dialogue_blips.py (see assets/credits.txt).
## The originals peaked at -23 dBFS and with -12/-15 dB of volume sat 22 dB below the interface
## sounds (peak measured on the UI bus: -33 dB against -10 dB), i.e. inaudible.
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


# --- Pure logic ---------------------------------------------------------------------------

## Speaker of a line from its prefix; &"" for the narrator.
static func speaker_of(line: String) -> StringName:
	for speaker_name in SPEAKERS:
		if line.begins_with(speaker_name + ":"):
			return StringName(speaker_name.to_lower())
	return &""


## Characters of the "Name:" prefix plus the spaces after it (0 if there is no speaker).
static func prefix_length(line: String) -> int:
	for speaker_name in SPEAKERS:
		if line.begins_with(speaker_name + ":"):
			var n := speaker_name.length() + 1
			while n < line.length() and line[n] == " ":
				n += 1
			return n
	return 0


## true if the character can trigger a blip: letter or digit (not space, punctuation or quotes).
static func is_voiced(c: String) -> bool:
	if c.is_empty() or c.strip_edges().is_empty():
		return false
	if SHORT_PAUSE_CHARS.contains(c) or LONG_PAUSE_CHARS.contains(c) or QUOTE_CHARS.contains(c):
		return false
	var code := c.unicode_at(0)
	# Letters (accents included) and digits; other symbols are silent.
	return (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code >= 192


## true if the letter number `voiced_index` (0, 1, 2...) of a line must sound: the 1st, 3rd, 5th...
static func should_blip(voiced_index: int) -> bool:
	return voiced_index % BLIP_EVERY == 0


## Pause (s) after character `i`: only at the end of a punctuation run ("..." pauses once).
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


## Plans the reveal: {times: PackedFloat32Array (instant at which each character becomes visible),
## blips: Array[{time, index, speaker}], duration: float}.
## With a `forced_speaker` other than AUTO the whole text is that speaker's body (&"" = narrator).
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


## Duration (s) of the full reveal of a text.
static func reveal_duration(text: String) -> float:
	return float(build_schedule(text)["duration"])


## How many characters are visible after `elapsed` s according to the plan.
static func visible_count(times: PackedFloat32Array, elapsed: float) -> int:
	var n := 0
	while n < times.size() and times[n] <= elapsed:
		n += 1
	return n


## Default voices: one AudioStreamRandomizer per speaker with its blips and a slight random pitch.
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


## Starts revealing `text` in `label` (visible_characters = 0). `speaker` fixes the voice (&"" =
## narrator); with AUTO it is detected from the "Kaelen:" / "Elysia:" prefix.
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


## true with the line complete, waiting for the player to advance.
func is_waiting() -> bool:
	return _complete


## true if the event is an advance press (attack, accept or left click; no echo).
static func is_advance_event(event: InputEvent) -> bool:
	if event.is_echo() or not event.is_pressed():
		return false
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	for action in ADVANCE_ACTIONS:
		if event.is_action_pressed(action):
			return true
	return false


## true once the input lock has passed (`now_ms` >= `unlock_at_ms`).
static func input_open(now_ms: int, unlock_at_ms: int) -> bool:
	return now_ms >= unlock_at_ms


func _lock_input() -> void:
	_unlock_at_ms = Time.get_ticks_msec() + ADVANCE_LOCK_MS


## Handles an advance press (tests use it too): completes, advances or ignores.
## Returns true if it did something.
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


## Completes the text instantly, without blips.
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
	if is_instance_valid(_label):
		_label.visible_characters = shown
	var blips: Array = _schedule["blips"]
	var last_due := -1
	while _blip_cursor < blips.size() and float(blips[_blip_cursor]["time"]) <= _elapsed:
		last_due = _blip_cursor
		_blip_cursor += 1
	if last_due >= 0:
		_play_blip(blips[last_due]["speaker"])   # if several piled up only the last one sounds
	if shown >= times.size():
		_complete_text()


func _complete_text() -> void:
	_revealing = false
	_complete = true
	_lock_input()
	set_process(false)
	if is_instance_valid(_label):
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
	player.play()   # the other player finishes its tail without being cut dead
	blip_played.emit(speaker)


func _input(event: InputEvent) -> void:
	if not (_revealing or _complete) or not is_advance_event(event):
		return
	get_viewport().set_input_as_handled()   # a press never reaches anyone else nor skips two lines
	press_advance()
