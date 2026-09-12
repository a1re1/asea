# ASEA • The Unwritten Sea — world registry (task-1).
# Loads the deterministic seeded location registry from data/locations.json and
# exposes typed, sorted accessors used by terrain generation, the chart, the
# HUD and the tests. Sea convention: an entry's (x, z) is the Godot world
# position; +X is east, +Z is south (Godot 3D axes).
#
# Registry invariants (enforced by tests/world_data_test.gd):
#  - exactly 9 large islands + 25 smaller discoveries = 34 locations
#  - unique ids, no overlapping land circles, everything inside the world box
#  - one harbor, with the boat spawn just off its pier
class_name WorldData
extends RefCounted

const RegistryFile: String = "res://data/locations.json"

## Half-extent of the playable sea square (world is +/- this on X and Z).
var world_half_extent: float = 2400.0

## All 34 locations: {id, name, kind, pos: Vector2(x,z), radius, seed, theme}.
## Sorted by id for deterministic iteration order.
var locations: Array[Dictionary] = []

var _by_id: Dictionary = {}


static func load_default() -> WorldData:
	var data := WorldData.new()
	data._load()
	return data


func _load() -> void:
	var text: String = ""
	var f := FileAccess.open(RegistryFile, FileAccess.READ)
	if f != null:
		text = f.get_as_text()
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	if parsed is Dictionary:
		_from_dict(parsed)
	else:
		push_error("WorldData: cannot parse %s; world would be empty" % RegistryFile)


func _from_dict(dict: Dictionary) -> void:
	world_half_extent = float(dict.get("world_half_extent", 2400.0))
	var raw: Array = dict.get("locations", [])
	var seen: Dictionary = {}
	var list: Array[Dictionary] = []
	for entry_v: Variant in raw:
		if entry_v is not Dictionary:
			continue
		var e: Dictionary = entry_v
		var id := String(e.get("id", ""))
		if id == "" or seen.has(id):
			continue
		seen[id] = true
		var pos_arr: Array = e.get("pos", [0, 0])
		var entry := {
			"id": id,
			"name": String(e.get("name", id)),
			"kind": String(e.get("kind", "islet")),
			"pos": Vector2(float(pos_arr[0] if pos_arr.size() > 0 else 0.0),
					float(pos_arr[1] if pos_arr.size() > 1 else 0.0)),
			"radius": float(e.get("radius", 40.0)),
			"seed": String(e.get("seed", id)),
			"theme": String(e.get("theme", "")),
		}
		list.append(entry)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["id"]) < String(b["id"]))
	locations = list
	_by_id.clear()
	for entry: Dictionary in locations:
		_by_id[String(entry["id"])] = entry


func get_location(id: String) -> Dictionary:
	return _by_id.get(id, {})


func get_location_pos(id: String) -> Vector2:
	var loc: Dictionary = _by_id.get(id, {})
	return loc.get("pos", Vector2.ZERO)


func get_location_radius(id: String) -> float:
	var loc: Dictionary = _by_id.get(id, {})
	return float(loc.get("radius", 40.0))


func has_location(id: String) -> bool:
	return _by_id.has(id)


func by_kind(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in locations:
		if String(entry["kind"]) == kind:
			out.append(entry)
	return out


func large_islands() -> Array[Dictionary]:
	return by_kind("island")


## The 25 smaller named discoveries: everything that is not a large island.
## Includes the home harbor (it is one of the 34 chartable locations).
func discoveries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in locations:
		if String(entry["kind"]) != "island":
			out.append(entry)
	return out


func harbor() -> Dictionary:
	var harbors: Array[Dictionary] = by_kind("harbor")
	return harbors[0] if harbors.size() > 0 else {}


## Deterministic per-location RandomNumberGenerator (layout is seeded; runtime
## visuals may re-seed from this so every launch looks identical).
static func rng_for(seed_text: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	return rng


## Start east of the harbor so the first northbound sail clears its shoreline.
func boat_spawn() -> Dictionary:
	var harbor_loc := harbor()
	if harbor_loc.is_empty():
		return {"pos": Vector2(0, 400), "heading": PI}
	var harbor_pos: Vector2 = get_location_pos(String(harbor_loc["id"]))
	var harbor_radius: float = float(harbor_loc["radius"])
	return {
		"pos": harbor_pos + Vector2(harbor_radius + 90.0, harbor_radius + 30.0),
		"heading": 0.0,  # facing -Z toward Firstlight Isle
	}


## True if the circle at pos/radius overlaps any registered land circle.
## Buoys and pure sea discoveries don't count as land unless include_nonland.
func overlaps_land(pos: Vector2, radius: float, include_nonland: bool = false,
		ignore_id: String = "") -> bool:
	for entry: Dictionary in locations:
		if String(entry["id"]) == ignore_id:
			continue
		var kind := String(entry["kind"])
		var is_land: bool = kind in ["island", "islet", "harbor", "ruin"]
		if not is_land and not include_nonland:
			continue
		var land_radius: float = float(entry["radius"])
		var separation: float = pos.distance_to(entry["pos"])
		if separation < land_radius + radius:
			return true
	return false


func inside_world(pos: Vector2, margin: float = 0.0) -> bool:
	# Square-world criterion: the center must fit inside the box after
	# applying the margin. Radius-aware containment is checked by the tests
	# per-axis (see test_all_inside_world_box).
	return absf(pos.x) <= world_half_extent - margin \
			and absf(pos.y) <= world_half_extent - margin


## True if a circle at pos/radius fits entirely inside the world square.
func circle_inside_world(pos: Vector2, radius: float) -> bool:
	return absf(pos.x) + radius <= world_half_extent \
			and absf(pos.y) + radius <= world_half_extent
