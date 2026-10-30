class_name Stage3
extends Node
## «Вечер». The sun goes down while the heroes keep walking:
## 1) catch five fireflies into a jar, which then lights the way;
## 2) a washed-out ditch with water cuts the street: find a plank by the fence,
##    drag it over and lay it across as a bridge;
## 3) find granny's house: pale blue, green roof, sunflowers along the fence.

signal finished

const FIREFLIES_NEEDED := 5

var hud: Hud
var player: Player
var friend: Friend
var street: Street
var atmosphere: Atmosphere

var done := false
var sun_tween: Tween
var fireflies_caught := 0
var plank_placed := false
var _phase := ""
var _jar: Node3D
var _jar_light: OmniLight3D
var _jar_glow: StandardMaterial3D
var _flies: Array[Firefly] = []
var _plank: Node3D
var _plank_spot: Node3D
var _carrying := false
var _wall: StaticBody3D
var _friend_crossed := false
var _said := {}


func begin() -> void:
	# One tween drives the sunset for the whole stage: evening, then dusk.
	sun_tween = create_tween()
	sun_tween.tween_property(atmosphere, "time_of_day", 0.85, 30.0)
	sun_tween.tween_property(atmosphere, "time_of_day", 1.45, 170.0)
	_build_ditch()
	_spawn_fireflies()
	_spawn_plank()
	await hud.say("Фиалка", "Темнеет… А бабушкин дом ещё дальше. Смотри — светлячки!")
	await hud.say("Бусик", "Наловим их в банку — будет фонарик!")
	_phase = "fireflies"
	_update_objective()


func _update_objective() -> void:
	match _phase:
		"fireflies":
			hud.set_objective("Поймай светлячков в банку: %d / %d" % [fireflies_caught, FIREFLIES_NEEDED])
		"ditch":
			hud.set_objective("Дорогу перерезала канава. Найди доску у забора и перекинь её через воду")
		"carry":
			hud.set_objective("Дотащи доску до канавы и положи её (E у края воды)")
		"granny":
			hud.set_objective("Найди бабушкин дом: голубой, с зелёной крышей, подсолнухи у забора")


## Returns true when the interaction belonged to this stage.
func handle_interact(target: Node) -> bool:
	if target is Firefly:
		_catch(target as Firefly)
		return true
	if target == _plank and not _carrying and not plank_placed:
		_pick_plank()
		return true
	if target == _plank_spot and _carrying:
		_place_plank()
		return true
	return false


# --------------------------------------------------------------- fireflies

func _spawn_fireflies() -> void:
	# Over bushes and burdocks along both verges, a short walk from stage 2.
	var spots := [Vector3(-3.3, 0, -84.0), Vector3(3.2, 0, -92.0), Vector3(-3.1, 0, -101.0),
		Vector3(3.4, 0, -108.0), Vector3(-3.4, 0, -116.0), Vector3(2.9, 0, -121.0), Vector3(-2.9, 0, -97.0)]
	for p: Vector3 in spots:
		var f := Firefly.new()
		f.position = Vector3(p.x, street.height_at(p.x, p.z), p.z)
		add_child(f)
		_flies.append(f)


func _make_jar() -> void:
	_jar = Node3D.new()
	_jar.position = Vector3(0.16, 0.16, -0.06)
	player.add_child(_jar)
	var glass := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.045
	cyl.bottom_radius = 0.05
	cyl.height = 0.11
	glass.mesh = cyl
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.85, 0.95, 1.0, 0.3)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.roughness = 0.05
	glass.material_override = gm
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_jar.add_child(glass)
	var lid := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.047
	lm.bottom_radius = 0.047
	lm.height = 0.015
	lid.mesh = lm
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.7, 0.68, 0.6)
	lmat.metallic = 0.8
	lid.material_override = lmat
	lid.position.y = 0.062
	_jar.add_child(lid)
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	core.mesh = sm
	_jar_glow = StandardMaterial3D.new()
	_jar_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_jar_glow.albedo_color = Color(0.8, 1.0, 0.4)
	_jar_glow.emission_enabled = true
	_jar_glow.emission = Color(0.8, 1.0, 0.35)
	core.material_override = _jar_glow
	_jar.add_child(core)
	_jar_light = OmniLight3D.new()
	_jar_light.light_color = Color(0.8, 1.0, 0.45)
	_jar_light.omni_range = 1.0
	_jar_light.light_energy = 0.4
	_jar_light.shadow_enabled = false
	_jar.add_child(_jar_light)


func _catch(f: Firefly) -> void:
	if _jar == null:
		_make_jar()
	_flies.erase(f)
	f.caught.connect(func() -> void:
		fireflies_caught += 1
		_jar_light.omni_range = 1.0 + fireflies_caught * 0.5
		_jar_light.light_energy = 0.4 + fireflies_caught * 0.3
		_jar_glow.emission_energy_multiplier = 1.0 + fireflies_caught * 0.8
		Audio.play_at("leaf", player.global_position, -18.0, 2.2)
		_on_firefly())
	f.catch_into(_jar)


func _on_firefly() -> void:
	if _phase != "fireflies":
		return
	_update_objective()
	match fireflies_caught:
		1:
			hud.say("Фиалка", "Поймал! Смотри, как светится!")
		3:
			hud.say("Бусик", "Ещё парочку — и будет настоящий фонарь.")
	if fireflies_caught >= FIREFLIES_NEEDED:
		_phase = "ditch"
		# The rest fly away into the dusk.
		for f in _flies:
			if is_instance_valid(f):
				f.queue_free()
		_flies.clear()
		await hud.say("Фиалка", "Ура, фонарик! Теперь не страшно. Пошли дальше.")
		_update_objective()


# ------------------------------------------------------------------- ditch

func _build_ditch() -> void:
	var zd := Street.DITCH_Z
	# Water surface in the channel.
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(Street.FENCE_X * 2.0, 1.1)
	water.mesh = plane
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.06, 0.07, 0.06, 0.88)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.04
	wm.metallic_specular = 0.8
	water.material_override = wm
	water.position = Vector3(0, -0.16, zd)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	_build_wall(INF)


## Invisible wall across the ditch; with a plank laid, a gap is left at it.
func _build_wall(gap_x: float) -> void:
	if _wall:
		_wall.queue_free()
	_wall = StaticBody3D.new()
	add_child(_wall)
	var spans: Array = [[-Street.FENCE_X, Street.FENCE_X]]
	if gap_x != INF:
		spans = [[-Street.FENCE_X, gap_x - 0.2], [gap_x + 0.2, Street.FENCE_X]]
	for sp: Array in spans:
		var w: float = sp[1] - sp[0]
		if w <= 0.05:
			continue
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(w, 1.2, 0.12)
		cs.shape = box
		cs.position = Vector3((sp[0] + sp[1]) * 0.5, 0.4, Street.DITCH_Z)
		_wall.add_child(cs)


func _spawn_plank() -> void:
	_plank = Node3D.new()
	_plank.set_script(load("res://scripts/actors/prop_interactable.gd"))
	_plank.set("prompt", "Взять доску")
	_plank.set("reach", 1.0)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 0.035, 1.8)
	mi.mesh = bm
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.38, 0.24)
	wood.roughness = 0.85
	mi.material_override = wood
	mi.position.y = 0.02
	_plank.add_child(mi)
	var x := -3.45
	var z := Street.DITCH_Z + 7.0
	_plank.position = Vector3(x, street.height_at(x, z) + 0.01, z)
	_plank.rotation.y = 0.12
	add_child(_plank)
	# The edge of the water where the plank can be laid.
	_plank_spot = Node3D.new()
	_plank_spot.set_script(load("res://scripts/actors/prop_interactable.gd"))
	_plank_spot.set("prompt", "Положить доску через канаву")
	_plank_spot.set("reach", 1.3)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.22
	torus.outer_radius = 0.28
	ring.mesh = torus
	ring.scale = Vector3(1, 0.15, 1)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(1.0, 0.85, 0.35)
	ring.material_override = rm
	_plank_spot.add_child(ring)
	var sx := -0.9
	var sz := Street.DITCH_Z + 0.95
	_plank_spot.position = Vector3(sx, street.height_at(sx, sz) + 0.03, sz)
	_plank_spot.visible = false
	add_child(_plank_spot)


func _pick_plank() -> void:
	_carrying = true
	_phase = "carry"
	_update_objective()
	Audio.play_at("door", _plank.global_position, -14.0, 1.8)
	_plank.remove_from_group("interactable")
	# Busik drags it behind him, one end on the ground.
	_plank.reparent(player, false)
	_plank.position = Vector3(0.0, 0.18, 0.75)
	_plank.rotation = Vector3(-0.2, 0.0, 0.0)
	_plank_spot.visible = true
	_plank_spot.add_to_group("interactable")
	hud.say("Бусик", "Тяжёлая… но дотащу!")


func _place_plank() -> void:
	_carrying = false
	plank_placed = true
	_plank_spot.remove_from_group("interactable")
	_plank_spot.visible = false
	var x := _plank_spot.global_position.x
	var zd := Street.DITCH_Z
	var bank := maxf(street.height_at(x, zd - 0.9), street.height_at(x, zd + 0.9))
	_plank.reparent(self, false)
	_plank.position = Vector3(x, bank - 0.005, zd)
	_plank.rotation = Vector3.ZERO
	Audio.play_at("door", _plank.global_position, -6.0, 0.7)
	# A thin walkway flush with the banks, and a gap in the wall right there.
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.36, 0.04, 2.0)
	cs.shape = box
	cs.position = Vector3(0, -0.02, 0)
	body.add_child(cs)
	_plank.add_child(body)
	_build_wall(x)
	_phase = "granny"
	hud.say("Фиалка", "Мостик! Ты гений. Только осторожно, не свались.")
	_update_objective()


# --------------------------------------------------------------- per frame

func _physics_process(_delta: float) -> void:
	if done or player == null or _phase == "":
		return
	var z := player.global_position.z
	# Fialka crosses the plank on her own once Busik is over.
	if plank_placed and not _friend_crossed and z < Street.DITCH_Z - 1.2:
		_friend_crossed = true
		var x := _plank.global_position.x
		friend.hold = true
		friend.go_to(Vector3(x, 0, Street.DITCH_Z + 1.3), false, func() -> void:
			friend.go_to(Vector3(x, 0, Street.DITCH_Z - 1.4), false, func() -> void: friend.hold = false))
	if _phase == "ditch" and z < Street.DITCH_Z + 5.0 and not _said.has("ditch"):
		_said["ditch"] = true
		hud.say("Фиалка", "Ой… Канава, и вода. Мы же утонем! Нужна доска.")
	if _phase == "granny" and not street.granny.is_empty():
		var gate: Vector3 = street.granny.gate_world
		if player.global_position.distance_to(gate) < 3.2:
			_arrive()


func _arrive() -> void:
	done = true
	hud.set_objective("")
	await hud.say("Фиалка", "Смотри! Голубой домик, зелёная крыша, подсолнухи… Это же бабушкин дом!")
	await hud.say("Бусик", "Свет в окнах горит. Ключик под геранью — помнишь?")
	finished.emit()
