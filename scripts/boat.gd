# ASEA sailing boat — planar physics, glb hull, wake.
extends Node3D

signal recovered

const MODEL_PATH := "res://assets/models/boat.glb"
const HULL_RADIUS := 8.0  # Match VoyageState.BOAT_DRAFT for safe shoreline saves.
const MAX_SPEED := 22.0
const BOOST_SPEED := 36.0
const THROTTLE_RATE := 0.85
const DRAG_K := 0.86
const SPEED_K := 1.7
const STEER_RATE := 1.25
const BRAKE_DECEL := 20.0
const SUBSTEP := 0.04
const LAND_KINDS := ["island", "islet", "harbor", "ruin"]

static var _model_cache: PackedScene

var world_data = null
var planar_pos: Vector2 = Vector2(150, 290)
var heading: float = 0.0
var speed: float = 0.0
var throttle: float = 0.0
var frozen: bool = false
var sim_time: float = 0.0

var _visual: Node3D
var _sail: Node3D
var _flag: Node3D
var _wake: MeshInstance3D
var _wake_pts: PackedVector3Array = PackedVector3Array()
var _steer_input: float = 0.0


func setup(data) -> void:
	world_data = data
	recover()


func _ready() -> void:
	_load_model()
	_build_wake()
	_sync_transform()


func _process(delta: float) -> void:
	if not frozen:
		step(delta, read_input())
	_animate(delta)


func read_input() -> Dictionary:
	return {
		"forward": Input.get_action_strength("sail_forward"),
		"back": Input.get_action_strength("sail_back"),
		"left": Input.get_action_strength("steer_left"),
		"right": Input.get_action_strength("steer_right"),
		"boost": Input.is_action_pressed("boost"),
		"brake": Input.is_action_pressed("brake"),
		"recover": Input.is_action_just_pressed("recover_boat"),
	}


func step(delta: float, input: Dictionary) -> void:
	if frozen or delta <= 0.0:
		return
	if bool(input.get("recover", false)):
		recover()
		return
	sim_time += delta
	var fwd := float(input.get("forward", 0.0))
	var back := float(input.get("back", 0.0))
	if fwd > 0.05:
		throttle = move_toward(throttle, 1.0, THROTTLE_RATE * delta * fwd)
	elif back > 0.05:
		throttle = move_toward(throttle, -0.4, THROTTLE_RATE * delta * back)
	_steer_input = float(input.get("right", 0.0)) - float(input.get("left", 0.0))
	var max_spd: float = BOOST_SPEED if bool(input.get("boost", false)) else MAX_SPEED
	if bool(input.get("brake", false)):
		throttle = move_toward(throttle, 0.0, 2.4 * delta)
		speed = move_toward(speed, 0.0, BRAKE_DECEL * delta)
	else:
		var target: float = throttle * max_spd
		var blend: float = 1.0 - exp(-SPEED_K * delta)
		speed = lerpf(speed, target, blend)
		if absf(throttle) < 0.02:
			speed *= exp(-DRAG_K * delta)
	var steer_scale: float = clampf(absf(speed) / MAX_SPEED, 0.28, 1.0)
	heading += _steer_input * STEER_RATE * steer_scale * delta
	var left := delta
	while left > 0.00005:
		var dt: float = minf(left, SUBSTEP)
		left -= dt
		_integrate(dt)
	_sync_transform()


func recover() -> void:
	speed = 0.0
	throttle = 0.0
	if world_data != null and world_data.has_method("boat_spawn"):
		var spawn: Dictionary = world_data.boat_spawn()
		planar_pos = spawn.get("pos", Vector2(150, 290))
		heading = float(spawn.get("heading", 0.0))
	else:
		planar_pos = Vector2(150, 290)
		heading = 0.0
	_sync_transform()
	recovered.emit()


func knots() -> float:
	return absf(speed) * 1.94384 * 0.12


func forward_xz() -> Vector2:
	return Vector2(sin(heading), -cos(heading))


func _integrate(dt: float) -> void:
	var dest: Vector2 = planar_pos + forward_xz() * speed * dt
	dest = _sweep(planar_pos, dest)
	planar_pos = _clamp_world(dest)


func _sweep(from: Vector2, to: Vector2) -> Vector2:
	var travel: Vector2 = to - from
	var dist: float = travel.length()
	if dist < 0.0001:
		return _resolve(to)
	var n: int = maxi(1, int(ceil(dist / (HULL_RADIUS * 0.35))))
	var p: Vector2 = from
	for i in n:
		var nxt: Vector2 = from.lerp(to, float(i + 1) / float(n))
		nxt = _resolve(nxt)
		if _overlaps(nxt):
			return _resolve(p)
		p = nxt
	return p


func _overlaps(pos: Vector2) -> bool:
	if world_data == null:
		return false
	return world_data.overlaps_land(pos, HULL_RADIUS, false, "")


func _resolve(pos: Vector2) -> Vector2:
	if world_data == null:
		return pos
	var p: Vector2 = pos
	for _pass in 8:
		var hit := false
		for entry in world_data.locations:
			if String(entry["kind"]) not in LAND_KINDS:
				continue
			var c: Vector2 = entry["pos"]
			var r: float = float(entry["radius"]) + HULL_RADIUS + 0.05
			var d: Vector2 = p - c
			var sep: float = d.length()
			if sep >= r:
				continue
			hit = true
			if sep < 0.0001:
				d = Vector2(1, 0)
				sep = 1.0
			var nrm: Vector2 = d / sep
			p = c + nrm * r
			var into: float = forward_xz().dot(-nrm)
			if into > 0.0 and speed * into > 0.0:
				speed *= (1.0 - clampf(into, 0.0, 1.0) * 0.9)
		if not hit:
			break
	return p


func _clamp_world(pos: Vector2) -> Vector2:
	var half := 2500.0
	if world_data != null:
		half = float(world_data.world_half_extent)
	var m: float = HULL_RADIUS + 2.0
	var lim: float = maxf(half - m, 1.0)
	return Vector2(clampf(pos.x, -lim, lim), clampf(pos.y, -lim, lim))


func _sync_transform() -> void:
	# The world root is identity; local coordinates also support isolated simulation.
	position = Vector3(planar_pos.x, 0.0, planar_pos.y)
	rotation = Vector3(0.0, -heading, 0.0)


func _load_model() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	if _model_cache == null and ResourceLoader.exists(MODEL_PATH):
		_model_cache = load(MODEL_PATH) as PackedScene
	if _model_cache == null:
		return
	var inst: Node = _model_cache.instantiate()
	ModelLibrary.toonify(inst)
	_visual.add_child(inst)
	_sail = inst.find_child("Boat_Sail", true, false) as Node3D
	_flag = inst.find_child("Boat_Flag", true, false) as Node3D


func _build_wake() -> void:
	_wake = MeshInstance3D.new()
	_wake.name = "Wake"
	_wake.top_level = true
	_wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.85, 0.95, 1.0, 0.7)
	_wake.material_override = mat
	add_child(_wake)


func _animate(delta: float) -> void:
	sim_time += delta * 0.35
	if _visual:
		_visual.position.y = sin(sim_time * 1.7) * 0.14
		_visual.rotation.z = sin(sim_time * 1.15) * 0.05 - _steer_input * 0.08
		_visual.rotation.x = sin(sim_time * 1.4) * 0.03
	if _sail:
		_sail.rotation.y = sin(sim_time * 2.1) * 0.14
	if _flag:
		_flag.rotation.y = sin(sim_time * 3.4) * 0.35
	_update_wake()


func _update_wake() -> void:
	if _wake == null:
		return
	var stern := global_position - Vector3(forward_xz().x, 0, forward_xz().y) * 4.6
	stern.y = 0.4
	_wake_pts.insert(0, stern)
	if _wake_pts.size() > 28:
		_wake_pts.resize(28)
	if _wake_pts.size() < 2 or absf(speed) < 0.4:
		_wake.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n: int = _wake_pts.size()
	for i in n:
		var t: float = float(i) / float(n - 1)
		var width: float = lerpf(1.7, 0.08, t)
		var alpha: float = lerpf(0.55, 0.0, t * t)
		var p: Vector3 = _wake_pts[i]
		var tangent := Vector3(1, 0, 0)
		if i + 1 < n:
			tangent = (_wake_pts[i] - _wake_pts[i + 1])
		elif i > 0:
			tangent = (_wake_pts[i - 1] - _wake_pts[i])
		tangent.y = 0.0
		if tangent.length() < 0.001:
			tangent = Vector3(forward_xz().x, 0, forward_xz().y)
		var side: Vector3 = Vector3(-tangent.z, 0, tangent.x).normalized() * width
		var col := Color(0.72, 0.9, 1.0, alpha)
		st.set_color(col)
		st.add_vertex(p + side)
		st.set_color(col)
		st.add_vertex(p - side)
	_wake.mesh = st.commit()
