# Isolated boat kinematics: sail_amount, wind, steer, collision, bounds, recovery fog.
extends RefCounted

const T := preload("res://tests/test_helper.gd")
const BoatScr: GDScript = preload("res://scripts/boat.gd")
const VoyageScr: GDScript = preload("res://scripts/voyage_state.gd")
const WorldScr: GDScript = preload("res://scripts/world_data.gd")
const WindScr: GDScript = preload("res://scripts/wind.gd")

const FAIR_DIR := Vector2(0.0, -1.0)
const FAIR_STR := 10.0
const HEADWIND_DIR := Vector2(0.0, 1.0)
const KNOTS_PER_MS := 1.94384
const MAX_SPEED := 16.0
const SWELL_TURN := 0.00025


func _data():
	return WorldScr.load_default()


func _boat(data) -> Node3D:
	var b: Node3D = BoatScr.new()
	b.world_data = data
	var spawn: Dictionary = data.boat_spawn()
	b.planar_pos = spawn["pos"]
	b.heading = float(spawn["heading"])
	b.speed = 0.0
	b.sail_amount = 0.0
	return b


func _fair(b: Node3D, strength: float = FAIR_STR) -> void:
	b.wind.set_fixed(FAIR_DIR, strength)


func _inp(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"forward": 0.0, "back": 0.0, "left": 0.0, "right": 0.0,
		"brake": false, "recover": false,
	}
	for k in overrides:
		d[k] = overrides[k]
	return d


func _unique_save() -> String:
	return "user://sailing_test_%d.json" % Time.get_ticks_usec()


func _rm_save(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _toward_from_head_angle(deg: float) -> Vector2:
	# heading 0 faces north; FROM is clockwise of north by deg; toward is opposite.
	var r: float = deg_to_rad(deg)
	return Vector2(-sin(r), cos(r))


func test_sail_holds_after_release() -> void:
	var b := _boat(_data())
	_fair(b)
	for _i in 40:
		b.step(0.05, _inp({"forward": 1.0}))
	T.ok(b.sail_amount > 0.7, "sail ramps toward 1 under W")
	T.ok(b.speed > 2.0, "speed builds under W with tailwind")
	var held: float = b.sail_amount
	var spd: float = b.speed
	b.step(0.05, _inp())
	T.ok(absf(b.sail_amount - held) < 1e-5, "sail_amount holds on W release")
	T.ok(b.speed > spd * 0.7, "glide continues after release")
	b.free()


func test_s_never_negative_and_space_coasts() -> void:
	var b := _boat(_data())
	_fair(b)
	for _i in 20:
		b.step(0.05, _inp({"back": 1.0}))
	T.ok(b.sail_amount >= 0.0, "S from zero stays non-negative")
	T.eq(b.sail_amount, 0.0, "S does not hoist")
	T.ok(b.speed >= 0.0, "S never reverses")
	for _i in 50:
		b.step(0.05, _inp({"forward": 1.0}))
	T.ok(b.sail_amount > 0.9, "W hoists near full")
	T.ok(b.speed > 1.0, "moving before reef")
	for _i in 40:
		b.step(0.05, _inp({"back": 1.0}))
	T.ok(b.sail_amount >= 0.0 and b.sail_amount < 0.05, "S lowers toward zero")
	T.ok(b.speed >= 0.0, "S never makes speed negative")
	# Re-hoist, then Space drops canvas immediately; hull still coasts one step.
	for _i in 50:
		b.step(0.05, _inp({"forward": 1.0}))
	T.ok(b.speed > 3.0, "has way before brake")
	b.step(0.05, _inp({"brake": true}))
	T.eq(b.sail_amount, 0.0, "Space zeros sail_amount")
	T.ok(b.speed > 0.5, "still moving after one Space step")
	for _i in 240:
		b.step(0.05, _inp({"brake": true}))
	T.ok(b.speed < 0.05, "coasts to stop after ~12s")
	b.free()


func test_headwind_rest_tailwind_moves() -> void:
	var data = _data()
	var head := _boat(data)
	head.heading = 0.0
	head.sail_amount = 1.0
	head.wind.set_fixed(HEADWIND_DIR, FAIR_STR)
	var rest: Vector2 = head.planar_pos
	for _i in 40:
		head.step(0.05, _inp())
	T.ok(head.speed < 0.05, "headwind stays at rest")
	T.ok(head.planar_pos.distance_to(rest) < 0.05, "headwind pose unmoved")
	head.free()
	var tail := _boat(data)
	tail.heading = 0.0
	tail.sail_amount = 1.0
	_fair(tail)
	var y0: float = tail.planar_pos.y
	for _i in 40:
		tail.step(0.05, _inp())
	T.ok(tail.speed > 1.0, "tailwind builds speed")
	T.ok(tail.planar_pos.y < y0 - 0.5, "northbound planar y decreases")
	tail.free()


func test_no_go_versus_tack() -> void:
	var data = _data()
	var nogo := _boat(data)
	nogo.heading = 0.0
	nogo.sail_amount = 1.0
	nogo.wind.set_fixed(_toward_from_head_angle(35.0), FAIR_STR)
	for _i in 50:
		nogo.step(0.05, _inp())
	T.ok(nogo.speed < 0.05, "35deg headwind is no-go")
	nogo.free()
	var tack := _boat(data)
	tack.heading = 0.0
	tack.sail_amount = 1.0
	tack.wind.set_fixed(_toward_from_head_angle(55.0), FAIR_STR)
	for _i in 50:
		tack.step(0.05, _inp())
	T.ok(tack.speed > 0.4, "55deg tack makes positive way")
	tack.free()


func test_wind_strength_and_partial_sail() -> void:
	var data = _data()
	var weak := _boat(data)
	var strong := _boat(data)
	weak.heading = 0.0
	strong.heading = 0.0
	weak.sail_amount = 1.0
	strong.sail_amount = 1.0
	weak.wind.set_fixed(FAIR_DIR, 4.0)
	strong.wind.set_fixed(FAIR_DIR, 8.0)
	for _i in 60:
		weak.step(0.05, _inp())
		strong.step(0.05, _inp())
	T.ok(strong.speed > weak.speed + 0.5, "strength 8 outruns strength 4")
	weak.free()
	strong.free()
	var reefed := _boat(data)
	var full := _boat(data)
	reefed.heading = 0.0
	full.heading = 0.0
	reefed.sail_amount = 0.35
	full.sail_amount = 1.0
	_fair(reefed)
	_fair(full)
	for _i in 60:
		reefed.step(0.05, _inp())
		full.step(0.05, _inp())
	T.ok(full.speed > reefed.speed + 0.5, "full canvas outruns 0.35 sail")
	T.ok(reefed.speed > 0.2, "partial sail still moves in a tailwind")
	reefed.free()
	full.free()


func test_zero_wind_legacy_boost_cap_knots() -> void:
	var data = _data()
	var calm := _boat(data)
	calm.heading = 0.0
	calm.sail_amount = 1.0
	calm.wind.set_fixed(FAIR_DIR, 0.0)
	for _i in 40:
		calm.step(0.05, _inp({"forward": 1.0}))
	T.ok(calm.speed < 0.02, "zero wind produces no speed")
	calm.free()
	var a := _boat(data)
	var c := _boat(data)
	_fair(a)
	_fair(c)
	var ctrl := _inp({"forward": 1.0, "right": 0.4})
	var boosted := ctrl.duplicate()
	boosted["boost"] = true
	for _i in 30:
		a.step(0.05, ctrl)
		c.step(0.05, boosted)
	T.near(a.sail_amount, c.sail_amount, 1e-6, "legacy boost does not change sail")
	T.near(a.speed, c.speed, 1e-6, "legacy boost does not change speed")
	T.near(a.heading, c.heading, 1e-6, "legacy boost does not change heading")
	T.ok(a.planar_pos.distance_to(c.planar_pos) < 1e-5, "legacy boost does not change pose")
	a.free()
	c.free()
	var cap := _boat(data)
	cap.heading = 0.0
	cap.sail_amount = 1.0
	cap.wind.set_fixed(FAIR_DIR, 40.0)
	for _i in 80:
		cap.step(0.05, _inp({"forward": 1.0}))
		T.ok(cap.speed <= MAX_SPEED + 1e-6, "speed never exceeds 16 m/s")
	T.near(cap.knots(), cap.speed * KNOTS_PER_MS, 1e-5, "knots is speed * 1.94384")
	cap.free()


func test_steer_and_visual_forward() -> void:
	var b := _boat(_data())
	b.heading = 0.0
	b.speed = 12.0
	b.sail_amount = 0.6
	_fair(b)
	b._sync_transform()
	for _i in 20:
		b.step(0.05, _inp({"right": 1.0, "forward": 1.0}))
	T.ok(b.heading > 0.15, "right steer increases heading (east)")
	var vis: Vector3 = -b.transform.basis.z
	var vis_xz := Vector2(vis.x, vis.z)
	if vis_xz.length() > 0.001:
		vis_xz = vis_xz.normalized()
	var fwd: Vector2 = b.forward_xz().normalized()
	T.ok(vis_xz.dot(fwd) > 0.95, "visual -Z.xz matches forward_xz after right turn")
	b.free()


func test_world_bounds() -> void:
	var data = _data()
	var b := _boat(data)
	_fair(b)
	b.planar_pos = Vector2(9000, 9000)
	b.speed = 5.0
	b.sail_amount = 1.0
	b.step(0.05, _inp({"forward": 1.0}))
	var half: float = float(data.world_half_extent)
	T.ok(absf(b.planar_pos.x) <= half and absf(b.planar_pos.y) <= half, "clamped to world")
	b.free()


func test_collision_slide_and_safe_save() -> void:
	var data = _data()
	var b := _boat(data)
	var island: Dictionary = data.by_kind("island")[0]
	var c: Vector2 = island["pos"]
	var r: float = float(island["radius"])
	b.planar_pos = c + Vector2(r + 40.0, 0)
	b.heading = atan2(-1.0, 0.0)  # toward -X into the circle
	b.speed = 16.0
	b.sail_amount = 1.0
	b.wind.set_fixed(Vector2(-1.0, 0.0), FAIR_STR)
	var dt: float = 0.05
	var max_step: float = MAX_SPEED * dt + 1e-4
	var prev: Vector2 = b.planar_pos
	for _i in 80:
		prev = b.planar_pos
		b.step(dt, _inp({"forward": 1.0}))
		var jump: float = b.planar_pos.distance_to(prev)
		T.ok(jump <= max_step, "no teleporting substep")
		T.ok(not data.overlaps_land(b.planar_pos, b.HULL_RADIUS, false, ""), "never overlapping land")
	T.ok(not data.overlaps_land(b.planar_pos, 8.0, false, ""), "pose accepted by VoyageState draft")
	var vs = VoyageScr.new()
	var path := _unique_save()
	vs.setup(data, path)
	vs.boat_position = b.planar_pos
	vs.boat_heading = b.heading
	T.ok(vs.save(), "collision pose saves")
	_rm_save(path)
	b.free()


func test_recovery_does_not_reveal_route() -> void:
	var data = _data()
	var b := _boat(data)
	var path := _unique_save()
	var vs = VoyageScr.new()
	vs.setup(data, path)
	var before_cells: int = vs.revealed_cells.size()
	var before_count: int = vs.get_charted_count()
	b.planar_pos = Vector2(-900, -900)
	b.heading = 1.2
	b.recover()
	vs.boat_position = b.planar_pos
	vs.boat_heading = b.heading
	vs.update_position(b.planar_pos, b.heading)
	T.ok(vs.revealed_cells.size() <= before_cells + 2, "recovery does not sweep remote cells")
	T.eq(vs.get_charted_count(), before_count, "recovery does not discover new locations")
	var spawn: Dictionary = data.boat_spawn()
	T.near(b.planar_pos.x, spawn["pos"].x, 0.5, "recovered x")
	T.near(b.planar_pos.y, spawn["pos"].y, 0.5, "recovered y")
	_rm_save(path)
	b.free()


func test_frozen_preserves_state() -> void:
	var b := _boat(_data())
	b.wind = WindScr.new()
	var live_control = WindScr.new()
	b.heading = 0.4
	b.speed = 7.0
	b.sail_amount = 0.55
	b.sim_time = 3.25
	b._sync_transform()
	b.frozen = true
	var pos: Vector2 = b.planar_pos
	var h: float = b.heading
	var spd: float = b.speed
	var sail: float = b.sail_amount
	var t0: float = b.sim_time
	var wd: Vector2 = b.wind.direction
	var ws: float = b.wind.strength
	var swell: Vector2 = b.wind.swell_direction
	var probes: Array = [
		_inp({"forward": 1.0}),
		_inp({"back": 1.0}),
		_inp({"left": 1.0}),
		_inp({"right": 1.0}),
		_inp({"brake": true}),
		_inp({"recover": true}),
	]
	for p in probes:
		b.step(0.05, p)
		live_control.step(0.05)
	T.ok(live_control.direction.distance_to(wd) > 1e-5, "unfrozen wind direction would change")
	T.ok(absf(live_control.strength - ws) > 1e-5, "unfrozen wind strength would change")
	T.ok(live_control.swell_direction.distance_to(swell) > 1e-6, "unfrozen swell would change")
	T.ok(b.planar_pos.distance_to(pos) < 1e-8, "frozen pose")
	T.near(b.heading, h, 1e-8, "frozen heading")
	T.near(b.speed, spd, 1e-8, "frozen speed")
	T.near(b.sail_amount, sail, 1e-8, "frozen sail_amount")
	T.near(b.sim_time, t0, 1e-8, "frozen sim_time")
	T.ok(b.wind.direction.distance_to(wd) < 1e-8, "frozen wind direction")
	T.near(b.wind.strength, ws, 1e-8, "frozen wind strength")
	T.ok(b.wind.swell_direction.distance_to(swell) < 1e-8, "frozen swell")
	b.free()


func test_timestep_and_hitch() -> void:
	var data = _data()
	var rates: Array = [30.0, 60.0, 120.0]
	var boats: Array = []
	for fps in rates:
		var b := _boat(data)
		b.heading = 0.0
		_fair(b)
		var n: int = int(fps)
		var dt: float = 1.0 / fps
		for _i in n:
			b.step(dt, _inp({"forward": 1.0}))
		boats.append(b)
	var hitch: Node3D = _boat(data)
	hitch.heading = 0.0
	_fair(hitch)
	hitch.step(1.0, _inp({"forward": 1.0}))
	var ref: Node3D = boats[1]
	var ref_sail: float = ref.sail_amount
	var ref_speed: float = ref.speed
	var ref_pos: Vector2 = ref.planar_pos
	var ref_heading: float = ref.heading
	for b in boats:
		T.near(b.sim_time, 1.0, 1e-5, "1s ramp sim_time")
		T.near(b.sail_amount, ref_sail, 1e-5, "1s ramp sail_amount")
		T.ok(absf(b.speed - ref_speed) <= 0.2, "1s ramp speed within 0.2")
		T.ok(b.planar_pos.distance_to(ref_pos) <= 0.2, "1s ramp position within 0.2")
		T.ok(absf(b.heading - ref_heading) <= 0.01, "1s ramp heading within 0.01")
		b.free()
	T.near(hitch.sim_time, 1.0, 1e-5, "hitch sim_time")
	T.near(hitch.sail_amount, ref_sail, 1e-5, "hitch sail_amount")
	T.ok(absf(hitch.speed - ref_speed) <= 0.2, "hitch speed within 0.2")
	T.ok(hitch.planar_pos.distance_to(ref_pos) <= 0.2, "hitch position within 0.2")
	T.ok(absf(hitch.heading - ref_heading) <= 0.01, "hitch heading within 0.01")
	hitch.free()


func test_wind_field_and_swell() -> void:
	var w = WindScr.new()
	var dlen: float = w.direction.length()
	T.ok(dlen > 0.999 and dlen < 1.001, "constructor direction is unit")
	T.ok(w.direction.length_squared() > 0.5, "constructor direction nonzero")
	T.ok(w.strength > 0.0, "constructor strength positive")
	T.ok(w.swell_direction.distance_to(w.direction) < 1e-6, "swell matches wind at init")
	var d0: Vector2 = w.direction
	var s0: float = w.strength
	w.step(1.0 / 60.0)
	T.ok(absf(w.direction.length() - 1.0) < 1e-5, "first tick stays unit")
	T.ok(w.direction.distance_to(d0) < 0.01, "first tick direction continuous")
	T.ok(absf(w.strength - s0) < 0.5, "first tick strength continuous")
	T.ok(w.strength > 0.0, "first tick strength positive")
	var live = WindScr.new()
	var start_dir: Vector2 = live.direction
	var start_str: float = live.strength
	var prev_swell: Vector2 = live.swell_direction
	var dt: float = 0.1
	for _i in 1200:
		live.step(dt)
		T.ok(absf(live.direction.length() - 1.0) < 1e-4, "120s direction unit")
		T.ok(live.strength > 0.0, "120s strength positive")
		T.ok(live.strength < 40.0, "120s strength bounded")
		T.ok(absf(live.swell_direction.length() - 1.0) < 1e-4, "swell stays unit")
		var turned: float = absf(angle_difference(prev_swell.angle(), live.swell_direction.angle()))
		T.ok(turned <= SWELL_TURN * dt + 1e-7, "swell turn <= 0.00025 rad/s")
		prev_swell = live.swell_direction
	T.ok(
		live.direction.distance_to(start_dir) > 1e-4 or absf(live.strength - start_str) > 1e-4,
		"120s actually changes strength or direction"
	)
	T.ok(live.swell_direction.distance_to(live.direction) > 1e-4, "swell lags after weather changes")
	var fx = WindScr.new()
	fx.set_fixed(Vector2(1.0, 0.0), 7.0)
	T.near(fx.direction.x, 1.0, 1e-6, "set_fixed direction x")
	T.near(fx.direction.y, 0.0, 1e-6, "set_fixed direction y")
	T.near(fx.strength, 7.0, 1e-6, "set_fixed strength")
	T.ok(fx.swell_direction.distance_to(fx.direction) < 1e-8, "set_fixed syncs swell")
	fx.step(5.0)
	T.near(fx.direction.x, 1.0, 1e-8, "fixed wind does not drift")
	T.near(fx.strength, 7.0, 1e-8, "fixed strength holds")
	T.ok(fx.swell_direction.distance_to(fx.direction) < 1e-8, "fixed swell stays synced")
