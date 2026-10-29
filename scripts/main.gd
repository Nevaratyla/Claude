extends Node3D
## Entry point: builds the world, spawns heroes, camera, UI and the story.
## Run with `-- --autoshot=<dir>` to render test screenshots and print stats, then quit.

var atmosphere: Atmosphere
var street: Street
var vegetation: Vegetation
var cars: Cars
var player: Player
var friend: Friend
var rig: CameraRig
var hud: Hud
var director: Director
var _shot_dir := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autoshot="):
			_shot_dir = arg.trim_prefix("--autoshot=")
		elif arg.begins_with("--preview="):
			var pv := Preview.new()
			pv.out_dir = arg.trim_prefix("--preview=")
			add_child(pv)
			return
	Game.set_quality(Game.quality)
	var t0 := Time.get_ticks_msec()
	hud = Hud.new()
	add_child(hud)
	atmosphere = Atmosphere.new()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
	street = Street.new()
	street.name = "Street"
	add_child(street)
	street.build()
	await Vegetation.bake_atlas(self)
	vegetation = Vegetation.new()
	vegetation.name = "Vegetation"
	add_child(vegetation)
	vegetation.build(street)
	cars = Cars.new()
	cars.name = "Cars"
	add_child(cars)
	cars.build(street)
	_spawn_pickups()
	_spawn_heroes()
	print("[world] built in %d ms, batches: %d, plots: %d, trees: %d, multimeshes: %d, berries: %d" % [
		Time.get_ticks_msec() - t0, street.draw_batches, street.plots.size(), vegetation.tree_count,
		vegetation.multimesh_count, vegetation.berry_spots.size()])

	director = Director.new()
	director.hud = hud
	director.player = player
	director.friend = friend
	director.rig = rig
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is BerryPickup:
			director.pickups.append(n)
	add_child(director)
	if _shot_dir != "":
		director.start(true)
		_autoshot.call_deferred()
	else:
		director.start()


func _spawn_pickups() -> void:
	for p: Vector3 in vegetation.berry_spots:
		# Skip spots blocked by a car parked on the verge.
		var blocked := false
		for car in cars.verge_cars:
			if absf(car.global_position.z - p.z) < 3.2 and signf(car.global_position.x) == signf(p.x):
				blocked = true
		if blocked:
			continue
		var b := BerryPickup.new()
		b.position = p
		add_child(b)


func _spawn_heroes() -> void:
	player = Player.new()
	player.name = "Busik"
	player.position = Vector3(0.5, 0.05, 0.0)
	add_child(player)
	friend = Friend.new()
	friend.name = "Fialka"
	friend.position = Vector3(-0.2, 0.05, 0.6)
	friend.leader = player
	add_child(friend)
	rig = CameraRig.new()
	rig.target = player
	add_child(rig)
	rig.exclude(player)
	rig.exclude(friend)
	player.camera_rig = rig


func _autoshot() -> void:
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.03
	cam.far = 1500.0
	add_child(cam)
	# Let physics settle the heroes on the ground first.
	for i in 20:
		await get_tree().physics_frame
	var heroes := player.global_position + Vector3(0, 0.25, 0)
	var views := [
		["heroes_close", heroes + Vector3(-0.35, 0.05, -1.1), heroes + Vector3(-0.2, -0.02, 0.2), false],
		["gameplay", Vector3.ZERO, Vector3.ZERO, true],
		["street_low", Vector3(0.6, 0.55, -2.0), Vector3(0.0, 0.7, -40.0), false],
		["fence_right", Vector3(1.2, 0.9, -230.0), Vector3(4.0, 1.2, -235.0), false],
		["berries", vegetation.berry_spots[1] + Vector3(-signf(vegetation.berry_spots[1].x) * 1.2, 0.5, 0.6), vegetation.berry_spots[1] + Vector3(0, 0.2, 0), false],
		["overview", Vector3(0.0, 25.0, 20.0), Vector3(0.0, 0.0, -80.0), false],
	]
	for v in views:
		if v[3]:
			rig.camera.make_current()
		else:
			cam.make_current()
			cam.global_position = v[1]
			cam.look_at(v[2])
		for i in 40:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_dir.path_join(v[0] + ".png"))
		print("[shot] %s draws=%d objs=%d prims=%d" % [v[0],
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	get_tree().quit()
