// Siluetas de árboles lejanos para el exterior: tarjetas verticales (una malla por anillo, ver _forest del
// generador) que giran hacia la cámara (solo en Y),
// dibujadas por el propio shader (pino escalonado o copa redonda, con bordes pixelados al estilo PSX).
// Sin textura, sin transparencia (se descarta el fragmento) y sin luces: es barato aun con cientos de
// árboles en una sola malla. Se funde con la neblina por su cuenta (fog_disabled): más claro y más
// difuminado cuanto más lejos, y con bruma en la base, como si salieran del mar de niebla.
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled, depth_draw_opaque;

uniform vec3 dark_color : source_color = vec3(0.035, 0.05, 0.075);
uniform vec3 haze_color : source_color = vec3(0.42, 0.46, 0.55);
uniform float fade_near = 60.0;
uniform float fade_far = 300.0;
uniform float max_haze = 0.85;
uniform vec2 pixel_grid = vec2(18.0, 48.0);

varying float v_seed;
varying float v_dist;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	// VERTEX = pie del árbol, UV = esquina (0..1), UV2 = (ancho, alto) en metros.
	vec3 origin = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - origin;
	vec3 right = normalize(vec3(to_cam.z, 0.0, -to_cam.x));
	vec3 world = origin + right * (UV.x - 0.5) * UV2.x + vec3(0.0, 1.0 - UV.y, 0.0) * UV2.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	v_seed = hash(origin.xz * 0.37);
	v_dist = length(to_cam);
}

void fragment() {
	vec2 q = (floor(UV * pixel_grid) + 0.5) / pixel_grid;
	float x = abs(q.x * 2.0 - 1.0);   // 0 al centro, 1 en el borde
	float h = 1.0 - q.y;              // 0 pie, 1 copa
	float jag = hash(floor(UV * pixel_grid) + v_seed * 17.0);
	float w;
	if (v_seed < 0.55) {
		// Pino: tres a cinco pisos de ramas que se estrechan.
		float layers = 3.0 + floor(v_seed * 8.0);
		float t = fract(h * layers);
		w = (1.0 - h) * (0.45 + 0.5 * t);
		w = h < 0.1 ? 0.07 : w;
	} else {
		// Árbol de copa redonda sobre un tronco.
		float d = (h - 0.62) / 0.36;
		w = h < 0.28 ? 0.06 : 0.85 * sqrt(max(0.0, 1.0 - d * d));
	}
	w += (jag - 0.5) * 0.12;
	if (x > w) {
		discard;
	}
	float haze = smoothstep(fade_near, fade_far, v_dist) * max_haze;
	haze = max(haze, (1.0 - smoothstep(0.0, 0.4, h)) * 0.55 * max_haze);
	vec3 col = dark_color * (0.8 + 0.5 * v_seed);
	ALBEDO = mix(col, haze_color, clamp(haze, 0.0, 1.0));
}
