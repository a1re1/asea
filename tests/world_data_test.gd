# ASEA world registry checks (task-1): counts, ids, layout, spawn.
# Run via: godot --headless --path . --script res://tests/run_tests.gd
extends RefCounted

const T := preload("res://tests/test_helper.gd")

## Fog policy anchor: voyage_state's initial reveal radius must stay at or
## below this so a fresh voyage hides every location except the home harbor.
const INITIAL_REVEAL_RADIUS: float = 300.0
const MIN_CHANNEL_GAP: float = 40.0
const BOAT_COLLISION_RADIUS: float = 12.0


func test_registry_counts() -> void:
	var wd: WorldData = WorldData.load_default()
	T.eq(wd.locations.size(), 34, "registry has exactly 34 locations")
	T.eq(wd.large_islands().size(), 9, "exactly 9 large islands")
	T.eq(wd.by_kind("harbor").size(), 1, "exactly 1 harbor")
	T.eq(wd.discoveries().size(), 25,
			"exactly 25 smaller discoveries (harbor included)")


func test_ids_and_fields() -> void:
	var wd: WorldData = WorldData.load_default()
	var seen: Dictionary = {}
	var unique: bool = true
	for entry: Dictionary in wd.locations:
		var id := String(entry["id"])
		if seen.has(id) or id == "":
			unique = false
		seen[id] = true
		T.ok(String(entry["name"]) != "", "%s has a display name" % id)
		T.ok(float(entry["radius"]) > 0.0, "%s has positive radius" % id)
	T.ok(unique, "all location ids are unique")
	T.ok(wd.has_location("harbor_thistlerow"), "harbor id resolves")
	T.ok(wd.get_location("nope_nothing").is_empty(), "unknown id returns empty dict")
	T.near(wd.get_location_pos("island_firstlight").x, 150.0, 0.01, "pos.x parses")
	T.near(wd.get_location_radius("island_firstlight"), 280.0, 0.01, "radius parses")


func test_no_land_overlap_and_channels() -> void:
	var wd: WorldData = WorldData.load_default()
	for entry: Dictionary in wd.locations:
		var id := String(entry["id"])
		T.ok(not wd.overlaps_land(entry["pos"], float(entry["radius"]) - 0.5, false, id),
				"%s does not overlap other land" % id)
	# Navigable channels: every land pair keeps a minimum gap.
	var min_gap: float = INF
	for a: Dictionary in wd.locations:
		if not _is_land(a):
			continue
		for b: Dictionary in wd.locations:
			if not _is_land(b) or String(b["id"]) <= String(a["id"]):
				continue
			var gap: float = a["pos"].distance_to(b["pos"]) \
					- float(a["radius"]) - float(b["radius"])
			min_gap = minf(min_gap, gap)
	T.ok(min_gap >= MIN_CHANNEL_GAP,
			"minimum channel gap between land circles is at least %f (got %f)"
					% [MIN_CHANNEL_GAP, min_gap])


func test_all_inside_world_box() -> void:
	var wd: WorldData = WorldData.load_default()
	for entry: Dictionary in wd.locations:
		var pos: Vector2 = entry["pos"]
		var radius: float = float(entry["radius"])
		T.ok(wd.circle_inside_world(pos, radius),
				"%s fully inside world square per-axis" % String(entry["id"]))
		T.ok(wd.inside_world(pos, 0.0), "%s center inside world box" % String(entry["id"]))


func test_fog_hides_distant_at_start() -> void:
	var wd: WorldData = WorldData.load_default()
	var spawn: Dictionary = wd.boat_spawn()
	var spawn_pos: Vector2 = spawn["pos"]
	var harbor_id := String(wd.harbor().get("id", ""))
	var farthest_island: float = 0.0
	for entry: Dictionary in wd.locations:
		var id := String(entry["id"])
		var dist: float = spawn_pos.distance_to(entry["pos"])
		if id == harbor_id:
			continue
		if String(entry["kind"]) == "island":
			farthest_island = maxf(farthest_island, dist)
		T.ok(dist > INITIAL_REVEAL_RADIUS,
				"%s starts hidden beyond initial reveal (%f > %f)"
						% [id, dist, INITIAL_REVEAL_RADIUS])
	T.ok(farthest_island > 5.0 * INITIAL_REVEAL_RADIUS,
			"farthest island far beyond initial reveal (%f)" % farthest_island)


func test_boat_spawn_valid() -> void:
	var wd: WorldData = WorldData.load_default()
	var spawn: Dictionary = wd.boat_spawn()
	T.ok(not spawn.is_empty(), "boat spawn exists")
	var pos: Vector2 = spawn["pos"]
	T.ok(not wd.overlaps_land(pos, BOAT_COLLISION_RADIUS),
			"boat spawn is clear of all land circles")
	T.ok(wd.inside_world(pos, BOAT_COLLISION_RADIUS), "boat spawn inside world box")
	var harbor_pos: Vector2 = wd.harbor()["pos"]
	T.ok(pos.distance_to(harbor_pos) < 400.0, "spawn near home harbor")
	T.ok(is_finite(float(spawn["heading"])), "spawn heading is finite")


## Operator invariant: the boat's first 150 units of forward travel stay over
## open water, and the spawn heading keeps Firstlight Isle ahead on the bow.
func test_spawn_forward_corridor_stays_water() -> void:
	var wd: WorldData = WorldData.load_default()
	var spawn: Dictionary = wd.boat_spawn()
	var pos: Vector2 = spawn["pos"]
	var forward := Vector2(0.0, -1.0)  # heading 0 = facing -Z
	for step: int in range(0, 16):
		var sample: Vector2 = pos + forward * (10.0 * float(step))
		T.ok(not wd.overlaps_land(sample, BOAT_COLLISION_RADIUS),
				"first-150u corridor is water at +%du (sample %s)"
						% [10 * step, str(sample)])
	var to_firstlight: Vector2 = wd.get_location_pos("island_firstlight") - pos
	var aim: float = cos(deg_to_rad(10.0))
	T.ok(forward.normalized().dot(to_firstlight.normalized()) > aim,
			"spawn faces Firstlight Isle ahead on the bow")


func test_deterministic_reload() -> void:
	var a: WorldData = WorldData.load_default()
	var b: WorldData = WorldData.load_default()
	T.eq(a.locations.size(), b.locations.size(), "reload yields same count")
	var same: bool = true
	for i: int in a.locations.size():
		if a.locations[i]["id"] != b.locations[i]["id"] \
				or a.locations[i]["pos"] != b.locations[i]["pos"]:
			same = false
			break
	T.ok(same, "layout identical across loads (deterministic registry)")


func test_rng_deterministic() -> void:
	var ra: RandomNumberGenerator = WorldData.rng_for("island_emberlight")
	var rb: RandomNumberGenerator = WorldData.rng_for("island_emberlight")
	var rc: RandomNumberGenerator = WorldData.rng_for("island_gullwatch")
	for i: int in 8:
		T.eq(ra.randf(), rb.randf(), "same seed same stream (i=%d)" % i)
	T.ok(ra.seed != 0 and rc.randf() != 0.0, "different seeds differ in practice")


func _is_land(entry: Dictionary) -> bool:
	return String(entry["kind"]) in ["island", "islet", "ruin", "harbor"]
