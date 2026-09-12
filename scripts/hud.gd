# ASEA cream/ink HUD — region, compass, knots, wind, sails, chart, toast, intro.
extends CanvasLayer

const CREAM := Color(0.96, 0.93, 0.84, 1)
const INK := Color(0.16, 0.14, 0.12, 1)
const INK_SOFT := Color(0.16, 0.14, 0.12, 0.72)

signal chart_pressed

var world_data = null
var voyage = null
var boat = null
var intro_visible: bool = true

var _hud_root: Control
var _panel: Panel
var _cpanel: Panel
var _word: Label
var _region: Label
var _compass: Label
var _knots: Label
var _wind_label: Label
var _sail_label: Label
var _point_of_sail_label: Label
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
		if _toast:
			_toast.visible = _toast_t > 0.0
			_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)


func toast(text: String) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast.visible = true
	_toast_t = 3.6


func dismiss_intro() -> void:
	intro_visible = false
	if _intro:
		_intro.visible = false


func _build() -> void:
	_hud_root = Control.new()
	_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.resized.connect(_layout)
	add_child(_hud_root)

	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.10, 0.14, 0.22, 0.86)
	psb.border_color = CREAM
	psb.set_border_width_all(1)
	psb.corner_radius_top_left = 6
	psb.corner_radius_top_right = 6
	psb.corner_radius_bottom_left = 6
	psb.corner_radius_bottom_right = 6

	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", psb)
	_hud_root.add_child(_panel)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 14
	box.offset_top = 8
	box.offset_right = -14
	box.offset_bottom = -10
	box.add_theme_constant_override("separation", 3)
	_panel.add_child(box)

	_word = _mk_label(box, "ASEA", 26)
	_region = _mk_label(box, "The Unwritten Sea  ·  0 / 34 charted", 15)
	_region.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_region.max_lines_visible = 2
	_compass = _mk_label(box, "N", 15)
	_knots = _mk_label(box, "0.0 kn", 17)
	_wind_label = _mk_label(box, "Wind FROM —", 15)
	_wind_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sail_label = _mk_label(box, "Sails  0%", 15)
	_point_of_sail_label = _mk_label(box, "Sails down", 15)
	_point_of_sail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_point_of_sail_label.max_lines_visible = 2
	_waypoint = _mk_label(box, "", 14)
	_waypoint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_waypoint.max_lines_visible = 2

	_chart_btn = Button.new()
	_chart_btn.text = "CHART"
	_chart_btn.custom_minimum_size = Vector2(96, 30)
	_chart_btn.focus_mode = Control.FOCUS_NONE
	_style_button(_chart_btn)
	_chart_btn.pressed.connect(func(): chart_pressed.emit())
	box.add_child(_chart_btn)

	_cpanel = Panel.new()
	_cpanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cpanel.add_theme_stylebox_override("panel", psb)
	_cpanel.set_anchor(SIDE_LEFT, 0.0)
	_cpanel.set_anchor(SIDE_RIGHT, 1.0)
	_cpanel.set_anchor(SIDE_TOP, 1.0)
	_cpanel.set_anchor(SIDE_BOTTOM, 1.0)
	_hud_root.add_child(_cpanel)
	_controls = _mk_label(_cpanel, "W raise sails   S lower sails   Space drop sails   A/D steer   R recover   M/Tab chart   RMB orbit   Wheel zoom", 13)
	_controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_controls.offset_left = 12
	_controls.offset_right = -12
	_controls.offset_top = 6
	_controls.offset_bottom = -6
	_controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_toast = _mk_label(_hud_root, "", 18)
	_toast.add_theme_color_override("font_shadow_color", Color(0.03, 0.10, 0.15))
	_toast.add_theme_constant_override("shadow_offset_x", 1)
	_toast.add_theme_constant_override("shadow_offset_y", 2)
	_toast.visible = false

	_intro = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.96, 0.93, 0.84, 0.94)
	sb.border_color = INK
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	_intro.add_theme_stylebox_override("panel", sb)
	_hud_root.add_child(_intro)
	var intro_box := VBoxContainer.new()
	intro_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	intro_box.offset_left = 16
	intro_box.offset_top = 10
	intro_box.offset_right = -16
	intro_box.offset_bottom = -12
	intro_box.add_theme_constant_override("separation", 6)
	_intro.add_child(intro_box)
	var intro_t := _mk_label(intro_box, "ASEA", 20)
	intro_t.add_theme_color_override("font_color", INK)
	var intro_s := _mk_label(intro_box, "Chart islands and sail the Unwritten Sea. Headwind: tack with A/D to fill sails. W raises sails, S lowers them; the setting holds after you release. Space drops sails.", 13)
	intro_s.add_theme_color_override("font_color", INK)
	intro_s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var dismiss := Button.new()
	dismiss.text = "Set sail"
	dismiss.focus_mode = Control.FOCUS_NONE
	_style_button(dismiss)
	dismiss.pressed.connect(dismiss_intro)
	intro_box.add_child(dismiss)

	call_deferred("_layout")


func _layout() -> void:
	if _hud_root == null or _panel == null:
		return
	var sz: Vector2 = _hud_root.size
	if sz.x < 8.0 or sz.y < 8.0:
		var vp := get_viewport()
		if vp:
			sz = vp.get_visible_rect().size
	if sz.x < 8.0 or sz.y < 8.0:
		return
	var small: bool = sz.x < 1100.0 or sz.y < 700.0
	var panel_w: float = minf(430.0, sz.x - 32.0)
	var panel_h: float = 278.0
	_panel.position = Vector2(16, 12)
	_panel.size = Vector2(panel_w, panel_h)

	var footer_h: float = 52.0 if sz.x < 1100.0 else 36.0
	_cpanel.offset_left = 16
	_cpanel.offset_right = -16
	_cpanel.offset_top = -(footer_h + 12.0)
	_cpanel.offset_bottom = -12.0

	if _toast:
		_toast.position = Vector2(16.0 + panel_w + 16.0, 18.0)
		_toast.size = Vector2(maxf(80.0, sz.x - panel_w - 48.0), 40.0)

	if _intro == null:
		return
	if small:
		var ix: float = 16.0 + panel_w + 12.0
		var iw: float = maxf(220.0, sz.x - ix - 16.0)
		if ix + 220.0 > sz.x - 16.0:
			ix = maxf(16.0, sz.x - 336.0)
			iw = minf(320.0, sz.x - ix - 16.0)
		_intro.position = Vector2(ix, 12.0)
		_intro.size = Vector2(iw, minf(188.0, sz.y - footer_h - 36.0))
		if _toast:
			_toast.position.y = _intro.position.y + _intro.size.y + 12.0
	else:
		_intro.position = Vector2(16.0, sz.y - 12.0 - footer_h - 12.0 - 160.0)
		_intro.size = Vector2(360.0, 160.0)


func _style_button(b: Button) -> void:
	b.add_theme_color_override("font_color", INK)
	var n := StyleBoxFlat.new()
	n.bg_color = CREAM
	n.border_color = INK
	n.set_border_width_all(1)
	b.add_theme_stylebox_override("normal", n)


func _mk_label(parent: Node, text: String, size: int, pos: Vector2 = Vector2.ZERO, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	if pos != Vector2.ZERO:
		l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", CREAM)
	l.horizontal_alignment = align
	parent.add_child(l)
	return l


func _refresh() -> void:
	if _compass == null or _wind_label == null:
		return
	if intro_visible and boat != null and (
			Input.is_action_pressed("sail_forward")
			or Input.is_action_pressed("sail_back")
			or Input.is_action_just_pressed("ui_accept")):
		dismiss_intro()
	if boat != null:
		var heading: float = float(boat.get("heading"))
		var deg := fposmod(rad_to_deg(heading), 360.0)
		_compass.text = "%s  ·  %.0f°" % [_cardinal(deg), deg]
		if boat.has_method("knots"):
			_knots.text = "%.1f kn" % boat.knots()
		else:
			_knots.text = "— kn"
	_wind_label.text = _wind_line()
	_sail_label.text = "Sails  %d%%" % _sail_pct()
	_point_of_sail_label.text = _point_of_sail_text()
	var count := 0
	if voyage != null and voyage.has_method("get_charted_count"):
		count = int(voyage.get_charted_count())
	var region := "The Unwritten Sea"
	if boat != null and world_data != null:
		region = _nearest_name(boat.planar_pos)
	_region.text = "%s  ·  %d / 34 charted" % [region, count]
	_waypoint.text = _waypoint_line()


func _wind_line() -> String:
	var props := _wind_props()
	if props.is_empty():
		return "Wind FROM —"
	var toward: Vector2 = props["direction"]
	if toward.length_squared() < 0.0001:
		toward = Vector2(1, 0)
	else:
		toward = toward.normalized()
	var from: Vector2 = -toward
	var bearing: float = fposmod(rad_to_deg(atan2(from.x, -from.y)), 360.0)
	var kn: float = float(props["strength"]) * 1.94384
	return "Wind FROM %s  ·  %.0f°  ·  %.1f kn" % [_cardinal(bearing), bearing, kn]


func _wind_props() -> Dictionary:
	if boat == null:
		return {}
	var w = boat.get("wind")
	if w == null:
		return {}
	var dir: Vector2 = Vector2.ZERO
	var strength := 0.0
	if w is Dictionary:
		dir = w.get("direction", Vector2.ZERO)
		strength = float(w.get("strength", 0.0))
	else:
		var d = w.get("direction")
		var s = w.get("strength")
		if d != null:
			dir = d
		if s != null:
			strength = float(s)
	return {"direction": dir, "strength": strength}


func _sail_pct() -> int:
	if boat == null:
		return 0
	var a = boat.get("sail_amount")
	if a == null:
		return 0
	return clampi(int(round(clampf(float(a), 0.0, 1.0) * 100.0)), 0, 100)


func _point_of_sail_text() -> String:
	if boat == null:
		return "Sails down"
	if boat.has_method("point_of_sail"):
		return str(boat.point_of_sail())
	return "Sails down"


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
