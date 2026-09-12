# ASEA • The Unwritten Sea — sea chart tests.
extends RefCounted

const T: GDScript = preload("res://tests/test_helper.gd")
const VoyageState: GDScript = preload("res://scripts/voyage_state.gd")
const SeaChartScript: GDScript = preload("res://scripts/sea_chart.gd")

var _wd: WorldData = null
var _save_counter: int = 0
var _saves: Array[String] = []
var _charts: Array[SeaChart] = []


func _wdz() -> WorldData:
	if _wd == null:
		_wd = WorldData.load_default()
	return _wd


func _unique_save_path() -> String:
	_save_counter += 1
	var p: String = "user://test_chart_%d_%d.json" % [Time.get_ticks_msec(), _save_counter]
	_saves.append(p)
	return p


func _cleanup_all() -> void:
	for chart: SeaChart in _charts:
		if is_instance_valid(chart):
			chart.free()
	_charts.clear()
	for p: String in _saves:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	_saves.clear()


func _make(sz: Vector2) -> Dictionary:
	var vs: VoyageState = VoyageState.new()
	vs.setup(_wdz(), _unique_save_path())
	var chart: SeaChart = SeaChartScript.new() as SeaChart
	_charts.append(chart)
	chart.size = sz
	chart.setup(_wdz(), vs)
	chart.set_chart_open(true)
	return {"chart": chart, "state": vs}


func test_layout_and_transform_two_sizes() -> void:
	for sz: Vector2 in [Vector2(1440, 900), Vector2(960, 600)]:
		var pack: Dictionary = _make(sz)
		var chart: SeaChart = pack["chart"]
		var map_r: Rect2 = chart.get_map_rect()
		T.ok(map_r.size.x > 280.0 and map_r.size.y > 280.0, "map square large at %s" % str(sz))
		T.near(map_r.size.x, map_r.size.y, 1.5, "map is square at %s" % str(sz))
		T.ok(chart.get_close_rect().size.x >= 48.0, "close button hittable at %s" % str(sz))
		T.ok(chart.get_sidebar_rect().size.x >= 120.0, "sidebar readable at %s" % str(sz))
		var origin: Vector2 = chart.world_to_map(Vector2.ZERO)
		var back: Vector2 = chart.map_to_world(origin)
		T.near(back.x, 0.0, 2.0, "roundtrip x at %s" % str(sz))
		T.near(back.y, 0.0, 2.0, "roundtrip y at %s" % str(sz))
		var harbor: Vector2 = chart.world_to_map(Vector2(0, 200))
		T.ok(map_r.has_point(harbor), "harbor plots inside map at %s" % str(sz))
		var fog: Color = chart.get_fog_color()
		T.near(fog.a, 1.0, 0.001, "fog fully opaque at %s" % str(sz))
	_cleanup_all()


func test_partial_fog_cannot_render_unrevealed_land() -> void:
	var pack: Dictionary = _make(Vector2(1440, 900))
	var chart: SeaChart = pack["chart"]
	var vs: VoyageState = pack["state"]
	T.ok(chart.would_draw_land("harbor_thistlerow"), "harbor land visible in initial fog")
	T.ok(not chart.would_draw_land("island_cinder"), "remote cinder hidden by fog")
	T.ok(not chart.would_draw_land("island_halcyon"), "halcyon hidden by fog")
	T.ok(not vs.is_discovered("island_cinder"), "cinder not discovered")
	T.ok(chart.get_fog_color().a >= 0.999, "mask policy fully opaque")
	# Force a far cell revealed without discovering the island: land still needs
	# a revealed cell overlapping the island circle.
	vs.revealed_cells["0:0"] = true
	T.ok(not chart.would_draw_land("island_cinder"), "partial far cell does not unmask cinder")
	vs.revealed_cells.clear()
	vs.revealed_cells["31:8"] = true
	T.ok(chart.would_draw_land("island_cinder"), "revealed west coast can render partial island")
	T.ok(not vs.is_revealed(Vector2(1700, -1500)), "island center remains covered")
	T.ok(not vs.is_revealed(Vector2(1975, -1500)), "far coast remains covered")
	T.ok(not vs.is_discovered("island_cinder"), "partial geometry does not expose island name")
	_cleanup_all()


func test_unknown_location_not_clickable() -> void:
	var pack: Dictionary = _make(Vector2(1440, 900))
	var chart: SeaChart = pack["chart"]
	var vs: VoyageState = pack["state"]
	var far: Vector2 = chart.world_to_map(Vector2(-1800, -1800))
	T.eq(chart.hit_id_at(far), "", "undiscovered far land is not a hit")
	T.eq(chart.hit_id_at(Vector2(-40, -40)), "", "outside map is not a hit")
	T.eq(String(vs.waypoint_id), "", "no waypoint after miss")
	_cleanup_all()


func test_known_location_click_sets_waypoint() -> void:
	var pack: Dictionary = _make(Vector2(1440, 900))
	var chart: SeaChart = pack["chart"]
	var vs: VoyageState = pack["state"]
	var harbor_pt: Vector2 = chart.world_to_map(Vector2(0, 200))
	T.eq(chart.hit_id_at(harbor_pt), "harbor_thistlerow", "harbor hit geometry")
	chart.simulate_click(harbor_pt)
	T.eq(String(vs.waypoint_id), "harbor_thistlerow", "click sets waypoint")
	_cleanup_all()


func test_close_emits_once() -> void:
	var pack: Dictionary = _make(Vector2(960, 600))
	var chart: SeaChart = pack["chart"]
	var n: Array[int] = [0]
	chart.close_requested.connect(func() -> void: n[0] += 1)
	var cr: Rect2 = chart.get_close_rect()
	chart.simulate_click(cr.get_center())
	T.eq(n[0], 1, "exactly one close_requested")
	_cleanup_all()


func test_sidebar_clicks_and_scale_match_drawing_at_two_sizes() -> void:
	for sz: Vector2 in [Vector2(1440, 900), Vector2(960, 600)]:
		var pack: Dictionary = _make(sz)
		var chart: SeaChart = pack["chart"]
		var vs: VoyageState = pack["state"]
		vs.update_position(Vector2(700, -500), PI / 2)
		var rows: Array[Dictionary] = chart.get_sidebar_rows()
		T.eq(rows.size(), 2, "two known destinations listed")
		for row: Dictionary in rows:
			var rect: Rect2 = row["rect"]
			var label_point: Vector2 = row["baseline"] - Vector2(0, 5)
			T.ok(rect.has_point(label_point), "drawn name lies inside its click target")
			T.ok(not rect.intersects(chart.get_target_rect()), "destination text cannot overlap list")
			T.eq(chart.hit_id_at(label_point), row["id"], "label click resolves correct destination")
			chart.simulate_click(label_point)
			T.eq(vs.waypoint_id, row["id"], "drawn row selects its own destination")
		var scale: Rect2 = chart.get_scale_rect()
		var left: Vector2 = chart.map_to_world(scale.position)
		var right: Vector2 = chart.map_to_world(scale.position + Vector2(scale.size.x, 0))
		T.near(left.distance_to(right), 500, 0.01, "scale represents 500 world meters")
	_cleanup_all()
