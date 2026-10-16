extends TestCase
# Logic of the ExitTrigger of level_gameplay.gd without a real scene: `player` is assigned by hand and the
# signal handler is called. Outside the tree advance_level is not requested (there is no GameState).

const LevelGameplay := preload("res://scripts/game/level_gameplay.gd")
const ArenaGameplay := preload("res://scripts/game/arena_gameplay.gd")


class ClosedExit extends "res://scripts/game/level_gameplay.gd":
	func _can_exit() -> bool:
		return false


func test_level_exit_once() -> void:
	var lg: Node3D = LevelGameplay.new()
	var p := Player.new()
	var other := Node3D.new()
	lg.player = p
	var count: Array[int] = [0]
	lg.exit_reached.connect(func() -> void: count[0] += 1)
	lg._on_exit_trigger_body_entered(other)
	assert_eq(count[0], 0, "another body does not count")
	lg._on_exit_trigger_body_entered(p)
	lg._on_exit_trigger_body_entered(p)
	assert_eq(count[0], 1, "exit_reached only once")
	lg.free()
	p.free()
	other.free()


func test_level_exit_respects_can_exit() -> void:
	var lg := ClosedExit.new()
	var p := Player.new()
	lg.player = p
	var count: Array[int] = [0]
	lg.exit_reached.connect(func() -> void: count[0] += 1)
	lg._on_exit_trigger_body_entered(p)
	assert_eq(count[0], 0, "_can_exit() false blocks the exit")
	assert_true(not lg._exit_used, "not consumed while the exit is not possible")
	lg.free()
	p.free()


func test_arena_exit_needs_cleared() -> void:
	var ag: Node3D = ArenaGameplay.new()
	var p := Player.new()
	ag.player = p
	var count: Array[int] = [0]
	ag.exit_reached.connect(func() -> void: count[0] += 1)
	ag._on_exit_trigger_body_entered(p)
	assert_eq(count[0], 0, "arena not cleared")
	ag.arena_cleared = true
	ag._on_exit_trigger_body_entered(p)
	ag._on_exit_trigger_body_entered(p)
	assert_eq(count[0], 1, "arena cleared: once")
	ag.free()
	p.free()


func test_exit_advances_level_default() -> void:
	var lg: Node3D = LevelGameplay.new()
	assert_true(lg.exit_advances_level, "active by default")
	lg.free()
