extends TestCase
# Phase 2 combos: Boss.combo_follow_up (pure rule) and the combo_next of each boss's attacks.

const BOSSES := [
	"res://scenes/bosses/boss_bonedragon.tscn",
	"res://scenes/bosses/boss_blackhorn.tscn",
	"res://scenes/bosses/boss_ghidorah.tscn",
]


func _attack(id: StringName, min_r: float, max_r: float, next: StringName = &"", phase_min := 1) -> BossAttack:
	var a := BossAttack.new()
	a.id = id
	a.min_range = min_r
	a.max_range = max_r
	a.combo_next = next
	a.phase_min = phase_min
	return a


func test_follow_up_only_in_phase_2() -> void:
	var bite := _attack(&"bite", 0.0, 4.0, &"tail")
	var tail := _attack(&"tail", 0.0, 5.0)
	var list: Array[BossAttack] = [bite, tail]
	assert_true(Boss.combo_follow_up(bite, list, 1, 2.0, 0) == null, "phase 1: no combo")
	assert_true(Boss.combo_follow_up(bite, list, 2, 2.0, 0) == tail, "phase 2: bite -> tail")
	assert_true(Boss.combo_follow_up(tail, list, 2, 2.0, 0) == null, "no combo_next: nothing")


func test_follow_up_respects_range_and_chain() -> void:
	var slam := _attack(&"slam", 0.0, 4.0, &"beam")
	var beam := _attack(&"beam", 8.0, 20.0)
	var list: Array[BossAttack] = [slam, beam]
	assert_true(Boss.combo_follow_up(slam, list, 2, 3.0, 0) == null, "too close for the beam")
	assert_true(Boss.combo_follow_up(slam, list, 2, 8.0 - Boss.COMBO_RANGE_SLACK + 0.1, 0) == beam, "within the slack")
	assert_true(Boss.combo_follow_up(slam, list, 2, 9.0, Boss.COMBO_MAX_CHAIN) == null, "one follow-up per string")


func test_follow_up_respects_its_phase_min_and_missing_ids() -> void:
	var slam := _attack(&"slam", 0.0, 4.0, &"charge")
	var charge := _attack(&"charge", 0.0, 16.0, &"", 3)
	var list: Array[BossAttack] = [slam, charge]
	assert_true(Boss.combo_follow_up(slam, list, 2, 5.0, 0) == null, "follow-up not unlocked in this phase")
	var lone := _attack(&"lone", 0.0, 4.0, &"ghost")
	var only: Array[BossAttack] = [lone]
	assert_true(Boss.combo_follow_up(lone, only, 2, 1.0, 0) == null, "an id that is not in the list")


func test_every_boss_has_combos_to_its_own_attacks() -> void:
	for path in BOSSES:
		var boss := (load(path) as PackedScene).instantiate() as Boss
		var ids := {}
		for a in boss.attacks:
			ids[a.id] = true
		var combos := 0
		for a in boss.attacks:
			if a.combo_next != &"":
				combos += 1
				assert_true(ids.has(a.combo_next), "%s: %s -> %s exists" % [path, a.id, a.combo_next])
				assert_true(a.combo_next != a.id, "%s: %s does not chain into itself" % [path, a.id])
		assert_true(combos >= 2, "%s: at least two combos (%d)" % [path, combos])
		boss.free()


func test_combo_warning_stays_readable() -> void:
	# Fastest follow-up warning: the shortest telegraph, at phase 2 speed, times COMBO_TELEGRAPH.
	for path in BOSSES:
		var boss := (load(path) as PackedScene).instantiate() as Boss
		for a in boss.attacks:
			if a.combo_next == &"":
				continue
			for b in boss.attacks:
				if b.id == a.combo_next:
					var warn := b.telegraph_time * Boss.COMBO_TELEGRAPH / Boss.PHASE2_SPEED
					assert_true(warn >= 0.6, "%s: %s warning %.2f s >= 0.6" % [path, b.id, warn])
		boss.free()
