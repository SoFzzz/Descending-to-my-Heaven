// Low mist layer of the exterior: a huge horizontal plane with value noise that drifts very slowly.
// Blends the haze color with transparency; unlit, no shadows and no depth writes.
// Several layers at different heights form the "sea of mist" under the island and blend the void
// into the horizon.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_mix;

uniform vec3 haze_color : source_color = vec3(0.42, 0.46, 0.55);
uniform float density : hint_range(0.0, 1.0) = 0.55;
uniform float noise_scale = 0.035;
uniform vec2 drift = vec2(0.012, 0.007);
uniform float clear_radius = 30.0;   // no mist right under the camera so it does not cover the island

varying vec3 v_world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz * noise_scale + drift * TIME;
	float n = vnoise(p) * 0.6 + vnoise(p * 2.7 + 7.0) * 0.4;
	float cam_h = length(v_world.xz - INV_VIEW_MATRIX[3].xz);
	float near_fade = smoothstep(clear_radius * 0.3, clear_radius * 2.0, cam_h);
	ALBEDO = haze_color * (0.9 + 0.2 * n);
	ALPHA = clamp(density * (0.55 + 0.7 * n) * near_fade, 0.0, 1.0);
}
