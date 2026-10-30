class_name AlienCar
extends Node3D
## An ordinary-looking car driven by the visitors. Drives along a lane on the
## uneven road with smooth acceleration and braking, wheels spinning,
## headlights on, engine and tyre sounds. While `watching`, the driver can
## spot the heroes through the windscreen.

signal arrived

const ACCEL := 2.5
const BRAKE := 2.8
const DRIVER_SIGHT := 16.0
const DRIVER_FOV := 38.0

var street: Street
var watching := false
var speed := 0.0
var _target_z := 0.0
var _max_speed := 0.0
var _driving := false
var _dir := 1.0                  # +1 drives toward +Z
var _car: Node3D
var _wheels: Array[Node3D] = []
var _wheel_r := 0.32
var _length := 4.2
var _engine: AudioStreamPlayer3D
var _tires: AudioStreamPlayer3D
var _body: AnimatableBody3D


## Call after the node is in the tree.
func setup(cars: Cars, model: String, paint: Color, start: Vector3) -> void:
	# Car faces local +X; turn it so it faces +Z (toward the heroes).
	global_position = start
	rotation.y = -PI * 0.5
	_car = cars.spawn(model, Vector3.ZERO, 0.0, self, paint, true)
	var to_local := global_transform.affine_inverse()
	var aabb := AABB()
	var first := true
	for mi: MeshInstance3D in _car.find_children("*", "MeshInstance3D", true, false):
		var a := (to_local * mi.global_transform) * mi.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
		if String(mi.name).begins_with("Wheel"):
			_wheels.append(mi)
			_wheel_r = mi.get_aabb().size.y * 0.5
	_length = aabb.size.x
	# Moving collision so the heroes cannot walk through it (and it shields them).
	_body = AnimatableBody3D.new()
	_body.sync_to_physics = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size
	cs.shape = box
	cs.position = aabb.get_center()
	_body.add_child(cs)
	add_child(_body)
	# Headlights.
	for side: float in [-0.55, 0.55]:
		var l := SpotLight3D.new()
		l.position = Vector3(_length * 0.5, 0.62, side)
		l.rotation.y = -PI * 0.5
		l.spot_range = 26.0
		l.spot_angle = 28.0
		l.light_energy = 3.0
		l.light_color = Color(1.0, 0.97, 0.9)
		l.shadow_enabled = false
		add_child(l)
	_engine = Audio.attach_loop("engine_loop", self, -2.0, 7.0)
	_tires = Audio.attach_loop("tires_loop", self, -40.0, 5.0)


func collision_rid() -> RID:
	return _body.get_rid()


## Drive along the lane until `z`, at up to `max_speed` m/s; emits `arrived`.
func drive_to(z: float, max_speed: float) -> void:
	_target_z = z
	_max_speed = max_speed
	_dir = signf(z - global_position.z)
	_driving = true
	rotation.y = -PI * 0.5 if _dir > 0 else PI * 0.5


func driver_eye() -> Vector3:
	return global_transform * Vector3(0.1, 1.15, -0.38)


func forward() -> Vector3:
	return global_basis.x.normalized()


func sees(hero: Hero, exclude: Array[RID]) -> bool:
	if not watching:
		return false
	var ex := exclude.duplicate()
	ex.append(_body.get_rid())
	return Alien.vision(get_world_3d(), driver_eye(), forward(), hero, ex, DRIVER_SIGHT, DRIVER_FOV)


func _physics_process(delta: float) -> void:
	if _driving:
		var left := (_target_z - global_position.z) * _dir
		var stop_speed := sqrt(maxf(0.0, 2.0 * BRAKE * left))
		var want := minf(_max_speed, stop_speed)
		speed = move_toward(speed, want, (ACCEL if want > speed else BRAKE * 1.5) * delta)
		var step := minf(speed * delta, maxf(left, 0.0))
		global_position.z += step * _dir
		if left <= 0.02:
			_driving = false
			speed = 0.0
			arrived.emit()
		for w in _wheels:
			w.rotate_object_local(Vector3.BACK, -step / _wheel_r)
	_follow_ground()
	_engine.pitch_scale = 0.8 + speed * 0.05
	_engine.volume_db = -4.0 + minf(speed, 8.0) * 0.6
	_tires.volume_db = linear_to_db(clampf(speed / 6.0, 0.001, 1.0)) - 6.0


func _follow_ground() -> void:
	if street == null:
		return
	var p := global_position
	var half := _length * 0.38 * _dir
	var hf := street.height_at(p.x, p.z + half)
	var hr := street.height_at(p.x, p.z - half)
	var yaw := -PI * 0.5 if _dir > 0 else PI * 0.5
	var pitch := atan2(hf - hr, absf(half) * 2.0)
	global_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, pitch)
	global_position.y = (hf + hr) * 0.5
