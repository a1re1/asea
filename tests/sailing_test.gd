# Isolated boat kinematics: throttle, steer, collision, bounds, recovery fog.
extends RefCounted

const T := preload("res://tests/test_helper.gd")
const BoatScr: GDScript = preload("res://scripts/boat.gd")
const VoyageScr: GDScript = preload("res://scripts/voyage_state.gd")
const WorldScr: GDScript = preload("res://scripts/world_data.gd")


func _data():
	return WorldScr.load_default()


func _boat(data) -> Node3D:
	var b: Node3D = BoatScr.new()
	b.world_data = data
	var spawn: Dictionary = data.boat_spawn()
	b.planar_pos = spawn["pos"]
	b.heading = float(spawn["heading"])
	b.speed = 0.0
	b.throttle = 0.0
	return b


func _inp(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"forward": 0.0, "back": 0.0, "left": 0.0, "right": 0.0,
		"boost": false, "brake": false, "recover": false,
	}
	for k in overrides:
		d[k] = overrides[k]
	return d


func _unique_save() -> String:
	return "user://sailing_test_%d.json" % Time.get_ticks_usec()


func test_throttle_holds_after_release() -> void:
	var b := _boat(_data())
	for _i in 40:
		b.step(0.05, _inp({"forward": 1.0}))
	T.ok(b.throttle > 0.7, "throttle ramps toward 1")
	T.ok(b.speed > 8.0, "speed builds under W")
	var held: float = b.throttle
	var spd: float = b.speed
	b.step(0.05, _inp())
	T.ok(absf(b.throttle - held) < 0.02, "throttle holds on release")
	T.ok(b.speed > spd * 0.7, "glide continues after release")
	b.free()


func test_steer_and_visual_forward() -> void:
	var b := _boat(_data())
	b.heading = 0.0
	b.speed = 12.0
	b.throttle = 0.6
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


func test_boost_brake_bounds() -> void:
	var data = _data()
	var b := _boat(data)
	for _i in 50:
		b.step(0.05, _inp({"forward": 1.0, "boost": true}))
	T.ok(b.speed > 22.0, "Shift exceeds cruise speed")
	for _i in 40:
		b.step(0.05, _inp({"brake": true}))
	T.ok(absf(b.speed) < 2.0, "Space brakes toward stop")
	b.planar_pos = Vector2(9000, 9000)
	b.speed = 5.0
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
	b.speed = 22.0
	b.throttle = 1.0
	var max_step: float = 36.0 * 0.05 * 1.5
	var prev: Vector2 = b.planar_pos
	for _i in 80:
		prev = b.planar_pos
		b.step(0.05, _inp({"forward": 1.0}))
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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	b.free()
