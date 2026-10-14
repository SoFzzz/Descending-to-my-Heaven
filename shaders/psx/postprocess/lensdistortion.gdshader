// Portado de Godot 3 a Godot 4 desde Godot-PSX-Starter-kit (MIT, DruidCZ; shaders de
// MenacingMecha y Ahopness). Original en _source/godot-psx-starter-kit/.
//SHADER ORIGINALY CREADED BY "jcant0n" FROM SHADERTOY
//PORTED AND MODIFYED TO GODOT BY AHOPNESS (@ahopness)
//LICENSE : CC0
//COMATIBLE WITH : GLES2, GLES3, WEBGL
//SHADERTOY LINK : https://www.shadertoy.com/view/4sSSzz

shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

uniform float strength :hint_range(-0.035, 0.035) = 0.0;

void fragment(){
	vec2 Resolution = 1.0 / SCREEN_PIXEL_SIZE; 
	vec2 uv = FRAGCOORD.xy / Resolution.xy;
	float aspectRatio = Resolution.x / Resolution.y;
	
	
	vec2 intensity = vec2(strength * aspectRatio);
	
	vec2 coords = uv;
	coords = (coords - 0.5) * 2.0;
	
	vec2 realCoordOffs;
	realCoordOffs.x = (1.0 - coords.y * coords.y) * intensity.y * (coords.x); 
	realCoordOffs.y = (1.0 - coords.x * coords.x) * intensity.x * (coords.y);
	
	vec4 color = texture(screen_texture, uv - realCoordOffs);	 
	
	COLOR = vec4(color);
}