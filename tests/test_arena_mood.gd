extends TestCase
# Per-arena lighting (ArenaMood in arena_N_gameplay.tscn) and the defeated boss tint.

const SCENES := [
	"res://scenes/levels/arena_1_gameplay.tscn",
	"res://scenes/levels/arena_2_gameplay.tscn",
	"res://scenes/levels/arena_3_gameplay.tscn",
]


func _mood_of(path: String) -> Array:
	var root := (load(path) as PackedScene).instantiate()
	var mood := root.get_node("Mood") as ArenaMood
	mood.apply_to(root.get_node("Level"))
	return [root, mood]


func test_each_arena_has_its_own_lighting() -> void:
	var seen: Array[String] = []
	for path in SCENES:
		var pair := _mood_of(path)
		var root: Node = pair[0]
		var mood := pair[1] as ArenaMood
		var sun := root.get_node("Level/Sun") as DirectionalLight3D
		var env := (root.get_node("Level/WorldEnvironment") as WorldEnvironment).environment
		assert_true(env == mood.environment, "the level uses its own Environment")
		assert_eq(env.ambient_light_color, mood.ambient_color)
		assert_eq(env.fog_light_color, mood.fog_color)
		assert_eq(sun.light_color, mood.sun_color)
		seen.append("%s|%s|%s|%s" % [env.ambient_light_color, env.fog_light_color, sun.light_color, env.adjustment_saturation])
		root.free()
	assert_eq(seen.size(), 3)
	assert_true(seen[0] != seen[1] and seen[1] != seen[2] and seen[0] != seen[2], "the 3 arenas look different")


func test_catacomb_is_darker_and_warmer_than_cloister() -> void:
	var a1: ArenaMood = _mood_of(SCENES[0])[1]
	var a2: ArenaMood = _mood_of(SCENES[1])[1]
	var a3: ArenaMood = _mood_of(SCENES[2])[1]
	assert_true(a1.ambient_color.r > a1.ambient_color.b, "arena 1 is warm")
	assert_true(a2.ambient_color.b > a2.ambient_color.r, "arena 2 is cold")
	assert_true(a1.fog_color.get_luminance() < a2.fog_color.get_luminance(), "the catacomb is darker")
	assert_true(a3.fog_end > a1.fog_end and a3.fog_end > a2.fog_end, "the ruins, in the open air, see farther")
	assert_true(a2.saturation < a1.saturation, "the cloister is desaturated")
	for m in [a1, a2, a3]:
		assert_true(m.defeat_tint != Color.WHITE, "each boss leaves its tint")
		(m.get_parent() as Node).free()


func test_level_environment_resource_is_not_mutated() -> void:
	var root := (load(SCENES[0]) as PackedScene).instantiate()
	var world := root.get_node("Level/WorldEnvironment") as WorldEnvironment
	var before := world.environment
	var energy := before.ambient_light_energy
	(root.get_node("Mood") as ArenaMood).apply_to(root.get_node("Level"))
	assert_true(world.environment != before, "a copy is assigned")
	assert_almost(before.ambient_light_energy, energy, 0.0001, "the original resource is left unchanged")
	root.free()
