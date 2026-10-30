class_name Director
extends Node
## Story flow. Stage 1: arrival in the closed dacha village, burdock leaves for
## granny's sore knee, a few more steps until a car is heard (stage 2 hook).

const LEAVES_NEEDED := 10
## After the last leaf the next event is only this far ahead (a few seconds).
const NEXT_EVENT_DIST := 10.0

var hud: Hud
var player: Player
var friend: Friend
var rig: CameraRig
var street: Street
var cars: Cars
var atmosphere: Atmosphere
var stage2: Stage2
var stage3: Stage3
var pickups: Array[BurdockPickup] = []

var _leaf_quest := false
var _leaf_done := false
var _said := {}
var _ended := false
var _goal_z := INF


func start(skip_intro := false) -> void:
	player.interacted.connect(_on_interact)
	Game.leaves_changed.connect(_on_leaves)
	Audio.ambient("ambient_day", -14.0, 4.0)
	if skip_intro:
		hud.fade.color.a = 0.0
		return
	player.frozen = true
	friend.frozen = true
	await hud.show_card("Конец августа.\nБусик и Фиалка получили письмо от бабушки.", 3.0)
	await hud.show_card("«Приходите ко мне в СНТ „Рассвет“.\nМой дом — в самом конце улицы.\nКлючик под горшком с геранью».", 4.0)
	await hud.show_card("Только вот пушистикам в посёлок вход запрещён.\nИдите тихо. Никто не должен вас заметить.", 3.5)
	await hud.fade_to(0.0, 2.0)
	player.frozen = false
	friend.frozen = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_hint("WASD — идти   Shift — бежать   Пробел — прыжок   C — красться\nE — действие   мышь — осмотреться   Esc — меню")
	await get_tree().create_timer(1.0).timeout
	await hud.say("Фиалка", "Ну вот мы и в «Рассвете»… Только тихо, сюда посторонним нельзя.")
	await hud.say("Бусик", "Бабушкин дом в самом конце улицы. Пойдём!")
	hud.set_objective("Иди по улице к дому бабушки")


func _process(_delta: float) -> void:
	if player == null:
		return
	_update_prompt()
	var z := player.global_position.z
	# Start the leaf quest when the first burdock comes into view.
	if not _leaf_quest and not pickups.is_empty():
		var first := pickups[0]
		if is_instance_valid(first) and player.global_position.distance_to(first.global_position) < 6.0:
			_start_leaf_quest()
	_line_at(z < -30.0, "rowan", "Фиалка", "Смотри, рябина какая рыжая… Осень скоро.")
	_line_at(z < -60.0, "quiet", "Бусик", "Тихо как… Даже собаки не лают.")
	_line_at(z < -95.0, "fences", "Фиалка", "Заборы тут какие высоченные. Мы как муравьи.")
	if _goal_z != INF and not _ended:
		var left := z - _goal_z
		if left <= 0.0:
			_ended = true
			_stage_end()
		else:
			hud.set_objective_text("Иди дальше по улице — ещё %d м" % ceili(left))


func _line_at(cond: bool, id: String, who: String, text: String) -> void:
	if cond and not _said.has(id):
		_said[id] = true
		hud.say(who, text)


func _start_leaf_quest() -> void:
	_leaf_quest = true
	hud.show_counter(true)
	await hud.say("Фиалка", "Ой, лопухи! Бабушка всегда прикладывает лопух к больной коленке. Нарвём ей листьев?")
	if not _leaf_done:
		_update_leaf_objective()


func _update_leaf_objective() -> void:
	hud.set_objective("Нарви листьев лопуха для бабушки: %d / %d" % [mini(Game.leaves, LEAVES_NEEDED), LEAVES_NEEDED])


func _update_prompt() -> void:
	if player.focus and player.focus.has_method("prompt_text"):
		hud.set_prompt("[E]  " + player.focus.prompt_text())
	else:
		hud.set_prompt("")


func _on_interact(target: Node) -> void:
	if stage3 and stage3.handle_interact(target):
		return
	if target is BurdockPickup:
		(target as BurdockPickup).pick()
		player.creature.happy = 1.0
		get_tree().create_timer(1.2).timeout.connect(func() -> void: player.creature.happy = 0.0)
		Game.add_leaves(1)


func _on_leaves(n: int) -> void:
	if not _leaf_quest:
		_start_leaf_quest()
	if _leaf_done:
		return
	_update_leaf_objective()
	match n:
		1:
			hud.say("Бусик", "Ого, лист больше меня! Как зонтик.")
		4:
			hud.say("Фиалка", "Самые большие выбирай, бабушке нужны большие.")
		7:
			hud.say("Фиалка", "Слышишь? Будто мотор вдалеке… А, показалось.")
	if n >= LEAVES_NEEDED:
		_leaf_done = true
		_goal_z = player.global_position.z - NEXT_EVENT_DIST
		hud.set_objective("Иди дальше по улице — ещё %d м" % int(NEXT_EVENT_DIST))
		await hud.say("Фиалка", "Целая охапка! Бабушкина коленка скажет спасибо. Пошли дальше!")


func _stage_end() -> void:
	stage2 = Stage2.new()
	stage2.name = "Stage2"
	stage2.hud = hud
	stage2.player = player
	stage2.friend = friend
	stage2.rig = rig
	stage2.street = street
	stage2.cars = cars
	add_child(stage2)
	stage2.finished.connect(_stage2_end)
	stage2.begin(player.global_position.z)


func _stage2_end() -> void:
	# Crickets take over from the birds; Stage3 drives the sunset itself.
	Audio.ambient("ambient_evening", -16.0, 30.0)
	stage3 = Stage3.new()
	stage3.name = "Stage3"
	stage3.hud = hud
	stage3.player = player
	stage3.friend = friend
	stage3.street = street
	stage3.atmosphere = atmosphere
	add_child(stage3)
	stage3.finished.connect(_stage3_end)
	await get_tree().create_timer(2.5, false).timeout
	stage3.begin()


func _stage3_end() -> void:
	hud.set_objective("Продолжение — этап 4: «У бабушки»")
	await hud.show_card("Конец третьего этапа.\nДальше: ключ под геранью, бабушка и горячий борщ.", 3.5)
