extends Node
## Autoload "GameState": run progress and every scene change.
##
## Two distinct indices:
## - `scene_index` (0..3): position in LEVEL_SCENES. 0 = exterior, 1..3 = arenas 1..3.
## - `current_level` (0..2, per the contract): max-health level (MAX_HP_BY_LEVEL). It drops after each
##   boss: exterior and arena 1 -> 0 (100), arena 2 -> 1 (70), arena 3 -> 2 (40). See level_for_scene().
##
## On start (outside the tests) it creates as its own children the transition (fade), the pause menu,
## the death screen and the debug overlay (F3/F5; only acts with Kaelen in the scene). Being children
## of an autoload they survive scene changes and exist in every playable scene without editing the
## level scenes.

const MAX_HP_BY_LEVEL: Array[int] = [100, 70, 40]
## The ending takes place inside arena_3 (corridor and Elysia's room).
const LEVEL_SCENES: Array[String] = [
	"res://scenes/levels/exterior_gameplay.tscn",
	"res://scenes/levels/arena_1_gameplay.tscn",
	"res://scenes/levels/arena_2_gameplay.tscn",
	"res://scenes/levels/arena_3_gameplay.tscn",
]
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const CREDITS_SCENE := "res://scenes/ui/credits.tscn"
const TRANSITION_SCENE := "res://scenes/ui/transition.tscn"
const PAUSE_MENU_SCENE := "res://scenes/ui/pause_menu.tscn"
const DEATH_SCREEN_SCENE := "res://scenes/ui/death_screen.tscn"
const DEBUG_OVERLAY_SCENE := "res://scenes/ui/debug_overlay.tscn"

## Title card of each scene entered with a transition: [title key, subtitle key] (translations.csv).
## Plain scenes (menu, credits) have none.
const SCENE_CARDS := {
	"res://scenes/levels/exterior_gameplay.tscn": ["TRANS_ZONE_0", "TRANS_SUB_0"],
	"res://scenes/levels/arena_1_gameplay.tscn": ["TRANS_FLOOR_1", "TRANS_SUB_1"],
	"res://scenes/levels/arena_2_gameplay.tscn": ["TRANS_FLOOR_2", "TRANS_SUB_2"],
	"res://scenes/levels/arena_3_gameplay.tscn": ["TRANS_FLOOR_3", "TRANS_SUB_3"],
}

## Set by reload_current_arena for the duration of its _change_scene call.
var _quick_next := false
## Scene being loaded in a background thread (preload_scene): the next change to it is instant.
var _preloading := ""
## Set by advance_level: the next arena opens with Kaelen walking in from its entry stairs (a retry
## does not). ArenaGameplay reads and clears it.
var arrival_walk := false
## Set by start_new_game: the exterior opens with the intro (IntroDirector reads and clears it).
var intro_pending := false

var current_level: int = 0   # 0, 1, 2
var scene_index: int = 0     # 0 = exterior, 1..3 = arenas
## Last path requested from _change_scene (for tests and debugging).
var last_requested_scene: String = ""
## true during a directed sequence (the arena 3 ending): pausing is not allowed. Cleared on scene
## change.
var cutscene_active := false

var transition: Node = null
var pause_menu: Node = null
var death_screen: Node = null
var debug_overlay: Node = null


func _ready() -> void:
	transition = _add_ui(TRANSITION_SCENE)
	pause_menu = _add_ui(PAUSE_MENU_SCENE)
	death_screen = _add_ui(DEATH_SCREEN_SCENE)
	debug_overlay = _add_ui(DEBUG_OVERLAY_SCENE)


func _add_ui(path: String) -> Node:
	if not ResourceLoader.exists(path):
		push_warning("GameState: missing %s" % path)
		return null
	var node := (load(path) as PackedScene).instantiate()
	add_child(node)
	return node


func get_player_max_hp() -> int:
	return MAX_HP_BY_LEVEL[clampi(current_level, 0, MAX_HP_BY_LEVEL.size() - 1)]


## Path of the playable scene for a scene index (0 = exterior, 1..3 = arenas); "" if there is none.
func scene_for_level(level: int) -> String:
	if level < 0 or level >= LEVEL_SCENES.size():
		return ""
	return LEVEL_SCENES[level]


## Max-health level (current_level) that matches a scene index.
func level_for_scene(index: int) -> int:
	return clampi(index - 1, 0, MAX_HP_BY_LEVEL.size() - 1)


## Starts loading `path` in a background thread: the following change to it does not stall the
## frame (change_scene_to_file loads the whole level at once). Safe to call more than once.
func preload_scene(path: String) -> void:
	if path.is_empty() or path == _preloading or not ResourceLoader.exists(path):
		return
	if ResourceLoader.load_threaded_request(path) == OK:
		_preloading = path


## Preloads whatever advance_level() will open next (the next floor, or the credits after arena 3).
func preload_next_level() -> void:
	var next := scene_index + 1
	preload_scene(scene_for_level(next) if next < LEVEL_SCENES.size() else CREDITS_SCENE)


## Starts a new run at the exterior. Returns false if the scene change could not start.
func start_new_game() -> bool:
	arrival_walk = false
	intro_pending = true
	if not _change_scene(scene_for_level(0)):
		return false
	_set_scene_index(0)
	return true


## After boss_defeated: next arena; from arena 3, the ending (credits or, if missing, the main menu).
func advance_level() -> void:
	var next := scene_index + 1
	if next >= LEVEL_SCENES.size():
		_change_scene(CREDITS_SCENE if ResourceLoader.exists(CREDITS_SCENE) else MAIN_MENU_SCENE)
		return
	arrival_walk = next >= 1   # every arena opens with Kaelen walking in up its entry stairs
	if _change_scene(scene_for_level(next)):
		_set_scene_index(next)
	else:
		arrival_walk = false


## Respawn after dying: reloads the current scene (new Kaelen, boss at full health, no leftover
## minions). Max health does not change: Kaelen calls health.reset(get_player_max_hp()).
func reload_current_arena() -> void:
	var path := _current_scene_path()
	var index := LEVEL_SCENES.find(path)
	arrival_walk = false
	_quick_next = true   # retrying: short fade, no title card
	var changed := _change_scene(path)
	_quick_next = false
	if changed and index >= 0:
		scene_index = index


func go_to_main_menu() -> void:
	arrival_walk = false
	_change_scene(MAIN_MENU_SCENE)


## true if there is no fade in progress, death screen or directed sequence (the pause menu asks this).
func can_pause() -> bool:
	if cutscene_active:
		return false
	if transition and transition.call(&"is_busy"):
		return false
	if death_screen and death_screen.call(&"is_active"):
		return false
	return true


## Translated [title, subtitle] of the card shown when entering `path`; [] if it has none.
func card_for_scene(path: String) -> Array[String]:
	var keys: Array = SCENE_CARDS.get(path, [])
	if keys.is_empty():
		return []
	return [tr(keys[0]), tr(keys[1])]


func _set_scene_index(index: int) -> void:
	scene_index = index
	current_level = level_for_scene(index)


func _current_scene_path() -> String:
	if is_inside_tree():
		var scene := get_tree().current_scene
		if scene and not scene.scene_file_path.is_empty():
			return scene.scene_file_path
	return scene_for_level(scene_index)


## Requests a scene change with a fade. Returns false (and does not change) if the scene does not
## exist or a fade is already running. Tests replace it so no scene is actually changed.
func _change_scene(path: String) -> bool:
	last_requested_scene = path
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("GameState: scene '%s' does not exist; not changing" % path)
		return false
	if not is_inside_tree():
		return false
	if transition and transition.call(&"is_busy"):
		return false
	if transition:
		var card := card_for_scene(path)
		if card.is_empty() or _quick_next:
			transition.call(&"fade_to", path, "", "", _quick_next)
		else:
			transition.call(&"fade_to", path, card[0], card[1])
	else:
		_swap_scene(path)
	return true


## Immediate change plus cleanup of the global state. The transition calls it with the screen black.
func _swap_scene(path: String) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	cutscene_active = false
	var tokens := get_node_or_null(^"/root/AttackTokens")
	if tokens:
		tokens.call(&"reset")
	var orchestrator := get_node_or_null(^"/root/Orchestrator")
	if orchestrator:
		orchestrator.call(&"end_arena")
	var audio := get_node_or_null(^"/root/AudioManager")
	if audio:
		audio.call(&"clear_duck")   # a ducked music level must not outlive the scene that set it
	if pause_menu:
		pause_menu.call(&"close_silently")
	if death_screen:
		death_screen.call(&"hide_now")
	if path == _preloading:
		_preloading = ""
		# Already loaded in the background (or nearly: load_threaded_get waits for the rest).
		var packed := ResourceLoader.load_threaded_get(path) as PackedScene
		if packed:
			get_tree().change_scene_to_packed(packed)
			return
	get_tree().change_scene_to_file(path)
