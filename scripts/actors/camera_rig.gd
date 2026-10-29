class_name CameraRig
extends Node3D
## Third-person orbit camera kept low to the ground, so the street feels huge
## from the heroes' 40 cm point of view. Mouse to orbit, wheel to zoom.

var target: Node3D
var yaw := 0.0
var pitch := -0.12
var distance := 1.5
var camera: Camera3D
var _arm: SpringArm3D
var _pos := Vector3.ZERO
var sensitivity := 0.0025
var cinematic := false          # Director drives the camera directly


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
	camera.far = 1500.0
	_arm.add_child(camera)
	camera.make_current()
	if target:
		_pos = _target_pos()


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
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * sensitivity
		pitch = clampf(pitch - event.relative.y * sensitivity, -1.2, 0.55)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(0.7, distance - 0.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(3.5, distance + 0.15)


func _process(delta: float) -> void:
	if cinematic or target == null:
		return
	var goal := _target_pos() + Vector3(0, 0.42, 0)
	_pos = _pos.lerp(goal, 1.0 - exp(-delta * 12.0))
	global_position = _pos
	rotation = Vector3(pitch, yaw, 0)
	_arm.spring_length = lerpf(_arm.spring_length, distance, 1.0 - exp(-delta * 8.0))
