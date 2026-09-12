# ASEA • The Unwritten Sea — voyage_state tests (task-1 author draft).
# Covers: initial harbor-only discovery, remote fog hidden, swept reveal,
# discovery-once + signal, save/load roundtrip via unique user:// paths,
# corrupt / wrong-version / nonfinite / out-of-bounds / beached / stale-id
# saves rejected, cell math, new_voyage reset. Cleans up its own saves.
extends RefCounted

const T: GDScript = preload("res://tests/test_helper.gd")
const VoyageState: GDScript = preload("res://scripts/voyage_state.gd")

var _wd: WorldData = null
var _save_counter: int = 0


func _wdz() -> WorldData:
	if _wd == null:
		_wd = WorldData.load_default()
	return _wd


## Unique save path per call so edited/retried runs never collide.
func _unique_save_path() -> String:
	_save_counter += 1
	return "user://test_voyage_%d_%d.json" % [Time.get_ticks_msec(), _save_counter]


func _cleanup(save_path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _fresh_state() -> VoyageState:
	var vs: VoyageState = VoyageState.new()
	vs.setup(_wdz(), _unique_save_path())
	return vs


# --- initial state ----------------------------------------------------------


func test_setup_harbor_only() -> void:
	var vs: VoyageState = _fresh_state()
	T.ok(vs != null, "state exists")
	T.eq(vs.get_charted_count(), 1, "exactly 1 charted at setup")
	T.ok(vs.is_discovered("harbor_thistlerow"), "harbor discovered at setup")
	for entry: Dictionary in _wdz().locations:
		var id: String = String(entry["id"])
		if id != "harbor_thistlerow":
			T.ok(not vs.is_discovered(id), "remote hidden at setup: %s" % id)
	T.eq(String(vs.waypoint_id), "", "no waypoint at setup")
	T.near(vs.boat_position.x, 150.0, 1.0, "spawn x")
	T.near(vs.boat_position.y, 290.0, 1.0, "spawn z")
	T.near(vs.boat_heading, 0.0, 0.001, "heading 0")
	T.ok(vs.cell_size > 0.0, "public cell_size positive")
	_cleanup(vs.save_path)


func test_initial_fog_local_only() -> void:
	var vs: VoyageState = _fresh_state()
	T.ok(vs.is_revealed(Vector2(150, 290)), "spawn revealed")
	T.ok(vs.is_revealed(Vector2(0, 200)), "harbor revealed")
	T.ok(not vs.is_revealed(Vector2(-2000, -2000)), "far NW fogged")
	T.ok(not vs.is_revealed(Vector2(2300, 2300)), "far SE fogged")
	T.ok(not vs.is_revealed(Vector2(0, -1800)), "far north fogged")
	_cleanup(vs.save_path)


func test_cell_size_grid_dimensions() -> void:
	var vs: VoyageState = _fresh_state()
	T.near(vs.cell_size, 125.0, 0.001, "cell size 125")
	T.ok(int(ceilf(_wdz().world_half_extent * 2.0 / vs.cell_size)) == 40,
			"40x40 grid = 1600 max fog cells")
	T.ok(not vs.is_revealed(Vector2(-2499, -2499)), "corner stays fogged")
	_cleanup(vs.save_path)


# --- discovery + fog sweep ----------------------------------------------------


func test_update_position_discovery_once_and_signal() -> void:
	var vs: VoyageState = _fresh_state()
	var signals: Array[String] = []
	vs.discovered.connect(func(id: String) -> void:
		signals.append(id))
	var center: Vector2 = _wdz().get_location_pos("small_copper_bell")
	vs.update_position(center, 0.0)
	vs.update_position(center + Vector2(0, 80), 0.0)
	T.eq(signals.count("small_copper_bell"), 1, "new discovery emits exactly once")
	T.eq(signals.count("harbor_thistlerow"), 0, "known harbor emits no duplicate")
	T.ok(vs.is_discovered("small_copper_bell"), "buoy discovered after pass")
	T.eq(vs.get_charted_count(), 2, "harbor and new buoy charted")
	var restored: VoyageState = VoyageState.new()
	restored.setup(_wdz(), vs.save_path)
	T.ok(restored.is_discovered("small_copper_bell"), "new discovery autosaved")
	_cleanup(vs.save_path)


func test_swept_path_reveals_without_gaps() -> void:
	var vs: VoyageState = _fresh_state()
	# Long straight voyage far past one reveal radius: every probe point on
	# the line must be revealed (sweep must not tunnel).
	var a: Vector2 = Vector2(150, 290)
	var b: Vector2 = Vector2(150, 1500)
	vs.update_position(b, 0.0)
	for t: int in range(0, 11):
		var probe: Vector2 = a.lerp(b, float(t) / 10.0)
		T.ok(vs.is_revealed(probe), "swept path revealed at t=%.1f" % (float(t) / 10.0))
	# Side offset outside the reveal corridor stays fogged.
	T.ok(not vs.is_revealed(Vector2(900, 800)), "outside corridor fogged")
	_cleanup(vs.save_path)


func test_long_jump_discovery_uses_true_segment() -> void:
	var vs: VoyageState = _fresh_state()
	var wd: WorldData = _wdz()
	# Find a location far from spawn and sail a long segment past its center.
	var target: Dictionary = {}
	var far_center: Vector2 = Vector2.ZERO
	for entry: Dictionary in wd.locations:
		var pos: Vector2 = entry["pos"]
		if pos.distance_to(Vector2(150, 290)) > 1200.0:
			target = entry
			far_center = pos
			break
	T.ok(not target.is_empty(), "found a remote target")
	if target.is_empty():
		_cleanup(vs.save_path)
		return
	var dir: Vector2 = (far_center - Vector2(150, 290)).normalized()
	var past: Vector2 = far_center + dir * 400.0
	var before: int = vs.get_charted_count()
	vs.update_position(past, 0.0)
	T.ok(vs.is_discovered(String(target["id"])),
			"long jump discovers target on true segment: %s" % String(target["id"]))
	T.ok(vs.get_charted_count() > before, "charted count increased")
	_cleanup(vs.save_path)


func test_waypoint_only_discovered_ids() -> void:
	var vs: VoyageState = _fresh_state()
	T.ok(not vs.set_waypoint("isle_foo_unknown"), "unknown id rejected")
	T.eq(String(vs.waypoint_id), "", "waypoint unchanged after reject")
	T.ok(vs.set_waypoint("harbor_thistlerow"), "discovered id accepted")
	T.eq(String(vs.waypoint_id), "harbor_thistlerow", "waypoint stored")
	T.ok(vs.set_waypoint(""), "empty clears")
	T.eq(String(vs.waypoint_id), "", "waypoint cleared")
	_cleanup(vs.save_path)


# --- persistence --------------------------------------------------------------


func test_save_load_roundtrip() -> void:
	var vs: VoyageState = _fresh_state()
	var path: String = vs.save_path
	var center: Vector2 = _wdz().get_location_pos("harbor_thistlerow")
	vs.update_position(center + Vector2(0, 200), 1.25)
	vs.set_waypoint("harbor_thistlerow")
	T.ok(vs.save(), "save returns true")
	var reveal_count: int = vs.revealed_cells.size()
	T.ok(reveal_count > 0, "some fog revealed before save")
	var vs2: VoyageState = VoyageState.new()
	vs2.setup(_wdz(), path)
	T.ok(vs2.is_discovered("harbor_thistlerow"), "discovery survives roundtrip")
	T.eq(vs2.get_charted_count(), vs.get_charted_count(), "count matches")
	T.near(vs2.boat_position.x, vs.boat_position.x, 0.01, "pose x roundtrip")
	T.near(vs2.boat_position.y, vs.boat_position.y, 0.01, "pose z roundtrip")
	T.near(vs2.boat_heading, vs.boat_heading, 0.01, "heading roundtrip")
	T.eq(vs2.revealed_cells.size(), reveal_count, "fog cells roundtrip")
	T.eq(String(vs2.waypoint_id), "harbor_thistlerow", "waypoint roundtrip")
	_cleanup(path)


func test_load_missing_file_returns_false_keeps_state() -> void:
	var vs: VoyageState = _fresh_state()
	var count: int = vs.get_charted_count()
	_cleanup(vs.save_path)
	T.ok(not vs.load_save(), "missing save returns false")
	T.eq(vs.get_charted_count(), count, "state untouched after failed load")
	_cleanup(vs.save_path)


func _write_save(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _expect_reject(path: String, text: String, label: String) -> void:
	var vs: VoyageState = VoyageState.new()
	vs.setup(_wdz(), path)
	_write_save(path, text)
	T.ok(not vs.load_save(), label)
	T.eq(vs.get_charted_count(), 1, "%s: falls back to fresh harbor-only" % label)
	T.near(vs.boat_position.x, 150.0, 1.0, "%s: spawn pose kept" % label)
	_cleanup(path)


func test_corrupt_json_rejected() -> void:
	_expect_reject(_unique_save_path(), "{not json at all", "corrupt JSON")


func test_wrong_version_rejected() -> void:
	var payload: String = JSON.stringify({
		"version": 999,
		"boat": {"pos": [150.0, 290.0], "heading": 0.0},
		"discovered": ["harbor_thistlerow"],
		"revealed": [],
	})
	_expect_reject(_unique_save_path(), payload, "wrong version")
	_expect_reject(_unique_save_path(), payload.replace("999", "1.9"), "fractional version")


func test_nonfinite_rejected() -> void:
	var payload: String = "{\"version\":1,\"boat\":{\"pos\":[150,NaN],\"heading\":0.0},\"discovered\":[],\"revealed\":[]}"
	_expect_reject(_unique_save_path(), payload, "NaN position")
	_expect_reject(_unique_save_path(), payload.replace("NaN", "1e999"), "overflowed position")


func test_invalid_waypoint_rejected_transactionally() -> void:
	var vs: VoyageState = _fresh_state()
	vs.set_waypoint("harbor_thistlerow")
	var before_fog: Dictionary = vs.revealed_cells.duplicate()
	_write_save(vs.save_path, JSON.stringify({
		"version": 1, "boat": {"pos": [900.0, 0.0], "heading": 2.0},
		"waypoint": 42, "discovered": [], "revealed": [],
	}))
	T.ok(not vs.load_save(), "wrong waypoint type rejected")
	T.eq(vs.boat_position, Vector2(150, 290), "failed load preserves original pose")
	T.eq(vs.waypoint_id, "harbor_thistlerow", "failed load preserves waypoint")
	T.eq(vs.revealed_cells, before_fog, "failed load preserves fog")
	var recovered: VoyageState = VoyageState.new()
	recovered.setup(_wdz(), vs.save_path)
	T.eq(recovered.get_charted_count(), 1, "setup falls back to fresh harbor on malformed save")
	T.eq(recovered.boat_position, Vector2(150, 290), "setup fallback is safe spawn")
	_cleanup(vs.save_path)


func test_out_of_bounds_pose_rejected() -> void:
	var payload: String = JSON.stringify({
		"version": 1,
		"boat": {"pos": [9999.0, 9999.0], "heading": 0.0},
		"discovered": [],
		"revealed": [],
	})
	_expect_reject(_unique_save_path(), payload, "out of bounds")


func test_beached_pose_rejected() -> void:
	# Drop the pose on a large island's center: overlaps_land(8) must reject.
	var beach: Vector2 = Vector2.ZERO
	for entry: Dictionary in _wdz().large_islands():
		beach = entry["pos"]
		break
	T.ok(_wdz().overlaps_land(beach, 8.0), "island center is land")
	var payload: String = JSON.stringify({
		"version": 1,
		"boat": {"pos": [beach.x, beach.y], "heading": 0.0},
		"discovered": ["harbor_thistlerow"],
		"revealed": [],
	})
	_expect_reject(_unique_save_path(), payload, "beached pose")


func test_stale_and_type_offenders_rejected() -> void:
	var bad_ids: String = JSON.stringify({
		"version": 1,
		"boat": {"pos": [150.0, 290.0], "heading": 0.0},
		"discovered": ["isle_never_existed", 42],
		"revealed": [],
	})
	_expect_reject(_unique_save_path(), bad_ids, "stale id + wrong type")


func test_load_validates_discovered_and_revealed_types() -> void:
	var path: String = _unique_save_path()
	var payload: String = JSON.stringify({
		"version": 1,
		"boat": {"pos": [150.0, 290.0], "heading": 0.0},
		"discovered": ["harbor_thistlerow"],
		"revealed": [[0, 0], ["x", 1], [1], [99, 99]],
	})
	# ["x",1] and [1] are corrupt -> whole load rejected.
	_expect_reject(path, payload, "bad revealed pairs")


func test_stale_unknown_discovered_id_dropped() -> void:
	var path: String = _unique_save_path()
	var payload: String = JSON.stringify({
		"version": 1,
		"boat": {"pos": [150.0, 290.0], "heading": 0.0},
		"discovered": ["isle_gone_forever"],
		"revealed": [[20, 20]],
	})
	# Unknown ids are dropped silently (not fatal), valid fog kept.
	_write_save(path, payload)
	var vs: VoyageState = VoyageState.new()
	vs.setup(_wdz(), path)
	T.ok(not vs.is_discovered("isle_gone_forever"), "stale id dropped")
	T.eq(vs.get_charted_count(), 0, "no charted from stale save")
	T.ok(vs.is_revealed(_cell_center(20, 20)), "valid fog cell kept")
	T.ok(vs.load_save(), "stale IDs do not invalidate otherwise valid save")
	T.ok(vs.is_revealed(_cell_center(20, 20)), "state survives reload")
	_cleanup(path)


func _cell_center(cx: int, cz: int) -> Vector2:
	var ext: float = _wdz().world_half_extent
	return Vector2((float(cx) + 0.5) * 125.0 - ext, (float(cz) + 0.5) * 125.0 - ext)


func test_new_voyage_resets_to_safe_spawn() -> void:
	var vs: VoyageState = _fresh_state()
	var center: Vector2 = _wdz().get_location_pos("harbor_thistlerow")
	vs.update_position(center + Vector2(0, 200), 1.25)
	vs.set_waypoint("harbor_thistlerow")
	T.ok(vs.get_charted_count() >= 1, "sailed somewhere first")
	vs.new_voyage()
	T.near(vs.boat_position.x, 150.0, 1.0, "new_voyage pose x")
	T.near(vs.boat_position.y, 290.0, 1.0, "new_voyage pose z")
	T.near(vs.boat_heading, 0.0, 0.001, "new_voyage heading 0")
	T.ok(vs.is_discovered("harbor_thistlerow"), "harbor rediscovered")
	T.eq(vs.get_charted_count(), 1, "only harbor charted again")
	T.ok(not vs.is_revealed(Vector2(0, -1800)), "remote fog refogged")
	T.ok(vs.is_revealed(Vector2(150, 290)), "spawn reveal restored")
	T.eq(String(vs.waypoint_id), "", "waypoint cleared")
	_cleanup(vs.save_path)
