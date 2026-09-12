# Shared three-sine ocean field: height bound, analytic slope, wind fallback.
extends RefCounted

const T := preload("res://tests/test_helper.gd")
const WavesScr: GDScript = preload("res://scripts/sea_waves.gd")
const OceanScr: GDScript = preload("res://scripts/ocean_environment.gd")

const HEIGHT_BOUND := 0.28
const FD_EPS := 0.0025


func test_height_bound_many_samples() -> void:
	var dirs: Array[Vector2] = [
		Vector2(0, -1), Vector2(1, 0), Vector2(-0.4, 0.9), Vector2.ZERO, Vector2(3, -2),
	]
	var times: Array[float] = [0.0, 0.37, 1.25, 8.0, 41.7]
	var max_abs := 0.0
	var finite := true
	for d in dirs:
		for t in times:
			for i in 9:
				for j in 9:
					var pos := Vector2(float(i - 4) * 17.3, float(j - 4) * 11.1)
					var h: float = WavesScr.height_at(pos, t, d)
					if not is_finite(h):
						finite = false
					max_abs = maxf(max_abs, absf(h))
	T.ok(finite, "height_at is finite at sampled positions")
	T.ok(max_abs <= HEIGHT_BOUND + 1e-6, "height_at abs <= 0.28 (got %s)" % max_abs)
	T.ok(is_equal_approx(WavesScr.A1 + WavesScr.A2 + WavesScr.A3, HEIGHT_BOUND), "amplitude sum is 0.28")
	T.ok(is_equal_approx(WavesScr.L1, 48.0) and is_equal_approx(WavesScr.L2, 72.0) and is_equal_approx(WavesScr.L3, 30.0), "wavelengths 48/72/30")
	T.ok(is_equal_approx(WavesScr.W1, 1.1) and is_equal_approx(WavesScr.W2, 0.75) and is_equal_approx(WavesScr.W3, 1.35), "angular velocities 1.1/.75/1.35")
	T.ok(is_equal_approx(WavesScr.ROT2, 0.65) and is_equal_approx(WavesScr.ROT3, -1.1), "rotations +0.65/-1.1")


func test_slope_matches_central_differences() -> void:
	var samples: Array[Vector2] = [
		Vector2.ZERO, Vector2(12.5, -3.2), Vector2(-40.0, 18.0), Vector2(7.7, 7.7), Vector2(100.0, -55.0),
	]
	var dirs: Array[Vector2] = [Vector2(0, -1), Vector2(0.6, -0.8), Vector2(-1, 0.2)]
	var worst := 0.0
	for pos in samples:
		for t in [0.0, 2.4, 9.1]:
			for d in dirs:
				var analytic: Vector2 = WavesScr.slope_at(pos, t, d)
				var hx: float = (
					float(WavesScr.height_at(pos + Vector2(FD_EPS, 0.0), t, d))
					- float(WavesScr.height_at(pos - Vector2(FD_EPS, 0.0), t, d))
				) / (2.0 * FD_EPS)
				var hz: float = (
					float(WavesScr.height_at(pos + Vector2(0.0, FD_EPS), t, d))
					- float(WavesScr.height_at(pos - Vector2(0.0, FD_EPS), t, d))
				) / (2.0 * FD_EPS)
				var err: Vector2 = Vector2(hx, hz) - analytic
				worst = maxf(worst, err.length())
	T.ok(worst < 2e-4, "analytic slope matches central FD (worst %s)" % worst)


func test_direction_normalization_and_zero_fallback() -> void:
	var pos := Vector2(5.0, -8.0)
	var t := 1.7
	var h_zero: float = WavesScr.height_at(pos, t, Vector2.ZERO)
	var h_fallback: float = WavesScr.height_at(pos, t, Vector2(0, -1))
	T.ok(is_equal_approx(h_zero, h_fallback), "zero direction uses Vector2(0,-1)")
	var h_long: float = WavesScr.height_at(pos, t, Vector2(0, -4))
	T.ok(is_equal_approx(h_long, h_fallback), "unnormalized (0,-4) matches unit fallback")
	var s_zero: Vector2 = WavesScr.slope_at(pos, t, Vector2.ZERO)
	var s_fb: Vector2 = WavesScr.slope_at(pos, t, Vector2(0, -1))
	T.ok(s_zero.is_equal_approx(s_fb), "slope fallback matches (0,-1)")


func test_elapsed_progression_moves_toward_wind() -> void:
	var wind := Vector2(0, -1)
	var pos := Vector2(0, 0)
	var h0: float = WavesScr.height_at(pos, 0.0, wind)
	var h_dt: float = WavesScr.height_at(pos, 0.15, wind)
	T.ok(not is_equal_approx(h0, h_dt), "height changes with elapsed time")
	# Crests travel toward wind: a later sample at pos - wind * ds should
	# resemble an earlier sample at pos (phase increases along +direction).
	var ds := 0.4
	var t := 1.0
	var h_here: float = WavesScr.height_at(pos, t, wind)
	var h_ahead: float = WavesScr.height_at(pos + wind.normalized() * ds, t, wind)
	var h_later: float = WavesScr.height_at(pos, t + 0.2, wind)
	T.ok(is_finite(h_here) and is_finite(h_ahead) and is_finite(h_later), "progression samples finite")
	var toward: float = WavesScr.height_at(pos - wind.normalized() * 0.5, 0.0, wind)
	var origin_later: float = WavesScr.height_at(pos, 0.5 * (TAU / 48.0) / 1.1, wind)
	# For a single wave, height_at(0, dt) ~= height_at(-dir * L * ω dt / TAU, 0).
	# Combined field: still expect the origin at small +t to match a point
	# slightly against the wind at t=0 more closely than a point with the wind.
	var against: float = WavesScr.height_at(pos + wind.normalized() * 0.5, 0.0, wind)
	T.ok(absf(origin_later - toward) < absf(origin_later - against), "phase travels toward swell direction")


func test_ocean_surface_patch_and_uniforms() -> void:
	var ocean: Node3D = OceanScr.new()
	ocean._build_ocean()
	var near: MeshInstance3D = ocean.get_node("OceanSurface")
	var far: MeshInstance3D = ocean.get_node("OceanFar")
	T.ok(near != null and far != null, "OceanSurface and OceanFar exist")
	var near_plane: PlaneMesh = near.mesh
	var far_plane: PlaneMesh = far.mesh
	T.ok(is_equal_approx(near_plane.size.x, 640.0), "near patch is 640 m")
	var quads := near_plane.subdivide_width + 1
	var spacing := near_plane.size.x / float(quads)
	var tris := quads * quads * 2
	T.ok(spacing <= 2.5 + 1e-6, "near vertex spacing <= 2.5 m (got %s)" % spacing)
	T.ok(tris == 131072, "near triangles 131072 (got %s)" % tris)
	T.ok(is_equal_approx(far_plane.size.x, 12000.0), "far sheet is 12 km")
	T.ok(is_equal_approx(far.position.y, 0.0), "far ocean at y=0")
	ocean.update_sailing(Vector2(17.3, -41.8), Vector2(2, 0), 0.4, 3.25)
	var near_mat: ShaderMaterial = near.material_override
	var far_mat: ShaderMaterial = far.material_override
	T.ok(is_equal_approx(float(near_mat.get_shader_parameter("wave_time")), 3.25), "near wave_time set")
	T.ok(is_equal_approx(float(far_mat.get_shader_parameter("wave_time")), 3.25), "far wave_time set")
	var wind: Vector2 = near_mat.get_shader_parameter("wind_dir")
	T.ok(wind.is_equal_approx(Vector2(1, 0)), "wind_dir normalized")
	var pc: Vector2 = near_mat.get_shader_parameter("patch_center")
	var pc_far: Vector2 = far_mat.get_shader_parameter("patch_center")
	T.ok(pc.is_equal_approx(pc_far), "shared patch_center")
	T.ok(is_equal_approx(float(near_mat.get_shader_parameter("patch_half")), 320.0), "patch_half 320")
	T.ok(is_equal_approx(float(far_mat.get_shader_parameter("far_sheet")), 1.0), "far_sheet flag on far")
	T.ok(is_equal_approx(float(near_mat.get_shader_parameter("far_sheet")), 0.0), "far_sheet flag off near")
	ocean.free()
