# ASEA sailing boat — planar physics, glb hull, wake.
extends Node3D

signal recovered

const MODEL_PATH := "res://assets/models/boat.glb"
const HULL_RADIUS := 8.0  # Match VoyageState.BOAT_DRAFT for safe shoreline saves.
const MAX_SPEED := 16.0
const SAIL_RATE := 0.85
const DRAG_K := 0.86
const SPEED_K := 1.7
const STEER_RATE := 1.25
const STEER_MIN := 0.26
const SUBSTEP := 0.04
const NO_GO_DEG := 40.0
const LAND_KINDS := ["island", "islet", "harbor", "ruin"]
const WindScr: GDScript = preload("res://scripts/wind.gd")

static var _model_cache: PackedScene

var world_data = null
var planar_pos: Vector2 = Vector2(150, 290)
var heading: float = 0.0
var speed: float = 0.0
var sail_amount: float = 0.0
var frozen: bool = false
var sim_time: float = 0.0
var wind = WindScr.new()

var _visual: Node3D
var _sail: Node3D
var _flag: Node3D
var _wake: MeshInstance3D
var _wake_pts: PackedVector3Array = PackedVector3Array()
var _steer_input: float = 0.0
var _sail_base_pos: Vector3 = Vector3(0.0, 4.90, 0.50)
var _sail_base_scale: Vector3 = Vector3.ONE
var _sail_base_rot: Vector3 = Vector3.ZERO
var _sail_foot_y: float = 1.42


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
		"brake": Input.is_action_pressed("brake"),
		"recover": Input.is_action_just_pressed("recover_boat"),
	}


func step(delta: float, input: Dictionary) -> void:
	if frozen or delta <= 0.0:
		return
	if bool(input.get("recover", false)):
		recover()
		return
	var drop := bool(input.get("brake", false))
	var fwd := float(input.get("forward", 0.0))
	var back := float(input.get("back", 0.0))
	_steer_input = float(input.get("right", 0.0)) - float(input.get("left", 0.0))
	var left := delta
	while left > 0.00005:
		var dt: float = minf(left, SUBSTEP)
		left -= dt
		# Hoist/lower inside the substep so a long hitch cannot dump a full
		# second of canvas in one go. Space still drops immediately.
		if drop:
			sail_amount = 0.0
		elif fwd > 0.05:
			sail_amount = move_toward(sail_amount, 1.0, SAIL_RATE * dt * fwd)
		elif back > 0.05:
			sail_amount = move_toward(sail_amount, 0.0, SAIL_RATE * dt * back)
		sim_time += dt
		if wind != null:
			wind.step(dt)
		_integrate(dt)
	_sync_transform()


func recover() -> void:
	speed = 0.0
	sail_amount = 0.0
	_wake_pts.clear()
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
	return absf(speed) * 1.94384


func point_of_sail() -> String:
	var ang: float = _wind_angle_from()
	var deg: float = rad_to_deg(ang)
	if sail_amount < 0.02:
		return "Sails down"
	if deg <= NO_GO_DEG:
		return "Headwind · tack to fill sails"
	if deg < 70.0:
		return "Close-hauled"
	if deg < 110.0:
		return "Beam reach"
	if deg < 150.0:
		return "Broad reach"
	return "Running"


func _wind_angle_from() -> float:
	# Angle between boat forward and the FROM direction (where wind originates).
	var toward: Vector2 = Vector2(0.0, -1.0)
	if wind != null:
		toward = wind.direction
	var from_dir: Vector2 = -toward
	var f: Vector2 = forward_xz()
	var d: float = clampf(f.dot(from_dir), -1.0, 1.0)
	return acos(d)


func _sail_drive() -> float:
	# Polar vs wind-FROM: ±40° no-go (zero), close-hauled usable, beam/broad
	# efficient, tailwind strong. Never negative — S cannot reverse.
	if sail_amount < 0.02 or wind == null:
		return 0.0
	var ang: float = _wind_angle_from()
	var no_go: float = deg_to_rad(NO_GO_DEG)
	if ang <= no_go:
		return 0.0
	var t: float = (ang - no_go) / (PI - no_go)
	t = clampf(t, 0.0, 1.0)
	# Rise after the cone; peak around beam/broad, remain strong on a run.
	var polar: float = 0.42 + 0.58 * smoothstep(0.0, 0.38, t)
	polar *= 0.92 + 0.08 * (1.0 - absf(t - 0.72) / 0.72)
	# Continuous 40–55° ramp so drive does not jump at the no-go edge.
	var tack: float = deg_to_rad(55.0)
	if ang < tack:
		var u: float = clampf((ang - no_go) / (tack - no_go), 0.0, 1.0)
		polar *= smoothstep(0.0, 1.0, u)
	var w: float = maxf(0.0, wind.strength)
	return sail_amount * w * polar


func forward_xz() -> Vector2:
	return Vector2(sin(heading), -cos(heading))


func _integrate(dt: float) -> void:
	# Substep integrates sails, wind, speed, steering, then movement.
	var drive: float = _sail_drive()
	var target: float = minf(drive, MAX_SPEED)
	var blend: float = 1.0 - exp(-SPEED_K * dt)
	if drive > 0.02:
		speed = lerpf(speed, target, blend)
	else:
		speed *= exp(-DRAG_K * dt)
		if speed < 0.02:
			speed = 0.0
	speed = clampf(speed, 0.0, MAX_SPEED)
	# Steering scales with speed; modest low-speed assist so a stopped boat can
	# still recover heading and tack through the no-go cone.
	var steer_scale: float = clampf(speed / MAX_SPEED, STEER_MIN, 1.0)
	heading += _steer_input * STEER_RATE * steer_scale * dt
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
	if _sail:
		_sail_base_pos = _sail.position
		_sail_base_scale = _sail.scale
		_sail_base_rot = _sail.rotation
		if _sail is MeshInstance3D:
			# Keep the authored clew height when gathering the canvas.
			_sail_foot_y = _sail_base_pos.y + (_sail as MeshInstance3D).get_aabb().position.y * _sail_base_scale.y


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


func _animate(_delta: float) -> void:
	# sim_time advances only in step() so buoyancy matches the ocean sampler.
	var swell: Vector2 = Vector2(0.0, -1.0)
	if wind != null:
		swell = wind.swell_direction
	var height: float = 0.0
	var slope: Vector2 = Vector2.ZERO
	height = SeaWaves.height_at(planar_pos, sim_time, swell)
	slope = SeaWaves.slope_at(planar_pos, sim_time, swell)
	if _visual:
		var fwd: Vector2 = forward_xz()
		var right: Vector2 = Vector2(-fwd.y, fwd.x)
		_visual.position.y = height
		_visual.rotation.z = clampf(slope.dot(right), -0.18, 0.18) - _steer_input * 0.08
		_visual.rotation.x = clampf(slope.dot(fwd), -0.12, 0.12)
	if _sail:
		# Gather the cloth without creating a singular mesh transform.
		var sy: float = lerpf(0.04, 1.0, clampf(sail_amount, 0.0, 1.0))
		_sail.scale = Vector3(_sail_base_scale.x, _sail_base_scale.y * sy, _sail_base_scale.z)
		# Foot/boom stay put; head gathers down the mast as canvas reefs.
		_sail.position = Vector3(
			_sail_base_pos.x,
			_sail_foot_y + (_sail_base_pos.y - _sail_foot_y) * sy,
			_sail_base_pos.z
		)
		var nogo: bool = sail_amount > 0.02 and _wind_angle_from() <= deg_to_rad(NO_GO_DEG)
		var flutter: float = 0.14 if nogo else 0.08
		var flutter_hz: float = 6.2 if nogo else 2.1
		_sail.rotation = _sail_base_rot
		_sail.rotation.y = _sail_base_rot.y + sin(sim_time * flutter_hz) * flutter
	if _flag and wind != null:
		# Local +Z is the pennant long axis; boat.rotation.y = -heading.
		_flag.rotation.y = atan2(wind.direction.x, wind.direction.y) + heading
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
