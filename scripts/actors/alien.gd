class_name Alien
extends Node3D
## A visitor in a long coat. Walks along a list of points, stops to look
## around, and can see the heroes: field of view, distance and a ray that must
## not be blocked (cars, fences). Animation is procedural, like the heroes'.

signal arrived

const MODEL := preload("res://assets/characters/alien.glb")
const WALK_SPEED := 1.1
const FOV_DEG := 62.0
const SIGHT := 11.0

var street: Street
var _parts := {}
var _rest := {}
var _path: Array[Vector3] = []
var _speed := WALK_SPEED
var _phase := 0.0
var _moving := false
var _scan_t := 0.0
var _scan := 0.0                 # 0..1 how much the head sweeps left-right
var _head_yaw := 0.0
var _look_at := Vector3.INF
var _time := randf() * 10.0
var _voice: AudioStreamPlayer3D
var duck := 0.0                  # 0 standing .. 1 bent low (getting into a car)


func _ready() -> void:
	var model: Node3D = MODEL.instantiate()
	model.rotation.y = PI          # model faces +Z, Godot forward is -Z
	add_child(model)
	_collect(model)
	_materials(model)
	_voice = AudioStreamPlayer3D.new()
	_voice.position.y = 1.6
	_voice.unit_size = 4.0
	_voice.max_distance = 40.0
	_voice.bus = "SFX"
	add_child(_voice)


func _collect(n: Node) -> void:
	for c in n.get_children():
		if c is Node3D:
			var key := String(c.name).split(".")[0]
			if key in ["Body", "Head", "Arm_L", "Arm_R", "Leg_L", "Leg_R"] and not _parts.has(key):
				_parts[key] = c
				_rest[key] = c.transform
		_collect(c)


func _materials(model: Node3D) -> void:
	var skin := StandardMaterial3D.new()
	skin.vertex_color_use_as_albedo = true
	skin.roughness = 0.5
	skin.subsurf_scatter_enabled = true
	skin.subsurf_scatter_strength = 0.25
	skin.rim_enabled = true
	skin.rim = 0.35
	var coat := StandardMaterial3D.new()
	coat.vertex_color_use_as_albedo = true
	coat.roughness = 0.92
	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color(0.01, 0.01, 0.012)
	eye.roughness = 0.04
	eye.metallic_specular = 1.0
	eye.clearcoat_enabled = true
	eye.clearcoat = 1.0
	var trim := StandardMaterial3D.new()          # buttons and belt
	trim.albedo_color = Color(0.03, 0.03, 0.035)
	trim.roughness = 0.45
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var key := String(mi.name).split(".")[0]
		if key == "CoatDeco":
			mi.material_override = trim
			continue
		var dark := key.begins_with("Eye") or key == "Face"
		mi.material_override = eye if dark else (skin if key == "Head" else coat)


## Walk through the points (y is taken from the ground); emits `arrived`.
func walk(points: Array[Vector3], speed := WALK_SPEED) -> void:
	_path = points.duplicate()
	_speed = speed
	_moving = true
	_look_at = Vector3.INF


## Stand and sweep the head left and right for a while.
func look_around(seconds: float) -> void:
	_moving = false
	_scan = 1.0
	_scan_t = seconds


func stare_at(point: Vector3) -> void:
	_look_at = point


func say(variant := -1) -> void:
	_voice.stream = Audio.stream("alien_voice%d" % (variant if variant >= 0 else randi_range(0, 3)))
	_voice.pitch_scale = randf_range(0.85, 1.1)
	_voice.play()


func eye_position() -> Vector3:
	var head: Node3D = _parts.get("Head")
	return head.global_position + Vector3(0, 0.19, 0) if head else global_position + Vector3(0, 1.7, 0)


func eye_forward() -> Vector3:
	var head: Node3D = _parts.get("Head")
	return head.global_basis.z.normalized() if head else -global_basis.z


## True if `hero` is in sight right now. Crouched heroes are harder to spot.
func sees(hero: Hero, exclude: Array[RID]) -> bool:
	return Alien.vision(get_world_3d(), eye_position(), eye_forward(), hero, exclude, SIGHT, FOV_DEG)


static func vision(world: World3D, eye: Vector3, fwd: Vector3, hero: Hero, exclude: Array[RID],
		sight: float, fov_deg: float) -> bool:
	var target := hero.global_position + Vector3(0, 0.12 if hero.wants_crouch else 0.26, 0)
	var to := target - eye
	var dist := to.length()
	var reach := sight * (0.55 if hero.wants_crouch else 1.0)
	if dist > reach:
		return false
	if fwd.angle_to(to) > deg_to_rad(fov_deg):
		return false
	var q := PhysicsRayQueryParameters3D.create(eye, target)
	q.exclude = exclude
	var hit := world.direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.collider == hero


func _physics_process(delta: float) -> void:
	_time += delta
	var speed := 0.0
	if _moving and not _path.is_empty():
		var goal := _path[0]
		var to := Vector3(goal.x - global_position.x, 0, goal.z - global_position.z)
		if to.length() < 0.1:
			_path.pop_front()
			if _path.is_empty():
				_moving = false
				arrived.emit()
		else:
			speed = _speed
			var step := to.normalized() * minf(_speed * delta, to.length())
			global_position += step
			var yaw := atan2(-to.x, -to.z)
			rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-delta * 6.0))
	if street:
		global_position.y = street.height_at(global_position.x, global_position.z)
	_animate(delta, speed)


func _animate(delta: float, speed: float) -> void:
	var move := clampf(speed / WALK_SPEED, 0.0, 1.0)
	_phase += delta * 5.2 * move
	var s := sin(_phase)
	var body: Node3D = _parts.get("Body")
	if body:
		var bob := absf(s) * 0.025 * move
		var sway := sin(_time * 0.9) * 0.015 * (1.0 - move)
		# Model faces +Z inside: a positive X rotation bends the top forward.
		body.transform = Transform3D(Basis(Vector3.RIGHT, duck * 0.75) * Basis(Vector3.FORWARD, sway + s * 0.03 * move)
			* _rest["Body"].basis, _rest["Body"].origin + Vector3(0, bob - duck * 0.42, 0))
	for leg in ["Leg_L", "Leg_R"]:
		var n: Node3D = _parts.get(leg)
		if n:
			var sign := 1.0 if leg == "Leg_L" else -1.0
			n.transform = Transform3D(Basis(Vector3.RIGHT, s * sign * 0.45 * move - duck * 0.9) * _rest[leg].basis,
				_rest[leg].origin)
	for arm in ["Arm_L", "Arm_R"]:
		var n: Node3D = _parts.get(arm)
		if n:
			var sign := 1.0 if arm == "Arm_L" else -1.0
			# Long arms hang stiffly and swing only a little: unsettling.
			n.transform = Transform3D(Basis(Vector3.RIGHT, -s * sign * 0.18 * move) * _rest[arm].basis, _rest[arm].origin)
	# Head: sweep while scanning, or turn toward a point of interest.
	if _scan_t > 0.0:
		_scan_t -= delta
		if _scan_t <= 0.0:
			_scan = 0.0
	var want := sin(_time * 0.8) * 1.0 * _scan + sin(_time * 0.37) * 0.15
	if _look_at != Vector3.INF:
		var to := global_basis.inverse() * (_look_at - global_position)
		want = clampf(atan2(-to.x, -to.z), -1.3, 1.3)
	_head_yaw = lerp_angle(_head_yaw, want, 1.0 - exp(-delta * 3.0))
	var head: Node3D = _parts.get("Head")
	if head:
		var tilt := sin(_time * 1.3) * 0.06
		# Yaw about the vertical axis turns the head the same way in model space.
		head.transform = Transform3D(Basis(Vector3.UP, _head_yaw) * Basis(Vector3.FORWARD, tilt) * _rest["Head"].basis,
			_rest["Head"].origin)
