// The whole street floor: old cracked asphalt in the middle, gravel shoulders,
// dirt with sparse grass near the fences. One material for the full kilometre.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/common.gdshaderinc"

uniform float road_half_width = 2.3;
uniform float gravel_width = 0.6;
uniform vec3 asphalt_color : source_color = vec3(0.2, 0.2, 0.195);
uniform vec3 asphalt_old : source_color = vec3(0.29, 0.285, 0.275);
uniform vec3 gravel_color : source_color = vec3(0.45, 0.43, 0.39);
uniform vec3 dirt_color : source_color = vec3(0.26, 0.21, 0.15);
uniform vec3 grass_color : source_color = vec3(0.17, 0.24, 0.08);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float ax = abs(p.x);
	vec4 big = nz(p, 0.018);
	vec4 mid = nz(p, 0.11);
	vec4 fine = nz(p, 0.9);
	vec4 micro = nz(p, 4.5);

	// Wobbly road edge, eroded asphalt.
	float edge = road_half_width + (big.g - 0.5) * 0.5 + (mid.r - 0.5) * 0.18;
	float road = 1.0 - smoothstep(edge - 0.05, edge + 0.04, ax);
	float gravel_edge = edge + gravel_width + (mid.g - 0.5) * 0.5;
	float gravel = (1.0 - road) * (1.0 - smoothstep(gravel_edge - 0.15, gravel_edge + 0.2, ax));

	// Asphalt: worn lighter in wheel tracks, dark repair patches, aggregate speckles.
	float track = exp(-pow((ax - 1.05) / 0.45, 2.0));
	vec3 asph = mix(asphalt_color, asphalt_old, smoothstep(0.2, 0.9, big.r * 0.9 + track * 0.3));
	float patch = smoothstep(0.66, 0.68, nz(p + vec2(31.0, 7.0), 0.025).r) * step(ax, edge - 0.3);
	asph = mix(asph, vec3(0.13, 0.13, 0.13) * (0.85 + fine.a * 0.3), patch * 0.9);
	float speck = smoothstep(0.55, 0.9, micro.a);
	asph *= 0.82 + speck * 0.35 + (fine.g - 0.5) * 0.2;
	// Cell lookup is warped by noise so crack lines meander instead of forming tiles,
	// and only some of the cell edges become cracks.
	vec2 warp = (vec2(mid.g, fine.r) - 0.5) * 2.4;
	float cell = nz(p + warp, 0.11).b;
	float crack_line = 1.0 - smoothstep(0.006, 0.03, cell);
	float crack_mask = smoothstep(0.38, 0.55, big.r) * smoothstep(0.35, 0.55, nz(p * 0.7 + 13.0, 0.05).g);
	float crack = crack_line * crack_mask * (1.0 - patch);
	float edge_crack = (1.0 - smoothstep(0.0, 0.3, edge - ax)) * (1.0 - smoothstep(0.01, 0.035, nz(p + warp, 0.3).b));
	crack = max(crack, edge_crack * 0.7);
	asph = mix(asph, vec3(0.05, 0.05, 0.045), crack * 0.85);

	// Gravel and dirt.
	vec3 grav = gravel_color * (0.65 + micro.a * 0.6) * (0.85 + fine.r * 0.3);
	float grass_mix = smoothstep(0.35, 0.65, mid.r + (ax - gravel_edge) * 0.8);
	vec3 lawn = grass_color * (0.7 + fine.r * 0.6);
	// Lawn variety inside the plots: sunlit patches, dry spots, clover.
	lawn = mix(lawn, vec3(0.36, 0.38, 0.16), smoothstep(0.55, 0.75, big.g) * 0.5);
	lawn = mix(lawn, vec3(0.12, 0.2, 0.06), smoothstep(0.5, 0.7, mid.a) * 0.4);
	lawn *= 0.85 + micro.r * 0.3;
	vec3 soil = mix(dirt_color * (0.7 + fine.g * 0.6), lawn, grass_mix);

	vec3 col = mix(soil, grav, gravel);
	col = mix(col, asph, road);
	// Fallen leaves along the edges.
	float leaves = smoothstep(0.78, 0.82, nz(p * 1.0 + 5.0, 0.6).a) * smoothstep(1.4, 2.6, ax);
	col = mix(col, mix(vec3(0.55, 0.32, 0.08), vec3(0.65, 0.5, 0.1), fine.a), leaves * 0.9);

	ALBEDO = col;
	float rough = mix(0.95, 0.82, road) - speck * road * 0.1;
	ROUGHNESS = mix(rough, 0.95, crack);
	SPECULAR = 0.4;
	vec3 n = noise_normal(p, 0.9, mix(2.0, 1.2, road), 1);
	vec3 n2 = noise_normal(p, 4.5, mix(3.0, 2.2, road), 3);
	vec3 na = n * 2.0 - 1.0;
	vec3 nb = n2 * 2.0 - 1.0;
	NORMAL_MAP = normalize(vec3(na.xy + nb.xy, na.z * nb.z)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	AO = 1.0 - crack * 0.6;
}
