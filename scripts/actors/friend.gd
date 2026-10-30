class_name Friend
extends Hero
## Fialka, the AI companion. Follows the player at a comfortable distance and
## catches up by running, but lives her own life: hops, crouches to sniff the
## ground, wanders off to look at things. Scripts can send her somewhere with
## `go_to` or make her hide with `scripted_crouch`.

var leader: Node3D
var _goal := Vector3.INF
var _goal_done: Callable
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _idle_look_t := 0.0
var _idle_look := Vector3.ZERO
var scripted_crouch := false
var _action_t := randf_range(3.0, 6.0)
var _crouch_left := 0.0
var _hops_left := 0
var _hop_t := 0.0
var _wander := Vector3.INF
var _wander_left := 0.0


func _ready() -> void:
	_init_body(preload("res://assets/characters/fialka.glb"), Color(0.45, 0.2, 0.75), Color(0.6, 0.38, 0.88))


## Walk to a point; `done` is called on arrival. Overrides following.
func go_to(point: Vector3, run := false, done := Callable()) -> void:
	_goal = point
	_goal_done = done
	wants_run = run


func stop_going() -> void:
	_goal = Vector3.INF


func _physics_process(delta: float) -> void:
	wish_dir = Vector3.ZERO
	wants_jump = false
	if _goal != Vector3.INF:
		var to := _goal - global_position
		to.y = 0
		if to.length() < 0.15:
			_goal = Vector3.INF
			wants_run = false
			if _goal_done.is_valid():
				_goal_done.call()
		else:
			wish_dir = to.normalized() * clampf(to.length() / 0.5, 0.3, 1.0)
	elif leader:
		# Walk beside the leader (not behind: that is where the camera looks from).
		var side := leader.global_basis.x * 0.7
		var back := leader.global_basis.z * 0.1
		var slot := leader.global_position + side + back
		var to := slot - global_position
		to.y = 0
		var dist := to.length()
		var leader_speed := Vector3(leader.velocity.x, 0, leader.velocity.z).length() if leader is CharacterBody3D else 0.0
		# A short wander overrides the slot while the leader stands still.
		if _wander != Vector3.INF:
			if leader_speed > 0.5 or dist > 3.0:
				_wander = Vector3.INF
			else:
				to = _wander - global_position
				to.y = 0
				dist = to.length()
				if dist < 0.2:
					_wander_left -= delta
					to = Vector3.ZERO
					if _wander_left <= 0.0:
						_wander = Vector3.INF
		if dist > 0.35:
			wish_dir = to.normalized() * clampf(dist / 1.2, 0.35, 1.0)
		wants_run = dist > 2.2 or leader_speed > Hero.WALK + 0.4
		_own_actions(delta, leader_speed)
	wants_crouch = scripted_crouch or _crouch_left > 0.0
	# Jump over small things if stuck while trying to move.
	if wish_dir.length() > 0.3:
		if global_position.distance_to(_last_pos) < 0.2 * delta:
			_stuck_t += delta
			if _stuck_t > 0.5:
				wants_jump = true
				_stuck_t = 0.0
		else:
			_stuck_t = 0.0
	_last_pos = global_position
	super(delta)
	_idle_behaviour(delta)


## Her own little habits, independent of what the player does.
func _own_actions(delta: float, leader_speed: float) -> void:
	_crouch_left = maxf(0.0, _crouch_left - delta)
	if _hops_left > 0:
		_hop_t -= delta
		if _hop_t <= 0.0 and is_on_floor():
			wants_jump = true
			_hops_left -= 1
			_hop_t = 0.55
	_action_t -= delta
	if _action_t > 0.0:
		return
	var idle := leader_speed < 0.3
	_action_t = randf_range(4.0, 9.0) if idle else randf_range(7.0, 15.0)
	var roll := randf()
	if idle:
		if roll < 0.35:
			# Crouch and sniff a plant on the ground.
			_crouch_left = randf_range(1.2, 2.2)
			_idle_look = global_position + -global_basis.z * 0.6 + Vector3(0, -0.2, 0)
			_idle_look_t = _crouch_left
		elif roll < 0.6:
			_hops_left = randi_range(1, 3)
			_hop_t = 0.0
		elif roll < 0.9:
			# Wander a few steps to look at something.
			var a := randf() * TAU
			_wander = leader.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(0.8, 1.6)
			_wander.x = clampf(_wander.x, -Street.FENCE_X + 0.4, Street.FENCE_X - 0.4)
			_wander_left = randf_range(1.0, 2.5)
			_idle_look = _wander + Vector3(0, -0.1, 0)
			_idle_look_t = 3.0
	elif roll < 0.3:
		# A happy hop now and then while walking.
		_hops_left = 1
		_hop_t = 0.0


func _idle_behaviour(delta: float) -> void:
	_idle_look_t -= delta
	if _idle_look_t <= 0.0:
		_idle_look_t = randf_range(2.0, 5.0)
		if leader and randf() < 0.5:
			_idle_look = leader.global_position + Vector3(0, 0.3, 0)
		else:
			_idle_look = global_position + Vector3(randf_range(-3, 3), randf_range(0.2, 2.0), randf_range(-3, 3))
	creature.look_target = _idle_look
