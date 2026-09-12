# ASEA • The Unwritten Sea — one island's mesh, props and shoreline (task-2).
# Generates a deterministic low-poly island: layered beach sand → grass → cliff
# stone bands, raised grassy land with hills/cliffs, a landmark silhouette,
# scattered props (palms, ruins, houses, rocks per theme) and pale shoreline
# foam rings that sit slightly above sea level to avoid z-fighting.
# Sea convention: +X east, +Z south, sea level Y=0; the node origin sits at the
# location center on the water.
class_name IslandSurface
extends Node3D

## Explicit preload keeps the headless --script run resolving this class
## (global class names can fail to resolve for dynamically loaded scripts).
const ModelLibraryScript := preload("res://scripts/model_library.gd")

## Registry entry {id, name, kind, pos, radius, seed, theme}.
var location: Dictionary = {}

## Seed text from the registry; drives all randomness.
var rng_seed: String = "seed"

## Radius of the island at sea level.
var terrain_radius: float = 100.0

## Approximate peak height for large islands.
var terrain_height: float = 20.0

## Simple mode: small islets/ruins/harbors (no cliffs, fewer props).
var build_simple: bool = false

## Number of angular segments around the island outline.
const SEGMENTS: int = 28

## Radial rings from rim to center.
const RINGS: int = 7

## Palette (sandstone / jade / cream / coral, shared with the HUD).
const COLOR_DEEP_SAND := Color(0.72, 0.54, 0.31)
const COLOR_WET_SAND := Color(0.58, 0.44, 0.27)
const COLOR_GRASS := Color(0.12, 0.43, 0.19)
const COLOR_GRASS_DARK := Color(0.07, 0.28, 0.14)
const COLOR_CLIFF := Color(0.72, 0.62, 0.52)
const COLOR_ROCK := Color(0.58, 0.55, 0.52)
const COLOR_TRUNK := Color(0.55, 0.42, 0.32)
const COLOR_CREAM := Color(0.96, 0.93, 0.85)

var _rng: RandomNumberGenerator = null
var _profile: Array[float] = []
var _rim: Array[float] = []
var _hill_phase: float = 0.0
var _terrain_faces := PackedVector3Array()

const SHORE_Y: float = 0.55
const FOAM_Y: float = 0.45


func build() -> void:
	_rng = WorldData.rng_for(rng_seed)
	_build_rim()
	_build_profile()
	_build_terrain_mesh()
	_build_foam_rings()
	if not build_simple:
		_build_props()
		_build_landmark()
	elif String(location.get("kind", "")) == "ruin":
		_build_small_ruin()
	elif String(location.get("kind", "")) == "harbor":
		_build_harbor_props()
	_build_collision()


## Seeded angular shoreline: shared by the outer land rim and foam.
## Max extent is 1.0 so the visible footprint matches the registry radius.
func _build_rim() -> void:
	_rim.clear()
	_hill_phase = _rng.randf_range(0.0, TAU)
	var n1 := 2 + _rng.randi_range(0, 2)
	var n2 := n1 + 1 + _rng.randi_range(0, 2)
	var a1 := 0.08 + _rng.randf() * 0.10
	var a2 := 0.04 + _rng.randf() * 0.06
	var p1 := _rng.randf_range(0.0, TAU)
	var p2 := _rng.randf_range(0.0, TAU)
	for s: int in SEGMENTS:
		var ang := TAU * float(s) / float(SEGMENTS)
		var w := 1.0 - a1 * (0.5 + 0.5 * sin(ang * float(n1) + p1))
		w -= a2 * (0.5 + 0.5 * sin(ang * float(n2) + p2))
		_rim.append(clampf(w, 0.72, 1.0))
	var mx := 0.01
	for v: float in _rim:
		mx = maxf(mx, v)
	for i: int in _rim.size():
		_rim[i] = _rim[i] / mx


func _rim_at(s: int) -> float:
	if _rim.size() != SEGMENTS:
		return 1.0
	return _rim[posmod(s, SEGMENTS)]


## Radial height profile: falls off from center to the shoreline.
func _build_profile() -> void:
	_profile.clear()
	var phase := _rng.randf_range(0.0, TAU)
	for i: int in RINGS + 1:
		var t := float(i) / float(RINGS)
		var falloff := 1.0 - smoothstep(0.50, 1.0, t)
		var noise := 1.0 + 0.18 * sin(t * 7.0 + phase)
		_profile.append(clampf(falloff * noise, 0.0, 1.0))


## Height at normalized radius t in [0,1].
func _height_at(t: float) -> float:
	var idx := clampf(t * float(RINGS), 0.0, float(RINGS))
	var i := int(idx)
	var f := idx - float(i)
	var a := _profile[i]
	var b := _profile[mini(i + 1, RINGS)]
	return lerpf(a, b, f)


func _height_for(t: float, ang: float) -> float:
	var base := _height_at(t)
	var hill := 0.0
	if t < 0.78:
		var lobe := 0.5 + 0.5 * sin(ang * 3.0 + _hill_phase)
		hill = (1.0 - smoothstep(0.12, 0.78, t)) * 0.42 * lobe
	var y := (base + hill) * terrain_height
	if t > 0.86:
		y = lerpf(y, SHORE_Y, smoothstep(0.86, 1.0, t))
	return maxf(y, SHORE_Y)


## Surface color by height and distance from center.
func _color_at(t: float, y: float) -> Color:
	var beach := t > 0.72
	var low_grass := y < terrain_height * 0.35
	if beach:
		return COLOR_WET_SAND if t > 0.92 else COLOR_DEEP_SAND
	if low_grass:
		return COLOR_GRASS
	return COLOR_GRASS_DARK if _rng.randf() < 0.4 else COLOR_GRASS


## Builds the island body as a radial disc mesh with per-vertex heights,
## vertex colors by band (sand/grass/cliff), and flat-ish facets.
func _build_terrain_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring_count := RINGS + 1
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	for r: int in ring_count:
		var t := float(r) / float(RINGS)
		for s: int in SEGMENTS:
			var ang := TAU * float(s) / float(SEGMENTS)
			var scale := lerpf(0.08, 1.0, t) * _rim_at(s)
			var rr := terrain_radius * scale
			var h := _height_for(t, ang)
			verts.append(Vector3(cos(ang) * rr, h, sin(ang) * rr))
			colors.append(_color_at(t, h))
	var center := Vector3(0.0, maxf(terrain_height, SHORE_Y), 0.0)
	for r: int in ring_count - 1:
		for s: int in SEGMENTS:
			var s2 := (s + 1) % SEGMENTS
			var a := r * SEGMENTS + s
			var b := r * SEGMENTS + s2
			var c := (r + 1) * SEGMENTS + s
			var d := (r + 1) * SEGMENTS + s2
			_emit_tri(st, verts, colors, a, c, b)
			_emit_tri(st, verts, colors, b, c, d)
	for s: int in SEGMENTS:
		var s2 := (s + 1) % SEGMENTS
		st.set_color(_color_at(0.0, center.y))
		st.add_vertex(center)
		st.set_color(colors[s])
		st.add_vertex(verts[s])
		st.set_color(colors[s2])
		st.add_vertex(verts[s2])
	st.generate_normals()
	var mesh := st.commit()
	_terrain_faces = mesh.get_faces()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	add_child(mi)


func _emit_tri(st: SurfaceTool, verts: PackedVector3Array, colors: PackedColorArray, i0: int, i1: int, i2: int) -> void:
	st.set_color(colors[i0])
	st.add_vertex(verts[i0])
	st.set_color(colors[i1])
	st.add_vertex(verts[i1])
	st.set_color(colors[i2])
	st.add_vertex(verts[i2])


func ring_count() -> int:
	return RINGS + 1


## Pale foam bands that follow the angular shoreline, lifted above wave height.
func _build_foam_rings() -> void:
	var foam_mat := StandardMaterial3D.new()
	foam_mat.albedo_color = Color(0.98, 0.99, 0.96, 0.78)
	foam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	foam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for k: int in 3:
		var ring := MeshInstance3D.new()
		ring.name = "FoamRing%d" % k
		ring.mesh = _foam_band_mesh(1.02 + float(k) * 0.035, 2.4 + float(k) * 0.8)
		ring.material_override = foam_mat
		ring.position = Vector3(0.0, FOAM_Y + float(k) * 0.04, 0.0)
		add_child(ring)


func _foam_band_mesh(radius_scale: float, half_width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := PackedVector3Array()
	var outer := PackedVector3Array()
	for s: int in SEGMENTS:
		var ang := TAU * float(s) / float(SEGMENTS)
		var mid := terrain_radius * _rim_at(s) * radius_scale
		inner.append(Vector3(cos(ang) * (mid - half_width), 0.0, sin(ang) * (mid - half_width)))
		outer.append(Vector3(cos(ang) * (mid + half_width), 0.0, sin(ang) * (mid + half_width)))
	var white := Color(0.98, 0.99, 0.96, 0.78)
	for s: int in SEGMENTS:
		var s2 := (s + 1) % SEGMENTS
		st.set_color(white)
		st.add_vertex(inner[s])
		st.set_color(white)
		st.add_vertex(outer[s])
		st.set_color(white)
		st.add_vertex(inner[s2])
		st.set_color(white)
		st.add_vertex(inner[s2])
		st.set_color(white)
		st.add_vertex(outer[s])
		st.set_color(white)
		st.add_vertex(outer[s2])
	st.generate_normals()
	return st.commit()


## Shore collision: an invisible cylinder wall + raised disc under the land.
func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "LandCollision"
	var cyl := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = terrain_radius + 2.0
	shape.height = maxf(terrain_height + 6.0, 10.0)
	cyl.shape = shape
	cyl.position = Vector3(0.0, shape.height * 0.5 - 0.5, 0.0)
	body.add_child(cyl)
	add_child(body)


## --- Cel-shaded material helper (toon diffuse, keeps Blender palette) ------

func _toon(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.roughness = 1.0
	mat.metallic = 0.0
	# Double-sided by default (imported GLB props keep their own cull_mode;
	# see model_library task — never force cull-back onto the thin sail).
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _prop_mesh_instance(mesh: Mesh, mat: Material, cull_dist: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	# Distance culling keeps distant props cheap; landmarks pass INF.
	if cull_dist < INF:
		mi.visibility_range_end = cull_dist
	return mi


## --- Props -----------------------------------------------------------------

func _land_y(t: float) -> float:
	return _height_at(t) * terrain_height


func _build_props() -> void:
	var theme := String(location.get("theme", "")).to_lower()
	var palm_count := 8 + _rng.randi_range(0, 5)
	for i: int in palm_count:
		var ang := _rng.randf_range(0.0, TAU)
		var t := _rng.randf_range(0.5, 0.86)
		_add_palm(_polar(ang, t), 7.0 + _rng.randf_range(0.0, 3.0))
	for i: int in 4 + _rng.randi_range(0, 4):
		var ang := _rng.randf_range(0.0, TAU)
		var t := _rng.randf_range(0.3, 0.95)
		_add_rock(_polar(ang, t), 1.0 + _rng.randf_range(0.0, 1.6))
	if theme.contains("ruin") or theme.contains("temple") or theme.contains("arch"):
		for i: int in 2 + _rng.randi_range(0, 2):
			_add_ruin_pillar(_polar(_rng.randf_range(0.0, TAU), 0.55 + _rng.randf_range(0.0, 0.2)))
	if theme.contains("town") or theme.contains("village") or theme.contains("harbor") \
			or theme.contains("cove") or theme.contains("haven") or theme.contains("house"):
		for i: int in 2 + _rng.randi_range(0, 2):
			_add_house(_polar(_rng.randf_range(0.0, TAU), 0.5 + _rng.randf_range(0.0, 0.25)))


func _polar(ang: float, t: float) -> Vector3:
	var wrapped := fposmod(ang, TAU)
	var sector := int(floor(wrapped / TAU * float(SEGMENTS)))
	var angle_a := TAU * float(sector) / float(SEGMENTS)
	var angle_b := TAU * float(sector + 1) / float(SEGMENTS)
	var a := Vector2(cos(angle_a), sin(angle_a)) * _rim_at(sector)
	var b := Vector2(cos(angle_b), sin(angle_b)) * _rim_at(sector + 1)
	var direction := Vector2(cos(wrapped), sin(wrapped))
	# Intersect the ray with the actual straight shoreline edge, then use the
	# same inner-ring offset as the terrain mesh instead of sampling inward.
	var rim_radius := a.cross(b - a) / direction.cross(b - a)
	var xz := direction * terrain_radius * rim_radius * lerpf(0.08, 1.0, clampf(t, 0.0, 1.0))
	return Vector3(xz.x, _surface_height_at(xz) + 0.05, xz.y)


func _surface_height_at(xz: Vector2) -> float:
	# Sample the rendered triangles, including their angular and radial
	# interpolation; the analytical hill function is only exact at vertices.
	for i: int in range(0, _terrain_faces.size(), 3):
		var a := _terrain_faces[i]
		var b := _terrain_faces[i + 1]
		var c := _terrain_faces[i + 2]
		var edge_b := Vector2(b.x - a.x, b.z - a.z)
		var edge_c := Vector2(c.x - a.x, c.z - a.z)
		var offset := xz - Vector2(a.x, a.z)
		var area := edge_b.cross(edge_c)
		if absf(area) < 0.000001:
			continue
		var weight_b := offset.cross(edge_c) / area
		var weight_c := edge_b.cross(offset) / area
		var weight_a := 1.0 - weight_b - weight_c
		if minf(weight_a, minf(weight_b, weight_c)) >= -0.00001:
			return a.y * weight_a + b.y * weight_b + c.y * weight_c
	return SHORE_Y


## Mounts an authored GLB prop when available (toon-shaded by ModelLibrary,
## scaled so its height matches `height`), else builds the procedural fallback.
## Returns the node unparented; caller sets position/rotation and adds it.
func _mount_model(kind: String, height: float, fallback: Callable,
		cull_dist: float = 900.0) -> Node3D:
	var node := ModelLibraryScript.make_prop(kind, fallback, cull_dist)
	if ModelLibraryScript.has_model(kind):
		var s := height / ModelLibraryScript.nominal_height(kind)
		node.scale = node.scale * s
	return node


func _add_palm(at: Vector3, height: float) -> void:
	var root := _mount_model("palm", height, _fallback_palm.bind(height))
	root.position = at
	root.rotation.y = _rng.randf_range(0.0, TAU)
	root.rotation.z = deg_to_rad(_rng.randf_range(-7.0, 7.0))
	add_child(root)


func _fallback_palm(height: float) -> Node3D:
	var root := Node3D.new()
	var trunk := _prop_mesh_instance(
			_cyl_mesh(0.22, 0.34, height, 6), _toon(COLOR_TRUNK), 900.0)
	trunk.position = Vector3(0.0, height * 0.5, 0.0)
	root.add_child(trunk)
	var frond := _prop_mesh_instance(
			_cone_mesh(2.6, 1.6, 7), _toon(Color(0.30, 0.66, 0.38)), 900.0)
	frond.position = Vector3(0.0, height + 0.5, 0.0)
	root.add_child(frond)
	return root


func _add_rock(at: Vector3, scale_f: float) -> void:
	var root := _mount_model("rock", 2.0 * scale_f, _fallback_rock.bind(scale_f))
	root.position = at + Vector3(0.0, 0.3 * scale_f, 0.0)
	root.rotation.y = _rng.randf_range(0.0, TAU)
	add_child(root)


func _fallback_rock(scale_f: float) -> Node3D:
	var mi := _prop_mesh_instance(
			_cone_mesh(1.6 * scale_f, 1.1 * scale_f, 6), _toon(COLOR_ROCK), 900.0)
	mi.position = Vector3(0.0, 0.3 * scale_f, 0.0)
	mi.scale.y = 0.7
	return mi


func _add_ruin_pillar(at: Vector3) -> void:
	var h := 2.5 + _rng.randf_range(0.0, 2.5)
	var mi := _prop_mesh_instance(
			_cyl_mesh(0.5, 0.62, h, 8), _toon(COLOR_CLIFF), 900.0)
	mi.position = at + Vector3(0.0, h * 0.5, 0.0)
	mi.rotation.z = deg_to_rad(_rng.randf_range(-6.0, 6.0))
	add_child(mi)


func _add_house(at: Vector3) -> void:
	var root := _mount_model("house", 7.0, _fallback_house)
	root.position = at
	root.rotation.y = _rng.randf_range(0.0, TAU)
	add_child(root)


func _fallback_house() -> Node3D:
	var root := Node3D.new()
	var body := _prop_mesh_instance(
			BoxMesh.new(), _toon(Color(0.93, 0.88, 0.78)), 900.0)
	body.scale = Vector3(4.0, 3.0, 3.4)
	body.position = Vector3(0.0, 1.5, 0.0)
	root.add_child(body)
	var roof := _prop_mesh_instance(
			_cone_mesh(3.2, 1.8, 4), _toon(Color(0.86, 0.44, 0.35)), 900.0)
	roof.position = Vector3(0.0, 3.9, 0.0)
	roof.rotation.y = 0.7854
	root.add_child(roof)
	return root


## --- Landmark: a memorable silhouette per island theme ---------------------

func _build_landmark() -> void:
	var theme := String(location.get("theme", "")).to_lower()
	var top := Vector3(0.0, terrain_height, 0.0)
	# Place the landmark above the real summit, clear of the inner hill lobes.
	for vertex: Vector3 in _terrain_faces:
		if vertex.y > top.y:
			top = vertex
	top.y += 0.05
	if theme.contains("lighthouse") or theme.contains("light") or theme.contains("tower"):
		_add_landmark_tower(top, COLOR_CREAM, Color(0.86, 0.44, 0.35), 18.0)
	elif theme.contains("ruin") or theme.contains("temple") or theme.contains("arch"):
		_add_landmark_arch(top, COLOR_CLIFF)
	elif theme.contains("town") or theme.contains("village") or theme.contains("house"):
		_add_landmark_tower(top, COLOR_CREAM, Color(0.45, 0.72, 0.47), 15.0)
	else:
		# Broad rock cones embed into the hill; narrow buildings sit on its summit.
		_add_landmark_peak(Vector3(0.0, terrain_height, 0.0))


func _add_landmark_tower(base: Vector3, body_col: Color, band_col: Color, h: float) -> void:
	var root := _mount_model("watchtower", h, _fallback_tower.bind(body_col, band_col, h), INF)
	root.name = "Landmark"
	root.position = base
	add_child(root)


func _fallback_tower(body_col: Color, band_col: Color, h: float) -> Node3D:
	var root := Node3D.new()
	var tower := _prop_mesh_instance(_cyl_mesh(1.6, 2.2, h, 10), _toon(body_col), INF)
	tower.position = Vector3(0.0, h * 0.5, 0.0)
	root.add_child(tower)
	for k: int in 2:
		var band := _prop_mesh_instance(
				_cyl_mesh(2.05, 2.05, h * 0.12, 10), _toon(band_col), INF)
		band.position = Vector3(0.0, h * (0.3 + 0.35 * float(k)), 0.0)
		root.add_child(band)
	var lamp := _prop_mesh_instance(
			_sphere_mesh(1.6), _toon(Color(1.0, 0.92, 0.6)), INF)
	lamp.position = Vector3(0.0, h + 1.0, 0.0)
	root.add_child(lamp)
	return root


func _add_landmark_arch(base: Vector3, col: Color) -> void:
	var root := _mount_model("ruin_arch", 10.0, _fallback_arch.bind(col), INF)
	root.name = "Landmark"
	root.position = base
	root.rotation.y = _rng.randf_range(0.0, TAU)
	add_child(root)


func _fallback_arch(col: Color) -> Node3D:
	var root := Node3D.new()
	for side: int in 2:
		var leg := _prop_mesh_instance(
				_cyl_mesh(0.9, 1.1, 10.0, 8), _toon(col), INF)
		leg.position = Vector3(-3.0 + 6.0 * float(side), 5.0, 0.0)
		root.add_child(leg)
	var lintel := _prop_mesh_instance(
			BoxMesh.new(), _toon(col), INF)
	lintel.scale = Vector3(8.4, 1.6, 2.2)
	lintel.position = Vector3(0.0, 10.6, 0.0)
	root.add_child(lintel)
	return root


func _add_landmark_peak(base: Vector3) -> void:
	var peak := _prop_mesh_instance(
			_cone_mesh(terrain_radius * 0.38, terrain_height * 0.9, 9),
			_toon(COLOR_CLIFF), INF)
	peak.position = base + Vector3(0.0, terrain_height * 0.42, 0.0)
	peak.name = "Landmark"
	add_child(peak)


## --- Small variants ---------------------------------------------------------

func _build_small_ruin() -> void:
	for i: int in 2 + _rng.randi_range(0, 2):
		_add_ruin_pillar(_polar(_rng.randf_range(0.0, TAU), 0.4 + _rng.randf_range(0.0, 0.35)))
	_add_rock(_polar(_rng.randf_range(0.0, TAU), 0.6), 1.2)


func _build_harbor_props() -> void:
	# A cream lighthouse stub + mooring posts so the start harbor reads as such.
	_add_landmark_tower(_polar(0.4, 0.35), COLOR_CREAM, Color(0.86, 0.44, 0.35), 12.0)
	for i: int in 4:
		var ang := 0.6 + float(i) * 0.35
		var post := _prop_mesh_instance(
				_cyl_mesh(0.18, 0.22, 2.2, 6), _toon(Color(0.55, 0.42, 0.32)), 600.0)
		post.position = _polar(ang, 0.93) + Vector3(0.0, 0.4, 0.0)
		add_child(post)


## --- Primitive helpers ------------------------------------------------------

func _cyl_mesh(top_r: float, bottom_r: float, h: float, seg: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


func _cone_mesh(r: float, h: float, seg: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = r
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


func _sphere_mesh(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 12
	m.rings = 6
	return m
