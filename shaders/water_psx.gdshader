// Agua simple al estilo PSX para los estanques de la isla: textura de agua (SBS Photorealistic Texture Pack 3,
// Elements 12, CC0) en dos capas que se desplazan en sentidos distintos con filtro nearest, tintada con los
// colores oscuros del estanque; olas por vértice en una malla poco subdividida y dos bandas de ondas
// cuantizadas a pocos tonos.
// El plano es un rectángulo; el shader recorta una superelipse (|x|³ + |y|³ < 1 en UV) para que el estanque tenga forma de ojo.
// Sin transparencia ni luces; la niebla del entorno sí le afecta.
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
uniform float tile_size = 7.0;          // metros que cubre una repetición de la textura
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
	if (pow(abs(c.x), 3.0) + pow(abs(c.y), 3.0) > 1.0) {
		discard;
	}
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float r1 = sin((w.x + w.z * 0.6) * ripple_scale + TIME * 0.8);
	float r2 = sin((w.z - w.x * 0.4) * ripple_scale * 1.7 - TIME * 0.6);
	float rip = floor((r1 * r2 * 0.5 + 0.5) * levels) / levels;
	vec2 base_uv = w.xz / tile_size;
	float ta = dot(texture(water_tex, base_uv + scroll_a * TIME).rgb, vec3(0.299, 0.587, 0.114));
	float tb = dot(texture(water_tex, base_uv * 1.7 + vec2(0.37, 0.61) + scroll_b * TIME).rgb, vec3(0.299, 0.587, 0.114));
	float tx = clamp((ta + tb) * 0.5, 0.0, 1.0);
	tx = floor(tx * 6.0 + 0.5) / 6.0;   // pocos tonos: look PSX
	vec3 col = mix(deep_color, shallow_color * 1.5, clamp(tx * tex_strength + rip * (1.0 - tex_strength), 0.0, 1.0));
	// Bordes más claros y reflejo del cielo de lejos (ángulo rasante).
	col = mix(col, shallow_color * 1.4, smoothstep(0.78, 1.0, dot(c, c)) * 0.5);
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 3.0);
	ALBEDO = mix(col, sky_color, clamp(fres * 0.5 + 0.05, 0.0, 0.6));
}
