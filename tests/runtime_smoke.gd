extends SceneTree

# Exercise the real main scene while keeping the player's voyage untouched.
const NORMAL_SAVE := "user://voyage.json"
const SMOKE_SAVE := "user://asea_capture_voyage.json"
const ACTIONS := ["sail_forward", "sail_back", "steer_left", "steer_right", "brake", "recover_boat", "toggle_chart", "close_chart"]
var _main: Node
var _backups: Dictionary = {}
var _executed := 0
var _failed := 0
var _finished := false


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> bool:
	_executed += 1
	if not condition:
		_failed += 1
	print("%s runtime: %s" % ["PASS" if condition else "FAIL", message])
	return condition


func _remember(path: String) -> bool:
	var existed := FileAccess.file_exists(path)
	var contents := PackedByteArray()
	if existed:
		var file := FileAccess.open(path, FileAccess.READ)
		if not _check(file != null, "can preserve existing save fixture"):
			return false
		contents = file.get_buffer(file.get_length())
	_backups[path] = {"existed": existed, "contents": contents}
	return true


func _matches_backup(path: String) -> bool:
	var saved: Dictionary = _backups[path]
	if FileAccess.file_exists(path) != bool(saved.existed):
		return false
	return not bool(saved.existed) or FileAccess.get_file_as_bytes(path) == saved.contents


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _chart_key() -> void:
	_key(KEY_M, true)
	_check(Input.is_action_just_pressed("toggle_chart"), "physical M reaches chart action")
	_main._process(1.0 / 60.0)
	_key(KEY_M, false)
	await process_frame
	await process_frame


func _advance(frames: int) -> void:
	# Real controllers and Input polling, with reproducible simulation time.
	for _frame in range(frames):
		_main.boat._process(1.0 / 60.0)
		_main._process(1.0 / 60.0)


func _place_fixture(position: Vector2, heading := 0.0) -> void:
	_main.boat.planar_pos = position
	_main.boat.heading = heading
	_main.boat.speed = 0.0
	_main.boat.sail_amount = 0.0
	_main.boat.wind.set_fixed(Vector2(0, -1), 10.0)
	_main.boat._sync_transform()
	# Setup is a teleport, so it must not be interpreted as a sailed segment.
	_main.voyage.boat_position = position
	_main.voyage.boat_heading = heading


func _run() -> void:
	if not _check("--asea-smoke" in OS.get_cmdline_user_args(), "isolated-save argument supplied"):
		_finish()
		return
	if not _remember(NORMAL_SAVE) or not _remember(SMOKE_SAVE):
		_finish()
		return
	create_timer(20.0, true, false, true).timeout.connect(func():
		if not _finished:
			_check(false, "runtime watchdog expired")
			_finish())
	var scene := load("res://scenes/main.tscn") as PackedScene
	if not _check(scene != null, "main scene loads"):
		_finish()
		return
	_main = scene.instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	await process_frame
	if not _check(_main.voyage != null and _main.boat != null and _main.chart != null, "main components initialized"):
		_finish()
		return
	if not _check(_main.voyage.save_path == SMOKE_SAVE, "main uses isolated save"):
		_finish()
		return
	_main.set_process(false)
	_main.boat.set_process(false)
	_main.hud.dismiss_intro()
	_check(_main.hud._region.size.y >= 18.0 and not _main.hud._region.text.is_empty(), "region label has visible laid-out text")
	_check(_main.world_data.locations.size() == 34, "all 34 locations loaded")
	_check(_main.world_data.large_islands().size() == 9, "nine large islands loaded")
	var boat = _main.boat
	var voyage = _main.voyage
	boat.wind.set_fixed(Vector2(0, -1), 10.0)
	_check(boat.process_priority < _main.process_priority, "boat advances before ocean uniforms each frame")
	var start: Vector2 = boat.planar_pos
	Input.action_press("sail_forward")
	_advance(240)
	_check(boat.planar_pos.distance_to(start) > 5.0 and boat.speed > 0.0, "forward input sails actual boat")
	var fair_wind = boat.wind
	boat.wind = load("res://scripts/wind.gd").new()
	boat.wind.step(120.0)
	_advance(1)
	var ocean_material: ShaderMaterial = _main._ocean._ocean_material
	_check(absf(float(ocean_material.get_shader_parameter("wave_time")) - boat.sim_time) < 1e-5, "ocean uses current boat simulation time")
	var ocean_direction: Vector2 = ocean_material.get_shader_parameter("wind_dir")
	_check(boat.wind.direction.distance_to(boat.wind.swell_direction) > 0.01 and ocean_direction.distance_to(boat.wind.swell_direction) < 1e-5, "ocean uses lagged swell when weather direction differs")
	boat.wind = fair_wind
	var old_heading: float = boat.heading
	Input.action_press("steer_right")
	_advance(30)
	Input.action_release("steer_right")
	_check(absf(boat.heading - old_heading) > 0.05, "steering input changes heading")
	Input.action_release("sail_forward")
	var sail: MeshInstance3D = boat._sail as MeshInstance3D
	var flag: Node3D = boat._flag
	if not _check(sail != null and flag != null, "actual sail and wind pennant meshes loaded"):
		_finish()
		return
	var raised_scale: float = sail.scale.y
	var foot_before: float = sail.position.y + sail.scale.y * sail.get_aabb().position.y
	_check(raised_scale > 0.9, "hoisted sail has full visual height")
	var flag_axis := Vector2(flag.global_basis.z.x, flag.global_basis.z.z).normalized()
	_check(flag_axis.dot(boat.wind.direction) > 0.98, "pennant world axis points with wind after steering")
	var raised_amount: float = boat.sail_amount
	_key(KEY_S, true)
	_check(Input.is_action_pressed("sail_back"), "physical S reaches lower-sail action")
	_advance(24)
	_key(KEY_S, false)
	_check(boat.sail_amount < raised_amount - 0.2 and boat.sail_amount >= 0.0, "physical S lowers canvas without reverse")
	_key(KEY_SPACE, true)
	_check(Input.is_action_pressed("brake"), "physical Space reaches drop-sail action")
	_advance(1)
	_key(KEY_SPACE, false)
	_check(boat.sail_amount == 0.0 and boat.speed > 0.5, "Space drops canvas while hull still coasts")
	_check(sail.scale.y > 0.0 and sail.scale.y <= 0.1 and sail.scale.y < raised_scale, "furled canvas has compact non-singular visual height")
	var foot_after: float = sail.position.y + sail.scale.y * sail.get_aabb().position.y
	_check(absf(foot_after - foot_before) < 0.08, "reefing keeps mesh foot at boom (raised %.4f, dropped %.4f)" % [foot_before, foot_after])
	await _chart_key()
	_check(_main.chart_open and _main.chart.visible, "M opens visible chart")
	_check(boat.frozen and _main.cam.frozen and not _main.hud.visible, "chart freezes sailing and camera controls")
	var frozen_pose: Vector2 = boat.planar_pos
	var frozen_heading: float = boat.heading
	var frozen_sail: float = boat.sail_amount
	var frozen_speed: float = boat.speed
	var frozen_time: float = boat.sim_time
	Input.action_press("sail_forward")
	Input.action_press("steer_left")
	_advance(45)
	_check(boat.planar_pos == frozen_pose and boat.heading == frozen_heading, "input cannot move boat while chart is open")
	_check(boat.sail_amount == frozen_sail and boat.speed == frozen_speed and boat.sim_time == frozen_time, "chart freezes canvas, speed and simulation clock")
	Input.action_release("steer_left")
	await _chart_key()
	_check(not _main.chart_open and not boat.frozen and not _main.cam.frozen, "M closes chart and unfreezes controls")
	_advance(60)
	_check(boat.planar_pos.distance_to(frozen_pose) > 1.0, "sailing resumes after chart closes")
	Input.action_release("sail_forward")
	_main.hud.chart_pressed.emit()
	_check(_main.chart_open and _main.chart.visible and boat.frozen, "HUD CHART signal opens chart")
	_main.chart.close_requested.emit()
	_check(not _main.chart_open and not boat.frozen, "chart close signal resumes sailing")

	var target: Dictionary = {}
	var approach := Vector2.ZERO
	for location: Dictionary in _main.world_data.locations:
		if location.kind != "buoy" or voyage.is_discovered(str(location.id)):
			continue
		var pos: Vector2 = location.pos
		var candidate := pos + Vector2(0.0, float(location.radius) + voyage.DISCOVERY_MARGIN + 10.0)
		if not _main.world_data.overlaps_land(candidate, 8.0) and not _main.world_data.overlaps_land(candidate - Vector2(0, 35), 8.0):
			target = location
			approach = candidate
			break
	if not _check(not target.is_empty(), "undiscovered buoy has safe sailing approach"):
		_finish()
		return
	_place_fixture(approach)
	_advance(1)
	_check(not voyage.is_discovered(str(target.id)), "approach starts outside discovery range")
	Input.action_press("sail_forward")
	_advance(240)
	Input.action_release("sail_forward")
	_check(voyage.is_discovered(str(target.id)), "sailing discovers buoy through main integration")
	_check(voyage.is_revealed(boat.planar_pos), "sailed water becomes charted")

	var spawn: Vector2 = _main.world_data.boat_spawn().pos
	var remote := Vector2.ZERO
	var middle := Vector2.ZERO
	var found_remote := false
	for candidate: Vector2 in [Vector2(2100, 2100), Vector2(-2100, 2100), Vector2(2100, -2100), Vector2(-2100, -2100)]:
		var halfway := candidate.lerp(spawn, 0.5)
		if not _main.world_data.overlaps_land(candidate, 8.0) and not voyage.is_revealed(halfway):
			remote = candidate
			middle = halfway
			found_remote = true
			break
	if not _check(found_remote, "recovery fixture crosses uncharted sea"):
		_finish()
		return
	_place_fixture(remote)
	_advance(1)
	_check(not voyage.is_revealed(middle), "fixture placement did not reveal recovery route")
	Input.action_press("recover_boat")
	_advance(1)
	Input.action_release("recover_boat")
	await process_frame
	await process_frame
	_check(boat.planar_pos.distance_to(spawn) < 0.01, "recovery input returns to harbor")
	_check(not voyage.is_revealed(middle), "recovery does not reveal intervening sea")
	_check(voyage.set_waypoint(str(target.id)), "charted waypoint accepted")
	_main.hud._refresh()
	await process_frame
	await process_frame
	_check(_main.hud._waypoint.size.y >= 18.0 and not _main.hud._waypoint.text.is_empty(), "selected waypoint has visible laid-out text")
	_main._save_voyage()
	_check(FileAccess.file_exists(SMOKE_SAVE), "runtime writes isolated voyage")
	var restored = load("res://scripts/voyage_state.gd").new()
	restored.setup(_main.world_data, SMOKE_SAVE)
	_check(restored.discovered_ids == voyage.discovered_ids and restored.is_discovered(str(target.id)), "discoveries persist through save/load")
	_check(restored.revealed_cells == voyage.revealed_cells, "charted fog persists through save/load")
	_check(restored.boat_position.distance_to(voyage.boat_position) < 0.01 and is_equal_approx(restored.boat_heading, voyage.boat_heading), "boat pose persists through save/load")
	_check(restored.waypoint_id == str(target.id), "waypoint persists through save/load")
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	for action: String in ACTIONS:
		Input.action_release(action)
	_key(KEY_M, false)
	_key(KEY_S, false)
	_key(KEY_SPACE, false)
	if is_instance_valid(_main):
		_main.free()
	if _backups.has(NORMAL_SAVE):
		_check(_matches_backup(NORMAL_SAVE), "player voyage remains byte-for-byte untouched")
	for path: String in _backups:
		if _matches_backup(path):
			continue
		var backup: Dictionary = _backups[path]
		if backup.existed:
			var file := FileAccess.open(path, FileAccess.WRITE)
			if _check(file != null, "restore preexisting save fixture"):
				file.store_buffer(backup.contents)
		else:
			_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "remove isolated save created by smoke")
	print('DRIP_VERIFY {"executed":%d,"passed":%d,"failed":%d}' % [_executed, _executed - _failed, _failed])
	quit(1 if _failed else 0)
