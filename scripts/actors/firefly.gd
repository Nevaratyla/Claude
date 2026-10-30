class_name Firefly
extends Node3D
## A firefly the player can catch (E) for the jar. It drifts around its spot,
## glows and blinks; it hovers low so a 40 cm hero can reach it.

signal caught

var reach := 1.1
var _home := Vector3.ZERO
var _t := randf() * 10.0
var _glow: MeshInstance3D
var _light: OmniLight3D
var _mat: StandardMaterial3D
var _done := false


func _ready() -> void:
	add_to_group("interactable")
	# Moved every rendered frame, not on physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_home = global_position
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.albedo_color = Color(0.85, 1.0, 0.35)
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	g.gradient = grad
	_mat.albedo_texture = g
	_glow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	_glow.mesh = q
	_glow.material_override = _mat
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)
	_light = OmniLight3D.new()
	_light.omni_range = 0.9
	_light.light_color = Color(0.8, 1.0, 0.4)
	_light.light_energy = 0.6
	_light.shadow_enabled = false
	add_child(_light)


func prompt_text() -> String:
	return "Поймать светлячка"


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	# Lazy figure-eight drift around the home spot, low over the grass.
	global_position = _home + Vector3(sin(_t * 0.7) * 0.45, 0.42 + sin(_t * 1.3) * 0.12, sin(_t * 1.1) * 0.35)
	var blink := 0.35 + 0.65 * pow(maxf(0.0, sin(_t * 2.3)), 2.0)
	_mat.albedo_color.a = blink
	_light.light_energy = 0.15 + blink * 0.5


## Flies into the jar.
func catch_into(jar: Node3D) -> void:
	if _done:
		return
	_done = true
	remove_from_group("interactable")
	var tw := create_tween()
	tw.tween_property(self, "global_position", jar.global_position, 0.45).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(self, "scale", Vector3.ONE * 0.3, 0.45)
	tw.tween_callback(func() -> void:
		caught.emit()
		queue_free())
