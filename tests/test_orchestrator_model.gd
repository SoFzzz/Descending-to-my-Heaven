extends TestCase
# OrchestratorModel tests (pure model of the Orchestrator, spec 8.3).

const Phase := OrchestratorModel.Phase


# Calm context by default; each test overrides what it cares about.
func _ctx(overrides := {}) -> Dictionary:
	var ctx := {
		hp_ratio = 1.0,
		enemies_near = 0,
		enemies_alive = 0,
		time_since_hit = 10.0,
		boss_phase = 1,
		boss_special = false,
	}
	ctx.merge(overrides, true)
	return ctx


# Advances `seconds` in 0.5 s steps (exact in floating point).
func _run(m: OrchestratorModel, seconds: float, ctx: Dictionary) -> int:
	var spent := 0
	for i in int(seconds / 0.5):
		spent += m.update(0.5, ctx)
	return spent


func test_damage_raises_intensity() -> void:
	var m := OrchestratorModel.new()
	m.on_player_damaged(20)
	assert_almost(m.intensity, 30.0)


func test_damage_intensity_is_clamped_to_100() -> void:
	var m := OrchestratorModel.new()
	m.on_player_damaged(500)
	assert_almost(m.intensity, 100.0)


func test_natural_decay() -> void:
	var m := OrchestratorModel.new()
	m.intensity = 50.0
	m.update(1.0, _ctx())   # no enemies near: -15/s
	assert_almost(m.intensity, 35.0)


func test_decay_with_enemies_near_is_8_per_second() -> void:
	var m := OrchestratorModel.new()
	m.intensity = 50.0
	m.update(1.0, _ctx({enemies_near = 1}))   # -8 + 2 for the nearby enemy
	assert_almost(m.intensity, 44.0)


func test_low_hp_raises_intensity() -> void:
	var m := OrchestratorModel.new()
	m.intensity = 50.0
	m.update(1.0, _ctx({hp_ratio = 0.29, enemies_near = 1}))   # +5 +2 -8
	assert_almost(m.intensity, 49.0)


func test_build_up_to_peak_at_80() -> void:
	var m := OrchestratorModel.new()
	m.intensity = 79.0
	m.update(0.1, _ctx({enemies_near = 3, enemies_alive = 3}))   # +6 -8 -> drops
	assert_eq(m.phase, Phase.BUILD_UP)
	m.on_player_damaged(10)   # +15 -> 94
	m.update(0.1, _ctx({enemies_near = 3, enemies_alive = 3}))
	assert_eq(m.phase, Phase.PEAK)


func test_peak_lasts_5s() -> void:
	var m := OrchestratorModel.new()
	m.on_player_damaged(60)   # 90
	var near := _ctx({enemies_near = 10, enemies_alive = 5})   # +20 -8: stays high
	m.update(0.5, near)
	assert_eq(m.phase, Phase.PEAK)
	_run(m, 4.5, near)
	assert_eq(m.phase, Phase.PEAK, "a los 4.5 s sigue en pico")
	_run(m, 0.5, near)
	assert_eq(m.phase, Phase.RELAX, "a los 5 s pasa a respiro")


func test_relax_waits_for_low_intensity() -> void:
	var m := OrchestratorModel.new()
	m.phase = Phase.RELAX
	m.intensity = 90.0
	m.relax_duration = 10.0
	# 10 s with many enemies near: the time is up but the intensity stays >= 30.
	var busy := _ctx({enemies_near = 10, enemies_alive = 5})
	_run(m, 12.0, busy)
	assert_eq(m.phase, Phase.RELAX, "intensidad alta: se queda en respiro")
	# With no enemies left it drops below 30 and returns.
	_run(m, 5.0, _ctx())
	assert_eq(m.phase, Phase.BUILD_UP)


func test_relax_does_not_end_before_its_duration() -> void:
	var m := OrchestratorModel.new()
	m.phase = Phase.RELAX
	m.relax_duration = 10.0
	m.intensity = 0.0
	_run(m, 9.5, _ctx())
	assert_eq(m.phase, Phase.RELAX)
	_run(m, 0.5, _ctx())
	assert_eq(m.phase, Phase.BUILD_UP)


func test_relax_duration_is_between_10_and_20() -> void:
	var m := OrchestratorModel.new()
	m.intensity = 0.0
	m.on_player_damaged(60)   # 90
	_run(m, 0.5, _ctx({enemies_near = 10, enemies_alive = 5}))   # -> peak
	_run(m, 5.0, _ctx({enemies_near = 10, enemies_alive = 5}))   # -> relax
	assert_eq(m.phase, Phase.RELAX)
	assert_true(m.relax_duration >= 10.0 and m.relax_duration <= 20.0, "duración %s" % m.relax_duration)


func test_low_hp_forces_relax() -> void:
	var m := OrchestratorModel.new()
	m.update(0.1, _ctx({hp_ratio = 0.2}))
	assert_eq(m.phase, Phase.RELAX)
	# And it does not leave while health stays low, even if time passes and the intensity is low.
	_run(m, 30.0, _ctx({hp_ratio = 0.2}))
	assert_eq(m.phase, Phase.RELAX)


func test_low_hp_forces_relax_from_peak() -> void:
	var m := OrchestratorModel.new()
	m.phase = Phase.PEAK
	m.intensity = 90.0
	m.update(0.1, _ctx({hp_ratio = 0.24}))
	assert_eq(m.phase, Phase.RELAX)


func test_no_spawn_in_relax_nor_peak() -> void:
	var m := OrchestratorModel.new()
	m.phase = Phase.RELAX
	assert_eq(m.update(0.5, _ctx()), 0)
	m.phase = Phase.PEAK
	assert_eq(m.update(0.5, _ctx({enemies_near = 10})), 0)


# --- Wave -> boss window -> wave cycle ----------------------------------------------------------

# Advances until the model returns a budget (at most `limit` s, 0.5 s steps). Returns
# {budget, t}: t = elapsed seconds (-1 if there was no wave).
func _until_wave(m: OrchestratorModel, ctx: Dictionary, limit := 60.0) -> Dictionary:
	var t := 0.0
	while t < limit:
		t += 0.5
		var b := m.update(0.5, ctx)
		if b > 0:
			return {budget = b, t = t}
	return {budget = 0, t = -1.0}


func test_first_wave_waits_first_wave_delay() -> void:
	var m := OrchestratorModel.new()
	assert_almost(m.first_wave_delay, 3.0)
	assert_eq(_run(m, 2.5, _ctx()), 0, "antes de 3 s no sale la primera oleada")
	assert_true(m.update(0.5, _ctx()) > 0, "a los 3 s sale")


func test_first_wave_delay_is_configurable() -> void:
	var m := OrchestratorModel.new()
	m.first_wave_delay = 1.0
	m.reset()
	var r := _until_wave(m, _ctx())
	assert_almost(r.t, 1.0)


func test_wave_size_is_two_or_three() -> void:
	var m := OrchestratorModel.new()
	assert_eq(m.max_alive, 3, "como mucho 3 esbirros vivos")
	# Doing well (1.4 x 4 = 5.6 >= 4) -> 3; doing badly (0.72 x 4 = 2.9 < 4) -> 2.
	var good := _until_wave(m, _ctx({time_since_hit = 99.0}))
	assert_eq(good.budget, 3)
	var m2 := OrchestratorModel.new()
	var bad := _until_wave(m2, _ctx({hp_ratio = 0.3, time_since_hit = 0.0}))
	assert_eq(bad.budget, 2)


func test_phase2_pushes_to_three() -> void:
	var m := OrchestratorModel.new()
	# With phase 2: minimum performance (0.6 x 4 x 1.5 = 3.6 < 4) -> 2; medium performance (5.3 >= 4) -> 3.
	assert_eq(m.wave_size_for(_ctx({hp_ratio = 0.0, time_since_hit = 0.0, boss_phase = 2}), 4.0), 2)
	assert_eq(m.wave_size_for(_ctx({hp_ratio = 0.5, time_since_hit = 4.0, boss_phase = 2}), 4.0), 3)


func test_wave_size_never_exceeds_three() -> void:
	var m := OrchestratorModel.new()
	m.base_budget = 1.0
	assert_eq(_until_wave(m, _ctx({time_since_hit = 99.0, boss_phase = 2})).budget, 3, "ni con presion maxima pasa de 3")
	var m2 := OrchestratorModel.new()
	m2.base_budget = 1000.0   # impossible pressure: minimum group
	assert_eq(_until_wave(m2, _ctx({hp_ratio = 0.5, time_since_hit = 0.0})).budget, 2)


func test_wave_size_respects_free_slots() -> void:
	var m := OrchestratorModel.new()
	m.max_alive = 2
	assert_eq(_until_wave(m, _ctx({time_since_hit = 99.0})).budget, 2, "sin huecos para 3 se limita a max_alive")
	var m2 := OrchestratorModel.new()
	assert_eq(m2.wave_size_for(_ctx({enemies_alive = 3}), 4.0), 0, "con 3 vivos no sale nadie")
	assert_eq(m2.wave_size_for(_ctx({enemies_alive = 2, time_since_hit = 99.0}), 4.0), 1, "con 2 vivos solo cabe 1")


func test_no_wave_while_minions_alive() -> void:
	var m := OrchestratorModel.new()
	assert_true(_until_wave(m, _ctx()).budget > 0)
	# Even if only 1 stays alive for a long time, no other wave arrives.
	assert_eq(_run(m, 120.0, _ctx({enemies_alive = 1})), 0)
	assert_eq(_run(m, 120.0, _ctx({enemies_alive = 4})), 0)


func test_window_starts_when_last_minion_dies() -> void:
	var m := OrchestratorModel.new()
	_until_wave(m, _ctx())
	# Long fight with minions alive: it does not count as a window.
	_run(m, 40.0, _ctx({enemies_alive = 3}))
	var window := m.window_duration()
	assert_almost(window, 12.0 * 0.9, 0.001)
	# With 0 alive the next wave takes exactly the window (0.5 s steps).
	var r := _until_wave(m, _ctx())
	assert_true(absf(r.t - window) <= 1.0, "tardó %s, ventana %s" % [r.t, window])


func test_window_scales_with_intensity() -> void:
	var m := OrchestratorModel.new()
	m.intensity = 0.0
	var low := m.window_duration()
	m.intensity = 100.0
	var high := m.window_duration()
	assert_true(low < 12.0 and high > 12.0, "low %s high %s" % [low, high])
	assert_true(low >= 12.0 * 0.7 and high <= 12.0 * 1.3 + 0.001, "dentro de +-30 %")


func test_window_is_configurable() -> void:
	var m := OrchestratorModel.new()
	m.clear_delay = 20.0
	_until_wave(m, _ctx())
	var r := _until_wave(m, _ctx())
	assert_true(absf(r.t - m.window_duration()) <= 1.0)
	assert_true(r.t > 15.0)


func test_cycle_repeats_waves() -> void:
	var m := OrchestratorModel.new()
	for i in 3:
		assert_true(_until_wave(m, _ctx()).budget > 0, "oleada %d" % i)
		_run(m, 10.0, _ctx({enemies_alive = 3}))


func test_failed_spawn_retries_soon() -> void:
	var m := OrchestratorModel.new()
	_until_wave(m, _ctx())
	m.retry_wave_soon()
	var r := _until_wave(m, _ctx())
	assert_almost(r.t, 1.0)


func test_no_wave_in_relax_or_low_hp_even_after_window() -> void:
	var m := OrchestratorModel.new()
	m.update(0.1, _ctx({hp_ratio = 0.2}))   # forces RELAX
	assert_eq(_run(m, 60.0, _ctx({hp_ratio = 0.2})), 0)


func test_relax_does_not_skip_the_window() -> void:
	var m := OrchestratorModel.new()
	_until_wave(m, _ctx())
	_run(m, 2.0, _ctx({enemies_alive = 2}))
	m.phase = Phase.RELAX
	m.relax_duration = 10.0
	_run(m, 10.0, _ctx())   # relax + window (10.8 s) without a wave
	# On returning to BUILD_UP the window has almost ended, but there was never a wave in RELAX.
	assert_eq(m.phase, Phase.BUILD_UP)


func test_no_spawn_during_boss_special() -> void:
	var m := OrchestratorModel.new()
	_run(m, 5.0, _ctx({boss_special = true}))   # the initial delay passes
	assert_eq(m.update(0.5, _ctx({boss_special = true})), 0)
	assert_true(m.update(0.5, _ctx()) > 0, "al terminar el ataque especial genera")


func test_reset_restarts_cycle() -> void:
	var m := OrchestratorModel.new()
	_until_wave(m, _ctx())
	_run(m, 3.0, _ctx({enemies_alive = 2}))
	m.reset()
	assert_eq(m.update(0.5, _ctx()), 0, "tras reset vuelve a esperar first_wave_delay")
	var r := _until_wave(m, _ctx())
	assert_true(r.t > 0.0 and r.t <= 3.0)


func test_cycle_state_labels() -> void:
	var m := OrchestratorModel.new()
	m.update(0.5, _ctx())
	assert_eq(m.cycle, OrchestratorModel.Cycle.FIRST_WAIT)
	_until_wave(m, _ctx())
	m.update(0.5, _ctx({enemies_alive = 3}))
	assert_eq(m.cycle, OrchestratorModel.Cycle.WAVE)
	m.update(0.5, _ctx())
	assert_eq(m.cycle, OrchestratorModel.Cycle.WINDOW)
	assert_true(m.wave_timer > 5.0)


func test_performance_factor_range() -> void:
	var m := OrchestratorModel.new()
	assert_almost(m.performance_factor(_ctx({hp_ratio = 1.0, time_since_hit = 99.0})), 1.4)
	assert_almost(m.performance_factor(_ctx({hp_ratio = 0.0, time_since_hit = 0.0})), 0.6)
	assert_almost(m.performance_factor(_ctx({hp_ratio = 0.5, time_since_hit = 10.0})), 1.0)


func test_reset_returns_to_build_up() -> void:
	var m := OrchestratorModel.new()
	m.phase = Phase.RELAX
	m.intensity = 77.0
	m.phase_time = 4.0
	m.reset()
	assert_eq(m.phase, Phase.BUILD_UP)
	assert_almost(m.intensity, 0.0)
	assert_true(_until_wave(m, _ctx()).budget > 0, "tras reset vuelve a generar la primera oleada")


func test_damage_scale_by_max_hp() -> void:
	assert_almost(OrchestratorModel.hp_damage_scale(100), 1.0, 0.0001)
	assert_almost(OrchestratorModel.hp_damage_scale(70), 1.214, 0.001)
	assert_almost(OrchestratorModel.hp_damage_scale(40), 1.75, 0.0001)
	assert_almost(OrchestratorModel.hp_damage_scale(0), 1.0, 0.0001, "sin vida máxima no escala")
	assert_almost(OrchestratorModel.hp_damage_scale(10), 2.0, 0.0001, "tope x2")
