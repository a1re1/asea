# Non-zero-failing test runner for ASEA.
# Runs every test script under res://tests/ except helpers, this runner, and
# runtime smoke scripts. Emits a DRIP_VERIFY line so external harnesses can
# count executed checks. A run with zero executed checks is NOT a pass.
# Usage (via tools/verify.sh):
#   godot --headless --path . --script res://tests/run_tests.gd
extends SceneTree

const TestHelper: GDScript = preload("res://tests/test_helper.gd")
const RUNNER_SCRIPT: String = "run_tests.gd"
const SMOKE_MARKER: String = "runtime_smoke"
const GLOBALS: Dictionary = {
	"Object": 1, "RefCounted": 1, "Resource": 1, "Node": 1, "GDScript": 1,
	"SceneTree": 1, "WorldData": 1, "VoyageState": 1,
}


func _init() -> void:
	var scripts: PackedStringArray = _collect_test_scripts()
	if scripts.is_empty():
		printerr("[asea-tests] NO TEST SUITES FOUND — failing (0 executed checks)")
		print("DRIP_VERIFY {\"executed\": 0, \"passed\": 0, \"failed\": 0}")
		quit(1)
		return
	var suites_passed: int = 0
	var suites_failed: int = 0
	var checks_executed: int = 0
	var checks_failed: int = 0
	var failed_suites: Array[String] = []
	for path: String in scripts:
		var result: Dictionary = _run_suite(path)
		suites_passed += int(result.get("suites_passed", 0))
		suites_failed += int(result.get("suites_failed", 0))
		checks_executed += int(result.get("checks_executed", 0))
		checks_failed += int(result.get("checks_failed", 0))
		if int(result.get("suites_failed", 0)) > 0:
			failed_suites.append(path.get_file())
	print("[asea-tests] TOTAL methods passed=%d failed=%d | checks executed=%d failed=%d"
			% [suites_passed, suites_failed, checks_executed, checks_failed])
	print("DRIP_VERIFY {\"executed\": %d, \"passed\": %d, \"failed\": %d}"
			% [checks_executed, checks_executed - checks_failed, checks_failed])
	if suites_failed > 0 or checks_failed > 0 or checks_executed == 0:
		printerr("[asea-tests] FAILING suites: %s" % ", ".join(failed_suites))
		quit(1)
	else:
		quit(0)


func _collect_test_scripts() -> PackedStringArray:
	var found: PackedStringArray = []
	var dir: DirAccess = DirAccess.open("res://tests")
	if dir == null:
		return found
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".gd") \
				and name != RUNNER_SCRIPT and not name.ends_with("_helper.gd") \
				and not name.begins_with(SMOKE_MARKER):
			found.append("res://tests/" + name)
		name = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found


func _run_suite(path: String) -> Dictionary:
	var script: GDScript = load(path) as GDScript
	if script == null:
		printerr("[asea-tests] FAIL: could not load %s" % path)
		return {"suites_passed": 0, "suites_failed": 1,
				"checks_executed": 1, "checks_failed": 1}
	var instance: RefCounted = script.new()
	var suites_passed: int = 0
	var suites_failed: int = 0
	var checks_executed: int = 0
	var checks_failed: int = 0
	# get_method_list() walks the inheritance chain; drop built-ins so only the
	# suite's own test_ methods count.
	var methods: PackedStringArray = []
	for m: Dictionary in instance.get_method_list():
		var method_name := String(m["name"])
		if GLOBALS.has(method_name):
			continue
		methods.append(method_name)
	methods.sort()
	for method: String in methods:
		if not method.begins_with("test_"):
			continue
		TestHelper.reset()
		print("[asea-tests] %s :: %s" % [path.get_file(), method])
		instance.call(method)
		var method_passed: int = TestHelper.get_passed()
		var method_failed: int = TestHelper.get_failed()
		checks_executed += method_passed + method_failed
		checks_failed += method_failed
		if method_failed > 0 or method_passed == 0:
			printerr("[asea-tests]   FAIL (%d passed, %d failed)"
					% [method_passed, method_failed])
			suites_failed += 1
		else:
			print("[asea-tests]   ok (%d checks)" % method_passed)
			suites_passed += 1
	return {"suites_passed": suites_passed, "suites_failed": suites_failed,
			"checks_executed": checks_executed, "checks_failed": checks_failed}
