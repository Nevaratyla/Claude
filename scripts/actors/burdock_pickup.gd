class_name BurdockPickup
extends Node3D
## A young burdock growing on the verge. Player presses E nearby to pick a
## leaf for granny. Meshes are shared between all pickups (a few variants), and
## a soft glint pulses above so they are easy to spot from a distance.

static var _meshes: Array[ArrayMesh] = []
static var _glint_mat: StandardMaterial3D
static var _glint_mesh: QuadMesh

var picked := false
var _glint: MeshInstance3D
var _plant: MeshInstance3D
var _t := randf() * 10.0


func _ready() -> void:
	add_to_group("interactable")
	if _meshes.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 5150
		for i in 4:
			# Fresher, lighter green than the decorative burdocks so they stand out.
			_meshes.append(Burdock.make_mesh(rng, rng.randi_range(7, 9), rng.randf_range(0.5, 0.6), Color(0.27, 0.46, 0.11)))
		_glint_mesh = QuadMesh.new()
		_glint_mesh.size = Vector2(0.14, 0.14)
		_glint_mat = StandardMaterial3D.new()
		_glint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glint_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_glint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glint_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_glint_mat.albedo_color = Color(1, 0.95, 0.75, 0.0)
		var g := GradientTexture2D.new()
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(0.5, 0.0)
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		g.gradient = grad
		_glint_mat.albedo_texture = g
	_plant = MeshInstance3D.new()
	_plant.mesh = _meshes[absi(hash(global_position)) % _meshes.size()]
	_plant.rotation.y = randf() * TAU
	_plant.visibility_range_end = 70.0
	add_child(_plant)
	_glint = MeshInstance3D.new()
	_glint.mesh = _glint_mesh
	_glint.material_override = _glint_mat.duplicate()
	_glint.position = Vector3(0, 0.65, 0)
	_glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glint)


func _process(delta: float) -> void:
	_t += delta
	if picked:
		return
	# Faint sparkle every couple of seconds so the leaves can be spotted.
	var pulse := maxf(0.0, sin(_t * 2.2)) ** 6
	(_glint.material_override as StandardMaterial3D).albedo_color.a = 0.25 + pulse * 0.75


func pick() -> void:
	if picked:
		return
	picked = true
	remove_from_group("interactable")
	_glint.visible = false
	# The plant shakes and shrinks: the big leaf has been torn off.
	var tw := create_tween()
	tw.tween_property(_plant, "rotation:z", 0.25, 0.08)
	tw.tween_property(_plant, "rotation:z", -0.2, 0.1)
	tw.tween_property(_plant, "rotation:z", 0.0, 0.08)
	tw.tween_property(_plant, "scale", Vector3(0.55, 0.45, 0.55), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
