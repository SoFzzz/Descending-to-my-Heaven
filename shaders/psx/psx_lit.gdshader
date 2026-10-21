// Portado de Godot 3 a Godot 4 desde Godot-PSX-Starter-kit (MIT, DruidCZ; shaders de
// MenacingMecha y Ahopness). Original en _source/godot-psx-starter-kit/.
shader_type spatial;
render_mode diffuse_lambert, vertex_lighting, cull_disabled, shadows_disabled, depth_draw_opaque;

uniform float precision_multiplier : hint_range(0.0, 1.0) = 1.0;
uniform vec4 modulate_color : source_color = vec4(1.0);
uniform sampler2D albedoTex : source_color, filter_nearest;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(.0, .0);
uniform vec2 uv_pan_velocity = vec2(0.0);
// Parpadeo al recibir un golpe (HitFlash): 0 = normal, 1 = todo del color del golpe.
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;
uniform vec3 hit_flash_color : source_color = vec3(1.0);
// Aura de aviso de ataque (AttackWarning): borde luminoso que sube y baja poco a poco.
// Va aparte del parpadeo para que un golpe no la apague.
uniform float aura : hint_range(0.0, 1.0) = 0.0;
uniform vec3 aura_color : source_color = vec3(1.0, 0.8, 0.2);

// https://github.com/dsoft20/psx_retroshader/blob/master/Assets/Shaders/psx-vertexlit.shader
const vec2 base_snap_res = vec2(160.0, 120.0);
vec4 get_snapped_pos(vec4 base_pos)
{
	vec4 snapped_pos = base_pos;
	snapped_pos.xyz = base_pos.xyz / base_pos.w; // convert to normalised device coordinates (NDC)
	vec2 snap_res = floor(base_snap_res * precision_multiplier);  // increase "snappy-ness"
	snapped_pos.x = floor(snap_res.x * snapped_pos.x) / snap_res.x;  // snap the base_pos to the lower-vertex_resolution grid
	snapped_pos.y = floor(snap_res.y * snapped_pos.y) / snap_res.y;
	snapped_pos.xyz *= base_pos.w;  // convert back to projection-space
	return snapped_pos;
}

void vertex()
{
	UV = UV * uv_scale + uv_offset;
	UV += uv_pan_velocity * TIME;

	POSITION = get_snapped_pos(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));  // snap position to grid

}

void fragment()
{
	vec3 base = (COLOR * texture(albedoTex, UV) * modulate_color).rgb;
	ALBEDO = mix(base, hit_flash_color, hit_flash);
	EMISSION = hit_flash_color * hit_flash * 0.5;
	if (aura > 0.0) {
		// Fresnel rim (cull_disabled: back faces too) + a slow pulse; a touch of tint on the body.
		float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
		rim = smoothstep(0.35, 1.0, rim);
		float pulse = 0.8 + 0.2 * sin(TIME * 9.0);
		ALBEDO = mix(ALBEDO, aura_color, aura * 0.18);
		EMISSION += aura_color * aura * pulse * (0.12 + 1.6 * rim * rim);
	}
}
