// Ground warning of an enemy attack (AttackWarning): a bright, slightly wavering rim, a faint
// noisy interior and a fill that grows from the attacker toward the edge as the blow approaches
// (`progress` 0 → 1), so the player reads both WHERE and WHEN it lands. PS1-style: ordered dither
// instead of smooth alpha, so it does not need sorted transparency and keeps the pixel look.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform vec3 color : source_color = vec3(1.0, 0.8, 0.2);
uniform vec3 core_color : source_color = vec3(1.0, 1.0, 0.8);
// 0 = disc, 1 = strip (fills along its length, from +Z toward −Z), 2 = ring (inner .. 1).
uniform int shape = 0;
uniform float inner = 0.0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform vec2 half_size = vec2(1.0, 1.0);

varying vec2 local;

const mat4 BAYER = mat4(
	vec4(0.0, 8.0, 2.0, 10.0), vec4(12.0, 4.0, 14.0, 6.0),
	vec4(3.0, 11.0, 1.0, 9.0), vec4(15.0, 7.0, 13.0, 5.0));

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	local = VERTEX.xz / half_size;
}

void fragment() {
	vec2 p = local;
	float d;          // 0 at the attacker side .. 1 at the far edge (what the fill sweeps)
	float edge_d;     // distance to the outline, 0 on it
	if (shape == 1) {
		d = (1.0 - p.y) * 0.5;
		edge_d = min(1.0 - abs(p.x), 1.0 - abs(p.y));
	} else {
		float r = length(p);
		if (shape == 2) {
			d = clamp((r - inner) / max(1.0 - inner, 0.001), 0.0, 1.0);
			edge_d = min(1.0 - r, r - inner);
		} else {
			d = r;
			edge_d = 1.0 - r;
		}
	}
	if (edge_d < 0.0) {
		discard;
	}
	float t = TIME;
	// Wavering rim and drifting noise: it reads as energy, not as a flat sticker.
	float wobble = noise(p * 6.0 + vec2(t * 1.3, -t * 0.9)) * 0.03;
	float rim = 1.0 - smoothstep(0.0, 0.07 + wobble, edge_d);
	float grain = noise(p * 9.0 - vec2(t * 0.6, t * 0.8));
	float fill = 1.0 - smoothstep(progress - 0.04, progress, d);
	float front = (1.0 - smoothstep(0.0, 0.06, abs(d - progress))) * step(0.02, progress) * step(d, 0.999);
	float body = 0.10 + 0.10 * grain;
	float alpha = max(max(rim * 0.85, fill * (0.30 + 0.25 * grain)), body) + front * 0.6;
	float pulse = 0.85 + 0.15 * sin(t * 10.0 + progress * 6.0);
	alpha *= strength * pulse;
	ivec2 px = ivec2(mod(FRAGCOORD.xy, 4.0));
	if (alpha * 16.0 <= BAYER[px.x][px.y] + 0.5) {
		discard;
	}
	ALBEDO = mix(color, core_color, max(rim, front) * 0.6);
	EMISSION = ALBEDO * 0.6;
}
