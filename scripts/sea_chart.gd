# ASEA • The Unwritten Sea — parchment fog-of-war chart.
class_name SeaChart
extends Control

signal close_requested

const TITLE: String = "The Unwritten Sea"
const LOCATION_TOTAL: int = 34
const MIN_BODY_PX: int = 14
const FINE_PX: int = 11
const LAND_KINDS: Array[String] = ["island", "islet", "harbor", "ruin"]

var world_data: WorldData = null
var state: VoyageState = null
var _open: bool = false
var _map_rect: Rect2 = Rect2()
var _close_rect: Rect2 = Rect2()
var _sidebar_rect: Rect2 = Rect2()
var _legend_rect: Rect2 = Rect2()
var _scale_rect: Rect2 = Rect2()
var _compass_origin: Vector2 = Vector2.ZERO
var _title_pos: Vector2 = Vector2.ZERO
var _progress_pos: Vector2 = Vector2.ZERO
var _target_pos: Vector2 = Vector2.ZERO
var _target_rect: Rect2 = Rect2()
var _layout_size: Vector2 = Vector2.ZERO
var _hit_ids: Array[String] = []
var _hit_rects: Array[Rect2] = []
var _sidebar_row_ids: Array[String] = []
var _sidebar_rows: Array[Rect2] = []
var _font: Font = ThemeDB.fallback_font


func setup(world: WorldData, voyage: VoyageState) -> void:
	world_data = world
	state = voyage
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_relayout()
	queue_redraw()


func set_player_pose(pos: Vector2, heading: float) -> void:
	if state == null:
		return
	if is_finite(pos.x) and is_finite(pos.y) and is_finite(heading):
		state.boat_position = pos
		state.boat_heading = heading
	queue_redraw()


func set_chart_open(open: bool) -> void:
	_open = open
	visible = open
	mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if open:
		_relayout()
	queue_redraw()


func get_map_rect() -> Rect2:
	_relayout()
	return _map_rect


func get_close_rect() -> Rect2:
	_relayout()
	return _close_rect


func get_sidebar_rect() -> Rect2:
	_relayout()
	return _sidebar_rect


func get_sidebar_rows() -> Array[Dictionary]:
	_relayout()
	var rows: Array[Dictionary] = []
	for i: int in range(_sidebar_rows.size()):
		rows.append({"id": _sidebar_row_ids[i], "rect": _sidebar_rows[i],
				"baseline": _sidebar_rows[i].position + Vector2(8, 16)})
	return rows


func get_target_rect() -> Rect2:
	_relayout()
	return _target_rect


func get_scale_rect() -> Rect2:
	_relayout()
	return _scale_rect


func world_to_map(world: Vector2) -> Vector2:
	_relayout()
	return _world_to_map(world)


func map_to_world(map_pt: Vector2) -> Vector2:
	_relayout()
	return _map_to_world(map_pt)


func would_draw_land(id: String) -> bool:
	if world_data == null or state == null:
		return false
	var loc: Dictionary = world_data.get_location(id)
	if loc.is_empty():
		return false
	var kind: String = String(loc.get("kind", ""))
	if kind not in LAND_KINDS:
		return false
	return _circle_has_revealed(loc.get("pos", Vector2.ZERO), float(loc.get("radius", 0.0)))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relayout()
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		_relayout()
		if _close_rect.has_point(mb.position):
			close_requested.emit()
			accept_event()
			return
		var hit: String = _hit_at(mb.position)
		if hit != "" and state != null:
			state.set_waypoint(hit)
			queue_redraw()
			accept_event()


func _hit_at(pt: Vector2) -> String:
	for i: int in range(_hit_ids.size()):
		if _hit_rects[i].has_point(pt):
			return _hit_ids[i]
	return ""


func _relayout() -> void:
	var sz: Vector2 = size
	if sz.x < 8.0 or sz.y < 8.0:
		sz = Vector2(1440, 900)
	_layout_size = sz
	var pad: float = maxf(10.0, minf(sz.x, sz.y) * 0.018)
	var title_h: float = maxf(28.0, sz.y * 0.055)
	var btn_w: float = maxf(88.0, sz.x * 0.08)
	var btn_h: float = maxf(28.0, title_h * 0.72)
	_close_rect = Rect2(sz.x - pad - btn_w, pad, btn_w, btn_h)
	_title_pos = Vector2(pad, pad + title_h * 0.78)
	var side_w: float = clampf(sz.x * 0.26, 200.0, 340.0)
	if sz.x < 1000.0:
		side_w = clampf(sz.x * 0.30, 180.0, 260.0)
	var body_top: float = pad + title_h + 4.0
	var body_h: float = sz.y - body_top - pad
	_sidebar_rect = Rect2(sz.x - pad - side_w, body_top, side_w, body_h)
	var map_left: float = pad
	var map_avail_w: float = _sidebar_rect.position.x - pad - map_left
	var map_side: float = minf(map_avail_w, body_h)
	_map_rect = Rect2(map_left + (map_avail_w - map_side) * 0.5, body_top, map_side, map_side)
	_legend_rect = Rect2(_sidebar_rect.position.x, _sidebar_rect.end.y - 140.0, _sidebar_rect.size.x, 136.0)
	_scale_rect = Rect2(_map_rect.position.x + 16.0, _map_rect.end.y - 32.0,
			_map_rect.size.x * 500.0 / (_half() * 2.0), 20.0)
	_compass_origin = Vector2(_map_rect.end.x - 48.0, _map_rect.position.y + 48.0)
	_progress_pos = _sidebar_rect.position + Vector2(12, 24)
	_target_rect = Rect2(_sidebar_rect.position + Vector2(12, 38), Vector2(side_w - 24, 48))
	_target_pos = _target_rect.position + Vector2(0, 16)
	_rebuild_hits()


func _half() -> float:
	if world_data == null:
		return 2500.0
	return world_data.world_half_extent


func _world_to_map(world: Vector2) -> Vector2:
	var h: float = _half()
	var t: Vector2 = Vector2((world.x + h) / (h * 2.0), (world.y + h) / (h * 2.0))
	return Vector2(_map_rect.position.x + t.x * _map_rect.size.x,
			_map_rect.position.y + t.y * _map_rect.size.y)


func _map_to_world(map_pt: Vector2) -> Vector2:
	var h: float = _half()
	var t: Vector2 = Vector2((map_pt.x - _map_rect.position.x) / maxf(_map_rect.size.x, 1.0),
			(map_pt.y - _map_rect.position.y) / maxf(_map_rect.size.y, 1.0))
	return Vector2(t.x * h * 2.0 - h, t.y * h * 2.0 - h)


func _circle_has_revealed(center: Vector2, radius: float) -> bool:
	if state == null:
		return false
	if state.is_revealed(center):
		return true
	var cell: float = maxf(state.cell_size, 1.0)
	var steps: int = maxi(1, int(ceilf(radius / cell)))
	for i: int in range(-steps, steps + 1):
		for j: int in range(-steps, steps + 1):
			var p: Vector2 = center + Vector2(float(i) * cell, float(j) * cell)
			if p.distance_to(center) > radius + cell * 0.5:
				continue
			if state.is_revealed(p):
				return true
	return false


func _rebuild_hits() -> void:
	_hit_ids.clear()
	_hit_rects.clear()
	_sidebar_row_ids.clear()
	_sidebar_rows.clear()
	if world_data == null or state == null:
		return
	for loc: Dictionary in world_data.locations:
		var id: String = String(loc.get("id", ""))
		if id == "" or not state.is_discovered(id):
			continue
		var pos: Vector2 = loc.get("pos", Vector2.ZERO)
		var r: float = float(loc.get("radius", 40.0))
		var c: Vector2 = _world_to_map(pos)
		var px: float = maxf(10.0, r / (_half() * 2.0) * _map_rect.size.x)
		var hit: Rect2 = Rect2(c.x - px, c.y - px, px * 2.0, px * 2.0)
		if _map_rect.intersects(hit):
			_hit_ids.append(id)
			_hit_rects.append(hit.intersection(_map_rect))
	var list_y: float = _target_rect.end.y + 10.0
	var row_h: float = 24.0
	var names: Array[String] = []
	for loc2: Dictionary in world_data.locations:
		var did: String = String(loc2.get("id", ""))
		if did != "" and state.is_discovered(did):
			names.append(did)
	names.sort()
	for did2: String in names:
		var row: Rect2 = Rect2(_sidebar_rect.position.x + 8, list_y, _sidebar_rect.size.x - 16, row_h)
		if row.end.y < _legend_rect.position.y - 4.0:
			_hit_ids.append(did2)
			_hit_rects.append(row)
			_sidebar_row_ids.append(did2)
			_sidebar_rows.append(row)
		list_y += row_h


func hit_id_at(pt: Vector2) -> String:
	_relayout()
	return _hit_at(pt)


func simulate_click(pt: Vector2) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = pt
	_gui_input(mb)


func _draw() -> void:
	if not _open and size.x < 8.0:
		return
	_relayout()
	var parchment := Color(0.82, 0.74, 0.55, 1.0)
	var ink := Color(0.16, 0.11, 0.07, 1.0)
	var sea := Color(0.18, 0.34, 0.42, 1.0)
	draw_rect(Rect2(Vector2.ZERO, _layout_size), parchment, true)
	draw_rect(Rect2(Vector2.ZERO, _layout_size), Color(0.35, 0.22, 0.12, 0.35), false, 6.0)
	_font.draw_string(get_canvas_item(), _title_pos, TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)
	draw_rect(_close_rect, Color(0.42, 0.18, 0.12, 1.0), true)
	_font.draw_string(get_canvas_item(), _close_rect.position + Vector2(12, _close_rect.size.y * 0.72),
			"Close", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.96, 0.92, 0.84))
	draw_rect(_map_rect, sea, true)
	draw_rect(_map_rect, ink, false, 2.0)
	_draw_land()
	_draw_fog()
	_draw_grid()
	_draw_markers()
	_draw_compass()
	_draw_scale()
	_draw_sidebar(ink)
	_draw_boat()


func _draw_land() -> void:
	if world_data == null or state == null:
		return
	for loc: Dictionary in world_data.locations:
		var kind: String = String(loc.get("kind", ""))
		if kind not in LAND_KINDS:
			continue
		var pos: Vector2 = loc.get("pos", Vector2.ZERO)
		var r: float = float(loc.get("radius", 40.0))
		if not _circle_has_revealed(pos, r):
			continue
		var c: Vector2 = _world_to_map(pos)
		var px: float = maxf(3.0, r / (_half() * 2.0) * _map_rect.size.x)
		var fill: Color = Color(0.45, 0.52, 0.32, 1.0)
		if kind == "harbor":
			fill = Color(0.55, 0.38, 0.22, 1.0)
		elif kind == "ruin":
			fill = Color(0.42, 0.36, 0.30, 1.0)
		elif kind == "islet":
			fill = Color(0.50, 0.58, 0.36, 1.0)
		draw_circle(c, px, fill)
		draw_arc(c, px, 0.0, TAU, 24, Color(0.22, 0.16, 0.10, 0.9), 1.5)


func _draw_fog() -> void:
	if state == null:
		return
	var h: float = _half()
	var cell: float = maxf(state.cell_size, 1.0)
	var cols: int = int(ceilf((h * 2.0) / cell))
	var rows: int = cols
	var fog: Color = get_fog_color()
	for cz: int in range(rows):
		var run_start: int = -1
		for cx: int in range(cols + 1):
			var revealed: bool = false
			if cx < cols:
				revealed = state.revealed_cells.has("%d:%d" % [cx, cz])
			if not revealed:
				if run_start < 0:
					run_start = cx
			elif run_start >= 0:
				_fog_span(run_start, cx, cz, cell, h, fog)
				run_start = -1
		if run_start >= 0:
			_fog_span(run_start, cols, cz, cell, h, fog)


func _fog_span(c0: int, c1: int, cz: int, cell: float, h: float, fog: Color) -> void:
	var a: Vector2 = _world_to_map(Vector2(float(c0) * cell - h, float(cz) * cell - h))
	var b: Vector2 = _world_to_map(Vector2(float(c1) * cell - h, float(cz + 1) * cell - h))
	var r: Rect2 = Rect2(a, b - a).abs().intersection(_map_rect)
	if r.size.x > 0.5 and r.size.y > 0.5:
		draw_rect(r, fog, true)


func get_fog_color() -> Color:
	return Color(0.05, 0.05, 0.07, 1.0)


func _draw_grid() -> void:
	var ink := Color(0.12, 0.18, 0.22, 0.28)
	var n: int = 8
	for i: int in range(n + 1):
		var t: float = float(i) / float(n)
		var x: float = _map_rect.position.x + t * _map_rect.size.x
		var y: float = _map_rect.position.y + t * _map_rect.size.y
		draw_line(Vector2(x, _map_rect.position.y), Vector2(x, _map_rect.end.y), ink, 1.0)
		draw_line(Vector2(_map_rect.position.x, y), Vector2(_map_rect.end.x, y), ink, 1.0)
	var h: float = _half()
	var g: int = int(-h)
	while g <= int(h):
		var p: Vector2 = _world_to_map(Vector2(float(g), -h))
		_font.draw_string(get_canvas_item(), Vector2(p.x + 2.0, _map_rect.position.y + 12.0),
				str(g), HORIZONTAL_ALIGNMENT_LEFT, -1, FINE_PX, Color(0.91, 0.84, 0.67, 0.85))
		g += 1250


func _draw_markers() -> void:
	if world_data == null or state == null:
		return
	for loc: Dictionary in world_data.locations:
		var id: String = String(loc.get("id", ""))
		if id == "" or not state.is_discovered(id):
			continue
		var pos: Vector2 = loc.get("pos", Vector2.ZERO)
		if not state.is_revealed(pos):
			continue
		var c: Vector2 = _world_to_map(pos)
		if not _map_rect.has_point(c):
			continue
		draw_circle(c, 3.5, Color(0.92, 0.82, 0.42, 1.0))
		draw_arc(c, 3.5, 0.0, TAU, 12, Color(0.18, 0.12, 0.06, 1.0), 1.0)
		if state.waypoint_id == id:
			draw_arc(c, 8.0, 0.0, TAU, 16, Color(0.85, 0.22, 0.16, 1.0), 2.0)


func _draw_boat() -> void:
	if state == null:
		return
	var c: Vector2 = _world_to_map(state.boat_position)
	c.x = clampf(c.x, _map_rect.position.x + 6.0, _map_rect.end.x - 6.0)
	c.y = clampf(c.y, _map_rect.position.y + 6.0, _map_rect.end.y - 6.0)
	var heading: float = state.boat_heading
	var tip := Vector2(0.0, -12.0).rotated(heading)
	var port := Vector2(-7.0, 8.0).rotated(heading)
	var starboard := Vector2(7.0, 8.0).rotated(heading)
	var pts: PackedVector2Array = PackedVector2Array([c + tip, c + starboard, c + port])
	draw_colored_polygon(pts, Color(0.95, 0.18, 0.12, 1.0))
	draw_polyline(PackedVector2Array([c + port, c + tip, c + starboard, c + port]), Color(0.08, 0.04, 0.02, 1.0), 1.5, true)


func _draw_compass() -> void:
	var o: Vector2 = _compass_origin
	if o == Vector2.ZERO:
		o = Vector2(_map_rect.end.x - 48.0, _map_rect.position.y + 48.0)
	draw_circle(o, 28.0, Color(0.90, 0.84, 0.68, 0.92))
	draw_arc(o, 28.0, 0.0, TAU, 32, Color(0.16, 0.11, 0.07, 1.0), 2.0)
	var n := Vector2(0, -22)
	var s := Vector2(0, 22)
	var e := Vector2(22, 0)
	var w := Vector2(-22, 0)
	draw_colored_polygon(PackedVector2Array([o + n, o + Vector2(4, 0), o + Vector2(-4, 0)]), Color(0.72, 0.16, 0.14, 1.0))
	draw_colored_polygon(PackedVector2Array([o + s, o + Vector2(4, 0), o + Vector2(-4, 0)]), Color(0.18, 0.16, 0.14, 1.0))
	draw_line(o + w, o + e, Color(0.16, 0.11, 0.07, 1.0), 1.5)
	_font.draw_string(get_canvas_item(), o + Vector2(-5, -30), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.16, 0.11, 0.07, 1.0))


func _draw_scale() -> void:
	var r: Rect2 = _scale_rect
	if r.size.x < 8.0:
		return
	var ink := Color(0.16, 0.11, 0.07, 1.0)
	draw_rect(Rect2(r.position - Vector2(8, 8), r.size + Vector2(16, 16)),
			Color(0.90, 0.84, 0.68, 1.0))
	draw_line(r.position, Vector2(r.end.x, r.position.y), ink, 2.0)
	draw_line(r.position, r.position + Vector2(0, 8), ink, 2.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + 8), ink, 2.0)
	_font.draw_string(get_canvas_item(), r.position + Vector2(0, 18), "500 m", HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_BODY_PX, ink)


func _draw_sidebar(ink: Color) -> void:
	if state == null or world_data == null:
		return
	draw_rect(_sidebar_rect, Color(0.78, 0.70, 0.52, 0.55), true)
	var charted: int = state.get_charted_count()
	_font.draw_string(get_canvas_item(), _progress_pos, "Charted %d / %d" % [charted, LOCATION_TOTAL],
			HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_BODY_PX, ink)
	for i: int in range(_sidebar_rows.size()):
		var id: String = _sidebar_row_ids[i]
		var row: Rect2 = _sidebar_rows[i]
		var name: String = String(world_data.get_location(id).get("name", id))
		if id == state.waypoint_id:
			draw_rect(row, Color(0.93, 0.83, 0.58, 0.9))
		_font.draw_string(get_canvas_item(), row.position + Vector2(8, 16),
				_fit_text(name, row.size.x - 16), HORIZONTAL_ALIGNMENT_LEFT,
				row.size.x - 16, MIN_BODY_PX, ink)
	var wp: String = state.waypoint_id
	if wp != "" and state.is_discovered(wp):
		var loc: Dictionary = world_data.get_location(wp)
		var name: String = String(loc.get("name", wp))
		var pos: Vector2 = loc.get("pos", Vector2.ZERO)
		var dist: float = state.boat_position.distance_to(pos)
		var target_ink := Color(0.48, 0.12, 0.08, 1.0)
		_font.draw_string(get_canvas_item(), _target_pos,
				_fit_text("Course: " + name, _target_rect.size.x),
				HORIZONTAL_ALIGNMENT_LEFT, _target_rect.size.x, MIN_BODY_PX, target_ink)
		_font.draw_string(get_canvas_item(), _target_pos + Vector2(0, 20),
				"%.0f m to destination" % dist, HORIZONTAL_ALIGNMENT_LEFT,
				_target_rect.size.x, MIN_BODY_PX, target_ink)
	else:
		_font.draw_string(get_canvas_item(), _target_pos, "Choose a charted destination",
				HORIZONTAL_ALIGNMENT_LEFT, _target_rect.size.x, MIN_BODY_PX, ink)
	var ly: float = _legend_rect.position.y + 14.0
	var lx: float = _legend_rect.position.x + 12
	_font.draw_string(get_canvas_item(), Vector2(lx, ly), "Legend", HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_BODY_PX, ink)
	_font.draw_string(get_canvas_item(), Vector2(lx, ly + 18.0), "Fog hides uncharted sea", HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_BODY_PX, ink)
	_font.draw_string(get_canvas_item(), Vector2(lx, ly + 36.0), "Click a charted mark to set course", HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_BODY_PX, ink)
	_font.draw_string(get_canvas_item(), Vector2(lx, ly + 54.0), "Close or M / Tab to leave", HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_BODY_PX, ink)


func _fit_text(text: String, max_width: float) -> String:
	if _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_BODY_PX).x <= max_width:
		return text
	var clipped: String = text
	while clipped.length() > 1:
		clipped = clipped.left(clipped.length() - 1)
		if _font.get_string_size(clipped + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_BODY_PX).x <= max_width:
			return clipped + "…"
	return "…"
