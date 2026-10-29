// Opaque window glass with fake interior depth, curtains and sky reflection.
// UV in metres across the pane. COLOR.r selects curtain style, COLOR.g interior light.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/common.gdshaderinc"

uniform vec3 curtain_a : source_color = vec3(0.85, 0.82, 0.72);
uniform vec3 curtain_b : source_color = vec3(0.7, 0.45, 0.4);
uniform vec3 lamp_color : source_color = vec3(1.0, 0.72, 0.4);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	// Curtain hangs on the left 20 cm of every pane.
	vec3 interior = vec3(0.035, 0.035, 0.04);
	float style = COLOR.r;
	float folds = sin(uv.x * 55.0) * 0.5 + 0.5;
	float left = 1.0 - smoothstep(0.18, 0.22, uv.x);
	vec3 curtain = mix(curtain_a, curtain_b, step(0.5, style)) * (0.6 + folds * 0.4);
	float has = step(0.25, style);
	vec3 col = mix(interior, curtain * 0.35, left * has);
	// Lit room at night.
	float lit = COLOR.g * (1.0 - g_daylight);
	vec3 emit = lamp_color * lit * 2.5 * (0.6 + 0.4 * (1.0 - left * has));
	ALBEDO = col;
	EMISSION = emit;
	METALLIC = 0.0;
	ROUGHNESS = 0.04 + nz(wpos.xz + wpos.y, 0.8).a * 0.03;
	SPECULAR = 0.9;
	// Slight waviness of old glass.
	NORMAL_MAP = noise_normal(wpos.xy + wpos.zy, 0.3, 0.6, 1);
}
