// Uber material for fences, houses, sheds and props. UV is in metres
// (set by MeshKit), vertex COLOR tints each object for variety.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/common.gdshaderinc"

// 0 painted, 1 wood planks (vertical grain), 2 corrugated metal, 3 brick,
// 4 concrete/plaster, 5 metal roof tile, 6 siding, 7 slate (wavy), 8 rubber/plastic
uniform int kind = 0;
uniform vec3 albedo : source_color = vec3(0.8);
uniform float roughness = 0.7;
uniform float metallic = 0.0;
uniform float grime = 0.5;       // dirt splash near the ground, streaks
uniform float uv_scale = 1.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 col = albedo * COLOR.rgb;
	float rough = roughness;
	float metal = metallic;
	vec3 nmap = vec3(0.5, 0.5, 1.0);
	float ao = 1.0;
	vec4 n1 = nz(uv, 0.05);
	vec4 n2 = nz(uv, 0.4);
	vec4 n3 = nz(uv * vec2(0.08, 1.0), 1.6);

	if (kind == 1) {
		// Wood: long grain along V, plank seams every ~0.14 m along U handled by geometry.
		float grain = texture(g_noise, vec2(uv.x * 3.0, uv.y * 0.12)).g;
		float rings = sin((uv.x * 40.0 + grain * 12.0)) * 0.5 + 0.5;
		col *= 0.78 + rings * 0.18 + (n2.r - 0.5) * 0.25;
		rough = clamp(rough + (grain - 0.5) * 0.2, 0.3, 1.0);
		nmap = vec3(0.5 + (rings - 0.5) * 0.12, 0.5, 1.0);
	} else if (kind == 2) {
		// Trapezoid corrugation, ~0.11 m pitch along U.
		float t = fract(uv.x / 0.115);
		float slope = (t < 0.2) ? 0.0 : (t < 0.35 ? 1.0 : (t < 0.65 ? 0.0 : (t < 0.8 ? -1.0 : 0.0)));
		nmap = normalize(vec3(-slope * 0.9, 0.0, 1.0)) * 0.5 + 0.5;
		float scratch = smoothstep(0.7, 0.75, n3.a);
		col *= 0.92 + (n2.g - 0.5) * 0.12 - scratch * 0.15;
		ao = 0.8 + (1.0 - abs(slope)) * 0.2;
	} else if (kind == 3) {
		// Brick bond 0.25 x 0.065 with mortar.
		vec2 b = uv / vec2(0.25, 0.075);
		b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
		vec2 f = fract(b);
		vec2 id = floor(b);
		float mortar = 1.0 - (smoothstep(0.0, 0.05, f.x) * smoothstep(1.0, 0.95, f.x)
			* smoothstep(0.0, 0.12, f.y) * smoothstep(1.0, 0.88, f.y));
		float bv = hash12(id);
		vec3 brick = col * (0.75 + bv * 0.4) * (0.85 + n2.a * 0.3);
		col = mix(brick, vec3(0.62, 0.6, 0.55), mortar);
		rough = mix(0.85, 0.95, mortar);
		nmap = mix(vec3(0.5, 0.5, 1.0), vec3(0.5 + (f.x - 0.5) * 0.4, 0.5 + (f.y - 0.5) * 0.4, 1.0), mortar);
		ao = 1.0 - mortar * 0.35;
	} else if (kind == 4) {
		col *= 0.8 + (n1.r - 0.5) * 0.35 + (n2.a - 0.5) * 0.15;
		nmap = noise_normal(uv, 0.9, 2.5, 3);
	} else if (kind == 5) {
		// Metal roof tile: wave across U, steps along V every 0.35 m.
		float w = sin(uv.x / 0.185 * 6.2832);
		float step_v = fract(uv.y / 0.35);
		nmap = normalize(vec3(-cos(uv.x / 0.185 * 6.2832) * 0.7, (step_v > 0.9 ? 1.6 : -0.15), 1.0)) * 0.5 + 0.5;
		ao = 0.75 + 0.25 * (w * 0.5 + 0.5) * smoothstep(1.0, 0.85, step_v);
		col *= 0.92 + (n2.g - 0.5) * 0.15;
	} else if (kind == 6) {
		// Horizontal siding boards, 0.2 m.
		float s = fract(uv.y / 0.2);
		nmap = normalize(vec3(0.0, s < 0.1 ? -1.2 : 0.12, 1.0)) * 0.5 + 0.5;
		ao = s < 0.1 ? 0.7 : 1.0;
		col *= 0.95 + (n2.r - 0.5) * 0.08;
	} else if (kind == 7) {
		// Asbestos slate, broad waves across U.
		float w = sin(uv.x / 0.167 * 6.2832);
		nmap = normalize(vec3(-cos(uv.x / 0.167 * 6.2832) * 0.6, 0.0, 1.0)) * 0.5 + 0.5;
		col *= 0.75 + (n1.g) * 0.35;
		// Lichen spots.
		col = mix(col, vec3(0.45, 0.48, 0.25), smoothstep(0.65, 0.8, n2.r) * 0.6);
		ao = 0.8 + (w * 0.5 + 0.5) * 0.2;
	} else if (kind == 9) {
		// Bark: vertical furrows, U around the trunk, V along it.
		float fur = texture(g_noise, vec2(uv.x * 0.9, uv.y * 0.08)).g;
		float ridge = smoothstep(0.35, 0.65, fur);
		col *= 0.55 + ridge * 0.6 + (n2.a - 0.5) * 0.2;
		nmap = normalize(vec3((fur - 0.5) * 2.2, 0.0, 1.0)) * 0.5 + 0.5;
		ao = 0.6 + ridge * 0.4;
		rough = 0.95;
	} else if (kind == 10) {
		// Birch: white bark with black horizontal lenticels and dark base.
		float len = texture(g_noise, vec2(uv.x * 0.15, uv.y * 1.4)).g;
		float mark = smoothstep(0.62, 0.7, len) * smoothstep(0.3, 0.6, n3.r);
		col = mix(vec3(0.86, 0.85, 0.8), vec3(0.08, 0.07, 0.07), mark);
		col *= 0.9 + n2.r * 0.15;
		rough = 0.7;
	} else {
		col *= 0.93 + (n2.r - 0.5) * 0.1;
	}

	// Weathering: rain streaks on vertical faces, dirt splash near the ground.
	float vertical = 1.0 - abs(wnrm.y);
	float streak = texture(g_noise, vec2(wpos.x * 0.6 + wpos.z * 0.6, wpos.y * 0.05)).g;
	col *= 1.0 - vertical * smoothstep(0.55, 0.8, streak) * 0.18 * grime;
	float splash = (1.0 - smoothstep(0.0, 0.45 + n2.r * 0.25, wpos.y)) * grime;
	col = mix(col, vec3(0.22, 0.18, 0.13), splash * 0.55);
	rough = mix(rough, 0.95, splash);

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	NORMAL_MAP = nmap;
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;
}
