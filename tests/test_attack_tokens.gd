extends TestCase
# Pruebas de AttackTokens (instancia el script, no el autoload).

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
