class_name Director
extends Node
## Story flow. Stage 1: arrival in the closed dacha village, raspberries for
## granny, a few more steps down the street until a car is heard (stage 2 hook).

const BERRIES_NEEDED := 10
## After the last berry the next event is only this far ahead (a few seconds).
const NEXT_EVENT_DIST := 10.0

var hud: Hud
var player: Player
var friend: Friend
var rig: CameraRig
var pickups: Array[BerryPickup] = []

var _berry_quest := false
var _berry_done := false
var _said := {}
var _ended := false
var _goal_z := INF


func start(skip_intro := false) -> void:
	player.interacted.connect(_on_interact)
	Game.berries_changed.connect(_on_berries)
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
	# Start the berry quest when the first raspberries come into view.
	if not _berry_quest and not pickups.is_empty():
		var first := pickups[0]
		if is_instance_valid(first) and player.global_position.distance_to(first.global_position) < 6.0:
			_start_berry_quest()
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


func _start_berry_quest() -> void:
	_berry_quest = true
	hud.show_berries(true)
	await hud.say("Фиалка", "Ой, малина! Бабушка обожает пироги с малиной. Давай наберём ей гостинец?")
	if not _berry_done:
		_update_berry_objective()


func _update_berry_objective() -> void:
	hud.set_objective("Собери малину для бабушки: %d / %d" % [mini(Game.berries, BERRIES_NEEDED), BERRIES_NEEDED])


func _update_prompt() -> void:
	if player.focus is BerryPickup:
		hud.set_prompt("[E]  Сорвать малину")
	else:
		hud.set_prompt("")


func _on_interact(target: Node) -> void:
	if target is BerryPickup:
		(target as BerryPickup).pick()
		player.creature.happy = 1.0
		get_tree().create_timer(1.2).timeout.connect(func() -> void: player.creature.happy = 0.0)
		Game.add_berries(1)


func _on_berries(n: int) -> void:
	if not _berry_quest:
		_start_berry_quest()
	if _berry_done:
		return
	_update_berry_objective()
	match n:
		1:
			hud.say("Бусик", "Спелая! Чур, одну я съем.")
		4:
			hud.say("Фиалка", "Не ешь всё сам! Это для бабушки.")
		7:
			hud.say("Фиалка", "Слышишь? Будто мотор вдалеке… А, показалось.")
	if n >= BERRIES_NEEDED:
		_berry_done = true
		_goal_z = player.global_position.z - NEXT_EVENT_DIST
		hud.set_objective("Иди дальше по улице — ещё %d м" % int(NEXT_EVENT_DIST))
		await hud.say("Фиалка", "Целая горсть! Бабушка испечёт пирог. Пошли дальше!")


func _stage_end() -> void:
	await hud.say("Фиалка", "Стой! Слышишь? Кто-то едет… Прячемся!", 3.0)
	hud.set_objective("Продолжение — этап 2: «Незваные гости»")
	await hud.show_card("Конец первого этапа.\nДальше: машины с пришельцами, прятки и вечер в посёлке.", 3.0)
