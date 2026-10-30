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
	print("[world] built in %d ms, batches: %d, plots: %d, trees: %d, multimeshes: %d, burdocks: %d" % [
		Time.get_ticks_msec() - t0, street.draw_batches, street.plots.size(), vegetation.tree_count,
		vegetation.multimesh_count, vegetation.burdock_spots.size()])

	director = Director.new()
	director.hud = hud
	director.player = player
	director.friend = friend
	director.rig = rig
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is BurdockPickup:
			director.pickups.append(n)
	add_child(director)
	if _shot_dir != "":
		director.start(true)
		_autoshot.call_deferred()
	else:
		director.start()


func _spawn_pickups() -> void:
	for p: Vector3 in vegetation.burdock_spots:
		# Skip spots blocked by a car parked on the verge.
		var blocked := false
		for car in cars.verge_cars:
			if absf(car.global_position.z - p.z) < 3.2 and signf(car.global_position.x) == signf(p.x):
				blocked = true
		if blocked:
			continue
		var b := BurdockPickup.new()
		b.position = Vector3(p.x, street.height_at(p.x, p.z), p.z)
		add_child(b)


func _spawn_heroes() -> void:
	player = Player.new()
	player.name = "Busik"
	player.position = Vector3(0.5, street.height_at(0.5, 0.0) + 0.05, 0.0)
	add_child(player)
	friend = Friend.new()
	friend.name = "Fialka"
	friend.position = Vector3(-0.2, street.height_at(-0.2, 0.6) + 0.05, 0.6)
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
		["burdock", vegetation.burdock_spots[1] + Vector3(-signf(vegetation.burdock_spots[1].x) * 1.6, 0.6, 0.9), vegetation.burdock_spots[1] + Vector3(0, 0.25, 0), false],
		["dirt_road", Vector3(0.9, 0.45, -16.0), Vector3(-0.3, 0.2, -32.0), false],
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
	await _test_quest()
	get_tree().quit()


## Walks the leaf quest: teleports to pickups, picks them, then steps forward
## and checks that the next event fires. Prints PASS/FAIL lines.
func _test_quest() -> void:
	print("[test] quality=%s pickups=%d" % [Game.QUALITY_NAMES[Game.quality], director.pickups.size()])
	var picked := 0
	for b in director.pickups:
		if picked >= Director.LEAVES_NEEDED:
			break
		player.global_position = b.global_position + Vector3(0.3 * -signf(b.global_position.x), 0.05, 0)
		for i in 3:
			await get_tree().physics_frame
		if player.focus == b:
			player.interacted.emit(b)
			picked += 1
		else:
			print("[test] FAIL: pickup at %s not in reach" % b.global_position)
	print("[test] leaves=%d %s" % [Game.leaves, "PASS" if Game.leaves >= Director.LEAVES_NEEDED else "FAIL"])
	await get_tree().create_timer(4.0).timeout
	var last_z := player.global_position.z
	print("[test] goal %.1f m ahead of last leaf %s" % [last_z - director._goal_z,
		"PASS" if last_z - director._goal_z <= 12.0 else "FAIL"])
	player.global_position = Vector3(0.0, street.height_at(0.0, director._goal_z - 0.5) + 0.05, director._goal_z - 0.5)
	# process_frame fires before nodes' _process, so give the Director a few frames.
	for i in 4:
		await get_tree().process_frame
	print("[test] next event fired: %s (z=%.1f goal=%.1f)" % ["PASS" if director._ended else "FAIL",
		player.global_position.z, director._goal_z])
	var furthest := 0.0
	for b in director.pickups:
		if is_instance_valid(b):
			furthest = minf(furthest, b.global_position.z)
	print("[test] burdock area length %.0f m" % -furthest)
