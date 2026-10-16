extends TestCase
# AttackTokens tests (instantiates the script, not the autoload).

const TokensScript := preload("res://scripts/ai/attack_tokens.gd")


func test_max_two_holders() -> void:
	var t: Node = TokensScript.new()
	var a := Node.new()
	var b := Node.new()
	var c := Node.new()
	assert_true(t.request(a))
	assert_true(t.request(b))
	assert_true(not t.request(c))
	for n in [t, a, b, c]:
		n.free()


func test_same_enemy_requesting_twice_keeps_one_token() -> void:
	var t: Node = TokensScript.new()
	var a := Node.new()
	assert_true(t.request(a))
	assert_true(t.request(a))
	assert_eq(t.holders_count(), 1)
	t.free()
	a.free()


func test_release_frees_a_slot() -> void:
	var t: Node = TokensScript.new()
	var a := Node.new()
	var b := Node.new()
	var c := Node.new()
	t.request(a)
	t.request(b)
	t.release(a)
	assert_true(t.request(c))
	for n in [t, a, b, c]:
		n.free()


func test_tokens_released_when_holder_freed() -> void:
	var t: Node = TokensScript.new()
	var a := Node.new()
	var b := Node.new()
	var c := Node.new()
	t.request(a)
	t.request(b)
	a.free()
	assert_true(t.request(c))
	for n in [t, b, c]:
		n.free()


func test_reset_clears_all() -> void:
	var t: Node = TokensScript.new()
	var a := Node.new()
	var b := Node.new()
	t.request(a)
	t.request(b)
	t.reset()
	assert_eq(t.holders_count(), 0)
	for n in [t, a, b]:
		n.free()


func test_is_holder_false_after_reset() -> void:
	var t: Node = TokensScript.new()
	var a := Node.new()
	t.request(a)
	assert_true(t.is_holder(a))
	t.reset()
	assert_true(not t.is_holder(a), "after reset() the minion is no longer the holder")
	for n in [t, a]:
		n.free()


func test_is_holder_false_after_release() -> void:
	var t: Node = TokensScript.new()
	var a := Node.new()
	t.request(a)
	t.release(a)
	assert_true(not t.is_holder(a))
	for n in [t, a]:
		n.free()


func test_freed_holder_is_pruned_in_place() -> void:
	var t: Node = TokensScript.new()
	var a := Node.new()
	var b := Node.new()
	assert_true(t.request(a))
	assert_true(t.request(b))
	a.free()
	assert_eq(t.holders_count(), 1)
	assert_true(t.is_holder(b))
	var c := Node.new()
	assert_true(t.request(c), "the freed slot is available again")
	for n in [t, b, c]:
		n.free()
