// Big cartoon eye: wet glossy ball, deep iris with limbal ring and radial
// fibres, pupil, two catchlights. `look` turns the iris inside the ball.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 iris_color : source_color = vec3(0.12, 0.35, 0.85);
uniform vec3 iris_dark : source_color = vec3(0.03, 0.08, 0.25);
uniform vec3 forward = vec3(0.0, 0.0, 1.0);   // local axis the eye looks along
uniform vec2 look = vec2(0.0);                  // x: right, y: up (radians-ish)
uniform float iris_size = 0.62;                 // half-angle in radians
uniform float pupil_size = 0.3;
uniform float blink = 0.0;                      // 0 open .. 1 closed
uniform vec3 lid_color : source_color = vec3(0.16, 0.36, 0.93);

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	vec3 d = normalize(lpos);
	vec3 fwd = normalize(forward + vec3(look.x, look.y, 0.0));
	float ang = acos(clamp(dot(d, fwd), -1.0, 1.0));
	// Angle around the look axis for fibres.
	vec3 side = normalize(cross(fwd, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(side, fwd);
	float around = atan(dot(d, up), dot(d, side));

	vec3 sclera = mix(vec3(0.98, 0.98, 0.99), vec3(0.85, 0.87, 0.92), smoothstep(1.2, 1.8, ang));
	float iris_m = 1.0 - smoothstep(iris_size - 0.02, iris_size + 0.02, ang);
	float t = ang / iris_size;
	vec3 iris = mix(iris_color * 1.25, iris_dark, smoothstep(0.55, 1.0, t));
	iris *= 0.85 + 0.25 * sin(around * 38.0 + t * 6.0) * smoothstep(0.35, 0.8, t);
	iris += iris_color * 0.35 * (1.0 - smoothstep(0.35, 0.75, t)) * smoothstep(-0.2, 0.6, dot(d, up));
	float pupil = 1.0 - smoothstep(pupil_size - 0.02, pupil_size + 0.02, ang);
	vec3 col = mix(sclera, iris, iris_m);
	col = mix(col, vec3(0.005, 0.006, 0.012), pupil);

	// Catchlights painted in (stay readable in shade too).
	vec3 hl_dir = normalize(fwd + up * 0.38 - side * 0.32);
	float hl = smoothstep(0.985, 0.992, dot(d, hl_dir));
	vec3 hl2_dir = normalize(fwd - up * 0.3 + side * 0.28);
	float hl2 = smoothstep(0.996, 0.998, dot(d, hl2_dir));

	// Eyelid: covers the eye from the top when blinking.
	float lid = step(1.0 - blink * 1.02, dot(d, up) * 0.5 + 0.5) * step(0.01, blink);

	ALBEDO = mix(col, lid_color, lid);
	// A little self-light keeps the whites clean when the face is in shade.
	EMISSION = (vec3(1.0) * (hl * 1.6 + hl2 * 0.9) + col * 0.12) * (1.0 - lid);
	ROUGHNESS = mix(0.04, 0.8, lid);
	SPECULAR = mix(0.9, 0.3, lid);
	CLEARCOAT = 1.0 - lid;
	CLEARCOAT_ROUGHNESS = 0.05;
}
