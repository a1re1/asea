# ASEA • The Unwritten Sea — model library (task-2, prop loading).
# Loads original Blender GLBs from res://assets/models/ when available and
# converts imported materials to cel-shaded toon WITHOUT losing the Blender
# palette: duplicate each material, use toon diffuse with a matte finish —
# base color, transparency, and cull_mode are preserved (thin double-sided
# Boat_Sail is never forced to backface culling).
class_name ModelLibrary
extends RefCounted

const ModelDir: String = "res://assets/models/%s.glb"
static var _toon_materials: Dictionary = {}

const NOMINAL_HEIGHT: Dictionary = {
	"palm": 9.0,
	"watchtower": 15.0,
	"ruin_arch": 10.0,
	"house": 7.0,
	"rock": 2.0,
	"buoy": 2.5,
	"boat": 8.0,
}


static func has_model(kind: String) -> bool:
	return ResourceLoader.exists(ModelDir % kind, "PackedScene")


static func nominal_height(kind: String) -> float:
	return float(NOMINAL_HEIGHT.get(kind, 5.0))


static func make_prop(kind: String, fallback: Callable, cull_dist: float = INF) -> Node3D:
	if has_model(kind):
		var scene: PackedScene = load(ModelDir % kind)
		if scene != null:
			var inst := scene.instantiate()
			if inst is Node3D:
				toonify(inst)
				if cull_dist < INF:
					_apply_cull_dist(inst, cull_dist)
				return inst as Node3D
	var built: Variant = fallback.call()
	return built as Node3D


static func toonify(root: Node) -> void:
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i: int in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			if mat is StandardMaterial3D:
				var sm := _toon_materials.get(mat) as StandardMaterial3D
				if sm == null:
					sm = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					sm.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
					# Share immutable overrides and retain their source materials, so
					# queued renderer updates cannot outlive a freed prop's material.
					sm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
					_toon_materials[mat] = sm
				mi.set_surface_override_material(i, sm)


static func _apply_cull_dist(root: Node, cull_dist: float) -> void:
	for child in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := child as GeometryInstance3D
		if gi != null:
			gi.visibility_range_end = cull_dist
