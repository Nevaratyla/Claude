// Physical-ish sky with sun glow and two cloud layers (cumulus + cirrus).
// Static clouds (no TIME) so the radiance cubemap only re-renders when the
// time of day changes; Sky uses incremental processing for that.
shader_type sky;

global uniform sampler2D g_noise : filter_linear_mipmap, repeat_enable;

uniform vec3 zenith : source_color = vec3(0.18, 0.38, 0.78);
uniform vec3 horizon : source_color = vec3(0.68, 0.79, 0.92);
uniform vec3 ground : source_color = vec3(0.32, 0.3, 0.27);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_energy = 14.0;
uniform float cloud_cover = 0.45;
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shade : source_color = vec3(0.62, 0.68, 0.78);
uniform float exposure = 1.0;

float fbm2(vec2 p) {
	float v = texture(g_noise, p).r * 0.55;
	v += texture(g_noise, p * 2.7 + 0.3).g * 0.3;
	v += texture(g_noise, p * 7.3 + 0.7).g * 0.15;
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 s = normalize(LIGHT0_DIRECTION);
	float y = d.y;
	float mu = max(dot(d, s), 0.0);

	vec3 col = mix(horizon, zenith, pow(clamp(y, 0.0, 1.0), 0.45));
	// Horizon haze warms toward the sun.
	col += sun_tint * pow(mu, 6.0) * 0.35 * (1.0 - clamp(y * 2.0, 0.0, 1.0));
	col += sun_tint * pow(mu, 64.0) * 0.6;

	if (y > 0.0) {
		vec2 cp = d.xz / (y + 0.08);
		// Cumulus.
		float c = fbm2(cp * 0.045 + vec2(0.13, 0.71));
		float cov = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.28, c);
		float thick = fbm2(cp * 0.045 + s.xz * 0.012 + vec2(0.13, 0.71));
		float lit = clamp(0.55 + (c - thick) * 6.0, 0.0, 1.0);
		vec3 ccol = mix(cloud_shade, cloud_lit, lit) + sun_tint * pow(mu, 12.0) * 0.6;
		// Cirrus streaks.
		float ci = texture(g_noise, vec2(cp.x * 0.02, cp.y * 0.12) + 0.4).g;
		float cirrus = smoothstep(0.55, 0.85, ci) * 0.45 * (1.0 - cov);
		float fade = smoothstep(0.0, 0.18, y);
		col = mix(col, ccol, cov * fade);
		col = mix(col, cloud_lit, cirrus * fade);
	} else {
		col = mix(horizon * 0.8, ground, clamp(-y * 6.0, 0.0, 1.0));
	}

	// Sun disk (not in reflections at half-res to avoid sparkles).
	if (!AT_CUBEMAP_PASS) {
		float disk = smoothstep(0.99985, 0.99993, mu);
		col += sun_tint * disk * sun_energy;
	}
	COLOR = col * exposure;
}
