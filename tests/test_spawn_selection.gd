extends TestCase
# Spawn point selection by tiers (OrchestratorModel.select_spawn_points, pure logic).
#  1 HIDDEN: outside the cone and at > 8 m;  2 FAR: at > 14 m even if in view;
#  3 FALLBACK: the farthest at > 8 m (even if seen), only if allow_visible_fallback.

const Tier := OrchestratorModel.SpawnTier


func _sel(points: Array[Vector3], in_view: Array[bool], fallback := false) -> Dictionary:
	return OrchestratorModel.select_spawn_points(points, Vector3.ZERO, in_view, fallback)


func test_tier1_hidden_and_far_enough() -> void:
	var pts: Array[Vector3] = [Vector3(10, 0, 0), Vector3(0, 0, 20), Vector3(5, 0, 0), Vector3(0, 0, -9)]
	var view: Array[bool] = [false, true, false, false]
	var r := _sel(pts, view)
	assert_eq(r.tier, Tier.HIDDEN)
	assert_eq(r.indices, [0, 3], "outside the cone and > 8 m; the 5 m one and the visible one are not")


func test_tier1_ignores_flat_height() -> void:
	# Distance is horizontal: a point 6 m in plan and 10 m high is not valid.
	var pts: Array[Vector3] = [Vector3(6, 10, 0)]
	var view: Array[bool] = [false]
	assert_eq(_sel(pts, view).tier, Tier.NONE)


func test_tier1_boundary_is_exclusive() -> void:
	var pts: Array[Vector3] = [Vector3(8, 0, 0)]
	var view: Array[bool] = [false]
	assert_eq(_sel(pts, view).tier, Tier.NONE, "at exactly 8 m not valid (> 8)")


func test_tier2_far_even_if_visible() -> void:
	var pts: Array[Vector3] = [Vector3(10, 0, 0), Vector3(15, 0, 0), Vector3(0, 0, 20), Vector3(14, 0, 0)]
	var view: Array[bool] = [true, true, true, true]
	var r := _sel(pts, view)
	assert_eq(r.tier, Tier.FAR)
	assert_eq(r.indices, [1, 2], "visible but at > 14 m (the exactly-14 one is not)")


func test_tier1_wins_over_tier2() -> void:
	var pts: Array[Vector3] = [Vector3(20, 0, 0), Vector3(9, 0, 0)]
	var view: Array[bool] = [true, false]
	var r := _sel(pts, view)
	assert_eq(r.tier, Tier.HIDDEN)
	assert_eq(r.indices, [1])


func test_tier3_needs_the_retry() -> void:
	var pts: Array[Vector3] = [Vector3(9, 0, 0), Vector3(12, 0, 0), Vector3(5, 0, 0)]
	var view: Array[bool] = [true, true, true]
	assert_eq(_sel(pts, view, false).tier, Tier.NONE, "the first attempt does not use the fallback")
	var r := _sel(pts, view, true)
	assert_eq(r.tier, Tier.FALLBACK)
	assert_eq(r.indices, [1], "only the farthest")


func test_tier3_never_below_8m() -> void:
	var pts: Array[Vector3] = [Vector3(7.9, 0, 0), Vector3(3, 0, 0)]
	var view: Array[bool] = [true, true]
	assert_eq(_sel(pts, view, true).tier, Tier.NONE, "nothing at > 8 m: the wave is delayed")
	assert_true(_sel(pts, view, true).indices.is_empty())


func test_empty_input() -> void:
	var pts: Array[Vector3] = []
	var view: Array[bool] = []
	var r := _sel(pts, view, true)
	assert_eq(r.tier, Tier.NONE)
	assert_true(r.indices.is_empty())


func test_missing_view_flags_count_as_visible() -> void:
	# in_view shorter than points: the missing ones are treated as visible (the prudent choice).
	var pts: Array[Vector3] = [Vector3(10, 0, 0), Vector3(0, 0, 10)]
	var view: Array[bool] = [false]
	var r := _sel(pts, view)
	assert_eq(r.tier, Tier.HIDDEN)
	assert_eq(r.indices, [0])


func test_player_position_is_used() -> void:
	var pts: Array[Vector3] = [Vector3(30, 0, 0)]
	var view: Array[bool] = [false]
	var r := OrchestratorModel.select_spawn_points(pts, Vector3(25, 0, 0), view, false)
	assert_eq(r.tier, Tier.NONE, "5 m from Kaelen")
