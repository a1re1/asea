# Shared assertion helper for ASEA tests.
# Test scripts preload this and call its STATIC methods; the runner resets the
# counters around each test method and requires at least one executed check.
# Example inside a test method:
#   const T := preload("res://tests/test_helper.gd")
#   T.ok(locations.size() == 34, "34 locations")
extends RefCounted

static var _passed: int = 0
static var _failed: int = 0


static func reset() -> void:
	_passed = 0
	_failed = 0


static func get_passed() -> int:
	return _passed


static func get_failed() -> int:
	return _failed


static func ok(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("[asea-tests]     assertion failed: %s" % label)


static func fail(label: String) -> void:
	ok(false, label)


static func eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		printerr("[asea-tests]     assertion failed: %s (expected %s, got %s)"
				% [label, str(expected), str(actual)])


static func near(actual: float, expected: float, tolerance: float, label: String) -> void:
	ok(absf(actual - expected) <= tolerance,
			"%s (expected %f +/- %f, got %f)" % [label, expected, tolerance, actual])


static func between(value: float, low: float, high: float, label: String) -> void:
	ok(value >= low and value <= high,
			"%s (expected in [%f, %f], got %f)" % [label, low, high, value])
