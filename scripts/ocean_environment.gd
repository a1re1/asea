# ASEA • The Unwritten Sea — ocean + atmosphere builder (self-contained).
#
# Main integration: add_child(preload("res://scripts/ocean_environment.gd").new())
#
# _ready() constructs, with no external assets or dependencies:
#   * dense near patch ~640 m at 2.5 m spacing (255 subdiv -> 256 quads, 131072 tris)
#   * low-poly 12 km far sheet at Y=0 with complementary square cutout
#   * one WorldEnvironment: pastel summery ProceduralSky with a warm sun
#     disc, sky ambient light, linear tonemap, gentle exponential haze
#   * one warm DirectionalLight3D with 4-split cascaded shadows
#   * sculptural low-poly cumulus clouds: one shared flat-shaded puff mesh
#     in a single MultiMesh (shared material), deterministic seed
extends Node3D

const OCEAN_SIZE := 12000.0
const FAR_SUBDIVISIONS := 47
const NEAR_SIZE := 640.0
const NEAR_SUBDIVISIONS := 255
const NEAR_SPACING := NEAR_SIZE / float(NEAR_SUBDIVISIONS + 1)
const PATCH_HALF := NEAR_SIZE * 0.5
const WAVE_CULL_MARGIN := 0.5

const CLOUD_CLUSTERS := 16
const CLOUD_PUFF_Y_MIN := 320.0
const CLOUD_PUFF_Y_MAX := 560.0
const CLOUD_SPREAD := 4200.0

var _ocean_material: ShaderMaterial
var _far_material: ShaderMaterial
var _near_ocean: MeshInstance3D
var _far_ocean: MeshInstance3D


func _ready() -> void:
	_build_ocean()
	_build_environment()
	_build_sun()
	_build_clouds()


func update_sailing(pos: Vector2, direction: Vector2, strength: float, elapsed: float) -> void:
	var snapped := Vector2(
		snappedf(pos.x, NEAR_SPACING),
		snappedf(pos.y, NEAR_SPACING)
	)
	if _near_ocean != null:
		_near_ocean.position = Vector3(snapped.x, 0.0, snapped.y)
	_apply_wave_uniforms(_ocean_material, snapped, direction, strength, elapsed, false)
	_apply_wave_uniforms(_far_material, snapped, direction, strength, elapsed, true)


# --- Ocean -------------------------------------------------------------------

func _make_ocean_material(shader: Shader, far_sheet: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("wave_time", 0.0)
	mat.set_shader_parameter("wind_dir", Vector2(0.0, -1.0))
	mat.set_shader_parameter("wind_strength", 0.0)
	mat.set_shader_parameter("patch_center", Vector2.ZERO)
	mat.set_shader_parameter("patch_half", PATCH_HALF)
	mat.set_shader_parameter("far_sheet", 1.0 if far_sheet else 0.0)
	return mat


func _apply_wave_uniforms(mat: ShaderMaterial, center: Vector2, direction: Vector2, strength: float, elapsed: float, far_sheet: bool) -> void:
	if mat == null:
		return
	var wind := direction.normalized() if direction.length_squared() > 1e-12 else Vector2(0.0, -1.0)
	mat.set_shader_parameter("wave_time", elapsed)
	mat.set_shader_parameter("wind_dir", wind)
	mat.set_shader_parameter("wind_strength", strength)
	mat.set_shader_parameter("patch_center", center)
	mat.set_shader_parameter("patch_half", PATCH_HALF)
	mat.set_shader_parameter("far_sheet", 1.0 if far_sheet else 0.0)


func _build_ocean() -> void:
	var shader: Shader = load("res://shaders/ocean.gdshader")
	_ocean_material = _make_ocean_material(shader, false)
	_far_material = _make_ocean_material(shader, true)

	var near_plane := PlaneMesh.new()
	near_plane.size = Vector2(NEAR_SIZE, NEAR_SIZE)
	near_plane.subdivide_width = NEAR_SUBDIVISIONS
	near_plane.subdivide_depth = NEAR_SUBDIVISIONS

	_near_ocean = MeshInstance3D.new()
	_near_ocean.name = "OceanSurface"
	_near_ocean.mesh = near_plane
	_near_ocean.material_override = _ocean_material
	_near_ocean.position = Vector3.ZERO
	_near_ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_near_ocean.extra_cull_margin = WAVE_CULL_MARGIN
	add_child(_near_ocean)

	var far_plane := PlaneMesh.new()
	far_plane.size = Vector2(OCEAN_SIZE, OCEAN_SIZE)
	far_plane.subdivide_width = FAR_SUBDIVISIONS
	far_plane.subdivide_depth = FAR_SUBDIVISIONS

	_far_ocean = MeshInstance3D.new()
	_far_ocean.name = "OceanFar"
	_far_ocean.mesh = far_plane
	_far_ocean.material_override = _far_material
	_far_ocean.position = Vector3.ZERO
	_far_ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_far_ocean.extra_cull_margin = WAVE_CULL_MARGIN
	add_child(_far_ocean)


# --- Sky, haze, tonemap ------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	# Soft pastel summery gradient: pale azure zenith melting into a warm,
	# peachy haze at the horizon; the sea-side ground colors echo the haze.
	sky_mat.sky_top_color = Color(0.42, 0.70, 0.89)
	sky_mat.sky_horizon_color = Color(1.00, 0.88, 0.76)
	sky_mat.sky_curve = 0.12
	sky_mat.sky_energy_multiplier = 1.0
	sky_mat.ground_bottom_color = Color(0.09, 0.20, 0.28)
	sky_mat.ground_horizon_color = Color(1.00, 0.88, 0.76)
	sky_mat.ground_curve = 0.10
	sky_mat.sun_angle_max = 14.0
	sky_mat.sun_curve = 0.10

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	# Gentle exponential haze: melts the far ocean into the pastel horizon so
	# the 12 km sheet never shows a hard far edge. Terrain stays readable
	# inside the ~5000-unit sandbox; haze only dominates near the horizon.
	env.fog_enabled = true
	env.fog_light_color = Color(1.00, 0.88, 0.77)
	env.fog_density = 0.00011
	env.fog_sky_affect = 0.15

	var world_env := WorldEnvironment.new()
	world_env.name = "OceanAtmosphere"
	world_env.environment = env
	add_child(world_env)


# --- Warm sun with useful shadows -------------------------------------------

func _build_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "WarmSun"
	sun.rotation_degrees = Vector3(-47.0, -28.0, 0.0)
	sun.light_color = Color(1.00, 0.93, 0.82)
	sun.light_energy = 0.35
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 700.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.5
	sun.shadow_blur = 1.0
	add_child(sun)


# --- Sculptural low-poly cumulus ---------------------------------------------

# One shared puff: low-poly sphere re-built with hard face normals for a
# chiseled, hand-sculpted silhouette. All clouds instance this single mesh.
func _make_puff_mesh() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 7
	sphere.rings = 4

	var src := sphere.get_mesh_arrays()
	var in_verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var in_idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]

	var out_verts := PackedVector3Array()
	var out_norms := PackedVector3Array()
	var out_idx := PackedInt32Array()
	for i in range(0, in_idx.size(), 3):
		var a := in_idx[i]
		var b := in_idx[i + 1]
		var c := in_idx[i + 2]
		var va := in_verts[a]
		var vb := in_verts[b]
		var vc := in_verts[c]
		var base := out_verts.size()
		out_verts.append(va)
		out_verts.append(vb)
		out_verts.append(vc)
		# Outward face normal from the triangle cross product, negated when it
		# faces inward — but the SphereMesh index winding is preserved exactly
		# (base, base+1, base+2): Godot's winding is already valid, and flipping
		# it lets back-face culling hide the exterior.
		var n := (vb - va).cross(vc - va).normalized()
		var centroid := (va + vb + vc) / 3.0
		if not n.is_finite() or n.length_squared() < 0.5:
			n = centroid.normalized()  # needle pole triangle fallback
		if n.dot(centroid) < 0.0:
			n = -n
		for j in 3:
			out_idx.append(base + j)
			out_norms.append(n)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_verts
	arrays[Mesh.ARRAY_NORMAL] = out_norms
	arrays[Mesh.ARRAY_INDEX] = out_idx
	var puff := ArrayMesh.new()
	puff.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return puff


func _build_clouds() -> void:
	var puff := _make_puff_mesh()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.90, 0.93)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = puff

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x41534541 & 0x7fffffff  # "ASEA" as hex — deterministic art direction

	var transforms: Array[Transform3D] = []
	for cluster in CLOUD_CLUSTERS:
		var cx := rng.randf_range(-CLOUD_SPREAD, CLOUD_SPREAD)
		var cz := rng.randf_range(-CLOUD_SPREAD, CLOUD_SPREAD)
		var cy := rng.randf_range(CLOUD_PUFF_Y_MIN, CLOUD_PUFF_Y_MAX)
		var cluster_scale := rng.randf_range(1.6, 2.5)
		var puff_count := rng.randi_range(5, 9)
		for p in puff_count:
			var px := cx + rng.randf_range(-34.0, 34.0) * cluster_scale
			var py := cy + rng.randf_range(-8.0, 10.0) * cluster_scale
			var pz := cz + rng.randf_range(-22.0, 22.0) * cluster_scale
			var s := rng.randf_range(14.0, 30.0) * cluster_scale
			var squash := rng.randf_range(0.55, 0.75)
			var basis := Basis().scaled(Vector3(s, s * squash, s))
			transforms.append(Transform3D(basis, Vector3(px, py, pz)))

	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])

	var clouds := MultiMeshInstance3D.new()
	clouds.name = "CumulusField"
	clouds.multimesh = mm
	# Clouds receive warm sunlight without casting distant shadows on the sea.
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	clouds.material_override = mat
	add_child(clouds)
