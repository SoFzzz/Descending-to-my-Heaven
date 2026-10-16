// Distant trees of the exterior (PS1 pack models, see scripts/environment/forest_ring.gd): alpha-cut
// texture, unlit and with the environment fog disabled: the shader itself darkens them and blends
// them toward the haze color by camera distance and by height (the trunks fade into the sea of
// mist). Nearest filtering to keep the PSX look.
// INSTANCE_CUSTOM = (y of the tree base, total height in meters).
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform vec3 haze_color : source_color = vec3(0.42, 0.46, 0.55);
uniform float fade_near = 10.0;
uniform float fade_far = 230.0;
uniform float max_haze = 0.88;
uniform float dark_mul = 0.38;
uniform float base_haze = 0.6;

varying float v_dist;
varying float v_frac;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 view_pos = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	v_dist = length(view_pos);
	v_frac = clamp((w.y - INSTANCE_CUSTOM.x) / max(INSTANCE_CUSTOM.y, 0.001), 0.0, 1.0);
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	if (t.a < 0.5) {
		discard;
	}
	float haze = smoothstep(fade_near, fade_far, v_dist) * max_haze;
	haze = max(haze, (1.0 - smoothstep(0.0, 0.35, v_frac)) * base_haze);
	vec3 col = t.rgb * dark_mul;
	ALBEDO = mix(col, haze_color, clamp(haze, 0.0, 1.0));
}
