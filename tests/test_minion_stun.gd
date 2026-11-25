extends TestCase
# Minion stun (oleada 1): every hit from Kaelen stuns a minion by its type, not by the kind of hit;
# bosses are never stunned. The real durations, frame by frame, are in minion_attacks_flow.

const S := MinionBrain.State


func test_stun_time_by_minion_type() -> void:
	assert_almost(Minion.stun_time(false), 0.6, 0.0001, "normal minion")
	assert_almost(Minion.stun_time(true), 0.35, 0.0001, "elite")
	assert_true(Minion.STUN_ELITE < Minion.STUN_NORMAL, "elites recover faster")


# Elites are the minions with their own spawn sound: the three elite scenes (cost 3) and no normal one.
func test_elites_are_the_cost_three_minions() -> void:
	var scenes := {
		"res://scenes/enemies/minion_skeleton.tscn": false,
		"res://scenes/enemies/minion_plague.tscn": false,
		"res://scenes/enemies/minion_wrapper.tscn": false,
		"res://scenes/enemies/minion_knight_elite.tscn": true,
		"res://scenes/enemies/minion_plague_elite.tscn": true,
		"res://scenes/enemies/minion_reaper_elite.tscn": true,
	}
	for path: String in scenes:
		var minion := (load(path) as PackedScene).instantiate() as Minion
		assert_eq(minion.is_elite(), scenes[path], path)
		assert_eq(minion.cost == 3, scenes[path], "%s cost" % path)
		minion.free()


# The kind of hit (normal / finisher / heavy) still exists for the push and the hit-stop.
func test_hit_kind_still_tells_finisher_and_heavy() -> void:
	var p := Player.new()
	var s := Stamina.new()
	p.stamina = s
	assert_true(p.try_attack())
	assert_eq(Minion.hit_kind(p), &"normal")
	p.combo_index = 2
	assert_eq(Minion.hit_kind(p), &"finisher")
	p._end_attack()
	assert_true(p.try_heavy_attack())
	assert_eq(Minion.hit_kind(p), &"heavy")
	p.free()
	s.free()


# Bosses have no stunned state: only minions are stunned.
func test_bosses_are_never_stunned() -> void:
	for key: String in Boss.State.keys():
		assert_true(not key.contains("STUN"), "Boss.State.%s" % key)
	assert_true(S.has("STUNNED"), "minions do have it")
