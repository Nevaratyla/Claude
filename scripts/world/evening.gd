class_name Evening
extends Node3D
## Things that only matter as the sun goes down: street lamps that switch on
## by themselves, and fireflies drifting around the heroes. Windows light up on
## their own in the window shader (it reads g_daylight; scripts use Game.daylight).

var street: Street
var follow: Node3D                       # fireflies stay around this node
var _lamps: Array[SpotLight3D] = []
var _bulb_mat: StandardMaterial3D
var _flies: GPUParticles3D
var _check_t := 0.0


func build(s: Street, hero: Node3D) -> void:
	street = s
	follow = hero
	_bulb_mat = StandardMaterial3D.new()
	_bulb_mat.albedo_color = Color(1.0, 0.9, 0.7)
	_bulb_mat.emission_enabled = true
	_bulb_mat.emission = Color(1.0, 0.78, 0.45)
	_bulb_mat.emission_energy_multiplier = 0.0
	var bulb_mesh := QuadMesh.new()
	bulb_mesh.size = Vector2(0.36, 0.14)
	for head: Vector3 in street.lamp_heads:
		var bulb := MeshInstance3D.new()
		bulb.mesh = bulb_mesh
		bulb.material_override = _bulb_mat
		bulb.position = head + Vector3(0, -0.005, 0)
		bulb.rotation.x = -PI * 0.5      # faces down
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bulb)
		var l := SpotLight3D.new()
		l.position = head
		l.rotation.x = -PI * 0.5
		l.spot_range = 13.0
		l.spot_angle = 58.0
		l.spot_attenuation = 1.2
		l.light_color = Color(1.0, 0.8, 0.55)
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lamps.append(l)
	_make_fireflies()


func _make_fireflies() -> void:
	_flies = GPUParticles3D.new()
	_flies.amount = 36
	_flies.lifetime = 6.0
	_flies.preprocess = 6.0
	_flies.local_coords = false
	_flies.visibility_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 6, 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(7.0, 0.6, 7.0)
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.2
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.15, 1.0))
	curve.add_point(Vector2(0.5, 0.3))
	curve.add_point(Vector2(0.7, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	_flies.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.85, 1.0, 0.35)
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	g.gradient = grad
	m.albedo_texture = g
	quad.material = m
	_flies.draw_pass_1 = quad
	_flies.emitting = false
	_flies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flies)


func _process(delta: float) -> void:
	var day := Game.daylight
	var dark := clampf((0.62 - day) / 0.4, 0.0, 1.0)
	_bulb_mat.emission_energy_multiplier = dark * 5.0
	if follow:
		_flies.global_position = follow.global_position + Vector3(0, 0.6, 0)
	_flies.emitting = dark > 0.15
	# Only lamps near the heroes are real lights (a handful at a time).
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = 0.4
	var p := follow.global_position if follow else Vector3.ZERO
	for l in _lamps:
		var near := l.global_position.distance_to(p) < 90.0
		l.visible = dark > 0.02 and near
		l.light_energy = dark * 2.2
