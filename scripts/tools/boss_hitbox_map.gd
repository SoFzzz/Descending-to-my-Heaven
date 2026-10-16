extends SceneTree
## Boss damage-zone coverage map: for each attack, plays its animation, walks the ACTIVE window
## and marks the floor points (0.5 m grid in the boss frame, -Z = forward) that would reach Kaelen
## (capsule of 0.3 m radius, axis from 0.4 to 1.3 m). Prints the map ('#' reached, '.' free inside
## the attack range, ' ' out of range) and the percentage of free area inside the range. Usage:
##   godot --headless --path . -s res://scripts/tools/boss_hitbox_map.gd

const BOSSES := [
	"res://scenes/bosses/boss_bonedragon.tscn",
	"res://scenes/bosses/boss_blackhorn.tscn",
	"res://scenes/bosses/boss_ghidorah.tscn",
]
const STEP := 0.5
const X_MAX := 8.0
const Z_MAX := 9.0
const KAELEN_RADIUS := 0.3
const SAMPLES := 24   # frames sampled in the ACTIVE window


func _initialize() -> void:
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _main() -> void:
	for path in BOSSES:
		var boss := (load(path) as PackedScene).instantiate() as Boss
		boss.set_physics_process(false)
		root.add_child(boss)
		await process_frame
		for attack in boss.attacks:
			await _map(boss, attack)
		boss.queue_free()
		await process_frame
	quit()


func _map(boss: Boss, attack: BossAttack) -> void:
	var anim := boss.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var hitboxes: Array[Node3D] = []
	hitboxes.append(boss.get_node(attack.hitbox_path) as Node3D)
	for p in attack.extra_hitbox_paths:
		hitboxes.append(boss.get_node(p) as Node3D)
	var nx := int(X_MAX * 2 / STEP) + 1
	var nz := int(Z_MAX * 2 / STEP) + 1
	var covered := PackedByteArray()
	covered.resize(nx * nz)
	anim.play(attack.animation)
	var base_xf := boss.global_transform
	for s in SAMPLES:
		var progress := (s + 0.5) / SAMPLES
		var t := attack.telegraph_time + attack.active_time * progress
		anim.seek(minf(t, anim.current_animation_length), true)
		# Boss spin and advance during ACTIVE, as boss.gd does.
		boss.global_transform = base_xf
		boss.rotation.y += deg_to_rad(attack.spin_degrees) * progress
		boss.global_position += -boss.global_basis.z * attack.advance_at(progress) if attack.spin_degrees == 0.0 else Vector3.ZERO
		await process_frame
		await process_frame
		for hb in hitboxes:
			var cs := hb.get_node(^"CollisionShape3D") as CollisionShape3D
			for iz in nz:
				for ix in nx:
					var local := Vector3(-X_MAX + ix * STEP, 0.0, -Z_MAX + iz * STEP)
					var world := base_xf * local
					if _touches(cs, world):
						covered[iz * nx + ix] = 1
	boss.global_transform = base_xf
	anim.stop()
	var in_range := 0
	var free := 0
	var lines: PackedStringArray = []
	for iz in nz:
		var row := ""
		for ix in nx:
			var local := Vector3(-X_MAX + ix * STEP, 0.0, -Z_MAX + iz * STEP)
			var flat := Vector2(local.x, local.z).length()
			var hit := covered[iz * nx + ix] == 1
			# "In range": the boss picks the attack with Kaelen at a distance of [min_range, max_range]
			# IN FRONT of it, inside a cone of about 30 degrees (it turns toward her during the
			# telegraph) and always within 1.5 m sideways; far sides / behind need no coverage.
			var forward := local.z <= 0.0 and absf(local.x) <= maxf(1.5, absf(local.z) * 0.6)
			var counted := flat >= maxf(attack.min_range, 0.5) and flat <= attack.max_range and forward
			if counted:
				in_range += 1
				if not hit:
					free += 1
			row += "#" if hit else ("." if counted else " ")
		lines.append(row)
	print("== %s / %s: range %.1f-%.1f m, free area inside the range: %d of %d cells (%.0f %%)" % [
			boss.display_name, attack.id, attack.min_range, attack.max_range, free, in_range,
			100.0 * free / maxf(1, in_range)])
	if OS.get_cmdline_user_args().has("map"):
		for l in lines:
			print(l)


func _touches(cs: CollisionShape3D, point_xz: Vector3) -> bool:
	var xf := cs.global_transform
	for i in 5:
		var p := point_xz + Vector3(0.0, lerpf(0.4, 1.3, i / 4.0), 0.0)
		if _dist(cs.shape, xf, p) <= KAELEN_RADIUS:
			return true
	return false


func _dist(shape: Shape3D, xf: Transform3D, p: Vector3) -> float:
	var l := xf.affine_inverse() * p
	if shape is SphereShape3D:
		return maxf(l.length() - (shape as SphereShape3D).radius, 0.0)
	if shape is BoxShape3D:
		var h := (shape as BoxShape3D).size * 0.5
		return Vector3(maxf(absf(l.x) - h.x, 0.0), maxf(absf(l.y) - h.y, 0.0), maxf(absf(l.z) - h.z, 0.0)).length()
	if shape is CapsuleShape3D:
		var c := shape as CapsuleShape3D
		var half := maxf(c.height * 0.5 - c.radius, 0.0)
		var q := Vector3(0.0, clampf(l.y, -half, half), 0.0)
		return maxf((l - q).length() - c.radius, 0.0)
	if shape is CylinderShape3D:
		var cy := shape as CylinderShape3D
		return Vector2(maxf(Vector2(l.x, l.z).length() - cy.radius, 0.0), maxf(absf(l.y) - cy.height * 0.5, 0.0)).length()
	return INF
