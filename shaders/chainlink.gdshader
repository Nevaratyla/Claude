// Chain-link (rabitsa) mesh drawn analytically on a single quad. UV in metres.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/common.gdshaderinc"

uniform vec3 wire_color : source_color = vec3(0.55, 0.56, 0.55);
uniform float cell = 0.05;
uniform float wire = 0.0035;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = UV / cell;
	// Rotate 45 degrees to get diamonds.
	vec2 q = vec2(p.x + p.y, p.x - p.y) * 0.7071;
	vec2 f = abs(fract(q) - 0.5);
	float w = wire / cell * 1.4142;
	// Mip-aware: keep wires visible but thin at distance.
	float aa = fwidth(q.x) * 0.75;
	float line = max(1.0 - smoothstep(w - aa, w + aa, 0.5 - f.x), 1.0 - smoothstep(w - aa, w + aa, 0.5 - f.y));
	float far_fill = clamp(aa * 4.0, 0.0, 0.6);
	ALPHA = max(line, far_fill * 0.5);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec4 n = nz(wpos.xz + wpos.y, 0.5);
	ALBEDO = wire_color * (0.8 + n.r * 0.3) * mix(1.0, 0.75, smoothstep(0.6, 0.8, n.g)); // rust spots
	METALLIC = 0.6;
	ROUGHNESS = 0.45;
}
