class_name BerryPickup
extends Node3D
## A handful of ripe raspberries hanging low on a cane that pokes through the
## fence. Player presses E nearby to pick it. Shared meshes/materials keep 40+
## pickups cheap.

static var _berry_mesh: SphereMesh
static var _berry_mat: StandardMaterial3D
static var _glint_mat: StandardMaterial3D
static var _glint_mesh: QuadMesh

var picked := false
var _glint: MeshInstance3D
var _t := randf() * 10.0


func _ready() -> void:
	add_to_group("interactable")
	if _berry_mesh == null:
		_berry_mesh = SphereMesh.new()
		_berry_mesh.radius = 0.011
		_berry_mesh.height = 0.024
		_berry_mesh.radial_segments = 10
		_berry_mesh.rings = 6
		_berry_mat = StandardMaterial3D.new()
		_berry_mat.albedo_color = Color(0.62, 0.04, 0.09)
		_berry_mat.roughness = 0.28
		_berry_mat.clearcoat_enabled = true
		_berry_mat.clearcoat = 0.6
		_berry_mat.subsurf_scatter_enabled = true
		_berry_mat.subsurf_scatter_strength = 0.4
		_glint_mesh = QuadMesh.new()
		_glint_mesh.size = Vector2(0.05, 0.05)
		_glint_mat = StandardMaterial3D.new()
		_glint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glint_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_glint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glint_mat.albedo_color = Color(1, 0.95, 0.8, 0.0)
		_glint_mat.no_depth_test = false
		var g := GradientTexture2D.new()
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(0.5, 0.0)
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		g.gradient = grad
		_glint_mat.albedo_texture = g
	# 5-8 raspberries dangling at different heights, each made of 7 drupelets.
	# One MultiMesh per pickup: a single draw call instead of ~50.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	var xforms: Array[Transform3D] = []
	for i in rng.randi_range(5, 8):
		var c := Vector3(rng.randf_range(-0.07, 0.07), rng.randf_range(0.12, 0.3), rng.randf_range(-0.05, 0.05))
		for k in 7:
			var a := k * TAU / 6.0
			var off := Vector3(cos(a) * 0.009, -absf(sin(a * 0.5)) * 0.01, sin(a) * 0.009) if k < 6 else Vector3(0, -0.012, 0)
			xforms.append(Transform3D(Basis(), c + off))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _berry_mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _berry_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 60.0
	add_child(mmi)
	_glint = MeshInstance3D.new()
	_glint.mesh = _glint_mesh
	_glint.material_override = _glint_mat.duplicate()
	_glint.position = Vector3(0, 0.26, 0)
	_glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glint)


func _process(delta: float) -> void:
	_t += delta
	if picked:
		return
	# Faint sparkle every few seconds so berries can be spotted in the grass.
	var pulse := maxf(0.0, sin(_t * 1.7)) ** 12
	(_glint.material_override as StandardMaterial3D).albedo_color.a = pulse * 0.8


func pick() -> void:
	if picked:
		return
	picked = true
	remove_from_group("interactable")
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
