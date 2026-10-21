extends Node
## Kaelen's heavy attack, the attack step toward a locked target and the lock-on strafe, in arena 1
## with the real tree and a training dummy:
##  godot --headless --path . res://tests/flow/kaelen_moves_flow.tscn
## The boss is switched off and the Orchestrator stopped. Exits with code 1 if anything fails.

const DUMMY := "res://scenes/enemies/training_dummy.tscn"

var _fails := 0
var _player: Player
var _level: Node


func _ready() -> void:
	_detach.call_deferred()


func _detach() -> void:
	var tree := get_tree()
	reparent(tree.root)
	var placeholder := Node.new()
	tree.root.add_child(placeholder)
	tree.current_scene = placeholder
	_run()


func _check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		_fails += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _run() -> void:
	_level = (load("res://scenes/levels/arena_1_gameplay.tscn") as PackedScene).instantiate()
	get_tree().current_scene.add_child(_level)
	await _wait(0.5)
	Orchestrator.end_arena()
	var boss := _level.get_node_or_null(^"Boss") as Node3D
	if boss:
		boss.process_mode = Node.PROCESS_MODE_DISABLED
		boss.global_position += Vector3.DOWN * 200.0
	_player = get_tree().get_first_node_in_group("player") as Player
	_player.health.reset(1000)

	await _heavy_without_target()
	for dist in [1.6, 2.6, 3.6]:
		await _heavy_on_dummy(dist)
	await _heavy_as_combo_finisher()
	await _attack_step(3.0, true)
	await _attack_step(3.0, false)
	await _strafe()

	print("FLOW: OK" if _fails == 0 else "FLOW: FAIL (%d)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _reset_player() -> void:
	_player.get_node("LockOn").target = null
	_player.stamina.current = _player.stamina.max_value
	_player.velocity = Vector3.ZERO
	await _wait(0.6)


func _spawn_dummy(dist: float) -> Node3D:
	var dummy := (load(DUMMY) as PackedScene).instantiate() as Node3D
	_level.add_child(dummy)
	var fwd := _player.get_facing()
	fwd.y = 0.0
	dummy.global_position = _player.global_position + fwd.normalized() * dist
	(dummy.get_node("Health") as Health).reset(1000)
	return dummy


## Without a target the heavy attack leaps ≈ 2 m forward and comes back to MOVE by itself.
func _heavy_without_target() -> void:
	await _reset_player()
	var start := _player.global_position
	var stamina_before := _player.stamina.current
	_check(_player.try_heavy_attack(), "heavy: starts from MOVE")
	_check(is_equal_approx(stamina_before - _player.stamina.current, Player.HEAVY_COST), "heavy: costs %d stamina" % Player.HEAVY_COST)
	await _wait(Player.HEAVY_END + 0.15)
	var moved := Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length()
	_check(moved > 1.5 and moved < 2.6, "heavy: leaps forward (%.2f m)" % moved)
	_check(_player.state == Player.State.MOVE, "heavy: back to MOVE after %.2f s" % Player.HEAVY_END)


## A dummy in front at `dist` m: the slam lands once, with HEAVY_DAMAGE, around the landing.
func _heavy_on_dummy(dist: float) -> void:
	await _reset_player()
	var dummy := _spawn_dummy(dist)
	var health := dummy.get_node("Health") as Health
	_player.get_node("LockOn").target = dummy
	await get_tree().physics_frame
	var before := health.current
	_player.try_heavy_attack()
	var t := 0.0
	var hit_at := -1.0
	while t < Player.HEAVY_END + 0.1:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if hit_at < 0.0 and health.current < before:
			hit_at = t
	_check(before - health.current == Player.HEAVY_DAMAGE, "heavy at %.1f m: one slam of %d (dealt %d)" % [dist, Player.HEAVY_DAMAGE, before - health.current])
	_check(hit_at >= Player.HEAVY_HIT_START - 0.05 and hit_at <= Player.HEAVY_HIT_END + 0.05, "heavy at %.1f m: lands at %.2f s" % [dist, hit_at])
	dummy.queue_free()


## Inside the combo window the heavy attack works as a finisher.
func _heavy_as_combo_finisher() -> void:
	await _reset_player()
	_player.try_attack()
	await _wait(Player.HIT_END[0] + 0.05)
	_check(_player.try_heavy_attack(), "heavy: chains as a combo finisher")
	_check(_player.is_heavy_attacking(), "heavy: the finisher is the heavy attack")
	await _wait(Player.HEAVY_END + 0.15)


## A dummy 3 m away is just out of the slash's reach (≈ 2.6 m): with it locked, the step reaches it.
func _attack_step(dist: float, locked: bool) -> void:
	await _reset_player()
	var dummy := _spawn_dummy(dist)
	var health := dummy.get_node("Health") as Health
	if locked:
		_player.get_node("LockOn").target = dummy
	await get_tree().physics_frame
	var before := health.current
	_player.try_attack()
	await _wait(0.9)
	var dealt := before - health.current
	if locked:
		_check(dealt == Player.combo_damage(0), "attack step: locked at %.1f m the first slash connects (%d)" % [dist, dealt])
	else:
		_check(dealt == 0, "attack step: without a lock she does not slide (%d)" % dealt)
	dummy.queue_free()


## Locked on, moving right: she keeps facing the dummy, walks at LOCK_MOVE_SPEED and the
## locomotion crossfades to the strafe blend.
func _strafe() -> void:
	await _reset_player()
	var dummy := _spawn_dummy(4.0)
	_player.get_node("LockOn").target = dummy
	Input.action_press(&"move_right")
	await _wait(1.0)
	var to := dummy.global_position - _player.global_position
	to.y = 0.0
	var facing := _player.get_facing()
	facing.y = 0.0
	var angle := rad_to_deg(facing.angle_to(to))
	_check(angle < 12.0, "strafe: keeps facing the target (%.1f°)" % angle)
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	_check(absf(speed - Player.LOCK_MOVE_SPEED) < 0.4, "strafe: walks at %.1f m/s (%.2f)" % [Player.LOCK_MOVE_SPEED, speed])
	var local := _player.local_ground_velocity()
	_check(absf(local.x) > absf(local.y), "strafe: moves sideways in her own frame (%s)" % local)
	var tree := _player.get_node("AnimationTree") as AnimationTree
	_check(is_equal_approx(float(tree.get(&"parameters/locomotion/lock/blend_amount")), 1.0), "strafe: locomotion fully on the strafe blend")
	Input.action_release(&"move_right")
	_player.get_node("LockOn").target = null
	await _wait(0.5)
	_check(is_zero_approx(float(tree.get(&"parameters/locomotion/lock/blend_amount"))), "strafe: back to free locomotion without a target")
	dummy.queue_free()
