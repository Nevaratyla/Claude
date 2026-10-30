class_name Preview
extends Node
## Dev tool: renders the heroes and cars up close without building the street.
## godot --path . -- --preview=<dir>   (main.gd hands over to this node)

var out_dir := "user://preview"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var world := Node3D.new()
	add_child(world)
	var atm := Atmosphere.new()
	world.add_child(atm)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://shaders/ground.gdshader")
	floor_mi.material_override = gm
	world.add_child(floor_mi)

	var heroes: Array[Creature] = []
	var specs := [["res://assets/characters/busik.glb", Color(0.12, 0.35, 0.85), Color(0.16, 0.36, 0.93), -0.22],
		["res://assets/characters/fialka.glb", Color(0.45, 0.2, 0.75), Color(0.6, 0.38, 0.88), 0.22]]
	for sp in specs:
		var c := Creature.new()
		c.iris_color = sp[1]
		c.lid_color = sp[2]
		c.position = Vector3(sp[3], 0, 0)
		c.rotation.y = PI      # face the camera (+Z)
		world.add_child(c)
		c.setup(load(sp[0]))
		heroes.append(c)
	var cars := Cars.new()
	world.add_child(cars)
	cars._make_materials()
	var x := -5.0
	for m: String in ["sedan", "hatch", "crossover"]:
		cars._spawn(m, Vector3(x, 0, -6), 0.4)
		x += 5.0

	var alien := Alien.new()
	world.add_child(alien)
	alien.global_position = Vector3(1.6, 0, -1.2)
	alien.rotation.y = PI - 0.5     # turned toward the camera
	var cam := Camera3D.new()
	cam.fov = 40
	cam.near = 0.02
	world.add_child(cam)
	cam.make_current()
	var shots := [
		["heroes_front", Vector3(0, 0.3, 1.05), Vector3(0, 0.24, 0)],
		["heroes_side", Vector3(0.95, 0.35, 0.45), Vector3(0, 0.22, 0)],
		["busik_face", Vector3(-0.22, 0.33, 0.42), Vector3(-0.22, 0.29, 0)],
		["cars", Vector3(0, 2.2, 6.0), Vector3(0, 0.8, -6)],
		["alien", Vector3(0.9, 1.3, 1.3), Vector3(1.6, 1.1, -1.2)],
		["alien_face", Vector3(1.25, 1.72, -0.55), Vector3(1.6, 1.68, -1.2)],
		["alien_low", Vector3(0.2, 0.25, 0.6), Vector3(1.6, 1.4, -1.2)],
	]
	for s in shots:
		cam.global_position = s[1]
		cam.look_at(s[2])
		for i in 30:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out_dir.path_join(s[0] + ".png"))
		print("[preview] ", s[0])
	get_tree().quit()
