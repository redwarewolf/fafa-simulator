class_name TestCase
extends RefCounted

## Minimal assertion base for tests/run_tests.gd. A test file extends this
## and defines test_* methods; failures are collected, not thrown, so one
## bad assertion doesn't hide the rest of the file's results.

var failures : Array[String] = []
var _current := ""

func _fail(msg: String) -> void:
	failures.append("%s: %s" % [_current, msg])

func assert_true(cond: bool, msg: String = "expected true") -> void:
	if not cond:
		_fail(msg)

func assert_eq(actual, expected, msg: String = "") -> void:
	if actual != expected:
		_fail("%s expected %s, got %s" % [msg, str(expected), str(actual)])

func assert_near(actual: float, expected: float, tol: float, msg: String = "") -> void:
	if absf(actual - expected) > tol:
		_fail("%s expected %.4f ± %.4f, got %.4f" % [msg, expected, tol, actual])

func assert_between(actual: float, lo: float, hi: float, msg: String = "") -> void:
	if actual < lo or actual > hi:
		_fail("%s expected in [%.4f, %.4f], got %.4f" % [msg, lo, hi, actual])
