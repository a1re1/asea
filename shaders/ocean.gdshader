// ASEA • The Unwritten Sea — ocean surface shader (GL Compatibility).
//
// Original look: deep cobalt open water giving way to rich turquoise banks,
// crossed by slow, broad caustic webs and diagonal foam streaks that drift
// with the swell. Everything is generated from layered sines (no texture
// reads), so there is no static high-frequency noise to alias.
//
// Compatibility constraints honored:
//   * plain spatial shader, no depth texture / framebuffer (SCREEN_TEXTURE,
//     DEPTH_TEXTURE, hint_screen_texture) sampling of any kind
//   * world-space pattern coordinates via varyings, so the motif field stays
//     cohesive no matter how the 12 km sheet is tiled or moved
//   * motifs fade to zero before the far horizon, killing distant shimmer
//   * vertex swell amplitude sums to 0.245 units (< 0.35 boat-scale bound)
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec3 deep_cobalt : source_color = vec3(0.015, 0.10, 0.32);
uniform vec3 rich_turquoise : source_color = vec3(0.02, 0.50, 0.54);
uniform vec3 foam_color : source_color = vec3(0.48, 0.78, 0.80);
uniform vec3 horizon_glint : source_color = vec3(0.04, 0.26, 0.40);

// Peak single-swell amplitude; the three swells below sum to 0.245 max.
uniform float swell_height = 0.12;
// World-space frequency of the motif field (cycles per unit, pre-multiplied).
uniform float motif_scale = 0.045;
// How fast the foam/caustic field drifts.
uniform float flow_speed = 0.55;
// Motif fade band: fully alive here, fully gone there (units from camera).
uniform float motif_near = 280.0;
uniform float motif_far = 1000.0;

varying vec3 v_world_pos;
varying float v_cam_dist;

// Three gentle directional swells + analytic normal. Called from vertex().
// Returns displacement in y; dy_xz receives the surface slope (dY/dx, dY/dz).
float swell(vec2 xz, float t, out vec2 slope) {
	float a1 = swell_height;             // 0.120
	float a2 = swell_height * 0.667;     // 0.080
	float a3 = swell_height * 0.375;     // 0.045
	float k1 = 0.075;
	float k2 = 0.045;
	float k3 = 0.115;
	vec2 d1 = vec2(0.9499, 0.3126);      // normalize(1.0, 0.33)
	vec2 d2 = vec2(-0.4820, 0.8762);     // normalize(-0.55, 1.0)
	vec2 d3 = vec2(0.6644, -0.7474);     // normalize(0.8, -0.9)
	float p1 = dot(xz, d1) * k1 + t * 0.55;
	float p2 = dot(xz, d2) * k2 - t * 0.38;
	float p3 = dot(xz, d3) * k3 + t * 0.70;
	float c1 = cos(p1) * a1 * k1;
	float c2 = cos(p2) * a2 * k2;
	float c3 = cos(p3) * a3 * k3;
	slope = d1 * c1 + d2 * c2 + d3 * c3;
	return a1 * sin(p1) + a2 * sin(p2) + a3 * sin(p3);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 slope;
	float y = swell(wp.xz, TIME, slope);
	VERTEX.y += y;
	// Analytic smooth normal (model space; the ocean node stays unrotated).
	NORMAL = normalize(vec3(-slope.x, 1.0, -slope.y));
	v_world_pos = vec3(wp.x, wp.y + y, wp.z);
	v_cam_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec2 p = v_world_pos.xz * motif_scale;
	float t = TIME * flow_speed;

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

	// --- Combine, then dissolve every motif before the far horizon ---
	float fade = 1.0 - smoothstep(motif_near, motif_far, v_cam_dist);
	float motif = clamp(web * 0.70 + streak * 0.30, 0.0, 1.0) * fade;

	// --- Palette: very broad, very slow turquoise banks over deep cobalt ---
	float tint = 0.5 + 0.5 * sin(p.x * 0.35 + t * 0.06) * sin(p.y * 0.28 - t * 0.05);
	vec3 base = mix(deep_cobalt, rich_turquoise, tint * 0.55);

	// Grazing angles pick up the pastel sky; keeps sea-to-sky contrast restful.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 col = mix(base, horizon_glint, fres * 0.10);

	ALBEDO = mix(col, foam_color, motif * 0.40);
	EMISSION = foam_color * motif * 0.008;
	ROUGHNESS = 0.72;
	METALLIC = 0.0;
	SPECULAR = 0.14;
}
