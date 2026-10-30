class_name Stage2
extends Node
## «Незваные гости». Two ordinary-looking cars come down the street. The
## heroes hide behind a parked car by the fence. The cars stop, the drivers
## stare, two visitors in coats get out and search around, almost reach the
## hiding place, then drive off. If they see Busik long enough, the scene
## restarts from the checkpoint.

signal finished
signal patrols_done

const LANE_X := -0.65
const HIDE_X := -2.55            # parked car centre, its far side is the hiding place

var hud: Hud
var player: Player
var friend: Friend
var street: Street
var cars: Cars

var hide_z := 0.0
var hide_spot := Vector3.ZERO
var checkpoint := Vector3.ZERO
var caught_count := 0
var done := false

var _run_id := 0
var _suspicion := 0.0
var _caught := false
var _cars: Array[AlienCar] = []
var _aliens: Array[Alien] = []
var _hide_car: Node3D
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var _heart: AudioStreamPlayer
var _t := 0.0
var _patrols_left := 0


func begin(at_z: float) -> void:
	checkpoint = Vector3(0.4, 0.0, at_z)
	checkpoint.y = street.height_at(checkpoint.x, checkpoint.z) + 0.05
	hide_z = at_z - 7.0
	var hy := street.height_at(HIDE_X, hide_z)
	_hide_car = cars.spawn("sedan", Vector3(HIDE_X, hy, hide_z), PI * 0.5, self, Color(0.55, 0.57, 0.58))
	cars._add_collision(_hide_car)
	hide_spot = Vector3(-3.62, street.height_at(-3.62, hide_z), hide_z)
	_make_marker()
	_heart = Audio.play("heartbeat", -60.0)
	_run()


func _make_marker() -> void:
	_marker = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.2
	torus.outer_radius = 0.27
	torus.rings = 24
	torus.ring_segments = 6
	_marker.mesh = torus
	_marker.scale = Vector3(1, 0.15, 1)
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.albedo_color = Color(1.0, 0.85, 0.35, 0.8)
	_marker.material_override = _marker_mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.position = hide_spot + Vector3(0, 0.04, 0)
	add_child(_marker)


func _alive(id: int) -> bool:
	return id == _run_id and is_inside_tree()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, false).timeout


# ----------------------------------------------------------------- sequence

func _run() -> void:
	_run_id += 1
	var id := _run_id
	_suspicion = 0.0
	_marker.visible = true
	Audio.play("sting", -4.0)
	hud.set_objective("Спрячься за машиной у забора!  C — пригнуться")
	hud.say("Фиалка", "Слышишь? Машина едет! Быстро за ту серую машину, к забору!")
	friend.go_to(hide_spot + Vector3(0.0, 0.0, -1.0), true, func() -> void: friend.scripted_crouch = true)

	var lead := _spawn_car("crossover", Color(0.06, 0.06, 0.07), hide_z - 105.0)
	var second := _spawn_car("sedan", Color(0.16, 0.18, 0.2), hide_z - 116.0)
	lead.drive_to(hide_z - 9.5, 8.5)
	second.drive_to(hide_z - 16.5, 8.5)
	await lead.arrived
	if not _alive(id):
		return
	hud.say("Бусик", "(шёпотом) Тихо… Не шевелись…")
	await _wait(3.5)
	if not _alive(id):
		return

	# Visitors get out: one on the road side, one on our side.
	for car in _cars:
		car.watching = false
	Audio.play_at("door", lead.global_position + Vector3(0.9, 0.8, 0), 0.0)
	var a1 := _spawn_alien(lead.global_position + Vector3(1.3, 0, 0.6))
	await _wait(0.7)
	if not _alive(id):
		return
	Audio.play_at("door", second.global_position + Vector3(-0.9, 0.8, 0), 0.0)
	var a2 := _spawn_alien(second.global_position + Vector3(-1.4, 0, 0.4))
	a1.say()
	hud.set_objective("Не высовывайся, пока они не уедут")

	_patrols_left = 2
	_patrol_1(a1, id)
	_patrol_2(a2, id)
	await patrols_done
	if not _alive(id):
		return

	# Back in the cars and away through the gate.
	for a in _aliens:
		a.queue_free()
	_aliens.clear()
	Audio.play_at("door", lead.global_position + Vector3(0.9, 0.8, 0), 0.0)
	await _wait(0.5)
	Audio.play_at("door", second.global_position + Vector3(-0.9, 0.8, 0), 0.0)
	await _wait(1.2)
	if not _alive(id):
		return
	for car in _cars:
		car.watching = true
		car.drive_to(Street.START_Z + 80.0, 7.0)
	await _wait(9.0)
	if not _alive(id):
		return
	_finish()


func _patrol_finished(id: int) -> void:
	if not _alive(id):
		return
	_patrols_left -= 1
	if _patrols_left == 0:
		patrols_done.emit()


## The scary one: walks right up to the front of the hiding car and looks around.
func _patrol_1(a: Alien, id: int) -> void:
	var y := 0.0
	await _wait(0.8)
	a.walk([Vector3(-0.2, y, hide_z - 6.0), Vector3(-1.0, y, hide_z - 3.4)])
	await a.arrived
	if not _alive(id):
		return
	a.stare_at(_hide_car.global_position + Vector3(0, 0.5, 0))
	await _wait(2.5)
	if not _alive(id):
		return
	a.say()
	a.look_around(4.0)
	await _wait(4.0)
	if not _alive(id):
		return
	a.walk([Vector3(0.4, y, hide_z + 1.0), Vector3(0.6, y, hide_z + 6.5)])
	await a.arrived
	if not _alive(id):
		return
	# Looks back along the street, toward the hiding place.
	a.stare_at(hide_spot + Vector3(0, 0.3, -2.0))
	await _wait(3.0)
	if not _alive(id):
		return
	a.look_around(2.5)
	await _wait(2.5)
	if not _alive(id):
		return
	a.walk([Vector3(1.6, y, hide_z - 4.0), _cars[0].global_position + Vector3(1.3, 0, 0.6)])
	await a.arrived
	_patrol_finished(id)


## The other one checks the opposite fence and peers into a yard.
func _patrol_2(a: Alien, id: int) -> void:
	var y := 0.0
	await _wait(1.2)
	a.walk([Vector3(1.0, y, hide_z - 12.0), Vector3(3.2, y, hide_z - 7.0)])
	await a.arrived
	if not _alive(id):
		return
	a.stare_at(Vector3(8.0, 1.0, hide_z - 7.0))
	await _wait(3.5)
	if not _alive(id):
		return
	a.look_around(3.0)
	await _wait(3.0)
	if not _alive(id):
		return
	a.walk([Vector3(2.4, y, hide_z - 1.0)])
	await a.arrived
	if not _alive(id):
		return
	a.say()
	a.look_around(3.0)
	await _wait(3.0)
	if not _alive(id):
		return
	a.walk([Vector3(0.8, y, hide_z - 12.0), _cars[1].global_position + Vector3(-1.4, 0, 0.4)])
	await a.arrived
	_patrol_finished(id)


func _spawn_car(model: String, paint: Color, z: float) -> AlienCar:
	var car := AlienCar.new()
	car.street = street
	add_child(car)
	car.setup(cars, model, paint, Vector3(LANE_X, street.height_at(LANE_X, z), z))
	car.watching = true
	_cars.append(car)
	return car


func _spawn_alien(pos: Vector3) -> Alien:
	var a := Alien.new()
	a.street = street
	add_child(a)
	a.global_position = Vector3(pos.x, street.height_at(pos.x, pos.z), pos.z)
	a.rotation.y = 0.0
	_aliens.append(a)
	return a


# ---------------------------------------------------------------- detection

func _physics_process(delta: float) -> void:
	if done or player == null:
		return
	_t += delta
	if _marker:
		_marker_mat.albedo_color.a = 0.45 + 0.35 * sin(_t * 4.0)
		_marker.visible = _marker.visible and player.global_position.distance_to(hide_spot) > 0.45
	if _caught:
		return
	var exclude: Array[RID] = [friend.get_rid()]
	var seen_by: Node3D = null
	var nearest := 99.0
	for a in _aliens:
		if not is_instance_valid(a):
			continue
		var d := a.global_position.distance_to(player.global_position)
		nearest = minf(nearest, d)
		if a.sees(player, exclude):
			seen_by = a
	for c in _cars:
		if is_instance_valid(c) and c.sees(player, exclude):
			seen_by = c
			nearest = minf(nearest, c.global_position.distance_to(player.global_position))
	if seen_by:
		_suspicion += delta * (1.6 if nearest < 5.0 else 0.9)
	else:
		_suspicion = maxf(0.0, _suspicion - delta * 0.35)
	hud.set_suspicion(_suspicion)
	var fear := maxf(_suspicion, clampf(1.0 - (nearest - 1.5) / 6.0, 0.0, 1.0))
	if _heart:
		_heart.volume_db = lerpf(-50.0, -2.0, fear)
		_heart.pitch_scale = lerpf(0.9, 1.35, fear)
	if _suspicion >= 1.0:
		_on_caught(seen_by)


func _on_caught(by: Node3D) -> void:
	_caught = true
	caught_count += 1
	Audio.play("caught", -2.0)
	if by is Alien:
		(by as Alien).stare_at(player.global_position + Vector3(0, 0.3, 0))
		(by as Alien).say()
	player.frozen = true
	hud.say("Фиалка", "Ой! Нас заметили!", 2.0)
	await _wait(1.3)
	await hud.fade_to(1.0, 0.8)
	_reset()
	await hud.show_card("Вас заметили…\nПопробуй ещё раз: спрячься за машиной и пригнись (C).", 2.2)
	await hud.fade_to(0.0, 0.8)
	player.frozen = false
	_caught = false
	_run()


## Clears this attempt and puts the heroes back at the checkpoint.
func _reset() -> void:
	_run_id += 1
	for a in _aliens:
		if is_instance_valid(a):
			a.queue_free()
	_aliens.clear()
	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	_cars.clear()
	_suspicion = 0.0
	hud.set_suspicion(0.0)
	player.global_position = checkpoint
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	friend.stop_going()
	friend.scripted_crouch = false
	friend.global_position = checkpoint + Vector3(-0.7, 0.0, 0.3)
	friend.velocity = Vector3.ZERO


func _finish() -> void:
	done = true
	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	_cars.clear()
	_marker.queue_free()
	friend.scripted_crouch = false
	hud.set_suspicion(0.0)
	var tw := create_tween()
	tw.tween_property(_heart, "volume_db", -60.0, 2.0)
	tw.tween_callback(_heart.queue_free)
	hud.say("Бусик", "Уф… Уехали. Кто это вообще был?!")
	await _wait(3.0)
	await hud.say("Фиалка", "Не знаю… Но лучше нам поскорее дойти до бабушки.")
	finished.emit()
