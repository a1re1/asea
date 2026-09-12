# ASEA foundation checks (task-1): project config, main scene, tooling.
# Run via: godot --headless --path . --script res://tests/run_tests.gd
extends RefCounted

const T := preload("res://tests/test_helper.gd")


func test_project_config() -> void:
	var cfg := ConfigFile.new()
	var err: int = cfg.load("res://project.godot")
	T.eq(err, OK, "project.godot loads")
	T.eq(str(cfg.get_value("application", "run/main_scene", "")),
			"res://scenes/main.tscn", "main scene is scenes/main.tscn")
	T.eq(str(cfg.get_value("rendering", "renderer/rendering_method", "")),
			"gl_compatibility", "Compatibility renderer for Mac/web")
	T.eq(int(cfg.get_value("display", "window/size/viewport_width", 0)), 1440,
			"viewport width 1440")
	T.eq(int(cfg.get_value("display", "window/size/viewport_height", 0)), 900,
			"viewport height 900")
	for action: String in ["sail_forward", "sail_back", "steer_left", "steer_right",
			"brake", "recover_boat", "toggle_chart", "close_chart"]:
		T.ok(InputMap.has_action(action), "input action registered: %s" % action)
	T.ok(not InputMap.has_action("boost"), "obsolete engine boost action removed")


func test_main_scene_loads_and_runs() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	T.ok(scene != null, "main.tscn loads as PackedScene")
	if scene == null:
		return
	var instance: Node = scene.instantiate()
	T.ok(instance is Node3D, "main scene root is Node3D")
	# Sailing rig (OceanEnvironment supplies WorldEnvironment/Sun at runtime,
	# so the scene itself must be placeholder-free).
	T.ok(instance.get_node_or_null("Boat") is Node3D, "Boat node present")
	var cam := instance.get_node_or_null("SailingCamera")
	T.ok(cam is Camera3D, "SailingCamera present")
	if cam is Camera3D:
		T.ok(cam.far >= 7000.0, "camera far plane >= 7000")
	T.ok(instance.get_node_or_null("HUD") is CanvasLayer, "HUD CanvasLayer present")
	T.ok(instance.get_node_or_null("ChartLayer") is CanvasLayer, "ChartLayer present")
	T.ok(instance.get_node_or_null("WorldEnvironment") == null,
			"no placeholder WorldEnvironment (runtime-built)")
	T.ok(instance.get_node_or_null("Sun") == null, "no placeholder Sun (runtime-built)")
	instance.free()


func test_tooling_exists() -> void:
	T.ok(FileAccess.file_exists("res://tools/verify.sh"), "tools/verify.sh exists")
	T.ok(FileAccess.file_exists("res://tests/run_tests.gd"), "tests/run_tests.gd exists")
	T.ok(FileAccess.file_exists("res://tests/test_helper.gd"), "tests/test_helper.gd exists")
	T.ok(FileAccess.file_exists("res://.gitignore"), ".gitignore exists")
	var f := FileAccess.open("res://.gitignore", FileAccess.READ)
	if f == null:
		T.fail(".gitignore readable")
		return
	var text: String = f.get_as_text()
	T.ok(text.contains(".godot/"), ".gitignore excludes .godot/")
	T.ok(text.contains(".drip/"), ".gitignore excludes .drip/")
