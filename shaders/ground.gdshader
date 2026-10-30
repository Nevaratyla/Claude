// Street floor and yards. Large-scale layout comes from vertex colour (set by
// Road): R carriageway, G asphalt wear, B puddle, A sagging wheel track. Flat
// yard quads pass zero colour. Fine detail comes from the shared noise texture.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/common.gdshaderinc"

uniform vec3 asphalt_color : source_color = vec3(0.2, 0.2, 0.195);
uniform vec3 dirt_road : source_color = vec3(0.33, 0.31, 0.28);   // crumbled base: gravel and grit
uniform vec3 gravel_color : source_color = vec3(0.45, 0.43, 0.39);
uniform vec3 dirt_color : source_color = vec3(0.26, 0.21, 0.15);
uniform vec3 grass_color : source_color = vec3(0.17, 0.24, 0.08);

varying vec3 wpos;
varying vec4 vmask;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vmask = COLOR;
}

void fragment() {
	vec2 p = wpos.xz;
	float ax = abs(p.x);
	vec4 big = nz(p, 0.018);
	vec4 mid = nz(p, 0.11);
	vec4 fine = nz(p, 0.9);
	vec4 micro = nz(p, 4.5);

	// Carriageway with a ragged edge.
	float road = smoothstep(0.35, 0.65, vmask.r + (mid.r - 0.5) * 0.25 + (fine.g - 0.5) * 0.12);
	// Worn asphalt breaks up into islands with the gravel base showing between.
	float keep_v = (1.0 - vmask.g) + (big.g - 0.5) * 0.55 + (mid.a - 0.5) * 0.3;
	float asph_keep = smoothstep(0.47, 0.53, keep_v);

	// Asphalt: even colour (no blotches), slightly polished wheel tracks, aggregate.
	float track = exp(-pow((ax - 0.9) / 0.4, 2.0));
	float speck = smoothstep(0.55, 0.9, micro.a);
	vec3 asph = asphalt_color * (0.92 + (big.r - 0.5) * 0.1 + track * 0.06);
	asph *= 0.84 + speck * 0.3 + (fine.g - 0.5) * 0.16;
	vec2 warp = (vec2(mid.g, fine.r) - 0.5) * 2.4;
	float cell = nz(p + warp, 0.11).b;
	float crack_line = 1.0 - smoothstep(0.006, 0.03, cell);
	float crack_mask = smoothstep(0.3, 0.5, big.r) * smoothstep(0.3, 0.5, nz(p * 0.7 + 13.0, 0.05).g);
	// Alligator cracking: a finer net of cracks in the most worn places.
	float fine_cell = nz(p + warp * 0.5, 0.35).b;
	float alligator = (1.0 - smoothstep(0.008, 0.03, fine_cell)) * smoothstep(0.55, 0.7, big.r) * smoothstep(0.4, 0.6, mid.g);
	float crack = max(crack_line * crack_mask, alligator * 0.8);
	// Broken asphalt rim: dark crumbling edge where it ends.
	float rim = smoothstep(0.47, 0.5, keep_v) * (1.0 - smoothstep(0.5, 0.58, keep_v));
	crack = max(crack, rim * 0.8);
	asph = mix(asph, vec3(0.05, 0.05, 0.045), crack * 0.85);

	// Crumbled patches: grit and gravel, darker where the wheels go.
	vec3 dirt = dirt_road * (0.82 + fine.r * 0.3 + (big.g - 0.5) * 0.15);
	dirt = mix(dirt, dirt * 0.65, vmask.a * (0.7 + mid.g * 0.5));
	float pebble = smoothstep(0.5, 0.75, micro.a);
	dirt = mix(dirt, mix(vec3(0.55, 0.53, 0.5), vec3(0.2, 0.19, 0.18), fine.a), pebble * 0.85);
	// Old asphalt also darkens a little in the sagging wheel tracks.
	asph *= 1.0 - vmask.a * 0.12;

	vec3 surface = mix(dirt, asph, asph_keep);

	// Verge: gravel shoulder, then soil and grass toward the fence; lawns behind.
	float gravel = (1.0 - road) * (1.0 - smoothstep(2.65, 3.15, ax + (mid.g - 0.5) * 0.5));
	vec3 grav = gravel_color * (0.65 + micro.a * 0.6) * (0.85 + fine.r * 0.3);
	float grass_mix = smoothstep(0.35, 0.65, mid.r + (ax - 3.1) * 0.8);
	vec3 lawn = grass_color * (0.7 + fine.r * 0.6);
	lawn = mix(lawn, vec3(0.36, 0.38, 0.16), smoothstep(0.55, 0.75, big.g) * 0.5);
	lawn = mix(lawn, vec3(0.12, 0.2, 0.06), smoothstep(0.5, 0.7, mid.a) * 0.4);
	lawn *= 0.85 + micro.r * 0.3;
	vec3 soil = mix(dirt_color * (0.7 + fine.g * 0.6), lawn, grass_mix);
	vec3 col = mix(soil, grav, gravel);
	col = mix(col, surface, road);
	float leaves = smoothstep(0.86, 0.9, nz(p + 5.0, 0.6).a) * smoothstep(1.4, 2.6, ax);
	col = mix(col, mix(vec3(0.55, 0.32, 0.08), vec3(0.65, 0.5, 0.1), fine.a), leaves * 0.9);

	// Puddles in deep potholes, with a damp darker ring.
	float wet = smoothstep(0.0, 0.4, vmask.b);
	float water = smoothstep(0.45, 0.6, vmask.b + (fine.g - 0.5) * 0.2);
	col *= 1.0 - wet * 0.35;
	col = mix(col, vec3(0.05, 0.045, 0.035), water);

	ALBEDO = col;
	float rough = mix(0.95, mix(0.95, 0.84, asph_keep), road) - speck * road * asph_keep * 0.08;
	rough = mix(rough, 0.95, crack * road);
	ROUGHNESS = mix(rough * (1.0 - wet * 0.3), 0.03, water);
	SPECULAR = mix(0.4, 0.6, water);
	float bump = mix(mix(2.0, 1.2, road * asph_keep), 2.6, road * (1.0 - asph_keep));
	vec3 n = noise_normal(p, 0.9, bump, 1);
	vec3 n2 = noise_normal(p, 4.5, bump * 1.5, 3);
	vec3 na = n * 2.0 - 1.0;
	vec3 nb = n2 * 2.0 - 1.0;
	vec3 nm = normalize(vec3(na.xy + nb.xy, na.z * nb.z));
	nm = normalize(mix(nm, vec3(0.0, 0.0, 1.0), water));
	NORMAL_MAP = nm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	AO = 1.0 - crack * road * 0.6;
}
