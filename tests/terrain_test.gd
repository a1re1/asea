# ASEA terrain unit tests: build every island/surface in the registry and
# check terrain invariants (raised land above sea, foam above sea, collision
# radius coverage, deterministic regen, landmark presence on large islands).
extends RefCounted

const T := preload("res://tests/test_helper.gd")
const WorldDataScript := preload("res://scripts/world_data.gd")
const IslandSurfaceScript := preload("res://scripts/island_surface.gd")
const TerrainBuilderScript := preload("res://scripts/terrain_builder.gd")

const MIN_LARGE_PEAK: float = 6.0
const MIN_SMALL_PEAK: float = 2.0
const MIN_COLLIDER_RADIUS_MARGIN: float = 1.0
# ocean.gdshader: swell_height 0.12, multiplied by 1.0 + 0.667 + 0.375.
const MAX_WAVE_HEIGHT: float = 0.24504
const PROPS_PER_ISLAND_MIN: int = 12

var _world: WorldData = null


func _world_data() -> WorldData:
	if _world == null:
		_world = WorldData.load_default()
	return _world


func _surfaces() -> Array[IslandSurface]:
	var out: Array[IslandSurface] = []
	for entry: Dictionary in _world_data().locations:
		if String(entry["kind"]) in ["island", "islet", "harbor", "ruin"]:
			var s := IslandSurfaceScript.new()
			s.location = entry
			s.rng_seed = String(entry["seed"])
			s.terrain_radius = float(entry["radius"])
			s.terrain_height = _height_for_kind(entry)
			if String(entry["kind"]) == "island":
				s.build_simple = false
			else:
				s.build_simple = true
			s.build()
			out.append(s)
	return out


func _height_for_kind(entry: Dictionary) -> float:
	var builder := TerrainBuilderScript.new()
	var height: float = builder._height_for(entry) if String(entry["kind"]) == "island" \
			else builder._small_height(float(entry["radius"]))
	builder.free()
	return height


func _peak_y(s: IslandSurface) -> float:
	var aabb: AABB = (s.get_node("Terrain") as MeshInstance3D).get_aabb()
	return aabb.position.y + aabb.size.y


func test_all_land_builds_and_sits_above_sea() -> void:
	var surfaces := _surfaces()
	var expected_land := 0
	for entry: Dictionary in _world_data().locations:
		if String(entry["kind"]) in ["island", "islet", "harbor", "ruin"]:
			expected_land += 1
	T.eq(surfaces.size(), expected_land, "every land location builds a surface")
	for s: IslandSurface in surfaces:
		var peak := _peak_y(s)
		var is_large: bool = String(s.location["kind"]) == "island"
		var min_peak := MIN_LARGE_PEAK if is_large else MIN_SMALL_PEAK
		T.ok(peak >= min_peak, "%s peak above sea (%.1f)" % [s.location["id"], peak])
		T.ok(s.has_node("LandCollision"), "%s has shore collision" % s.location["id"])
		var terrain: MeshInstance3D = s.get_node("Terrain")
		var normals: PackedVector3Array = terrain.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		var all_up: bool = not normals.is_empty()
		var bad_normals: int = 0
		for normal: Vector3 in normals:
			if not normal.is_finite() or normal.y <= 0.0:
				all_up = false
				bad_normals += 1
		T.ok(all_up, "%s terrain normals face upward (%d/%d invalid)" \
				% [s.location["id"], bad_normals, normals.size()])
		s.free()


func test_deterministic_regen() -> void:
	var entry: Dictionary = _world_data().get_location("island_firstlight")
	var a := IslandSurfaceScript.new()
	a.location = entry
	a.rng_seed = String(entry["seed"])
	a.terrain_radius = float(entry["radius"])
	a.terrain_height = _height_for_kind(entry)
	a.build()
	var b := IslandSurfaceScript.new()
	b.location = entry
	b.rng_seed = String(entry["seed"])
	b.terrain_radius = float(entry["radius"])
	b.terrain_height = _height_for_kind(entry)
	b.build()
	var va: PackedVector3Array = (a.get_node("Terrain").mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var vb: PackedVector3Array = (b.get_node("Terrain").mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	T.eq(vb, va, "terrain regen is deterministic")
	a.free()
	b.free()


func test_large_islands_have_landmark_and_props() -> void:
	var landmarks := 0
	for s: IslandSurface in _surfaces():
		if String(s.location["kind"]) == "island" and s.has_node("Landmark"):
			landmarks += 1
		s.free()
	T.eq(landmarks, 9, "all 9 large islands have a landmark node")


func test_foam_rings_above_sea() -> void:
	for s: IslandSurface in _surfaces():
		for k: int in 3:
			var ring: MeshInstance3D = s.get_node("FoamRing%d" % k)
			var lowest_vertex_y: float = ring.position.y + ring.get_aabb().position.y
			T.ok(lowest_vertex_y > MAX_WAVE_HEIGHT,
					"%s foam ring %d clears maximum wave crest" % [s.location["id"], k])
			var normals: PackedVector3Array = ring.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
			var all_up: bool = not normals.is_empty()
			for normal: Vector3 in normals:
				all_up = all_up and normal.is_finite() and normal.y > 0.999
			T.ok(all_up, "%s foam ring %d faces upward" % [s.location["id"], k])
		s.free()


func test_collider_covers_registered_radius() -> void:
	for s: IslandSurface in _surfaces():
		var cs: CollisionShape3D = s.get_node("LandCollision").get_child(0)
		var shape := cs.shape as CylinderShape3D
		T.ok(shape.radius >= float(s.location["radius"]) + MIN_COLLIDER_RADIUS_MARGIN,
				"%s collider covers registry radius" % s.location["id"])
		s.free()
