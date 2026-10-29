class_name Creature
extends Node3D
## Visual + procedural animation of a fluffy hero. The model (from
## tools/make_characters.py) has one node per body part with its pivot at the
## joint, so walking, ear flop, tail wag, blinking and squash are all done here.

const FUR := preload("res://shaders/fur.gdshader")
const EYE := preload("res://shaders/eye.gdshader")

@export var iris_color := Color(0.12, 0.35, 0.85)
@export var lid_color := Color(0.16, 0.36, 0.93)

# Inputs set by the controller every frame.
var velocity := Vector3.ZERO        # world space
var grounded := true
var crouch := 0.0                   # 0..1
var look_target := Vector3.ZERO     # world point, or ZERO to look ahead
var happy := 0.0                    # tail wag, ear perk

var _parts := {}
var _rest := {}
var _phase := 0.0
var _time := 0.0
var _blink_t := 2.0
var _blink := 0.0
var _land := 0.0
var _was_grounded := true
var _ear_ang := {"Ear_L": Vector2.ZERO, "Ear_R": Vector2.ZERO}
var _ear_vel := {"Ear_L": Vector2.ZERO, "Ear_R": Vector2.ZERO}
var _head_look := Vector2.ZERO
var _prev_vel := Vector3.ZERO
var _eye_mat: ShaderMaterial
var _fur_mats: Array[ShaderMaterial] = []
var _shell_nodes: Array[MeshInstance3D] = []
var _model: Node3D


func setup(scene: PackedScene) -> void:
	_model = scene.instantiate()
	# The model faces +Z; Godot's forward is -Z.
	_model.rotation.y = PI
	add_child(_model)
	_collect(_model)
	_apply_materials()
	Game.quality_changed.connect(func(_q: int) -> void: _apply_materials())


func _collect(n: Node) -> void:
	for c in n.get_children():
		if c is Node3D:
			var key := String(c.name).split(".")[0].split("_0")[0]
			for want in ["Body", "Head", "Leg_L", "Leg_R", "Arm_L", "Arm_R", "Tail", "Ear_L", "Ear_R",
					"Eye_L", "Eye_R", "Mouth", "Lashes", "Flower"]:
				if key == want and not _parts.has(want):
					_parts[want] = c
					_rest[want] = c.transform
		_collect(c)


## Returns [skin, shells]: the skin material and the first of the chained
## shell passes. Shells go on a separate shadowless copy of the mesh, so the
## hero casts one solid shadow instead of a speckled one from every layer.
func _fur_chain(length: float, density: float) -> Array[ShaderMaterial]:
	var shells: int = [2, 4, 9, 14][Game.quality]
	var mats: Array[ShaderMaterial] = []
	for i in shells + 1:
		var m := ShaderMaterial.new()
		m.shader = FUR
		m.set_shader_parameter("shell", float(i) / shells)
		m.set_shader_parameter("fur_length", length)
		m.set_shader_parameter("density", density)
		m.render_priority = i
		_fur_mats.append(m)
		if i > 1:
			mats[i - 1].next_pass = m
		mats.append(m)
	return [mats[0], mats[1]]


func _apply_materials() -> void:
	_fur_mats.clear()
	for n in _shell_nodes:
		n.queue_free()
	_shell_nodes.clear()
	var body_fur := _fur_chain(0.015, 780.0)
	var ear_fur := _fur_chain(0.007, 1100.0)
	_eye_mat = ShaderMaterial.new()
	_eye_mat.shader = EYE
	_eye_mat.set_shader_parameter("iris_color", iris_color)
	_eye_mat.set_shader_parameter("iris_dark", iris_color.darkened(0.75))
	_eye_mat.set_shader_parameter("lid_color", lid_color)
	_eye_mat.set_shader_parameter("iris_size", 0.8)
	_eye_mat.set_shader_parameter("pupil_size", 0.4)
	var dark := StandardMaterial3D.new()
	dark.vertex_color_use_as_albedo = true
	dark.roughness = 0.4
	var flower := StandardMaterial3D.new()
	flower.vertex_color_use_as_albedo = true
	flower.roughness = 0.5
	flower.rim_enabled = true
	for key: String in _parts:
		var mi := _parts[key] as MeshInstance3D
		if mi == null:
			continue
		match key:
			"Eye_L", "Eye_R":
				mi.material_override = _eye_mat
			"Mouth", "Lashes":
				mi.material_override = dark
			"Flower":
				mi.material_override = flower
			"Ear_L", "Ear_R":
				_dress_fur(mi, ear_fur)
			_:
				_dress_fur(mi, body_fur)


func _dress_fur(mi: MeshInstance3D, fur: Array[ShaderMaterial]) -> void:
	mi.material_override = fur[0]
	var shell := MeshInstance3D.new()
	shell.mesh = mi.mesh
	shell.material_override = fur[1]
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(shell)
	_shell_nodes.append(shell)


## Runs on the physics tick so physics interpolation smooths the parts
## together with the body on high-refresh screens.
func _physics_process(delta: float) -> void:
	if _model == null:
		return
	_time += delta
	var flat := Vector3(velocity.x, 0, velocity.z)
	var speed := flat.length()
	var move := clampf(speed / 2.1, 0.0, 1.0)
	var run := clampf((speed - 2.1) / 2.5, 0.0, 1.0)
	var local_vel := global_basis.inverse() * flat
	var accel := (velocity - _prev_vel) / maxf(delta, 0.001)
	_prev_vel = velocity

	# Landing squash.
	if grounded and not _was_grounded:
		_land = clampf(-_prev_vel.y * 0.25, 0.3, 1.0)
	_was_grounded = grounded
	_land = move_toward(_land, 0.0, delta * 4.0)

	_phase += delta * (7.0 + run * 5.5) * move
	var s := sin(_phase)
	var c := cos(_phase)
	var air := 0.0 if grounded else 1.0

	# Body: bob, sway, lean into motion, breathing, squash/stretch.
	var breathe := sin(_time * 2.1) * 0.012 * (1.0 - move)
	var bob := absf(s) * (0.012 + run * 0.012) * move
	var squash := -_land * 0.22 + air * 0.08 + bob * 2.0 - crouch * 0.18
	var body: Node3D = _parts.get("Body")
	if body:
		var t: Transform3D = _rest["Body"]
		# Model space faces +Z, so a positive X rotation tips the top forward.
		var lean := Basis(Vector3.RIGHT, -local_vel.z * 0.09 + run * 0.05) \
			* Basis(Vector3.FORWARD, s * 0.07 * move)
		var sc := Vector3(1.0 - squash * 0.5 + breathe, 1.0 + squash + breathe * 0.5, 1.0 - squash * 0.5 + breathe)
		body.transform = Transform3D(lean * t.basis.scaled(sc), t.origin + Vector3(0, bob - crouch * 0.04 - _land * 0.02, 0))

	# Legs swing opposite each other; in the air they tuck.
	for leg in ["Leg_L", "Leg_R"]:
		var n: Node3D = _parts.get(leg)
		if n:
			var sign := 1.0 if leg == "Leg_L" else -1.0
			var swing := s * sign * (0.55 + run * 0.35) * move
			var tuck := air * 0.5 + crouch * 0.6
			n.transform = Transform3D(Basis(Vector3.RIGHT, swing - tuck) * _rest[leg].basis,
				_rest[leg].origin + Vector3(0, maxf(0.0, s * sign) * 0.012 * move, 0))
	# Arms: held at the chest, swing a little when walking, raise when running/jumping.
	for arm in ["Arm_L", "Arm_R"]:
		var n: Node3D = _parts.get(arm)
		if n:
			var sign := 1.0 if arm == "Arm_L" else -1.0
			var swing := -s * sign * 0.35 * move
			var raise := run * 0.5 + air * 0.8
			n.transform = Transform3D(Basis(Vector3.RIGHT, swing - raise * 0.6) * Basis(Vector3.FORWARD, sign * raise * 0.4) * _rest[arm].basis, _rest[arm].origin)

	# Head: counter-bob, smooth look toward a target, idle glances.
	var head: Node3D = _parts.get("Head")
	if head:
		var want := Vector2(sin(_time * 0.5) * 0.25 + sin(_time * 1.3) * 0.08, sin(_time * 0.7) * 0.06) * (1.0 - move)
		if look_target != Vector3.ZERO:
			var to := global_basis.inverse() * (look_target - head.global_position)
			# Model faces -Z in this node's space.
			want = Vector2(clampf(atan2(-to.x, -to.z), -0.9, 0.9), clampf(atan2(to.y, Vector2(to.x, to.z).length()), -0.45, 0.5))
		_head_look = _head_look.lerp(want, 1.0 - exp(-delta * 5.0))
		var tilt := sin(_time * 0.9) * 0.05 * (1.0 - move) + happy * 0.12 * sin(_time * 2.0)
		head.transform = Transform3D(Basis(Vector3.UP, _head_look.x) * Basis(Vector3.RIGHT, -_head_look.y + bob * 3.0)
			* Basis(Vector3.FORWARD, tilt) * _rest["Head"].basis, _rest["Head"].origin + Vector3(0, -bob * 0.4, 0))

	# Ears: damped springs driven by bobbing, acceleration and landing.
	for ear in ["Ear_L", "Ear_R"]:
		var n: Node3D = _parts.get(ear)
		if n == null:
			continue
		var sign := 1.0 if ear == "Ear_L" else -1.0
		var local_acc := global_basis.inverse() * accel
		var target := Vector2(clampf(local_acc.z * 0.02, -0.5, 0.5) + c * 0.25 * move,
			sign * (0.08 + happy * 0.15 + air * 0.5 - _land * 0.4) + s * 0.15 * move * sign)
		var a: Vector2 = _ear_ang[ear]
		var v: Vector2 = _ear_vel[ear]
		v += (target - a) * 90.0 * delta
		v *= exp(-delta * 7.0)
		a += v * delta
		_ear_ang[ear] = a
		_ear_vel[ear] = v
		n.transform = Transform3D(Basis(Vector3.RIGHT, a.x) * Basis(Vector3.FORWARD, a.y) * _rest[ear].basis, _rest[ear].origin)

	# Tail wag.
	var tail: Node3D = _parts.get("Tail")
	if tail:
		var wag := sin(_time * (6.0 + happy * 8.0)) * (0.25 + happy * 0.5) + s * 0.3 * move
		tail.transform = Transform3D(Basis(Vector3.UP, wag) * _rest["Tail"].basis, _rest["Tail"].origin)

	# Blinking.
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink_t = randf_range(1.8, 5.0)
		_blink = 1.0
	_blink = move_toward(_blink, 0.0, delta * 7.0)
	var lid := clampf(1.0 - absf(_blink * 2.0 - 1.0), 0.0, 1.0) if _blink > 0.0 else 0.0
	_eye_mat.set_shader_parameter("blink", maxf(lid, crouch * 0.25))
	_eye_mat.set_shader_parameter("look", Vector2(_head_look.x * 0.15, _head_look.y * 0.15))
	for m in _fur_mats:
		m.set_shader_parameter("wobble", move + air)
