extends SceneTree
## Frame profile of level 3: forces Ghidorah attacks (bite, tail sweep and beam) in two rounds
## and records the time of every frame. Run WITH a window (no --headless):
##   godot --path . --resolution 1280x720 -s res://scripts/tools/ghidorah_profile.gd
## Prints the slow frames (> SLOW_MS) with the boss state and a per-round summary.

const SLOW_MS := 12.0
const PLAN := [
	[2.0, &"bite", 3.0], [8.0, &"tail_sweep", 4.0], [14.0, &"beam", 11.0],
	[21.0, &"bite", 3.0], [27.0, &"tail_sweep", 4.0], [33.0, &"beam", 11.0],
]
const END_TIME := 40.0

var _level: Node
var _boss: Boss
var _player: Node3D
var _all: Array[BossAttack] = []
var _t := 0.0
var _last_us := 0
var _next := 0
var _frames: Array = []   # [t, ms, state, attack, draws, nodes]
var _frame_no := 0


func _initialize() -> void:
	_level = (load("res://scenes/levels/arena_3_gameplay.tscn") as PackedScene).instantiate()
	root.add_child(_level)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # real time of each frame, without the 60 Hz cap
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frame_no += 1
	if _player == null:
		if _frame_no < 5:
			return
		_boss = _level.get_node_or_null(^"Boss") as Boss
		_player = _level.get_node_or_null(^"Kaelen") as Node3D
		_player.set(&"_god", true)
		_all = _boss.attacks.duplicate()
		_boss.attacks = []
		_last_us = Time.get_ticks_usec()
		return
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0
	_last_us = now
	_t += ms / 1000.0
	if _next < PLAN.size() and _t >= PLAN[_next][0]:
		_force(PLAN[_next][1], PLAN[_next][2])
		_next += 1
	_frames.append([_t, ms, _boss.state, _boss.current_attack.id if _boss.current_attack else &"-",
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
			RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())])
	if _t >= END_TIME:
		_report()
		quit()


func _force(id: StringName, distance: float) -> void:
	for a in _all:
		if a.id == id:
			_boss.attacks = [a] as Array[BossAttack]
	_boss.brain.last_attack_id = &""
	var dir := (_player.global_position - _boss.global_position)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.BACK
	_player.global_position = _boss.global_position + dir * distance + Vector3.UP * 0.2
	print("[%.2f] forcing %s (frame %d)" % [_t, id, _frame_no])


func _report() -> void:
	var sorted: Array = _frames.map(func(f): return f[1])
	sorted.sort()
	print("--- slow frames (> %.0f ms) ---" % SLOW_MS)
	for f in _frames:
		if f[1] > SLOW_MS:
			print("t=%.2f  %.1f ms  state=%d attack=%s draws=%d nodes=%d proc=%.1f phys=%.1f gpu=%.1f rcpu=%.1f" % [f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8], f[9]])
	var sum := 0.0
	for v in sorted:
		sum += v
	print("--- summary: %d frames, mean %.2f ms, median %.2f, p99 %.2f, max %.1f ---" % [
			sorted.size(), sum / sorted.size(), sorted[sorted.size() / 2], sorted[int(sorted.size() * 0.99)], sorted.back()])
	for round_i in 2:
		var lo := 0.0 if round_i == 0 else 19.0
		var hi := 19.0 if round_i == 0 else 40.0
		var m := 0.0
		var n := 0
		for f in _frames:
			if f[0] >= lo and f[0] < hi:
				m = maxf(m, f[1])
				n += 1
		print("round %d: max %.1f ms (%d frames)" % [round_i + 1, m, n])

	var groups := {}
	for f in _frames:
		var key := "%s/%d" % [f[3], f[2]]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(f[1])
	var keys := groups.keys()
	keys.sort()
	for k in keys:
		var arr: Array = groups[k]
		arr.sort()
		var total := 0.0
		for v in arr:
			total += v
		print("  %-14s n=%4d mean=%.2f p95=%.2f max=%.1f ms" % [k, arr.size(), total / arr.size(), arr[int(arr.size() * 0.95)], arr.back()])
