// Bakes the foliage atlas once at startup (see LeafAtlas). 4x2 tiles:
// 0 broad leaves, 1 small (birch), 2 needles, 3 compound (rowan), 4 scale (thuja),
// 5 raspberry leaves, 6 flower petals, 7 one big burdock leaf (base at the bottom).
// Output: R tone variation, G fruit mask, B unused, A coverage.
shader_type canvas_item;
render_mode blend_disabled;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float leaf_sdf(vec2 lp, float len, float wid) {
	float x = lp.x / len;
	if (x < 0.0 || x > 1.0) return -1.0;
	return wid * pow(sin(x * 3.14159), 0.75) - abs(lp.y);
}

void fragment() {
	vec2 tiles = vec2(4.0, 2.0);
	vec2 tid = floor(UV * tiles);
	int tile = int(tid.x + tid.y * tiles.x);
	vec2 tuv = fract(UV * tiles);
	// Keep a padded border so mipmaps do not bleed between tiles.
	tuv = (tuv - 0.04) / 0.92;
	float inside = -1.0;
	float tone = 0.0;
	float fruit = 0.0;
	if (tile == 7 && tuv.x > 0.0 && tuv.x < 1.0 && tuv.y > 0.0 && tuv.y < 1.0) {
		// Broad cordate burdock leaf with a wavy margin and pale veins.
		vec2 q = vec2(tuv.x - 0.5, 1.0 - tuv.y);           // y: 0 base .. 1 tip
		vec2 e = vec2(q.x / 0.47, (q.y - 0.47) / 0.5);
		float ang = atan(e.y, e.x);
		float r = length(e) * (1.0 + 0.035 * sin(ang * 15.0) + 0.02 * sin(ang * 6.0 + 1.0));
		inside = 1.0 - r;
		// Notch where the petiole joins (heart-shaped base).
		if (q.y < 0.12 && abs(q.x) < (0.12 - q.y) * 0.7) inside = -1.0;
		float mid = 1.0 - smoothstep(0.004, 0.012, abs(q.x));
		float lat = 1.0 - smoothstep(0.0, 0.035, abs(fract((q.y - abs(q.x) * 0.85) * 6.0) - 0.5));
		lat *= smoothstep(0.02, 0.06, abs(q.x));
		tone = 0.35 + 0.15 * sin(q.x * 9.0 + q.y * 5.0) + max(mid, lat * 0.6) * 0.5;
	} else if (tuv.x > 0.0 && tuv.x < 1.0 && tuv.y > 0.0 && tuv.y < 1.0) {
		float n = (tile == 2) ? 6.0 : (tile == 4 ? 6.0 : (tile == 7 ? 1.0 : 3.0));
		vec2 cell = floor(tuv * n);
		vec2 f = fract(tuv * n);
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 c = cell + vec2(float(i), float(j));
				if (c.x < 0.0 || c.y < 0.0 || c.x >= n || c.y >= n) continue;
				float h = hash12(c + float(tile) * 7.0);
				float h2 = hash12(c * 1.7 + 3.0 + float(tile));
				vec2 base = vec2(float(i), float(j)) + vec2(h, h2) * 0.6 + 0.2;
				vec2 d = f - base;
				float ang = h * 6.2832;
				if (tile == 2) ang = 1.5708 + (h - 0.5) * 0.6;
				mat2 r = mat2(vec2(cos(ang), -sin(ang)), vec2(sin(ang), cos(ang)));
				vec2 lp = r * d;
				float s = -1.0;
				if (tile == 0) s = leaf_sdf(lp + vec2(0.45, 0.0), 0.95, 0.3);
				else if (tile == 1) s = leaf_sdf(lp + vec2(0.3, 0.0), 0.62, 0.26);
				else if (tile == 2) s = leaf_sdf(lp + vec2(0.55, 0.0), 1.1, 0.075);
				else if (tile == 3) {
					// Pinnate leaf: row of leaflets.
					for (int k = 0; k < 5; k++) {
						vec2 q = lp + vec2(0.4 - float(k) * 0.18, 0.0);
						float side = (k % 2 == 0) ? 1.0 : -1.0;
						s = max(s, leaf_sdf(mat2(vec2(0.8, 0.6 * side), vec2(-0.6 * side, 0.8)) * q, 0.3, 0.08));
					}
					s = max(s, 0.012 - abs(lp.y) - step(0.45, abs(lp.x)) );
				}
				else if (tile == 4) s = 0.42 - length(d * vec2(1.0, 0.7)) - 0.1 * sin(atan(d.y, d.x) * 7.0 + h * 6.0);
				else if (tile == 5) {
					// Trifoliate raspberry leaf with serrated edge.
					for (int k = 0; k < 3; k++) {
						float a2 = float(k - 1) * 0.9;
						vec2 q = mat2(vec2(cos(a2), -sin(a2)), vec2(sin(a2), cos(a2))) * lp;
						s = max(s, leaf_sdf(q + vec2(0.05, 0.0), 0.5, 0.2) - 0.012 * abs(sin(q.x * 90.0)));
					}
					if (h2 < 0.35 && length(d - vec2(0.18, -0.12)) < 0.12) { s = 1.0; fruit = 1.0; }
				}
				else if (tile == 6) {
					float a3 = atan(d.y, d.x);
					s = (0.32 + 0.12 * cos(a3 * 5.0)) - length(d);
				}
				if (s > inside) {
					inside = s;
					tone = h;
				}
			}
		}
	}
	float a = smoothstep(-0.01, 0.015, inside);
	COLOR = vec4(tone, fruit, 0.0, a);
}
