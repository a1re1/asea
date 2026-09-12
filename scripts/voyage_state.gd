# ASEA • The Unwritten Sea — voyage state (fog of war + save), task-1 author draft.
# Single owner of persistent voyage progression:
#   - a coarse fog-of-war cell grid over the world square (revealed = seen),
#   - the set of discovered locations (chart names/waypoints unlock),
#   - the boat's current pose and the save file that persists everything.
#
# Coordinate convention matches WorldData: locations use (x, z) stored in
# Vector2(x, z) — +X east, +Z south; heading 0 faces -Z (north). World coords
# span [-world_half_extent, +world_half_extent] on both axes (negative through
# positive), so every grid conversion is offset by +world_half_extent.
#
# Save format (user://voyage.json by default) — deliberately tiny and bounded:
#   {
#     "version": 1,
#     "boat": {"pos": [x, z], "heading": h},      # finite floats, in-bounds
#     "discovered": ["id", ...],                  # unknown/stale ids dropped
#     "revealed": [[cx, cz], ...],                # fog cell indices (int pairs)
#   }
# JSON version/types/finites/bounds/corruption are validated on load; any
# invalid save is ignored (returns false) and setup() falls back to a fresh
# voyage — never to a corrupt half-state. Load is transactional: nothing is
# committed to live state until every field has validated.
class_name VoyageState
extends RefCounted

## Emitted exactly once per location, when it is first discovered.
signal discovered(id: String)

const SAVE_VERSION: int = 1
const DEFAULT_SAVE_PATH: String = "user://voyage.json"

## Safety cap: a save larger than this is treated as corrupt, never parsed into
## memory. A real save stays in the low single-digit kilobytes.
const MAX_SAVE_BYTES: int = 262144

## Boat radius used for the "saved boat must be in water" check.
const BOAT_DRAFT: float = 8.0

## Public on purpose: chart/main may query the fog resolution. World side is
## 5000 units, so 125-unit cells give 40x40 = 1600 fog cells maximum (worst
## case, whole world revealed). The chart draws each revealed row as merged
## horizontal spans, so the per-frame rect count stays far below that.
const cell_size: float = 125.0

## Radius (world units) revealed around any position the boat reaches.
const REVEAL_RADIUS: float = 240.0

## A location is discovered when the shortest distance from its center to the
## actual boat travel segment is <= radius + DISCOVERY_MARGIN. Initial
## (fresh-voyage) discovery uses only the spawn point distance.
const DISCOVERY_MARGIN: float = 140.0

## Initial calm-water reveal around the spawn: keeps the harbor + approach
## visible on a fresh voyage while every remote island stays hidden.
## tests/world_data_test.gd anchors this at <= 300.0.
const INITIAL_REVEAL_RADIUS: float = 300.0

var world_data: WorldData = null
var save_path: String = DEFAULT_SAVE_PATH

## Current boat pose (Vector2(x, z), heading in radians, 0 = -Z/north).
var boat_position: Vector2 = Vector2.ZERO
var boat_heading: float = 0.0

## Charted destination id, "" when none (persisted).
var waypoint_id: String = ""

## Ids of locations already discovered (persisted). Unknown/stale ids in the
## save are dropped on load.
var discovered_ids: Dictionary = {}

## Set of revealed fog cell keys "cx:cz" (persisted). Cells are indexed from
## the world's negative corner: cx = floor((x + world_half_extent)/cell_size).
var revealed_cells: Dictionary = {}

var _fog_cols: int = 0
var _fog_rows: int = 0
var _grid_ready: bool = false


func setup(world: WorldData, path: String = DEFAULT_SAVE_PATH) -> void:
	world_data = world
	save_path = path if path != "" else DEFAULT_SAVE_PATH
	_reset_runtime()
	if load_save():
		return
	# No (valid) save: fall back to a safe fresh voyage at the spawn pose.
	new_voyage()


func new_voyage() -> void:
	_reset_runtime()
	if world_data == null:
		return
	var spawn: Dictionary = world_data.boat_spawn()
	var spawn_pos: Vector2 = spawn.get("pos", Vector2.ZERO)
	boat_position = spawn_pos
	boat_heading = float(spawn.get("heading", 0.0))
	_reveal_circle(boat_position, INITIAL_REVEAL_RADIUS)
	# Initial discovery measures the spawn point only: the harbor (≈175 units
	# away, within the 300-unit initial reveal) is charted, everything else
	# stays hidden.
	_discover_from_segment(boat_position, boat_position)
	save()


## Feed the boat's latest pose (called every frame by main while sailing).
## Reveals the swept disc around the path from the previous pose to pos and
## discovers every location whose (radius + margin) the travelled segment
## actually touches. Robust to long per-frame jumps (fog sweep samples the
## segment; discovery measures the true segment, so nothing tunnels).
## Returns true if anything new was discovered this call.
func update_position(pos: Vector2, heading: float) -> bool:
	if world_data == null:
		return false
	if not (is_finite(pos.x) and is_finite(pos.y)) or not is_finite(heading):
		return false
	if not world_data.inside_world(pos, 0.0):
		return false
	var from: Vector2 = boat_position
	boat_position = pos
	boat_heading = heading
	_reveal_circle(from, REVEAL_RADIUS)
	_reveal_circle(pos, REVEAL_RADIUS)
	var length: float = from.distance_to(pos)
	if length > REVEAL_RADIUS * 0.5:
		var steps: int = mini(int(ceilf(length / (REVEAL_RADIUS * 0.5))), 64)
		for i: int in range(1, steps):
			_reveal_circle(from.lerp(pos, float(i) / float(steps)), REVEAL_RADIUS)
	var found: int = _discover_from_segment(from, pos)
	if found > 0:
		save()
	return found > 0


## True if this location has been discovered (chart may name it).
func is_discovered(id: String) -> bool:
	return discovered_ids.has(id)


## True if the fog at this world position has been revealed. Positions outside
## the world box are always unrevealed (fog past the map edge).
func is_revealed(pos: Vector2) -> bool:
	if world_data == null:
		return false
	var cell: Vector2i = _cell_of(pos)
	if cell.x < 0 or cell.y < 0 or cell.x >= _fog_cols or cell.y >= _fog_rows:
		return false
	return revealed_cells.has("%d:%d" % [cell.x, cell.y])


## Number of chartable locations discovered so far (max 34).
func get_charted_count() -> int:
	return discovered_ids.size()


## Set the charted destination. Only already-discovered locations are valid
## waypoints; "" clears. Returns true when the request was accepted.
func set_waypoint(id: String) -> bool:
	if id == "":
		waypoint_id = ""
		save()
		return true
	if not discovered_ids.has(id):
		return false
	waypoint_id = id
	save()
	return true


# --- persistence -----------------------------------------------------------


## Write the voyage to save_path as a small bounded JSON document.
## Returns true on success.
func save() -> bool:
	if world_data == null or save_path == "":
		return false
	# Persist only finite, in-bounds, on-water poses; a drift-out-of-world or
	# beached pose must never become the restore point.
	if not (is_finite(boat_position.x) and is_finite(boat_position.y)):
		return false
	if not is_finite(boat_heading):
		return false
	if not world_data.inside_world(boat_position, 0.0):
		return false
	if world_data.overlaps_land(boat_position, BOAT_DRAFT, false, ""):
		return false
	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"boat": {
			"pos": [boat_position.x, boat_position.y],
			"heading": boat_heading,
		},
		"waypoint": waypoint_id,
		"discovered": _sorted_discovered_ids(),
		"revealed": _sorted_revealed_cells(),
	}
	var text: String = JSON.stringify(payload)
	var f: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


## Load and validate the save at save_path transactionally: every field is
## checked before any live state changes. Returns false (state untouched)
## on any corruption, wrong version, non-finite
## number, out-of-bounds pose, or beached boat.
func load_save() -> bool:
	if world_data == null or save_path == "":
		return false
	var f: FileAccess = FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return false
	if f.get_length() > MAX_SAVE_BYTES:
		f.close()
		return false
	var text: String = f.get_as_text()
	f.close()
	if text.length() > MAX_SAVE_BYTES:
		return false
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK:
		return false
	var parsed: Variant = parser.data
	if parsed is not Dictionary:
		return false
	var dict: Dictionary = parsed
	var version_v: Variant = dict.get("version", null)
	if version_v is not float or not is_finite(version_v) or version_v != float(SAVE_VERSION):
		return false
	var waypoint_v: Variant = dict.get("waypoint", "")
	if waypoint_v is not String:
		return false
	var found_boat: Dictionary = {}
	if not _validate_boat(dict.get("boat", null), found_boat):
		return false
	var found_discovered: Dictionary = {}
	if not _validate_discovered(dict.get("discovered", null), found_discovered):
		return false
	var found_revealed: Dictionary = {}
	if not _validate_revealed(dict.get("revealed", null), found_revealed):
		return false
	# Everything validated: commit atomically (single writer, no half state).
	boat_position = found_boat["pos"]
	boat_heading = found_boat["heading"]
	waypoint_id = waypoint_v
	if waypoint_id != "" and not found_discovered.has(waypoint_id):
		waypoint_id = ""
	discovered_ids = found_discovered
	revealed_cells = found_revealed
	_ensure_grid()
	return true


# --- discovery geometry -----------------------------------------------------


## Discover every location whose shortest distance from its center to the
## actual travelled segment (from -> pos) is <= radius + DISCOVERY_MARGIN.
## Emits discovered(id) exactly once per location. Initial discovery passes
## the same point twice (a degenerate segment = the spawn point itself).
func _discover_from_segment(from: Vector2, to: Vector2) -> int:
	var newly_found: int = 0
	for entry: Dictionary in world_data.locations:
		var id: String = String(entry["id"])
		if discovered_ids.has(id):
			continue
		var reach: float = float(entry["radius"]) + DISCOVERY_MARGIN
		var center: Vector2 = entry["pos"]
		if _segment_point_distance(from, to, center) <= reach:
			discovered_ids[id] = true
			discovered.emit(id)
			newly_found += 1
	return newly_found


## Shortest distance between a point and a segment, clamped at both ends.
func _segment_point_distance(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab: Vector2 = b - a
	var denom: float = ab.length_squared()
	if denom <= 0.0001:
		return a.distance_to(p)
	var t: float = clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	var closest: Vector2 = a + ab * t
	return closest.distance_to(p)


# --- fog geometry ------------------------------------------------------------


## Mark every fog cell whose square touches the disc (pos, radius) revealed.
## Conservative: slightly over-reveals at edges so the swept path can never
## leave fog gaps.
func _reveal_circle(pos: Vector2, radius: float) -> void:
	_ensure_grid()
	var reach: float = maxf(radius, 0.0) + cell_size * 0.5
	if radius <= 0.0:
		return
	var c0: int = maxi(int(floorf((pos.x - reach + world_data.world_half_extent) / cell_size)), 0)
	var c1: int = mini(int(floorf((pos.x + reach + world_data.world_half_extent) / cell_size)), _fog_cols - 1)
	var r0: int = maxi(int(floorf((pos.y - reach + world_data.world_half_extent) / cell_size)), 0)
	var r1: int = mini(int(floorf((pos.y + reach + world_data.world_half_extent) / cell_size)), _fog_rows - 1)
	for cz: int in range(r0, r1 + 1):
		for cx: int in range(c0, c1 + 1):
			var center: Vector2 = Vector2(
					(float(cx) + 0.5) * cell_size - world_data.world_half_extent,
					(float(cz) + 0.5) * cell_size - world_data.world_half_extent)
			if center.distance_squared_to(pos) <= reach * reach:
				revealed_cells["%d:%d" % [cx, cz]] = true


# --- save field validators (pure; write into found_* buffers) ----------------


## Strict boat pose: {"pos": {"pos": [x, z], "heading": h}}; all finite,
## in-bounds and on water. Writes into `out` (keys "pos"/"heading") instead of
## live state so a late failure cannot leave a half-mutated voyage.
func _validate_boat(boat_v: Variant, out: Dictionary) -> bool:
	if boat_v is not Dictionary:
		return false
	var boat: Dictionary = boat_v
	var pos_v: Variant = boat.get("pos", null)
	if pos_v is not Array or (pos_v as Array).size() != 2:
		return false
	var arr: Array = pos_v
	# Strict JSON number check BEFORE any float() conversion.
	for item: Variant in arr:
		if item is not float or not is_finite(item):
			return false
	var heading_v: Variant = boat.get("heading", null)
	if heading_v is not float or not is_finite(heading_v):
		return false
	var xz: Vector2 = Vector2(arr[0], arr[1])
	if not world_data.inside_world(xz, 0.0):
		return false
	if world_data.overlaps_land(xz, BOAT_DRAFT, false, ""):
		return false
	out["pos"] = xz
	out["heading"] = heading_v
	return true


# --- private state -----------------------------------------------------------


## Clear all runtime progression (pose, waypoint, fog, discoveries). Does not
## touch the save file on disk.
func _reset_runtime() -> void:
	boat_position = Vector2.ZERO
	boat_heading = 0.0
	waypoint_id = ""
	discovered_ids = {}
	revealed_cells = {}
	_fog_cols = 0
	_fog_rows = 0
	_grid_ready = false


## Compute grid dims from world_data (idempotent).
func _ensure_grid() -> void:
	if world_data == null:
		return
	var ext: float = world_data.world_half_extent
	_fog_cols = int(ceilf((ext * 2.0) / cell_size))
	_fog_rows = _fog_cols
	_grid_ready = true


## Fog cell containing a world position (grid anchored at the negative corner).
func _cell_of(pos: Vector2) -> Vector2i:
	if not _grid_ready:
		_ensure_grid()
	return Vector2i(
			int(floorf((pos.x + world_data.world_half_extent) / cell_size)),
			int(floorf((pos.y + world_data.world_half_extent) / cell_size)))


## Deterministic save field: sorted "cx:cz" keys turned into [cx, cz] pairs.
func _sorted_revealed_cells() -> Array:
	var pairs: Array = []
	for key: Variant in revealed_cells.keys():
		var parts: PackedStringArray = String(key).split(":")
		if parts.size() != 2:
			continue
		pairs.append([int(parts[0]), int(parts[1])])
	pairs.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ai: Array = a
		var bi: Array = b
		if ai[0] != bi[0]:
			return ai[0] < bi[0]
		return ai[1] < bi[1])
	return pairs


## Deterministic save field: sorted discovered ids (unknown ids are impossible
## here — they only enter via load, which validates them).
func _sorted_discovered_ids() -> Array:
	var ids: Array = discovered_ids.keys()
	ids.sort()
	return ids


## Validate + collect the "discovered" array into found. Strict: the field
## must exist as an Array of Strings; every id must exist in world_data
## (unknown/stale ids are dropped, not fatal) and be a known location.
func _validate_discovered(v: Variant, found: Dictionary) -> bool:
	if v is not Array:
		return false
	for item: Variant in v:
		if item is not String:
			return false
		var id: String = item
		if world_data.has_location(id):
			found[id] = true
	return true


## Validate + collect the "revealed" array into found. Keys are [cx, cz]
## integer pairs inside the grid; anything else is corrupt.
func _validate_revealed(v: Variant, found: Dictionary) -> bool:
	if v is not Array:
		return false
	var ext: float = world_data.world_half_extent
	var max_cell: int = int(ceilf((ext * 2.0) / cell_size)) - 1
	for item: Variant in v:
		if item is not Array or (item as Array).size() != 2:
			return false
		var pair: Array = item
		for n: Variant in pair:
			# JSON ints arrive as floats; require whole, finite, in-grid.
			if n is not float or not is_finite(n) or (n as float) != floorf(n):
				return false
			if (n as float) < 0.0 or (n as float) > float(max_cell):
				return false
		found["%d:%d" % [int(pair[0]), int(pair[1])]] = true
	return true
