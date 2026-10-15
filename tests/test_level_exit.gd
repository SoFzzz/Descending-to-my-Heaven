extends TestCase
# Lógica del ExitTrigger de level_gameplay.gd sin escena real: se asigna `player` a mano y se llama al
# manejador de la señal. Fuera del árbol no se pide advance_level (no hay GameState).

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
	assert_eq(count[0], 0, "otro cuerpo no cuenta")
	lg._on_exit_trigger_body_entered(p)
	lg._on_exit_trigger_body_entered(p)
	assert_eq(count[0], 1, "exit_reached solo una vez")
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
	assert_eq(count[0], 0, "_can_exit() false bloquea la salida")
	assert_true(not lg._exit_used, "no se consume mientras no se pueda salir")
	lg.free()
	p.free()


func test_arena_exit_needs_cleared() -> void:
	var ag: Node3D = ArenaGameplay.new()
	var p := Player.new()
	ag.player = p
	var count: Array[int] = [0]
	ag.exit_reached.connect(func() -> void: count[0] += 1)
	ag._on_exit_trigger_body_entered(p)
	assert_eq(count[0], 0, "arena sin despejar")
	ag.arena_cleared = true
	ag._on_exit_trigger_body_entered(p)
	ag._on_exit_trigger_body_entered(p)
	assert_eq(count[0], 1, "arena despejada: una vez")
	ag.free()
	p.free()


func test_exit_advances_level_default() -> void:
	var lg: Node3D = LevelGameplay.new()
	assert_true(lg.exit_advances_level, "activo por defecto")
	lg.free()
