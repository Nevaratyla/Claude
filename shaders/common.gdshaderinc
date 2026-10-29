// Shared helpers. Every world shader samples one 512px seamless noise texture
// (g_noise, built in Game autoload) instead of computing fbm per pixel.
global uniform sampler2D g_noise : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform vec4 g_wind;      // xy: direction, z: strength, w: gust speed
global uniform float g_daylight; // 1 = noon, 0 = night

// Noise lookups by world-space metres.
vec4 nz(vec2 p_m, float scale) {
	return texture(g_noise, p_m * scale);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Height-to-normal via finite differences on the noise texture.
vec3 noise_normal(vec2 p_m, float scale, float strength, int ch) {
	float e = 1.0 / 512.0;
	vec2 uv = p_m * scale;
	float h = texture(g_noise, uv)[ch];
	float hx = texture(g_noise, uv + vec2(e, 0.0))[ch];
	float hy = texture(g_noise, uv + vec2(0.0, e))[ch];
	vec3 n = normalize(vec3((h - hx) * strength, (h - hy) * strength, 1.0));
	return n * 0.5 + 0.5;
}

// Wind sway offset for vegetation. h01: 0 at the root, 1 at the tip.
vec3 wind_offset(vec3 world_pos, float h01, float flex, float t) {
	vec2 dir = normalize(g_wind.xy + vec2(0.0001));
	float gust = texture(g_noise, world_pos.xz * 0.004 + dir * t * 0.02 * g_wind.w).r;
	float wave = sin(t * 1.7 + dot(world_pos.xz, vec2(0.37, 0.21))) * 0.5
		+ sin(t * 3.1 + world_pos.x * 0.9) * 0.25;
	float amp = g_wind.z * flex * h01 * h01;
	vec3 o;
	o.xz = dir * amp * (gust * 1.3 + wave * 0.4);
	o.y = -length(o.xz) * 0.25;
	return o;
}
