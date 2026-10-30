class_name CameraRig
extends Node3D
## Camera with two modes (V to switch, also in the pause menu):
## third person — low orbit camera, so the street feels huge from a 40 cm hero;
## first person — the hero's own eyes (their body only casts a shadow).
## `peek` raises the third-person camera, e.g. to look over a car while hiding.

var target: Node3D
var yaw := 0.0
var pitch := -0.12
var distance := 1.5
var camera: Camera3D
var _arm: SpringArm3D
var _pos := Vector3.ZERO
var sensitivity := 0.0025
var cinematic := false          # Director drives the camera directly
var first_person := false
var peek := 0.0                 # extra height in metres (third person)
var _peek_now := 0.0
var _bob := 0.0


func _ready() -> void:
	top_level = true
	# The rig is moved every rendered frame, so it must not be physics-interpolated.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_arm = SpringArm3D.new()
	_arm.spring_length = distance
	_arm.margin = 0.08
	var sphere := SphereShape3D.new()
	sphere.radius = 0.08
	_arm.shape = sphere
	add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 64.0
	camera.near = 0.03
	camera.far = 900.0
	_arm.add_child(camera)
	camera.make_current()
	if target:
		_pos = _target_pos()
	Game.settings_changed.connect(_apply_mode)
	_apply_mode.call_deferred()


func _apply_mode() -> void:
	first_person = Game.first_person
	if target and target.has_method("set_first_person"):
		target.set_first_person(first_person)


## The hero moves on physics ticks (60 Hz); reading its interpolated transform
## keeps the camera smooth at any frame rate instead of stepping 60 times a second.
func _target_pos() -> Vector3:
	return target.get_global_transform_interpolated().origin


## Keeps these bodies (the heroes) from pushing the camera in.
func exclude(body: CollisionObject3D) -> void:
	_arm.add_excluded_object(body.get_rid())


func _unhandled_input(event: InputEvent) -> void:
	if cinematic:
		return
	if event.is_action_pressed("camera_mode"):
		Game.set_option("first_person", not Game.first_person)
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := sensitivity * Game.mouse_sens
		yaw -= event.relative.x * sens
		pitch = clampf(pitch - event.relative.y * sens, -1.35 if first_person else -1.2, 1.2 if first_person else 0.55)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(0.7, distance - 0.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(3.5, distance + 0.15)


func _process(delta: float) -> void:
	if cinematic or target == null:
		return
	if first_person:
		# Eyes of a 40 cm hero, lower when crouching, with a light walking bob.
		var hero := target as Hero
		var eye := 0.24 if hero and hero.wants_crouch else 0.33
		var spd := Vector3(hero.velocity.x, 0, hero.velocity.z).length() if hero else 0.0
		_bob += delta * spd * 5.5
		var bob := sin(_bob) * 0.008 * clampf(spd, 0.0, 1.5)
		_pos = _target_pos() + Vector3(0, eye + bob, 0)
		global_position = _pos
		rotation = Vector3(pitch, yaw, 0)
		_arm.spring_length = 0.0
		return
	_peek_now = lerpf(_peek_now, peek, 1.0 - exp(-delta * 3.0))
	var goal := _target_pos() + Vector3(0, 0.42 + _peek_now, 0)
	_pos = _pos.lerp(goal, 1.0 - exp(-delta * 12.0))
	global_position = _pos
	rotation = Vector3(pitch, yaw, 0)
	_arm.spring_length = lerpf(_arm.spring_length, distance, 1.0 - exp(-delta * 8.0))
