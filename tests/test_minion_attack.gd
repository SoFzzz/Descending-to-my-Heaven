extends TestCase
# Minion attack repertoire: timeline, weighted choice and the attack lists of each minion scene.

const SCENES := [
	"res://scenes/enemies/minion_skeleton.tscn",
	"res://scenes/enemies/minion_knight_elite.tscn",
	"res://scenes/enemies/minion_plague.tscn",
	"res://scenes/enemies/minion_plague_elite.tscn",
	"res://scenes/enemies/minion_wrapper.tscn",
	"res://scenes/enemies/minion_reaper_elite.tscn",
]


func _attack(id: StringName, min_r: float, max_r: float, weight := 1.0) -> MinionAttack:
	var a := MinionAttack.new()
	a.id = id
	a.min_range = min_r
	a.max_range = max_r
	a.weight = weight
	return a


func test_single_hit_timeline() -> void:
	var a := MinionAttack.new()
	a.windup = 0.5
	a.active = 0.3
	a.recover = 0.8
	assert_almost(a.strike_time(), 0.8)
	assert_almost(a.total_time(), 1.6)
	assert_true(not a.is_active_at(0.49))
	assert_true(a.is_active_at(0.5))
	assert_true(a.is_active_at(0.79))
	assert_true(not a.is_active_at(0.8))
	assert_eq(a.hit_index_at(0.6), 0)
	assert_eq(a.hit_index_at(0.2), -1)


func test_combo_has_separate_windows() -> void:
	var a := MinionAttack.new()
	a.windup = 0.5
	a.active = 0.2
	a.hits = 3
	a.hit_gap = 0.35
	assert_almost(a.strike_time(), 0.5 + 0.6 + 0.7)
	assert_eq(a.hit_index_at(0.6), 0)
	assert_eq(a.hit_index_at(0.8), -1, "gap between the first and the second hit")
	assert_eq(a.hit_index_at(1.1), 1)
	assert_eq(a.hit_index_at(1.65), 2)
	assert_eq(a.hit_index_at(1.81), -1, "after the last hit")


func test_choose_respects_range() -> void:
	var list := [_attack(&"melee", 0.0, 1.6), _attack(&"cast", 3.0, 7.0)]
	for roll in [0.0, 0.3, 0.7, 0.99]:
		assert_eq(MinionAttack.choose(list, 1.0, &"", roll), 0, "close: only the melee")
		assert_eq(MinionAttack.choose(list, 5.0, &"", roll), 1, "far: only the cast")


func test_choose_falls_back_to_the_melee() -> void:
	var list := [_attack(&"cast", 3.0, 7.0), _attack(&"melee", 0.0, 1.6)]
	assert_eq(MinionAttack.choose(list, 2.2, &"", 0.5), 1, "nothing in range -> smallest min_range")
	assert_eq(MinionAttack.choose([], 1.0, &"", 0.5), -1)


func test_choose_penalises_repeats() -> void:
	var list := [_attack(&"a", 0.0, 2.0), _attack(&"b", 0.0, 2.0)]
	# Weights after the repeat penalty: a = 0.35, b = 1.0 -> a only below 0.35 / 1.35.
	assert_eq(MinionAttack.choose(list, 1.0, &"a", 0.2), 0)
	assert_eq(MinionAttack.choose(list, 1.0, &"a", 0.3), 1)
	assert_eq(MinionAttack.choose(list, 1.0, &"", 0.3), 0, "without a repeat it is 50/50")


func test_reach_is_the_longest_max_range() -> void:
	assert_almost(MinionAttack.reach([_attack(&"a", 0.0, 1.6), _attack(&"b", 3.0, 7.0)], 1.5), 7.0)
	assert_almost(MinionAttack.reach([], 1.5), 1.5, 0.001, "empty list keeps attack_range")


func test_classic_swing_without_a_list() -> void:
	var minion := Minion.new()
	var a := minion.get_attack()
	assert_eq(a.clip, minion.anim_attack)
	assert_almost(a.windup, Minion.WINDUP_TIME)
	assert_almost(a.active, Minion.ACTIVE_TIME)
	assert_almost(a.recover, Minion.RECOVER_TIME)
	assert_almost(a.max_range, minion.attack_range)
	minion.free()


func test_every_minion_scene_has_several_attacks_with_real_clips() -> void:
	for path in SCENES:
		var scene := load(path) as PackedScene
		assert_true(scene != null, path)
		if scene == null:
			continue
		var minion := scene.instantiate() as Minion
		assert_true(minion.attacks.size() >= 2, "%s: at least two attacks" % path)
		var melee := false
		var ids := {}
		for a in minion.attacks:
			assert_true(not ids.has(a.id), "%s: %s repeated" % [path, a.id])
			ids[a.id] = true
			if a.min_range <= 0.0:
				melee = true
			assert_true(a.total_time() >= 1.0 and a.total_time() <= 3.5, "%s/%s: bounded duration" % [path, a.id])
			assert_true(a.windup >= 0.45, "%s/%s: readable windup (>= 0.45 s)" % [path, a.id])
			assert_true(a.max_range > a.min_range, "%s/%s: valid range" % [path, a.id])
		assert_true(melee, "%s: one attack from distance 0 (the fallback)" % path)
		# The clips exist in the model.
		var model := minion.model_scene.instantiate()
		var anim := Minion._find_animation_player(model)
		for a in minion.attacks:
			assert_true(anim != null and anim.has_animation(a.clip), "%s: clip %s" % [path, a.clip])
		model.free()
		minion.free()


func test_ranged_minion_asks_for_a_token_from_further() -> void:
	var minion := (load("res://scenes/enemies/minion_plague.tscn") as PackedScene).instantiate() as Minion
	minion.brain.attack_range = MinionAttack.reach(minion.attacks, minion.attack_range)
	assert_true(minion.token_range() > Minion.TOKEN_RANGE, "the cast reaches beyond 4 m")
	var skeleton := Minion.new()
	assert_almost(skeleton.token_range(), Minion.TOKEN_RANGE, 0.001, "classic minion keeps 4 m")
	skeleton.free()
	minion.free()


func test_runners_show_the_run_clip_only_when_fast() -> void:
	var S := MinionBrain.State
	assert_eq(Minion.clip_kind(S.CHASE, 5.5, 4.75), &"run")
	assert_eq(Minion.clip_kind(S.CHASE, 3.5, 4.75), &"walk")
	assert_eq(Minion.clip_kind(S.CHASE, 5.5), &"walk", "without a threshold it never runs")
	assert_eq(Minion.clip_kind(S.ATTACK, 6.0, 4.75), &"attack", "attacking wins over running")


func test_chase_speed_sprints_only_far_away() -> void:
	assert_almost(Minion.chase_speed(3.5, 6.0, 10.0, 6.0), 6.0)
	assert_almost(Minion.chase_speed(3.5, 6.0, 4.0, 6.0), 3.5)
	assert_almost(Minion.chase_speed(3.5, 0.0, 10.0, 6.0), 3.5, 0.001, "run_speed 0: it walks")


func test_arena_3_minions_are_runners() -> void:
	for path in ["res://scenes/enemies/minion_wrapper.tscn", "res://scenes/enemies/minion_reaper_elite.tscn"]:
		var minion := (load(path) as PackedScene).instantiate() as Minion
		assert_true(minion.run_speed > minion.move_speed and minion.anim_run != &"", "%s runs" % path)
		var model := minion.model_scene.instantiate()
		var anim := Minion._find_animation_player(model)
		assert_true(anim.has_animation(minion.anim_run), "%s: clip %s" % [path, minion.anim_run])
		model.free()
		minion.free()
