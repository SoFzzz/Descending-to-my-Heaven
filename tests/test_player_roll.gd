extends TestCase
# Tests for Kaelen's roll (invulnerability window, stamina cost and flags).


func test_iframes_window() -> void:
	assert_true(not Player.iframes_active_at(0.0), "t = 0.0")
	assert_true(Player.iframes_active_at(0.05), "t = 0.05")
	assert_true(Player.iframes_active_at(0.30), "t = 0.30")
	assert_true(not Player.iframes_active_at(0.45), "t = 0.45")


func test_roll_needs_stamina() -> void:
	var p := Player.new()
	var s := Stamina.new()
	p.stamina = s
	s.current = 0.0
	assert_true(not p.try_roll(), "try_roll with 0 stamina")
	assert_eq(p.state, Player.State.MOVE)
	p.free()
	s.free()


# Review focus 4: after boss_defeated, finishing a roll must not remove invulnerability.
func test_invulnerable_combines_flags() -> void:
	var p := Player.new()
	var s := Stamina.new()
	var h := Health.new()
	p.stamina = s
	p.health = h
	assert_true(p.try_roll(), "try_roll with full stamina")
	assert_eq(p.state, Player.State.ROLL)
	p._advance_roll(0.1)                 # within the i-frames window
	assert_true(p.is_invulnerable(), "i-frames active")
	p._on_boss_defeated(null)            # victory in the middle of the roll
	p._advance_roll(Player.ROLL_DURATION) # the roll ends
	assert_eq(p.state, Player.State.MOVE)
	assert_true(p.is_invulnerable(), "victory keeps invulnerability")
	assert_true(h.invulnerable, "Health also becomes invulnerable")
	p.free()
	s.free()
	h.free()


func _make_player() -> Array:
	var p := Player.new()
	var s := Stamina.new()
	var h := Health.new()
	h.reset(100)
	p.stamina = s
	p.health = h
	p._connect_components()
	return [p, s, h]


func _free_all(nodes: Array) -> void:
	for n in nodes:
		(n as Node).free()


# The roll clip is roll_to_run (its length checked against kaelen.glb); its rise lands at the end of the
# travel, so the recovery is the get-up (about 0.26 s).
func test_roll_clip_and_recovery_come_from_roll_to_run() -> void:
	var model := (load("res://assets/characters/kaelen/kaelen.glb") as PackedScene).instantiate()
	var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_true(anim != null and anim.has_animation(Player.ROLL_CLIP), "kaelen.glb has roll_to_run")
	var length := anim.get_animation(Player.ROLL_CLIP).length
	model.free()
	assert_almost(length, Player.ROLL_CLIP_LENGTH, 0.01, "roll_to_run length")
	var scale := Player.roll_anim_scale(length)
	assert_almost(Player.ROLL_CLIP_RISE / scale, Player.ROLL_DURATION, 0.01, "the get-up starts when the travel ends")
	assert_almost(Player.ROLL_RECOVERY, 0.26, 0.01)
	assert_true(Player.ROLL_IFRAME_END < Player.ROLL_DURATION, "the recovery has no i-frames")


# After the travel she is in MOVE but getting up: no i-frames, no roll, no flask.
func test_roll_recovery_follows_the_travel() -> void:
	var n := _make_player()
	var p: Player = n[0]
	assert_true(p.try_roll())
	p._advance_roll(Player.ROLL_DURATION)
	assert_eq(p.state, Player.State.MOVE)
	assert_true(p.is_roll_recovering(), "recovering after the roll")
	assert_true(not p.is_invulnerable(), "the recovery has no i-frames")
	assert_true(not p.try_roll(), "she cannot roll again while getting up")
	(n[2] as Health).current = 50
	assert_eq(p.heal_blocked_reason(), "busy", "nor drink")
	p._tick_roll_recovery(Player.ROLL_RECOVERY)
	assert_true(not p.is_roll_recovering(), "the recovery ends after ROLL_RECOVERY")
	assert_true(p.try_roll(), "then she can roll")
	_free_all(n)


# Mashing roll: a roll pressed late in the travel or during the get-up waits in the buffer and runs
# only when the recovery ends (it never cuts it).
func test_roll_spam_waits_for_the_recovery() -> void:
	var n := _make_player()
	var p: Player = n[0]
	assert_true(p.try_roll())
	p._advance_roll(Player.ROLL_DURATION - 0.05)
	p.buffer_action(&"roll")
	p._advance_roll(0.05)
	assert_eq(p.state, Player.State.MOVE, "the stored roll does not run when the travel ends")
	assert_true(p.is_roll_recovering())
	p._tick_buffer(Player.ROLL_RECOVERY * 0.5)
	p._tick_roll_recovery(Player.ROLL_RECOVERY * 0.5)
	p.buffer_action(&"roll")   # pressed again during the get-up
	p._tick_buffer(Player.ROLL_RECOVERY * 0.5)
	assert_true(p._tick_roll_recovery(Player.ROLL_RECOVERY * 0.5), "the recovery ends")
	assert_eq(p.state, Player.State.ROLL, "the stored roll runs right after the get-up")
	_free_all(n)


# A single roll press 0.05 s before the travel ends is not lost: the buffer waits through the get-up
# (it does not expire there) and the roll runs exactly when the recovery ends.
func test_single_roll_press_at_travel_end_waits_for_the_recovery() -> void:
	var n := _make_player()
	var p: Player = n[0]
	assert_true(p.try_roll())
	p._advance_roll(Player.ROLL_DURATION - 0.05)
	p.buffer_action(&"roll")   # the only press
	p._tick_buffer(0.05)       # what the ROLL state does on its frame
	p._advance_roll(0.05)
	assert_eq(p.state, Player.State.MOVE, "the travel ends; the roll waits")
	var t := 0.0
	const DT := 1.0 / 60.0
	while p.state == Player.State.MOVE and t < 1.0:
		p._tick_buffer(DT)          # the MOVE branch, in its order: buffer, then the recovery step
		p._tick_roll_recovery(DT)
		t += DT
	assert_eq(p.state, Player.State.ROLL, "the buffered roll runs")
	assert_almost(t, Player.ROLL_RECOVERY, DT * 1.01, "exactly when the recovery ends (%.3f s)" % t)
	_free_all(n)


# Roll attack: an attack stored late in the roll comes out when the travel ends, and an attack during
# the get-up cuts it (also the heavy attack).
func test_attack_after_roll_is_immediate() -> void:
	var n := _make_player()
	var p: Player = n[0]
	assert_true(p.try_roll())
	p._advance_roll(Player.ROLL_DURATION - 0.1)
	p.buffer_action(&"attack")
	p._advance_roll(0.1)
	assert_eq(p.state, Player.State.ATTACK, "the stored attack runs when the travel ends")
	assert_eq(p.combo_index, 0)
	assert_true(not p.is_roll_recovering(), "the attack cancels the get-up")
	p._end_attack()
	(n[1] as Stamina).current = 100.0
	assert_true(p.try_roll())
	p._advance_roll(Player.ROLL_DURATION)
	assert_true(p.is_roll_recovering())
	assert_true(p.try_heavy_attack(), "the heavy attack also cuts the get-up")
	assert_true(not p.is_roll_recovering())
	_free_all(n)


# A hit during the get-up stuns her (HURT) and ends the recovery.
func test_hit_during_recovery_enters_hurt() -> void:
	var n := _make_player()
	var p: Player = n[0]
	assert_true(p.try_roll())
	p._advance_roll(Player.ROLL_DURATION)
	(n[2] as Health).take_damage(10)
	assert_eq(p.state, Player.State.HURT)
	assert_true(not p.is_roll_recovering())
	_free_all(n)
