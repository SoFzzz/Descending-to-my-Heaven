extends TestCase
# Lock-on tests (target released and max distance of 15 m / 25 m with bosses).
# Outside the tree, LockOn measures with `position` (origin and target have no parent).


func _make(distance: float, boss: bool) -> Array:
	var lock := LockOn.new()
	var origin := Node3D.new()
	var target := Node3D.new()
	target.add_to_group("lockable")
	if boss:
		target.add_to_group("boss")
	target.position = Vector3(0.0, 0.0, distance)
	lock.origin = origin
	lock.target = target
	return [lock, origin, target]


func test_lock_on_drops_invalid_target() -> void:
	var n := _make(3.0, false)
	var lock: LockOn = n[0]
	(n[2] as Node3D).free()
	lock.validate()
	assert_eq(lock.target, null)
	lock.free()
	(n[1] as Node3D).free()


func test_lock_on_range() -> void:
	var n := _make(16.0, false)
	(n[0] as LockOn).validate()
	assert_eq((n[0] as LockOn).target, null, "16 m sin grupo boss se suelta")
	for x in n:
		(x as Node).free()

	n = _make(16.0, true)
	(n[0] as LockOn).validate()
	assert_eq((n[0] as LockOn).target, n[2], "16 m con grupo boss se mantiene")
	for x in n:
		(x as Node).free()

	n = _make(26.0, true)
	(n[0] as LockOn).validate()
	assert_eq((n[0] as LockOn).target, null, "26 m con grupo boss se suelta")
	for x in n:
		(x as Node).free()

	n = _make(14.0, false)
	(n[0] as LockOn).validate()
	assert_eq((n[0] as LockOn).target, n[2], "14 m sin grupo boss se mantiene")
	for x in n:
		(x as Node).free()


func test_max_range() -> void:
	assert_almost(LockOn.max_range_for(false), 15.0)
	assert_almost(LockOn.max_range_for(true), 25.0)
