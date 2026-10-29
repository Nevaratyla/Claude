class_name Hero
extends CharacterBody3D
## Shared movement for both heroes. A subclass fills `wish_dir`, `wants_run`,
## `wants_jump`, `wants_crouch` every physics tick; this class moves the body
## and feeds the Creature visual.

const WALK := 1.4
const RUN := 3.2
const SNEAK := 0.7
const ACCEL := 9.0
const AIR_ACCEL := 2.5
const JUMP_V := 3.3
const TURN_SPEED := 10.0

var creature: Creature
var wish_dir := Vector3.ZERO
var wants_run := false
var wants_jump := false
var wants_crouch := false
var frozen := false
var _crouch := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _init_body(model: PackedScene, iris: Color, lid: Color) -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.12
	shape.height = 0.42
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.21
	add_child(cs)
	floor_snap_length = 0.1
	floor_max_angle = deg_to_rad(50)
	creature = Creature.new()
	creature.iris_color = iris
	creature.lid_color = lid
	add_child(creature)
	creature.setup(model)


func _physics_process(delta: float) -> void:
	if frozen:
		wish_dir = Vector3.ZERO
		wants_jump = false
	_crouch = move_toward(_crouch, 1.0 if wants_crouch else 0.0, delta * 5.0)
	var top := SNEAK if wants_crouch else (RUN if wants_run else WALK)
	var target := Vector3(wish_dir.x, 0, wish_dir.z).limit_length(1.0) * top
	var flat := Vector3(velocity.x, 0, velocity.z)
	var a := ACCEL if is_on_floor() else AIR_ACCEL
	flat = flat.move_toward(target, a * top * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	if is_on_floor():
		if wants_jump:
			velocity.y = JUMP_V
	else:
		velocity.y -= _gravity * delta
	wants_jump = false
	move_and_slide()

	# Face the movement direction smoothly.
	if flat.length() > 0.15:
		var yaw := atan2(-flat.x, -flat.z)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-TURN_SPEED * delta))
	creature.velocity = velocity
	creature.grounded = is_on_floor()
	creature.crouch = _crouch
