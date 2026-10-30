class_name Cars
extends Node3D
## Parked cars: some in the yards behind the gates, a few on the verge against
## the fences (like the reference photo). Verge cars have collision so the
## heroes can hide behind them.

const MODELS := {
	"sedan": preload("res://assets/cars/sedan.glb"),
	"hatch": preload("res://assets/cars/hatch.glb"),
	"crossover": preload("res://assets/cars/crossover.glb"),
}
const PAINTS := [Color(0.85, 0.85, 0.82), Color(0.08, 0.08, 0.09), Color(0.55, 0.1, 0.08),
	Color(0.12, 0.22, 0.42), Color(0.45, 0.47, 0.5), Color(0.2, 0.35, 0.22), Color(0.62, 0.58, 0.5)]

var rng := RandomNumberGenerator.new()
var verge_cars: Array[Node3D] = []
var _mats := {}


func build(street: Street) -> void:
	rng.seed = 4242
	_make_materials()
	var verge_z := [-45.0, -128.0, -205.0, -262.0, -310.0]
	for z: float in verge_z:
		var side := -1 if rng.randf() < 0.5 else 1
		var cx := side * (Street.FENCE_X - 1.0)
		var car := _spawn(_pick_model(), Vector3(cx, street.height_at(cx, z), z), PI * 0.5 if rng.randf() < 0.5 else -PI * 0.5)
		_add_collision(car)
		verge_cars.append(car)
	for p in street.plots:
		if p.has("gate_world") and rng.randf() < 0.35:
			var s: int = p.side
			var g: Vector3 = p.gate_world
			var pos := Vector3(s * (Street.FENCE_X + 3.2), 0, g.z)
			_spawn(_pick_model(), pos, 0.0 if s > 0 else PI)


func _pick_model() -> String:
	return ["sedan", "hatch", "crossover", "sedan", "crossover"][rng.randi_range(0, 4)]


func _make_materials() -> void:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.04, 0.05, 0.06)
	glass.metallic = 0.2
	glass.roughness = 0.04
	_mats["glass"] = glass
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.04, 0.04, 0.04)
	rubber.roughness = 0.85
	_mats["rubber"] = rubber
	var rim := StandardMaterial3D.new()
	rim.albedo_color = Color(0.7, 0.71, 0.72)
	rim.metallic = 0.9
	rim.roughness = 0.28
	_mats["rim"] = rim
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.06, 0.06, 0.065)
	trim.roughness = 0.55
	_mats["trim"] = trim
	var lf := StandardMaterial3D.new()
	lf.albedo_color = Color(0.85, 0.87, 0.9)
	lf.metallic = 0.6
	lf.roughness = 0.08
	_mats["light_front"] = lf
	var lr := StandardMaterial3D.new()
	lr.albedo_color = Color(0.55, 0.03, 0.03)
	lr.roughness = 0.15
	_mats["light_rear"] = lr
	var plate := StandardMaterial3D.new()
	plate.albedo_color = Color(0.92, 0.92, 0.9)
	plate.roughness = 0.5
	_mats["plate"] = plate
	var lf_on := StandardMaterial3D.new()
	lf_on.albedo_color = Color(1, 1, 0.95)
	lf_on.emission_enabled = true
	lf_on.emission = Color(1.0, 0.97, 0.88)
	lf_on.emission_energy_multiplier = 4.0
	_mats["light_front_on"] = lf_on
	var lr_on := StandardMaterial3D.new()
	lr_on.albedo_color = Color(0.6, 0.02, 0.02)
	lr_on.emission_enabled = true
	lr_on.emission = Color(1.0, 0.05, 0.03)
	lr_on.emission_energy_multiplier = 2.5
	_mats["light_rear_on"] = lr_on


func _paint(col: Color) -> StandardMaterial3D:
	var key := col.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.metallic = 0.55
		m.roughness = 0.32
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = 0.08
		_mats[key] = m
	return _mats[key]


func _spawn(model: String, pos: Vector3, yaw: float) -> Node3D:
	return spawn(model, pos, yaw, self, PAINTS[rng.randi_range(0, PAINTS.size() - 1)])


## Instantiates a car under `parent` with shared materials. `lights_on` swaps
## in glowing head/tail light materials.
func spawn(model: String, pos: Vector3, yaw: float, parent: Node, paint_col: Color, lights_on := false) -> Node3D:
	var car: Node3D = MODELS[model].instantiate()
	car.position = pos
	car.rotation.y = yaw
	parent.add_child(car)
	var paint := _paint(paint_col)
	for mi: MeshInstance3D in car.find_children("*", "MeshInstance3D", true, false):
		mi.visibility_range_end = 220.0
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var nm := src.resource_name if src else ""
			if lights_on and nm.begins_with("light_"):
				nm += "_on"
			mi.set_surface_override_material(i, paint if nm == "paint" or not _mats.has(nm) else _mats[nm])
	return car


func _add_collision(car: Node3D) -> void:
	var body := StaticBody3D.new()
	car.add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var aabb := AABB()
	var first := true
	for mi: MeshInstance3D in car.find_children("*", "MeshInstance3D", true, false):
		var a := mi.transform * mi.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
	box.size = aabb.size
	cs.shape = box
	cs.position = aabb.get_center()
	body.add_child(cs)
