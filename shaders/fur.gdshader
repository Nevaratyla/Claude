// Shell fur. The base pass (shell = 0) is the solid skin; extra passes chained
// through next_pass push the surface out along the normal and keep only
// strand cross-sections, which reads as soft fur. Colour from vertex COLOR.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float shell = 0.0;          // 0 skin .. 1 outermost layer
uniform float fur_length = 0.009;   // metres
uniform float density = 1100.0;     // strands per metre (cell frequency)
uniform float thickness = 0.62;
uniform float gravity = 0.4;
uniform vec3 tint : source_color = vec3(1.0);
uniform float wobble = 0.0;         // driven by motion, ruffles the tips

varying vec3 lpos;
varying vec3 lnrm;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
	// COLOR.a masks fur length (0 around the eyes and mouth).
	float s = shell * COLOR.a;
	VERTEX += NORMAL * fur_length * s;
	// Tips droop a little and ruffle when the creature moves.
	VERTEX.y -= fur_length * gravity * s * s;
	VERTEX += vec3(sin(TIME * 9.0 + lpos.y * 200.0), 0.0, cos(TIME * 8.0 + lpos.x * 210.0)) * wobble * fur_length * s * s * 0.5;
}

void fragment() {
	vec3 base = COLOR.rgb * tint;
	if (shell > 0.0) {
		if (shell > COLOR.a + 0.001) discard;
		vec3 p = lpos * density;
		vec3 c = floor(p);
		vec3 jitter = vec3(hash13(c + 1.7), hash13(c + 5.3), hash13(c + 9.1)) - 0.5;
		vec3 f = fract(p) - 0.5 - jitter * 0.4;
		float len = 0.45 + 0.55 * hash13(c);              // strand length 45..100%
		if (shell > len) discard;
		float r = thickness * 0.5 * (1.0 - shell / len);  // taper to the tip
		// Distance to the strand axis, measured across the surface.
		vec3 n = normalize(lnrm);
		vec3 q = f - n * dot(f, n);
		// Far away the strands are sub-pixel: fall back to solid shells so the
		// silhouette stays fuzzy without shimmering.
		float px = length(fwidth(p));
		if (px < 0.9 && length(q) > r) discard;
		if (px >= 0.9 && shell > 0.55) discard;
	}
	// Roots darker, tips lighter; soft sheen on the rim.
	float t = shell;
	vec3 col = base * mix(0.62, 1.08, t);
	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	RIM = 0.55;
	RIM_TINT = 0.6;
	BACKLIGHT = base * 0.25 * t;
	AO = mix(0.7, 1.0, t);
	AO_LIGHT_AFFECT = 0.5;
}
