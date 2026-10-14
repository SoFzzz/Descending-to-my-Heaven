// Portado de Godot 3 a Godot 4 desde Godot-PSX-Starter-kit (MIT, DruidCZ; shaders de
// MenacingMecha y Ahopness). Original en _source/godot-psx-starter-kit/.
//SHADER ORIGINALY CREADED BY "demofox" FROM SHADERTOY
//PORTED AND MODIFYED TO GODOT BY AHOPNESS (@ahopness)
//LICENSE : CC0
//COMATIBLE WITH : GLES2, GLES3, WEBGL
//SHADERTOY LINK : https://www.shadertoy.com/view/XdXSzX

shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

uniform float contrast :hint_range(0.0, 3.0) = 1.0;
uniform float brightness :hint_range(-1.0, 1.0) = 0.0;


void fragment(){
	vec2 uv = FRAGCOORD.xy / (1.0 / SCREEN_PIXEL_SIZE).xy;
	
	vec3 pixelColor = texture(screen_texture, uv).xyz;
	
	// Grayscale
	float pixelGrey = dot(pixelColor, vec3(0.2126, 0.7152, 0.0722));
	pixelColor = vec3(pixelGrey);
	
	// Contrast
	pixelColor.rgb = ((pixelColor.rgb - 0.5) * max(contrast, 0.0)) + 0.5;
	
	// Brightness
	pixelColor.rgb += brightness;
	
	COLOR = vec4(pixelColor, 1.0);
}