extends TestCase
# Pruebas de la lógica y del cableado de los sonidos de esbirros, Kaelen, jefes y escenarios.

const BOSS_ATTACK_SOUNDS := {
	"blackhorn_charge": "attack_charge",
	"blackhorn_pounce": "attack_pounce",
	"blackhorn_slam": "attack_ground_slam",
	"bonedragon_bite": "attack_bite",
	"bonedragon_stomp": "attack_ground_slam",
	"bonedragon_tail_sweep": "attack_tail_sweep",
	"ghidorah_bite": "attack_bite",
	"ghidorah_tail_sweep": "attack_tail_sweep",
}


func test_step_voices_are_limited() -> void:
	assert_true(Minion.step_voice_allowed(true, 5.0, 0, false), "cerca y con voces libres")
	assert_true(not Minion.step_voice_allowed(true, 5.0, Minion.STEP_MAX_VOICES, false), "sin voces libres")
	assert_true(Minion.step_voice_allowed(true, 5.0, Minion.STEP_MAX_VOICES, true), "el que ya suena sigue sonando")


func test_step_voices_need_walking_and_hearing_distance() -> void:
	assert_true(not Minion.step_voice_allowed(false, 2.0, 0, true), "parado no suena")
	assert_true(not Minion.step_voice_allowed(true, Minion.STEP_HEARING_DISTANCE + 0.1, 0, true), "demasiado lejos")
	assert_true(Minion.step_voice_allowed(true, Minion.STEP_HEARING_DISTANCE, 0, false), "justo en el límite")


func test_stamina_ran_out_only_on_the_transition() -> void:
	assert_true(Player.stamina_ran_out(10.0, 0.0))
	assert_true(not Player.stamina_ran_out(0.0, 0.0), "ya estaba a 0")
	assert_true(not Player.stamina_ran_out(50.0, 20.0), "todavía queda")
	assert_true(not Player.stamina_ran_out(0.0, 5.0), "regenerando")


func test_every_boss_attack_has_its_sound() -> void:
	for attack_name in BOSS_ATTACK_SOUNDS:
		var attack := load("res://resources/attacks/%s.tres" % attack_name) as BossAttack
		assert_true(attack != null and attack.sfx_active != null, attack_name)
		if attack and attack.sfx_active:
			var expected: String = BOSS_ATTACK_SOUNDS[attack_name]
			assert_true(attack.sfx_active.resource_path.ends_with("/%s.mp3" % expected), attack_name)


func test_minion_scenes_have_normal_sounds_and_arena_walk() -> void:
	var walk := {"skeleton": "minion_walk_arena_1_2", "plague": "minion_walk_arena_1_2", "wrapper": "minion_walk_arena_3"}
	for minion_name in walk:
		var minion := (load("res://scenes/enemies/minion_%s.tscn" % minion_name) as PackedScene).instantiate() as Minion
		assert_true(minion.sfx_attack != null and minion.sfx_death != null, minion_name)
		assert_true(minion.sfx_step != null and minion.sfx_step.resource_path.ends_with("/%s.mp3" % walk[minion_name]), minion_name)
		minion.free()


func test_looping_streams_are_set_to_loop() -> void:
	for path in ["monsters/minion_walk_arena_1_2", "monsters/minion_walk_arena_3",
			"ambient/arena_1_ambience", "ambient/arena_2_ambience", "ambient/arena_3_ambience"]:
		var stream := load("res://assets/audio/sfx/%s.mp3" % path) as AudioStreamMP3
		assert_true(stream != null and stream.loop, path)


func test_kaelen_has_her_sounds() -> void:
	var kaelen := (load("res://scenes/player/kaelen.tscn") as PackedScene).instantiate() as Player
	assert_true(kaelen.sfx_roll != null and kaelen.sfx_hurt != null and kaelen.sfx_death != null and kaelen.sfx_tired != null)
	kaelen.free()


func test_arenas_have_ambience_and_gate_sound() -> void:
	for i in [1, 2, 3]:
		var scene := load("res://scenes/levels/arena_%d_gameplay.tscn" % i) as PackedScene
		var state := scene.get_state()
		var found := {}
		for p in state.get_node_property_count(0):
			found[state.get_node_property_name(0, p)] = true
		assert_true(found.has(&"ambience") and found.has(&"gate_sound"), "arena %d" % i)
