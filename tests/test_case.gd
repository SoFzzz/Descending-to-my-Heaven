class_name TestCase
extends RefCounted
# Convención: todo archivo de prueba empieza con `extends TestCase`; las pruebas que crean nodos los liberan con `free()` al final.

var failed: bool = false
var message: String = ""


func _fail(text: String, msg: String) -> void:
	failed = true
	if message.is_empty():
		message = text + (" — " + msg if not msg.is_empty() else "")


func assert_eq(actual, expected, msg := "") -> void:
	if actual != expected:
		_fail("esperado %s, obtenido %s" % [str(expected), str(actual)], msg)


func assert_true(cond: bool, msg := "") -> void:
	if not cond:
		_fail("se esperaba true, obtenido false", msg)


func assert_almost(actual: float, expected: float, eps := 0.001, msg := "") -> void:
	if absf(actual - expected) > eps:
		_fail("esperado ~%s (±%s), obtenido %s" % [str(expected), str(eps), str(actual)], msg)
