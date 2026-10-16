extends Node
## The ending must always move on: if a fade is running when it finishes, it waits for the
## transition to be free and then advances (GameState ignores advance_level() while busy).
##   godot --headless --path . res://tests/flow/ending_finish_flow.tscn
## Exits with code 1 if anything fails.

const Director := preload("res://scripts/game/ending_director.gd")

var _fails := 0


class FakeTransition extends Node:
	var busy := false

	func is_busy() -> bool:
		return busy


class FakeGameState extends Node:
	var transition: Node
	var advanced := 0

	func advance_level() -> void:
		advanced += 1


func _ready() -> void:
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		_fails += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _make(busy: bool) -> Array:
	var state := FakeGameState.new()
	var transition := FakeTransition.new()
	transition.busy = busy
	state.transition = transition
	add_child(state)
	add_child(transition)
	var director := Director.new()
	add_child(director)
	return [state, transition, director]


func _run() -> void:
	# 1. Free transition: advances at once.
	var a := _make(false)
	a[2]._advance_when_free(a[0])
	_check(a[0].advanced == 1, "free transition: advances immediately")

	# 2. Busy transition: waits, then advances exactly once when it frees up.
	var b := _make(true)
	b[2]._advance_when_free(b[0])
	await _frames(5)
	_check(b[0].advanced == 0, "busy transition: does not advance (and does not give up)")
	b[1].busy = false
	await _frames(3)
	_check(b[0].advanced == 1, "transition freed: advances once")
	await _frames(3)
	_check(b[0].advanced == 1, "no repeated advance")

	# 3. If the director leaves the tree while waiting, it never advances afterwards.
	var c := _make(true)
	c[2]._advance_when_free(c[0])
	await _frames(2)
	c[2].free()
	c[1].busy = false
	await _frames(3)
	_check(c[0].advanced == 0, "freed director does not advance")

	print("FLOW: OK" if _fails == 0 else "FLOW: FAIL (%d)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
