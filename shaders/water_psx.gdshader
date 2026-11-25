// Simple PSX-style water for the island ponds: water texture (SBS Photorealistic Texture Pack 3,
// Elements 12, CC0) in two layers scrolling in different directions with nearest filtering, tinted
// with the dark pond colors; per-vertex waves on a low-subdivision mesh and two ripple bands
// quantized to a few tones.
// The mesh is built from the cells of the hole (level_builder._ponds), so it already has the shape of the pond: the
// shader does not cut anything out (it used to discard a superellipse, which left parts of the holes uncovered).
// No transparency or lights; the environment fog does affect it.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque;

uniform vec3 deep_color : source_color = vec3(0.05, 0.14, 0.17);
uniform vec3 shallow_color : source_color = vec3(0.09, 0.22, 0.25);
uniform vec3 sky_color : source_color = vec3(0.42, 0.46, 0.55);
uniform float wave_height = 0.05;
uniform float wave_speed = 0.9;
uniform float ripple_scale = 0.9;
uniform float levels = 3.0;
uniform sampler2D water_tex : source_color, filter_nearest, repeat_enable;
uniform float tile_size = 7.0;          // meters covered by one texture repeat
uniform vec2 scroll_a = vec2(0.020, 0.008);
uniform vec2 scroll_b = vec2(-0.012, 0.016);
uniform float tex_strength = 0.8;

varying vec2 v_uv;
varying float v_wave;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wave = sin(w.x * 0.8 + TIME * wave_speed) * 0.5 + sin(w.z * 1.1 - TIME * wave_speed * 0.7) * 0.5;
	VERTEX.y += v_wave * wave_height;
	v_uv = UV;
}

void fragment() {
	vec2 c = v_uv * 2.0 - 1.0;
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float r1 = sin((w.x + w.z * 0.6) * ripple_scale + TIME * 0.8);
	float r2 = sin((w.z - w.x * 0.4) * ripple_scale * 1.7 - TIME * 0.6);
	float rip = floor((r1 * r2 * 0.5 + 0.5) * levels) / levels;
	vec2 base_uv = w.xz / tile_size;
	float ta = dot(texture(water_tex, base_uv + scroll_a * TIME).rgb, vec3(0.299, 0.587, 0.114));
	float tb = dot(texture(water_tex, base_uv * 1.7 + vec2(0.37, 0.61) + scroll_b * TIME).rgb, vec3(0.299, 0.587, 0.114));
	float tx = clamp((ta + tb) * 0.5, 0.0, 1.0);
	tx = floor(tx * 6.0 + 0.5) / 6.0;   // few tones: PSX look
	vec3 col = mix(deep_color, shallow_color * 1.5, clamp(tx * tex_strength + rip * (1.0 - tex_strength), 0.0, 1.0));
	// Lighter edges and distant sky reflection (grazing angle).
	col = mix(col, shallow_color * 1.4, smoothstep(0.78, 1.0, dot(c, c)) * 0.5);
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 3.0);
	ALBEDO = mix(col, sky_color, clamp(fres * 0.5 + 0.05, 0.0, 0.6));
}
