extends Node
## Kaelen's heavy attack, the attack step toward a locked target, the lock-on strafe, the combo's
## finisher (it closes the combo), the roll's recovery (no roll spam) and the roll attack, in arena 1
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
	await _finisher_closes_combo()
	await _finisher_follow_through_is_punishable()
	await _roll_spam_waits_for_recovery()
	await _roll_attack()
	await _sword_moves_every_physics_frame()

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


## The 3rd hit closes the combo: no hit chains from it, it plays to FINISHER_END and the next attack
## starts the combo over. Attack is mashed every frame (through the real input path).
func _finisher_closes_combo() -> void:
	await _reset_player()
	_player.health.reset(1000)
	var t := 0.0
	var finisher_at := -1.0
	var back_at := -1.0
	var restart_index := -1
	var chained_from_finisher := false
	_player.try_attack()
	while t < 3.0 and restart_index < 0:
		_player.stamina.current = _player.stamina.max_value
		_player._attack_pressed = true   # mashing the attack button
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if finisher_at < 0.0 and _player.is_finisher():
			finisher_at = t
		elif finisher_at >= 0.0 and back_at < 0.0:
			if _player.state == Player.State.ATTACK and _player.combo_index != 2:
				back_at = t
				restart_index = _player.combo_index
			elif _player.state == Player.State.ATTACK and _player._attack_time < t - finisher_at - 0.05:
				chained_from_finisher = true   # the clock restarted while still on the 3rd hit
	_check(finisher_at > 0.0, "combo: mashing reaches the finisher (%.2f s)" % finisher_at)
	_check(not chained_from_finisher, "combo: nothing chains from the finisher")
	var lasted := back_at - finisher_at
	_check(absf(lasted - Player.FINISHER_END) <= 0.05, "combo: the finisher plays its follow-through (%.2f s, expected %.2f)" % [lasted, Player.FINISHER_END])
	_check(restart_index == 0, "combo: the next attack starts the combo over (hit %d)" % (restart_index + 1))
	_player._end_attack()
	_player._play_action(&"locomotion")


## Hyper armor holds during the finisher's damage window and drops in its follow-through: a hit there
## interrupts it (HURT). The same on the heavy attack's landing.
func _finisher_follow_through_is_punishable() -> void:
	await _reset_player()
	_player.health.reset(1000)
	var hurtbox := _player.get_node("Hurtbox") as Hurtbox
	_player.try_attack()
	_player.combo_index = 2
	await _wait(Player.HIT_START[2] + 0.02)
	hurtbox.receive_hit(10, null)
	_check(_player.state == Player.State.ATTACK, "finisher: armored during its damage window")
	_player._tick_hurt_iframes(Player.HURT_IFRAMES)
	await _wait(Player.HIT_END[2] - Player.HIT_START[2] + 0.1)
	_check(_player.state == Player.State.ATTACK and not _player._armor_on, "finisher: no hyper armor in the follow-through")
	hurtbox.receive_hit(10, null)
	_check(_player.state == Player.State.HURT, "finisher: a hit in the follow-through interrupts it")
	await _wait(Player.HURT_IFRAMES + 0.1)
	_player.stamina.current = _player.stamina.max_value
	_player.try_heavy_attack()
	await _wait(Player.HEAVY_HIT_END + 0.05)
	_check(_player.state == Player.State.ATTACK and not _player._armor_on, "heavy: no hyper armor while landing")
	hurtbox.receive_hit(10, null)
	_check(_player.state == Player.State.HURT, "heavy: a hit while landing interrupts it")
	await _wait(Player.HURT_IFRAMES + 0.1)


## Mashing roll does not cut the get-up: each roll starts ROLL_DURATION + ROLL_RECOVERY after the
## previous one; the roll state plays roll_to_run over that whole time.
func _roll_spam_waits_for_recovery() -> void:
	await _reset_player()
	var tree := _player.get_node("AnimationTree") as AnimationTree
	var scale := float(tree.get(&"parameters/roll/speed/scale"))
	_check(absf(scale - Player.roll_anim_scale(Player.ROLL_CLIP_LENGTH)) < 0.01, "roll: roll_to_run fitted to the roll and its recovery (x%.2f)" % scale)
	var starts: Array[float] = []
	var recovering_seen := false
	var t := 0.0
	var was_rolling := false
	var pressed := false
	while t < 2.6 and starts.size() < 3:
		_player.stamina.current = _player.stamina.max_value
		pressed = not pressed
		if pressed:
			Input.action_press(&"roll")
		else:
			Input.action_release(&"roll")
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var rolling := _player.state == Player.State.ROLL
		if rolling and not was_rolling:
			starts.append(t)
		was_rolling = rolling
		recovering_seen = recovering_seen or _player.is_roll_recovering()
	Input.action_release(&"roll")
	_check(recovering_seen, "roll: a recovery follows the roll")
	_check(starts.size() >= 2, "roll: spamming still rolls again (%d rolls)" % starts.size())
	var cycle := Player.ROLL_DURATION + Player.ROLL_RECOVERY
	for i in range(1, starts.size()):
		var gap := starts[i] - starts[i - 1]
		_check(gap >= cycle - 0.034, "roll: roll %d waits for the get-up (%.2f s >= %.2f)" % [i + 1, gap, cycle])
	await _wait(cycle + 0.2)


## An attack pressed late in the roll comes out right when the travel ends (no wait for the get-up).
func _roll_attack() -> void:
	await _reset_player()
	_player.try_roll()
	var t := 0.0
	var attack_at := -1.0
	while t < 1.5 and attack_at < 0.0:
		if t >= Player.ROLL_DURATION - Player.BUFFER_TIME * 0.5 and _player.state == Player.State.ROLL:
			_player._attack_pressed = true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if _player.state == Player.State.ATTACK:
			attack_at = t
	_check(absf(attack_at - Player.ROLL_DURATION) <= 0.034, "roll attack: the slash starts as the roll ends (%.2f s)" % attack_at)
	_check(_player.combo_index == 0 and not _player.is_roll_recovering(), "roll attack: it is the first hit and cuts the get-up")
	await _wait(Player.HIT_END[0] + Player.COMBO_WINDOW + 0.2)


## The sword hitbox follows the hand on every physics frame of a slash (Kaelen is posed on physics
## frames), so its sweep does not depend on how many idle frames the machine draws.
func _sword_moves_every_physics_frame() -> void:
	await _reset_player()
	var tree := _player.get_node("AnimationTree") as AnimationTree
	_check(tree.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS, "sword: Kaelen is posed on physics frames")
	var sword := _player.get_node("SwordHitbox") as Node3D
	_player.try_attack()
	var frames := 0
	var still := 0
	var last := sword.global_position
	while _player._attack_time < Player.HIT_END[0]:
		await get_tree().physics_frame
		if _player._attack_time >= Player.HIT_START[0]:
			frames += 1
			if sword.global_position.is_equal_approx(last):
				still += 1
		last = sword.global_position
	_check(frames >= 8 and still == 0, "sword: moves on every physics frame of the slash (%d frames, %d still)" % [frames, still])
	await _wait(Player.COMBO_WINDOW + 0.2)
