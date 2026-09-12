# ASEA cream/ink HUD — region, compass, knots, chart, toast, intro.
extends CanvasLayer

const CREAM := Color(0.96, 0.93, 0.84, 1)
const INK := Color(0.16, 0.14, 0.12, 1)
const INK_SOFT := Color(0.16, 0.14, 0.12, 0.72)

signal chart_pressed

var world_data = null
var voyage = null
var boat = null
var intro_visible: bool = true

var _word: Label
var _region: Label
var _compass: Label
var _knots: Label
var _waypoint: Label
var _controls: Label
var _toast: Label
var _intro: Control
var _chart_btn: Button
var _toast_t: float = 0.0


func setup(data, state, boat_node) -> void:
	world_data = data
	voyage = state
	boat = boat_node


func _ready() -> void:
	layer = 10
	_build()


func _process(delta: float) -> void:
	_refresh()
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.visible = _toast_t > 0.0
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)


func toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_t = 3.6


func dismiss_intro() -> void:
	intro_visible = false
	if _intro:
		_intro.visible = false


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := Panel.new()
	panel.position = Vector2(16, 12)
	panel.size = Vector2(430, 208)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.10, 0.14, 0.22, 0.86)
	psb.border_color = CREAM
	psb.set_border_width_all(1)
	psb.corner_radius_top_left = 6
	psb.corner_radius_top_right = 6
	psb.corner_radius_bottom_left = 6
	psb.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", psb)
	root.add_child(panel)

	_word = _mk_label(panel, "ASEA", 26, Vector2(14, 6), HORIZONTAL_ALIGNMENT_LEFT)
	_region = _mk_label(panel, "The Unwritten Sea  ·  0 / 34 charted", 15, Vector2(14, 38), HORIZONTAL_ALIGNMENT_LEFT)
	_compass = _mk_label(panel, "N  ·  wind E", 15, Vector2(14, 60), HORIZONTAL_ALIGNMENT_LEFT)
	_knots = _mk_label(panel, "0.0 kn", 17, Vector2(14, 82), HORIZONTAL_ALIGNMENT_LEFT)
	_waypoint = _mk_label(panel, "", 14, Vector2(14, 106), HORIZONTAL_ALIGNMENT_LEFT)
	_waypoint.size = Vector2(400, 44)
	_waypoint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_chart_btn = Button.new()
	_chart_btn.text = "CHART"
	_chart_btn.position = Vector2(14, 162)
	_chart_btn.custom_minimum_size = Vector2(96, 30)
	_chart_btn.focus_mode = Control.FOCUS_NONE
	_style_button(_chart_btn)
	_chart_btn.pressed.connect(func(): chart_pressed.emit())
	panel.add_child(_chart_btn)

	var cpanel := Panel.new()
	cpanel.position = Vector2(16, 848)
	cpanel.size = Vector2(930, 36)
	cpanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cpanel.add_theme_stylebox_override("panel", psb)
	root.add_child(cpanel)
	_controls = _mk_label(cpanel, "W/S throttle   A/D steer   Shift faster   Space brake   R recover   M/Tab chart   RMB orbit   Wheel zoom", 13, Vector2(12, 8), HORIZONTAL_ALIGNMENT_LEFT)

	_toast = _mk_label(root, "", 18, Vector2(470, 18), HORIZONTAL_ALIGNMENT_LEFT)
	_toast.add_theme_color_override("font_shadow_color", Color(0.03, 0.10, 0.15))
	_toast.add_theme_constant_override("shadow_offset_x", 1)
	_toast.add_theme_constant_override("shadow_offset_y", 2)
	_toast.visible = false

	_intro = Panel.new()
	_intro.position = Vector2(16, 680)
	_intro.size = Vector2(360, 148)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.96, 0.93, 0.84, 0.94)
	sb.border_color = INK
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	_intro.add_theme_stylebox_override("panel", sb)
	root.add_child(_intro)
	var intro_t := _mk_label(_intro, "ASEA", 20, Vector2(16, 10), HORIZONTAL_ALIGNMENT_LEFT)
	intro_t.add_theme_color_override("font_color", INK)
	var intro_s := _mk_label(_intro, "The Unwritten Sea — chart islands, sail, discover.", 13, Vector2(16, 42), HORIZONTAL_ALIGNMENT_LEFT)
	intro_s.add_theme_color_override("font_color", INK)
	intro_s.custom_minimum_size = Vector2(328, 36)
	intro_s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var dismiss := Button.new()
	dismiss.text = "Set sail"
	dismiss.position = Vector2(16, 100)
	dismiss.focus_mode = Control.FOCUS_NONE
	_style_button(dismiss)
	dismiss.pressed.connect(dismiss_intro)
	_intro.add_child(dismiss)


func _style_button(b: Button) -> void:
	b.add_theme_color_override("font_color", INK)
	var n := StyleBoxFlat.new()
	n.bg_color = CREAM
	n.border_color = INK
	n.set_border_width_all(1)
	b.add_theme_stylebox_override("normal", n)


func _mk_label(parent: Node, text: String, size: int, pos: Vector2, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", CREAM)
	l.horizontal_alignment = align
	parent.add_child(l)
	return l


func _refresh() -> void:
	if boat == null:
		return
	if intro_visible and (
			Input.is_action_pressed("sail_forward")
			or Input.is_action_pressed("sail_back")
			or Input.is_action_just_pressed("ui_accept")):
		dismiss_intro()
	var heading: float = float(boat.heading)
	var deg := fposmod(rad_to_deg(heading), 360.0)
	_compass.text = "%s  ·  wind E" % _cardinal(deg)
	_knots.text = "%.1f kn" % boat.knots()
	var count := 0
	if voyage != null and voyage.has_method("get_charted_count"):
		count = int(voyage.get_charted_count())
	var region := "The Unwritten Sea"
	if world_data != null:
		region = _nearest_name(boat.planar_pos)
	_region.text = "%s  ·  %d / 34 charted" % [region, count]
	_waypoint.text = _waypoint_line()


func _waypoint_line() -> String:
	if voyage == null or world_data == null or boat == null:
		return ""
	var id := str(voyage.waypoint_id)
	if id == "":
		return ""
	var dest: Vector2 = world_data.get_location_pos(id)
	var d: Vector2 = dest - boat.planar_pos
	var dist: float = d.length()
	var bearing := atan2(d.x, -d.y)
	var rel := rad_to_deg(angle_difference(boat.heading, bearing))
	var loc: Dictionary = world_data.get_location(id) if world_data.has_method("get_location") else {}
	var name := str(loc.get("name", id))
	return "Waypoint %s  ·  %s  ·  %.0f m" % [name, _rel_label(rel), dist]


func _rel_label(rel: float) -> String:
	if absf(rel) < 8.0:
		return "ahead"
	if rel < 0.0:
		return "port %.0f°" % absf(rel)
	return "starboard %.0f°" % absf(rel)


func _cardinal(deg: float) -> String:
	var dirs := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return dirs[int(round(deg / 45.0)) % 8]


func _nearest_name(pos: Vector2) -> String:
	if world_data == null:
		return "The Unwritten Sea"
	var best := "Open water"
	var best_d := 1e12
	for entry in world_data.locations:
		var d: float = pos.distance_to(entry["pos"]) - float(entry["radius"])
		if d < best_d:
			best_d = d
			best = str(entry.get("name", "Sea"))
	if best_d > 180.0:
		return "Open water"
	return best
