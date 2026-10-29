// Grass clumps instanced via MultiMesh. UV.y: 0 root, 1 tip.
// INSTANCE color tints clumps (dry / fresh / weed).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/common.gdshaderinc"

uniform vec3 root_color : source_color = vec3(0.06, 0.09, 0.03);
uniform float fade_start = 32.0;
uniform float fade_end = 44.0;
uniform bool flower_mode = false;

varying float v_tip;

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_tip = UV.y;
	// Shrink into the ground near the end of the visibility range: no pop.
	float dist = length(root - (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	float shrink = 1.0 - smoothstep(fade_start, fade_end, dist);
	VERTEX.y *= shrink;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 off = wind_offset(wp, UV.y, 0.35, TIME);
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
	// Normals point up so clumps blend with the ground lighting.
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.6));
}

void fragment() {
	vec3 tip = COLOR.rgb;
	vec3 col = mix(root_color, tip, smoothstep(0.0, 0.7, v_tip));
	if (flower_mode) {
		// Stems stay green; UV.x >= 2 marks the petal quads (cut to a 5-petal shape).
		col = mix(root_color, vec3(0.25, 0.38, 0.1), v_tip);
		if (UV.x >= 2.0) {
			vec2 q = vec2(UV.x - 2.5, UV.y - 0.5);
			float a = atan(q.y, q.x);
			float r = length(q);
			float petal = 0.32 + 0.14 * cos(a * 5.0);
			if (r > petal) discard;
			col = r < 0.1 ? vec3(0.95, 0.75, 0.15) : COLOR.rgb * (0.85 + r);
		}
	}
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	ALBEDO = col;
	ROUGHNESS = 0.6;
	SPECULAR = 0.3;
	BACKLIGHT = col * 0.5;
	AO = mix(0.35, 1.0, v_tip);
	AO_LIGHT_AFFECT = 0.5;
}
