// ASEA • The Unwritten Sea — ocean surface shader (GL Compatibility).
//
// Identical three-sine field as scripts/sea_waves.gd. Explicit wave_time /
// wind_dir uniforms (never TIME) so pause agrees with the boat sampler.
// Near patch fades displacement+slope to exactly 0 at the square edge;
// far sheet discards the complementary interior square. World-space color.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec3 deep_cobalt : source_color = vec3(0.015, 0.10, 0.32);
uniform vec3 rich_turquoise : source_color = vec3(0.02, 0.50, 0.54);
uniform vec3 foam_color : source_color = vec3(0.48, 0.78, 0.80);
uniform vec3 horizon_glint : source_color = vec3(0.04, 0.26, 0.40);

uniform float motif_scale = 0.045;
uniform float flow_speed = 0.55;
uniform float motif_near = 280.0;
uniform float motif_far = 1000.0;

uniform float wave_time = 0.0;
uniform vec2 wind_dir = vec2(0.0, -1.0);
uniform float wind_strength = 0.0;
uniform vec2 patch_center = vec2(0.0);
uniform float patch_half = 320.0;
uniform float far_sheet = 0.0;

varying vec3 v_world_pos;
varying float v_height;

vec2 rotate_dir(vec2 d, float ang) {
	float c = cos(ang);
	float s = sin(ang);
	return vec2(d.x * c - d.y * s, d.x * s + d.y * c);
}

vec2 base_wind(vec2 d) {
	float ls = dot(d, d);
	if (ls > 1e-12) {
		return d * inversesqrt(ls);
	}
	return vec2(0.0, -1.0);
}

// Three directional sines matching SeaWaves. slope is (dY/dx, dY/dz).
float swell(vec2 xz, float t, vec2 wind, out vec2 slope) {
	vec2 d1 = base_wind(wind);
	vec2 d2 = rotate_dir(d1, 0.65);
	vec2 d3 = rotate_dir(d1, -1.1);
	float a1 = 0.14;
	float a2 = 0.09;
	float a3 = 0.05;
	float k1 = TAU / 48.0;
	float k2 = TAU / 72.0;
	float k3 = TAU / 30.0;
	float p1 = dot(xz, d1) * k1 - t * 1.1;
	float p2 = dot(xz, d2) * k2 - t * 0.75;
	float p3 = dot(xz, d3) * k3 - t * 1.35;
	float c1 = cos(p1) * a1 * k1;
	float c2 = cos(p2) * a2 * k2;
	float c3 = cos(p3) * a3 * k3;
	slope = d1 * c1 + d2 * c2 + d3 * c3;
	return a1 * sin(p1) + a2 * sin(p2) + a3 * sin(p3);
}

float edge_fade(vec2 xz) {
	vec2 d = abs(xz - patch_center);
	float m = max(d.x, d.y);
	// Exactly 0 at and beyond the square edge; 1 in the interior.
	return 1.0 - smoothstep(patch_half * 0.82, patch_half, m);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 slope = vec2(0.0);
	float y = 0.0;
	float fade = 0.0;
	if (far_sheet < 0.5) {
		fade = edge_fade(wp.xz);
		y = swell(wp.xz, wave_time, wind_dir, slope) * fade;
		slope *= fade;
		VERTEX.y += y;
		NORMAL = normalize(vec3(-slope.x, 1.0, -slope.y));
	} else {
		NORMAL = vec3(0.0, 1.0, 0.0);
	}
	v_height = y;
	v_world_pos = vec3(wp.x, wp.y + y, wp.z);
}

void fragment() {
	if (far_sheet > 0.5) {
		vec2 d = abs(v_world_pos.xz - patch_center);
		if (max(d.x, d.y) <= patch_half) {
			discard;
		}
	}

	float t = wave_time * flow_speed;
	vec2 p = v_world_pos.xz * motif_scale;

	// --- Broad caustic web: ridges where two slow wave fields cross zero ---
	float w1 = sin(p.x * 2.1 + t * 0.50 + sin(p.y * 1.3 - t * 0.23) * 0.8);
	float w2 = sin(p.y * 1.7 - t * 0.41 + sin(p.x * 1.1 + t * 0.31) * 0.8);
	float web_distance = min(abs(w1), abs(w2));
	float web_edge = clamp(fwidth(web_distance) * 0.8, 0.012, 0.06);
	float web = 1.0 - smoothstep(0.045 - web_edge, 0.045 + web_edge, web_distance);

	// --- Diagonal foam streaks, threshold softened by local slope (no alias) ---
	float s_mix = sin(p.x * 0.9 + p.y * 0.6 + t * 0.35) * 0.6
			+ sin(p.x * 0.5 - p.y * 0.8 - t * 0.27) * 0.4;
	float band = clamp(fwidth(s_mix), 0.025, 0.07);
	float streak = smoothstep(0.88 - band, 0.88 + band, s_mix);

	float cam_dist = length(v_world_pos - CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(motif_near, motif_far, cam_dist);
	float accent = clamp(wind_strength * 0.12, 0.0, 0.12);
	float motif = clamp(web * 0.70 + streak * 0.30, 0.0, 1.0) * fade;

	// --- Palette: very broad, very slow turquoise banks over deep cobalt ---
	float tint_raw = 0.5 + 0.5 * sin(p.x * 0.35 + t * 0.06) * sin(p.y * 0.28 - t * 0.05);
	float levels = 4.0;
	float scaled = tint_raw * levels;
	float fw = clamp(fwidth(scaled) * 0.85, 0.001, 0.49);
	float tint_q = (floor(scaled) + smoothstep(0.5 - fw, 0.5 + fw, fract(scaled))) / levels;
	vec3 base = mix(deep_cobalt, rich_turquoise, tint_q * 0.55);

	// Grazing angles pick up the pastel sky; keeps sea-to-sky contrast restful.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 col = mix(base, horizon_glint, fres * 0.10);

	// Restrained crest accent, fwidth-softened and distance-faded.
	float crest_n = clamp(v_height / 0.28, 0.0, 1.0);
	float crest_w = clamp(fwidth(crest_n) * 1.4, 0.02, 0.10);
	float crest = smoothstep(0.58 - crest_w, 0.78 + crest_w, crest_n) * fade;

	ALBEDO = mix(col, foam_color, motif * 0.40 + crest * 0.18 + accent * 0.04);
	EMISSION = foam_color * (motif * 0.008 + crest * 0.012);
	ROUGHNESS = 0.72;
	METALLIC = 0.0;
	SPECULAR = 0.14;
}
