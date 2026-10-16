extends Node
## Floor transition: it cannot fire twice, Kaelen is locked and the new scene is paused while the
## screen is black, the card can be skipped, retrying is quick and has no card, and the card texts
## are translated.
##   godot --headless --path . res://tests/flow/transition_flow.tscn
## Exits with code 1 if anything fails.

const TRANSITION := preload("res://scenes/ui/transition.tscn")

var _fails := 0


class FakeParent extends Node:
	var swapped: Array[String] = []

	func _swap_scene(path: String) -> void:
		swapped.append(path)


class FakePlayer extends Node:
	var locked := false

	func _ready() -> void:
		add_to_group(&"player")

	func set_cutscene(on: bool) -> void:
		locked = on


func _ready() -> void:
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		_fails += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _make() -> Array:
	var parent := FakeParent.new()
	add_child(parent)
	var transition := TRANSITION.instantiate()
	parent.add_child(transition)
	return [parent, transition]


func _wait_free(transition: Node) -> float:
	var start := Time.get_ticks_msec()
	while transition.is_busy():
		await get_tree().process_frame
	return (Time.get_ticks_msec() - start) / 1000.0


func _run() -> void:
	var player := FakePlayer.new()
	add_child(player)
	var pair := _make()
	var parent: FakeParent = pair[0]
	var transition: Node = pair[1]

	# 1. Card transition: locks Kaelen, cannot fire twice, black + paused while the card shows.
	var start := Time.get_ticks_msec()
	transition.fade_to("res://a.tscn", "Floor 1", "Bone Dragon")
	transition.fade_to("res://b.tscn", "Floor 2", "Blackhorn")   # ignored: already busy
	_check(transition.is_busy(), "busy right after fade_to")
	_check(player.locked, "Kaelen is locked as soon as the screen starts closing")
	await transition.covered
	await _frames(3)
	_check(transition.is_black(), "black when the scene is swapped")
	_check(get_tree().paused, "the new scene is paused while the screen is black")
	await _frames(2)
	_check(get_tree().paused and transition.is_black(), "still paused and black during the card")
	await _wait_free(transition)
	var total := (Time.get_ticks_msec() - start) / 1000.0
	_check(parent.swapped == ["res://a.tscn"], "the scene was swapped exactly once (%s)" % str(parent.swapped))
	_check(not get_tree().paused, "unpaused when the transition ends")
	_check(total >= 1.5 and total <= 2.7, "total duration %.2f s within 1.5-2.7 s" % total)

	# 2. A key press during the card cuts the hold.
	player.locked = false
	start = Time.get_ticks_msec()
	transition.fade_to("res://c.tscn", "Floor 2", "Blackhorn")
	await transition.covered
	await get_tree().create_timer(0.6, true, false, true).timeout   # inside the hold
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(3)
	_check(transition.card_skipped(), "pressing a key moves the card to its exit phase")
	await _wait_free(transition)
	var skipped := (Time.get_ticks_msec() - start) / 1000.0
	_check(skipped < total, "pressing a key shortens the transition (%.2f s vs %.2f s)" % [skipped, total])
	_check(parent.swapped.size() == 2, "second transition swapped once")

	# 3. Retry: quick and without a card, never paused, Kaelen not locked by the transition.
	player.locked = false
	start = Time.get_ticks_msec()
	transition.fade_to("res://d.tscn", "", "", true)
	await transition.covered
	await _frames(3)
	_check(not get_tree().paused, "quick fade does not pause the scene")
	await _wait_free(transition)
	var quick := (Time.get_ticks_msec() - start) / 1000.0
	_check(quick < 0.9, "quick fade lasts %.2f s (< 0.9 s)" % quick)
	_check(not player.locked, "quick fade does not lock Kaelen")

	# 4. Card texts exist in both languages.
	var card_checks := {
		"res://scenes/levels/exterior_gameplay.tscn": ["El templo", "The temple"],
		"res://scenes/levels/arena_1_gameplay.tscn": ["Catacumba", "Catacomb"],
		"res://scenes/levels/arena_2_gameplay.tscn": ["Claustro", "Cloister"],
		"res://scenes/levels/arena_3_gameplay.tscn": ["Ruinas", "Ruins"],
	}
	var game_state := get_node("/root/GameState")
	var previous := TranslationServer.get_locale()
	for path in card_checks:
		TranslationServer.set_locale("es")
		var es: Array = game_state.card_for_scene(path)
		TranslationServer.set_locale("en")
		var en: Array = game_state.card_for_scene(path)
		_check(es.size() == 2 and card_checks[path][0] in es[0] and not es[0].begins_with("TRANS_"),
				"%s title in Spanish: %s" % [path.get_file(), str(es)])
		_check(en.size() == 2 and card_checks[path][1] in en[0] and not en[0].begins_with("TRANS_"),
				"%s title in English: %s" % [path.get_file(), str(en)])
	TranslationServer.set_locale(previous)
	_check(game_state.card_for_scene("res://scenes/ui/main_menu.tscn").is_empty(), "the menu has no card")

	print("FLOW: OK" if _fails == 0 else "FLOW: FAIL (%d)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
