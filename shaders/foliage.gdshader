// Leaf cards for trees and bushes, instanced via MultiMesh. Leaf shapes come
// from the atlas baked once at startup (LeafAtlas), so a pixel costs one
// texture fetch and distant crowns stay stable thanks to mipmaps.
// COLOR.rgb: leaf tint, COLOR.a: 0..1 height in the crown (wind flex, AO).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/common.gdshaderinc"

global uniform sampler2D g_leaf_atlas : filter_linear_mipmap_anisotropic, repeat_disable;

uniform int tile = 0;
uniform vec3 autumn_color : source_color = vec3(0.85, 0.45, 0.08);
uniform float autumn = 0.15;
uniform vec3 fruit_color : source_color = vec3(0.75, 0.08, 0.05);
uniform float flex = 0.25;
uniform float translucency = 0.6;
uniform float alpha_cut = 0.45;
uniform bool random_flip = true;    // off for single-leaf tiles that have a base

varying float v_seed;
varying flat int v_flip;

void vertex() {
	vec3 wroot = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_seed = hash12(wroot.xz * 0.37 + VERTEX.xz * 3.1 + VERTEX.y);
	v_flip = int(v_seed * 4.0);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 off = wind_offset(wroot, COLOR.a, flex, TIME);
	off += (texture(g_noise, wp.xz * 0.35 + TIME * 0.5).g - 0.5) * 0.05 * g_wind.z * COLOR.a;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
}

void fragment() {
	vec2 uv = UV;
	// Flip/rotate per card so repeated cards do not look identical.
	if (random_flip) {
		if ((v_flip & 1) == 1) uv.x = 1.0 - uv.x;
		if ((v_flip & 2) == 2) uv = uv.yx;
	}
	vec2 cell = vec2(float(tile % 4), float(tile / 4));
	vec2 auv = (cell + 0.04 + uv * 0.92) / vec2(4.0, 2.0);
	vec4 t = texture(g_leaf_atlas, auv);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	float tone = t.r;
	vec3 col = COLOR.rgb * (0.72 + tone * 0.5);
	float turn = hash12(floor(uv * 3.0) + v_seed * 31.0);
	col = mix(col, autumn_color * (0.8 + tone * 0.4), step(1.0 - autumn, turn));
	col = mix(col, fruit_color, t.g);
	ALBEDO = col;
	// Keep the crown-bent normal on both sides of the card.
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	ROUGHNESS = mix(0.6, 0.25, t.g);
	SPECULAR = 0.35;
	BACKLIGHT = col * translucency;
	AO = mix(0.5, 1.0, COLOR.a);
	AO_LIGHT_AFFECT = 0.35;
}
