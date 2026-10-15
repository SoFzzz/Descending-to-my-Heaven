extends TestCase
# Selección de puntos de aparición por tiers (OrchestratorModel.select_spawn_points, lógica pura).
#   1 HIDDEN: fuera del cono y a > 8 m;  2 FAR: a > 14 m aunque estén a la vista;
#   3 FALLBACK: el más lejano a > 8 m (aunque se vea), solo si allow_visible_fallback.

const Tier := OrchestratorModel.SpawnTier


func _sel(points: Array[Vector3], in_view: Array[bool], fallback := false) -> Dictionary:
	return OrchestratorModel.select_spawn_points(points, Vector3.ZERO, in_view, fallback)


func test_tier1_hidden_and_far_enough() -> void:
	var pts: Array[Vector3] = [Vector3(10, 0, 0), Vector3(0, 0, 20), Vector3(5, 0, 0), Vector3(0, 0, -9)]
	var view: Array[bool] = [false, true, false, false]
	var r := _sel(pts, view)
	assert_eq(r.tier, Tier.HIDDEN)
	assert_eq(r.indices, [0, 3], "fuera del cono y > 8 m; el de 5 m y el visible no")


func test_tier1_ignores_flat_height() -> void:
	# La distancia es horizontal: un punto a 6 m en planta y 10 m de alto no vale.
	var pts: Array[Vector3] = [Vector3(6, 10, 0)]
	var view: Array[bool] = [false]
	assert_eq(_sel(pts, view).tier, Tier.NONE)


func test_tier1_boundary_is_exclusive() -> void:
	var pts: Array[Vector3] = [Vector3(8, 0, 0)]
	var view: Array[bool] = [false]
	assert_eq(_sel(pts, view).tier, Tier.NONE, "a exactamente 8 m no vale (> 8)")


func test_tier2_far_even_if_visible() -> void:
	var pts: Array[Vector3] = [Vector3(10, 0, 0), Vector3(15, 0, 0), Vector3(0, 0, 20), Vector3(14, 0, 0)]
	var view: Array[bool] = [true, true, true, true]
	var r := _sel(pts, view)
	assert_eq(r.tier, Tier.FAR)
	assert_eq(r.indices, [1, 2], "visibles pero a > 14 m (el de exactamente 14 no)")


func test_tier1_wins_over_tier2() -> void:
	var pts: Array[Vector3] = [Vector3(20, 0, 0), Vector3(9, 0, 0)]
	var view: Array[bool] = [true, false]
	var r := _sel(pts, view)
	assert_eq(r.tier, Tier.HIDDEN)
	assert_eq(r.indices, [1])


func test_tier3_needs_the_retry() -> void:
	var pts: Array[Vector3] = [Vector3(9, 0, 0), Vector3(12, 0, 0), Vector3(5, 0, 0)]
	var view: Array[bool] = [true, true, true]
	assert_eq(_sel(pts, view, false).tier, Tier.NONE, "el primer intento no usa el respaldo")
	var r := _sel(pts, view, true)
	assert_eq(r.tier, Tier.FALLBACK)
	assert_eq(r.indices, [1], "solo el más lejano")


func test_tier3_never_below_8m() -> void:
	var pts: Array[Vector3] = [Vector3(7.9, 0, 0), Vector3(3, 0, 0)]
	var view: Array[bool] = [true, true]
	assert_eq(_sel(pts, view, true).tier, Tier.NONE, "nada a > 8 m: la oleada se retrasa")
	assert_true(_sel(pts, view, true).indices.is_empty())


func test_empty_input() -> void:
	var pts: Array[Vector3] = []
	var view: Array[bool] = []
	var r := _sel(pts, view, true)
	assert_eq(r.tier, Tier.NONE)
	assert_true(r.indices.is_empty())


func test_missing_view_flags_count_as_visible() -> void:
	# in_view más corto que points: los que faltan se tratan como visibles (lo prudente).
	var pts: Array[Vector3] = [Vector3(10, 0, 0), Vector3(0, 0, 10)]
	var view: Array[bool] = [false]
	var r := _sel(pts, view)
	assert_eq(r.tier, Tier.HIDDEN)
	assert_eq(r.indices, [0])


func test_player_position_is_used() -> void:
	var pts: Array[Vector3] = [Vector3(30, 0, 0)]
	var view: Array[bool] = [false]
	var r := OrchestratorModel.select_spawn_points(pts, Vector3(25, 0, 0), view, false)
	assert_eq(r.tier, Tier.NONE, "a 5 m de Kaelen")
