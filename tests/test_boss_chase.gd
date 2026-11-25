extends TestCase
# Chase gap and phase-2 roar (AGENTS.md 18.3, wave 1, agent 2). Pure logic: the unit runner works
# without a scene tree, so the behaviour in the real arenas is checked in tests/flow/boss_combo_flow
# (a Kaelen circling the boss inside its reach must be attacked; the phase-2 roar pushes her).
#
# The gap: while the boss is still approaching (distance > engage_range) BossBrain.choose only lets
# `opener` attacks start. The Bone Dragon has none and walked at 3 m/s, slower than Kaelen's lock-on
# step (Player.LOCK_MOVE_SPEED = 3.2 m/s), so a Kaelen backing off inside its bite / tail range was
# chased forever without a single attack. Ghidorah had the same gap between 5 m and its 8 m tail.

const DT := 1.0 / 60.0
const BONEDRAGON := "res://scenes/bosses/boss_bonedragon.tscn"


func _boss() -> Boss:
	var boss := (load(BONEDRAGON) as PackedScene).instantiate() as Boss
	boss.health = boss.get_node(^"Health") as Health
	boss.health.reset(500)
	return boss


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	return rng


func test_approaching_boss_without_openers_cannot_attack() -> void:
	# The rule that made the gap: approaching = only openers. The Bone Dragon has none.
	var boss := _boss()
	for attack in boss.attacks:
		assert_true(not attack.opener, "%s is not an opener" % attack.id)
	assert_true(boss.brain.choose(boss.attacks, 4.0, 1, _rng(), true) == null, "approaching at 4 m: nothing")
	assert_true(boss.brain.choose(boss.attacks, 4.0, 1, _rng(), false) != null, "but bite / tail reach 4 m")
	boss.free()


func test_reach_is_the_longest_range_usable_in_the_phase() -> void:
	var boss := _boss()
	assert_almost(BossBrain.reach(boss.attacks, 1), 5.5, 0.001, "Bone Dragon: the tail sweep")
	boss.free()
	var charge := load("res://resources/attacks/blackhorn_charge.tres") as BossAttack
	var slam := load("res://resources/attacks/blackhorn_slam.tres") as BossAttack
	var list: Array[BossAttack] = [slam, charge]
	assert_almost(BossBrain.reach(list, 1), 4.0, 0.001, "the charge does not count in phase 1")
	assert_almost(BossBrain.reach(list, 2), 16.0, 0.001, "it does in phase 2")


func test_chase_stalls_when_kaelen_keeps_her_distance() -> void:
	var brain := BossBrain.new()
	var stalled := false
	var t := 0.0
	while not stalled and t < 2.0:
		t += DT
		stalled = brain.track_chase(DT, 4.0, true)   # she backs off as fast as the boss walks
	assert_true(stalled, "stalled")
	assert_almost(t, BossBrain.CHASE_PATIENCE, DT * 1.5, "after CHASE_PATIENCE s")


func test_chase_does_not_stall_while_the_boss_gains_ground() -> void:
	var brain := BossBrain.new()
	var distance := 5.5
	for i in 60:   # 1 s closing at 2 m/s, slower than any boss
		distance -= 2.0 * DT
		assert_true(not brain.track_chase(DT, distance, true), "closing in: no stall (%.2f m)" % distance)


func test_chase_stall_resets_out_of_reach_and_on_attack() -> void:
	var brain := BossBrain.new()
	for i in 30:
		brain.track_chase(DT, 4.0, true)
	assert_true(brain.chase_stall_seconds() > 0.4)
	brain.track_chase(DT, 9.0, false)
	assert_almost(brain.chase_stall_seconds(), 0.0, 0.0001, "out of reach resets it")
	for i in 30:
		brain.track_chase(DT, 4.0, true)
	brain.reset_chase()
	assert_almost(brain.chase_stall_seconds(), 0.0, 0.0001, "an attack (or another goal) resets it")


func test_slow_approach_still_counts_as_progress() -> void:
	# Closing 0.5 m every 0.5 s (1 m/s) keeps resetting the stall: only < 0.83 m/s is "stalled".
	var brain := BossBrain.new()
	var distance := 5.0
	for i in 90:
		distance -= 1.0 * DT
		assert_true(not brain.track_chase(DT, distance, true), "1 m/s of progress is enough")


# --- Phase-2 roar -----------------------------------------------------------------------------

func test_phase_roar_is_short() -> void:
	var boss := _boss()
	boss.phase = 2
	boss.state = Boss.State.CHASE
	boss.start_phase_roar()
	assert_true(boss.phase_roaring and boss.state == Boss.State.ROAR, "roars")
	var t := 0.0
	while boss.state == Boss.State.ROAR and t < 6.0:
		t += DT
		boss._state_time += DT   # what _physics_process does before _run_state
		boss._run_state(DT, false)
	assert_almost(t, Boss.PHASE2_ROAR_TIME, DT * 1.5, "lasts PHASE2_ROAR_TIME, not the whole clip")
	assert_true(Boss.PHASE2_ROAR_TIME >= 1.3 and Boss.PHASE2_ROAR_TIME <= 1.7, "about 1.5 s")
	assert_true(not boss.phase_roaring and not boss.is_invulnerable(), "and then it can be hit again")
	boss.free()


func test_phase_roar_is_invulnerable() -> void:
	var boss := _boss()
	boss.state = Boss.State.CHASE
	boss.start_phase_roar()
	boss._on_hurt(60, null)
	assert_eq(boss.health.current, 500, "no damage during the phase roar")
	assert_true(boss.is_invulnerable())
	boss.free()


func test_phase_roar_fires_the_repel_shockwave() -> void:
	var boss := _boss()
	boss.state = Boss.State.CHASE
	boss.start_phase_roar()
	assert_almost(boss._repel_push_left, boss.repel_push_delay, 0.0001, "the repel shockwave, after its warning")
	var t := 0.0
	while boss._repel_push_left > 0.0 and t < 1.0:
		t += DT
		boss._state_time += DT
		boss._run_state(DT, false)
	assert_almost(t, boss.repel_push_delay, DT * 1.5, "it leaves repel_push_delay s after the roar starts")
	assert_true(boss.state == Boss.State.ROAR, "while the roar goes on")
	boss.free()


func test_phase_roar_resets_the_repel_window_but_not_the_tactics() -> void:
	var boss := _boss()
	boss.state = Boss.State.CHASE
	boss._register_repel_damage(40)
	boss.start_phase_roar()
	assert_true(boss.repel.on_cooldown(), "no second roar right after the phase one")
	assert_eq(boss.repel.recent_damage(), 0, "the burst before it is cleared")
	assert_eq(boss.repel_count, 0, "it is not a repel reaction")
	assert_true(boss._clock - boss._last_repel_clock > BossTactics.REPEL_RECOVERY, "no WAIT after it")
	boss.free()


func test_crossing_half_health_queues_the_phase_roar() -> void:
	var boss := _boss()
	boss._on_health_changed(250, 500)
	assert_eq(boss.phase, 2)
	assert_true(boss._pending_roar, "the roar starts on the next physics frame")
	boss.free()


# --- No hit feedback while invulnerable --------------------------------------------------------
# The boss's hurtboxes have no Health (the boss applies the damage itself), so before this a sword hit
# during a roar still passed Hurtbox.can_be_hit(): hit-stop, sound, sparks and the model flash for a
# hit that did nothing. The hurtbox now asks its guard (the boss).

func _hurtbox_of(boss: Boss) -> Hurtbox:
	var hb := boss.get_node(^"Model/metarig/Skeleton3D/SkullAttach/HeadHurtbox") as Hurtbox
	hb.health = null
	hb.guard = boss   # what Boss._ready does (it does not run outside the tree)
	return hb


func _swing_at(hurtbox: Hurtbox) -> Array:
	var hits := []
	hurtbox.hurt.connect(func(amount: int, _source: Node) -> void: hits.append(amount))
	var sword := Hitbox.new()
	sword.damage = 20
	sword._active = true   # activate() defers monitoring; outside the tree it is set by hand
	sword._on_area_entered(hurtbox)
	sword.free()
	return hits


func test_hit_during_the_phase_roar_is_ignored_whole() -> void:
	var boss := _boss()
	var hb := _hurtbox_of(boss)
	boss.state = Boss.State.CHASE
	boss.start_phase_roar()
	assert_true(not hb.can_be_hit(), "the hurtbox refuses the hit: no hit-stop, sound or flash")
	assert_eq(_swing_at(hb).size(), 0, "nothing reaches the hurtbox")
	boss.free()


func test_hit_during_the_repel_roar_is_ignored_whole() -> void:
	var boss := _boss()
	var hb := _hurtbox_of(boss)
	boss.state = Boss.State.CHASE
	boss.start_repel()
	assert_true(not hb.can_be_hit(), "repel roar: no feedback either")
	boss.free()


func test_normal_hits_still_land() -> void:
	var boss := _boss()
	var hb := _hurtbox_of(boss)
	boss.state = Boss.State.CHASE
	assert_true(hb.can_be_hit(), "a vulnerable boss takes the hit (Hitbox gives its feedback)")
	var hits := []
	hb.hurt.connect(func(amount: int, _source: Node) -> void: hits.append(amount))
	hb.receive_hit(20, null)   # what Hitbox._on_area_entered does after the gate
	assert_eq(hits, [25], "head multiplier (20 x 1.25)")
	boss.free()


func test_hurtboxes_without_guard_are_unchanged() -> void:
	var health := Health.new()
	health.reset(100)
	var hb := Hurtbox.new()
	hb.health = health
	assert_true(hb.can_be_hit(), "Kaelen / minions: only their Health decides")
	health.invulnerable = true
	assert_true(not hb.can_be_hit())
	hb.free()
	health.free()
