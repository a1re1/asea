# ASEA main — world, sailing, voyage persistence and chart integration.
extends Node3D

const SAVE_PATH := "user://voyage.json"
const CAPTURE_SAVE := "user://asea_capture_voyage.json"

var world_data = null
var voyage = null
var boat: Node3D
var cam: Camera3D
var hud: CanvasLayer
var chart = null
var chart_open: bool = false
var _save_accum: float = 0.0
var _frames: int = 0
var _capture_mode: String = ""
var _ocean = null
var _terrain = null
var _isolated_save: bool = false


func _ready() -> void:
	boat = get_node_or_null("Boat")
	cam = get_node_or_null("SailingCamera")
	hud = get_node_or_null("HUD")
	_parse_cli()
	world_data = _try_world()
	if boat and boat.has_method("setup"):
		boat.setup(world_data)
	_try_ocean()
	_try_terrain()
	voyage = _try_voyage()
	if boat and boat.has_signal("recovered"):
		boat.connect("recovered", _on_boat_recovered)
	if boat and voyage != null:
		boat.planar_pos = voyage.boat_position
		boat.heading = voyage.boat_heading
		if boat.has_method("_sync_transform"):
			boat._sync_transform()
	if hud and hud.has_method("setup"):
		hud.setup(world_data, voyage, boat)
		if hud.has_signal("chart_pressed"):
			hud.chart_pressed.connect(_on_chart_pressed)
	if voyage != null and voyage.has_signal("discovered"):
		voyage.discovered.connect(_on_discovered)
	_try_chart()
	if boat == null or cam == null or hud == null or world_data == null or voyage == null or chart == null or _ocean == null or _terrain == null:
		push_error("ASEA cannot start: a required world component failed to load")
		get_tree().quit(1)
		return
	if cam:
		cam.far = maxf(cam.far, 8000.0)
		if "target" in cam:
			cam.target = boat
	print("[asea] main scene ready")


func _process(delta: float) -> void:
	_frames += 1
	if not chart_open and boat != null and voyage != null and voyage.has_method("update_position"):
		voyage.update_position(boat.planar_pos, boat.heading)
	_save_accum += delta
	if _save_accum >= 8.0:
		_save_accum = 0.0
		_save_voyage()
	if Input.is_action_just_pressed("toggle_chart"):
		_set_chart_open(not chart_open)
	if Input.is_action_just_pressed("close_chart") and chart_open:
		_set_chart_open(false)
	if _capture_mode != "" and _frames >= 60:
		_do_capture()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_voyage()


func _on_chart_pressed() -> void:
	_set_chart_open(not chart_open)


func _on_boat_recovered() -> void:
	if voyage == null or boat == null:
		return
	# Recovery teleports home; it must not chart the intervening sea.
	voyage.boat_position = boat.planar_pos
	voyage.boat_heading = boat.heading
	voyage.update_position(boat.planar_pos, boat.heading)
	_save_voyage()


func _on_discovered(id: String) -> void:
	if hud == null or world_data == null:
		return
	var loc: Dictionary = {}
	if world_data.has_method("get_location"):
		loc = world_data.get_location(id)
	var loc_name := str(loc.get("name", id))
	if hud.has_method("toast"):
		hud.toast("Discovered  ·  %s" % loc_name)


func _set_chart_open(open: bool) -> void:
	chart_open = open
	if hud:
		hud.visible = not open
	if boat:
		boat.frozen = open
	if cam and "frozen" in cam:
		cam.frozen = open
	if chart != null:
		if chart.has_method("set_chart_open"):
			chart.set_chart_open(open)
		if open and chart.has_method("set_player_pose") and boat:
			chart.set_player_pose(boat.planar_pos, boat.heading)
	if not open:
		_save_voyage()


func _save_voyage() -> void:
	if voyage != null and voyage.has_method("save"):
		voyage.save()


func _try_world():
	if not ResourceLoader.exists("res://scripts/world_data.gd"):
		return null
	var scr = load("res://scripts/world_data.gd")
	if scr == null:
		return null
	if scr.has_method("load_default"):
		return scr.load_default()
	return null


func _try_ocean() -> void:
	if not ResourceLoader.exists("res://scripts/ocean_environment.gd"):
		return
	var scr = load("res://scripts/ocean_environment.gd")
	if scr == null:
		return
	_ocean = scr.new()
	_ocean.name = "OceanEnvironment"
	add_child(_ocean)


func _try_terrain() -> void:
	if world_data == null or not ResourceLoader.exists("res://scripts/terrain_builder.gd"):
		return
	var scr = load("res://scripts/terrain_builder.gd")
	if scr == null:
		return
	_terrain = scr.new()
	if "world_data" in _terrain:
		_terrain.world_data = world_data
	_terrain.name = "Terrain"
	add_child(_terrain)


func _try_voyage():
	if world_data == null or not ResourceLoader.exists("res://scripts/voyage_state.gd"):
		return null
	var scr = load("res://scripts/voyage_state.gd")
	if scr == null:
		return null
	var vs = scr.new()
	var path := SAVE_PATH
	if _capture_mode != "" or _isolated_save:
		path = CAPTURE_SAVE
	if vs.has_method("setup"):
		vs.setup(world_data, path)
	if _capture_mode != "" or _isolated_save:
		if vs.has_method("new_voyage"):
			vs.new_voyage()
	return vs


func _try_chart() -> void:
	if world_data == null or voyage == null:
		return
	if not ResourceLoader.exists("res://scripts/sea_chart.gd"):
		return
	var scr = load("res://scripts/sea_chart.gd")
	if scr == null:
		return
	chart = scr.new()
	chart.name = "SeaChart"
	var layer := get_node_or_null("ChartLayer")
	if layer:
		layer.add_child(chart)
	else:
		add_child(chart)
	if chart.has_method("setup"):
		chart.setup(world_data, voyage)
	if chart.has_signal("close_requested"):
		chart.close_requested.connect(func(): _set_chart_open(false))
	if chart.has_method("set_chart_open"):
		chart.set_chart_open(false)
	if chart is Control:
		(chart as Control).focus_mode = Control.FOCUS_NONE


func _parse_cli() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--capture-map="):
			_capture_mode = arg
		elif arg.begins_with("--capture="):
			_capture_mode = arg
		elif arg == "--asea-smoke":
			_isolated_save = true


func _do_capture() -> void:
	var path := ""
	if _capture_mode.begins_with("--capture-map="):
		path = _capture_mode.substr("--capture-map=".length())
		_set_chart_open(true)
	elif _capture_mode.begins_with("--capture="):
		path = _capture_mode.substr("--capture=".length())
	_capture_mode = ""
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.get_width() == 0 or img.get_height() == 0:
		push_error("Capture produced no rendered image")
		get_tree().quit(1)
		return
	if img.save_png(path) != OK:
		push_error("Cannot write capture to " + path)
		get_tree().quit(1)
		return
	print("[asea] captured ", path)
	get_tree().quit()
