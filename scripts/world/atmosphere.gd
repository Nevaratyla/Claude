class_name Atmosphere
extends Node3D
## Sun, sky, fog and post effects. `time_of_day`: 0 = afternoon, 1 = evening, 2 = dusk.

const SKY_SHADER := preload("res://shaders/sky.gdshader")

# Keyframes: sun elevation, azimuth (deg), sun color, sun energy, zenith, horizon,
# ambient energy, fog color, exposure.
const KEYS := [
	{"el": 38.0, "az": 150.0, "sun": Color(1.0, 0.95, 0.86), "e": 2.6,
		"zen": Color(0.16, 0.36, 0.78), "hor": Color(0.66, 0.78, 0.92),
		"amb": 1.0, "fog": Color(0.7, 0.78, 0.88), "exp": 1.0, "day": 1.0},
	{"el": 9.0, "az": 115.0, "sun": Color(1.0, 0.66, 0.36), "e": 2.0,
		"zen": Color(0.17, 0.27, 0.55), "hor": Color(0.95, 0.66, 0.45),
		"amb": 0.75, "fog": Color(0.85, 0.62, 0.5), "exp": 1.15, "day": 0.6},
	{"el": -4.0, "az": 100.0, "sun": Color(0.9, 0.42, 0.3), "e": 0.0,
		"zen": Color(0.05, 0.08, 0.2), "hor": Color(0.36, 0.26, 0.35),
		"amb": 0.35, "fog": Color(0.2, 0.2, 0.3), "exp": 1.6, "day": 0.1},
]

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var time_of_day := 0.0: set = set_time_of_day


func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.15
	sun.directional_shadow_split_3 = 0.4
	sun.directional_shadow_blend_splits = true
	sun.light_angular_distance = 0.5
	add_child(sun)

	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.2
	env.ssao_detail = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 60.0
	env.fog_depth_end = 900.0
	env.fog_depth_curve = 1.6
	env.fog_aerial_perspective = 0.7
	env.fog_sky_affect = 0.0
	env.fog_sun_scatter = 0.25
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_length = 80.0
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_ambient_inject = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	var cam_attr := CameraAttributesPractical.new()
	cam_attr.dof_blur_far_enabled = false
	we.camera_attributes = cam_attr
	add_child(we)

	Game.quality_changed.connect(_apply_quality)
	_apply_quality(Game.quality)
	set_time_of_day(time_of_day)


func _apply_quality(q: int) -> void:
	# SDFGI and volumetric fog are expensive and misbehave on integrated
	# graphics (washed-out, too bright surfaces), so only ULTRA uses them.
	env.sdfgi_enabled = q == Game.Quality.ULTRA
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.1
	env.sdfgi_energy = 0.9
	env.ssil_enabled = q == Game.Quality.ULTRA
	env.ssr_enabled = q == Game.Quality.ULTRA
	env.ssr_max_steps = 48
	env.volumetric_fog_enabled = q == Game.Quality.ULTRA
	env.ssao_enabled = q >= Game.Quality.MEDIUM
	env.glow_enabled = q >= Game.Quality.MEDIUM
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q == Game.Quality.LOW \
		else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = [35.0, 70.0, 120.0, 180.0][q]
	sun.shadow_blur = 1.0 if q == Game.Quality.LOW else 1.2
	# Sun-size soft shadows (PCSS) look noisy at low sample counts and cost a lot.
	sun.light_angular_distance = 0.0 if q <= Game.Quality.MEDIUM else 0.5
	RenderingServer.environment_set_ssao_quality(
		[RenderingServer.ENV_SSAO_QUALITY_VERY_LOW, RenderingServer.ENV_SSAO_QUALITY_LOW,
		RenderingServer.ENV_SSAO_QUALITY_MEDIUM, RenderingServer.ENV_SSAO_QUALITY_HIGH][q], true, 0.5, 2, 50.0, 300.0)
	(env.sky as Sky).radiance_size = Sky.RADIANCE_SIZE_64 if q == Game.Quality.LOW else Sky.RADIANCE_SIZE_256


func set_time_of_day(t: float) -> void:
	time_of_day = clampf(t, 0.0, float(KEYS.size() - 1))
	if sun == null:
		return
	var i := mini(floori(time_of_day), KEYS.size() - 2)
	var f := time_of_day - i
	var a: Dictionary = KEYS[i]
	var b: Dictionary = KEYS[i + 1]
	var el := lerpf(a.el, b.el, f)
	var az := lerpf(a.az, b.az, f)
	sun.rotation_degrees = Vector3(-el, az, 0.0)
	var sun_col: Color = a.sun.lerp(b.sun, f)
	sun.light_color = sun_col
	sun.light_energy = lerpf(a.e, b.e, f) * clampf(el / 4.0 + 0.2, 0.0, 1.0)
	sun.visible = el > -2.0
	sky_mat.set_shader_parameter("zenith", a.zen.lerp(b.zen, f))
	sky_mat.set_shader_parameter("horizon", a.hor.lerp(b.hor, f))
	sky_mat.set_shader_parameter("sun_tint", sun_col)
	sky_mat.set_shader_parameter("cloud_lit", Color(1, 1, 1).lerp(sun_col, clampf(1.0 - el / 30.0, 0.0, 1.0)))
	sky_mat.set_shader_parameter("cloud_shade", a.hor.lerp(b.hor, f).darkened(0.25))
	env.ambient_light_energy = lerpf(a.amb, b.amb, f)
	env.ambient_light_sky_contribution = 0.85
	var fog_col: Color = a.fog.lerp(b.fog, f)
	env.fog_light_color = fog_col
	env.volumetric_fog_albedo = fog_col
	env.tonemap_exposure = lerpf(a.exp, b.exp, f)
	RenderingServer.global_shader_parameter_set("g_daylight", lerpf(a.day, b.day, f))
