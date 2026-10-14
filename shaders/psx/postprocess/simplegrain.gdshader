// Portado de Godot 3 a Godot 4 desde Godot-PSX-Starter-kit (MIT, DruidCZ; shaders de
// MenacingMecha y Ahopness). Original en _source/godot-psx-starter-kit/.
//SHADER ORIGINALY CREADED BY "juniorxsound" FROM SHADERTOY
//PORTED AND MODIFYED TO GODOT BY AHOPNESS (@ahopness)
//LICENSE : CC0
//COMATIBLE WITH : GLES2, GLES3, WEBGL
//SHADERTOY LINK : https://www.shadertoy.com/view/ldScWw

shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

uniform float amount :hint_range(0.0, 0.4) = 0.1;

float grain (vec2 st, float time){
	return fract(sin(dot(st.xy, vec2(17.0,180.)))* 2500. + time);
}

void fragment(){
	//Coords
	vec2 uv =  FRAGCOORD.xy / (1.0 / SCREEN_PIXEL_SIZE).xy;
	
	//Produce some noise based on the coords
	vec3 grainPlate = vec3(grain(uv, TIME));
	
	//Get the image
	vec4 img = texture(screen_texture, uv);
	
	//Mix the two signals together
	vec3 mixer = mix(img.rgb, grainPlate, amount);
	
	
	COLOR = vec4(mixer,1.0); 
}