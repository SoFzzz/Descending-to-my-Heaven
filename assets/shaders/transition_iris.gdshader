shader_type canvas_item;
// Closing iris used by the scene transition: `cover` 0 = clear, 1 = full black. The edge is banded
// into a few steps (PSX-like) instead of a smooth gradient, and the aperture is slightly squashed
// so it closes on an oval rather than a perfect circle.

uniform float cover : hint_range(0.0, 1.0) = 0.0;
uniform float bands : hint_range(2.0, 16.0) = 6.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(1.0, 0.82);
	float d = length(p) * 1.55;
	float r = mix(1.5, -0.1, cover);
	float a = smoothstep(r - 0.3, r, d);
	a = floor(a * bands + 0.5) / bands;
	COLOR = vec4(0.0, 0.0, 0.0, max(a, step(0.999, cover)));
}
