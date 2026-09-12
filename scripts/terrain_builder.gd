# ASEA • The Unwritten Sea — procedural island terrain builder (task-2).
# Deterministic per-island mesh + collision from data/locations.json.
# Public API: assign world_data then add_child; _ready builds islands.
class_name TerrainBuilder
extends Node3D

const ModelLibraryScript := preload("res://scripts/model_library.gd")
const IslandSurfaceScript := preload("res://scripts/island_surface.gd")

var world_data: WorldData = null
var collider_margin: float = 4.0
var build_mode: String = "both"
var _island_surfaces: Array = []


func _ready() -> void:
	if world_data == null:
		world_data = WorldData.load_default()
	for entry: Dictionary in world_data.locations:
		var kind := String(entry["kind"])
		match kind:
			"island":
				_build_large_island(entry)
			"islet", "ruin", "harbor":
				_build_small_land(entry)
			"buoy", "sea":
				_build_poi(entry)


func _build_large_island(entry: Dictionary) -> void:
	var pos: Vector2 = entry["pos"]
	var surface: IslandSurface = IslandSurfaceScript.new()
	surface.location = entry
	surface.rng_seed = String(entry["seed"])
	surface.terrain_radius = float(entry["radius"])
	surface.terrain_height = _height_for(entry)
	add_child(surface)
	surface.position = Vector3(pos.x, 0.0, pos.y)
	surface.build()
	_island_surfaces.append(surface)


func _build_small_land(entry: Dictionary) -> void:
	var pos: Vector2 = entry["pos"]
	var surface: IslandSurface = IslandSurfaceScript.new()
	surface.location = entry
	surface.rng_seed = String(entry["seed"])
	surface.terrain_radius = float(entry["radius"])
	surface.terrain_height = _small_height(float(entry["radius"]))
	surface.build_simple = true
	add_child(surface)
	surface.position = Vector3(pos.x, 0.0, pos.y)
	surface.build()
	_island_surfaces.append(surface)


func _build_poi(entry: Dictionary) -> void:
	var pos: Vector2 = entry["pos"]
	var kind := String(entry["kind"])
	var root := Node3D.new()
	root.name = String(entry["id"])
	root.position = Vector3(pos.x, 0.45, pos.y)
	var node: Node3D
	if kind == "buoy":
		node = ModelLibraryScript.make_prop("buoy", _fallback_buoy, 1200.0)
	else:
		node = ModelLibraryScript.make_prop("rock", _fallback_sea_marker, 900.0)
	root.add_child(node)
	add_child(root)


func _fallback_buoy() -> Node3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.45
	mesh.bottom_radius = 0.55
	mesh.height = 2.4
	mesh.radial_segments = 8
	mesh.rings = 1
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.44, 0.35)
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
	mi.material_override = mat
	mi.position = Vector3(0.0, 1.2, 0.0)
	return mi


func _fallback_sea_marker() -> Node3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.4
	mesh.height = 2.2
	mesh.radial_segments = 10
	mesh.rings = 6
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.72, 0.62)
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mi.material_override = mat
	mi.position = Vector3(0.0, 0.6, 0.0)
	return mi


func _height_for(entry: Dictionary) -> float:
	var radius: float = float(entry["radius"])
	var theme := String(entry.get("theme", "")).to_lower()
	var seed := String(entry.get("seed", "")).to_lower()
	var base := clampf(radius * 0.38, 80.0, 150.0)
	if theme.contains("cliff") or seed == "halcyon" or seed == "cinder":
		return minf(150.0, base + 28.0)
	if theme.contains("spire") or theme.contains("volcan") or seed == "needle":
		return minf(150.0, base + 40.0)
	if theme.contains("atoll") or theme.contains("terrace") or seed == "firstlight":
		return maxf(80.0, base - 12.0)
	return base


func _small_height(radius: float) -> float:
	return clampf(radius * 0.22, 4.0, 14.0)


func nearest_land_distance(pos: Vector2) -> float:
	var best := INF
	for entry: Dictionary in world_data.locations:
		var kind := String(entry["kind"])
		if kind in ["island", "islet", "harbor", "ruin"]:
			var d := pos.distance_to(entry["pos"]) - float(entry["radius"])
			best = minf(best, d)
	return best
