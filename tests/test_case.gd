class_name TestCase
extends RefCounted
# Convention: every test file starts with `extends TestCase`; tests that create nodes free them with `free()` at the end.

var failed: bool = false
var message: String = ""


func _fail(text: String, msg: String) -> void:
	failed = true
	if message.is_empty():
		message = text + (" — " + msg if not msg.is_empty() else "")


func assert_eq(actual, expected, msg := "") -> void:
	if actual != expected:
		_fail("expected %s, got %s" % [str(expected), str(actual)], msg)


func assert_true(cond: bool, msg := "") -> void:
	if not cond:
		_fail("expected true, got false", msg)


func assert_almost(actual: float, expected: float, eps := 0.001, msg := "") -> void:
	if absf(actual - expected) > eps:
		_fail("expected ~%s (±%s), got %s" % [str(expected), str(eps), str(actual)], msg)
