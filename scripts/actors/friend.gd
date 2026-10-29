class_name Friend
extends Hero
## Fialka, the AI companion. Follows the player at a comfortable distance,
## catches up by running, looks around when idle, can be sent to a spot
## (hiding, scripted moves) with `go_to`.

var leader: Node3D
var _goal := Vector3.INF
var _goal_done: Callable
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _idle_look_t := 0.0
var _idle_look := Vector3.ZERO


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
		if dist > 0.35:
			wish_dir = to.normalized() * clampf(dist / 1.2, 0.35, 1.0)
		wants_run = dist > 2.2 or leader_speed > 2.0
		wants_crouch = leader is Hero and (leader as Hero).wants_crouch
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


func _idle_behaviour(delta: float) -> void:
	_idle_look_t -= delta
	if _idle_look_t <= 0.0:
		_idle_look_t = randf_range(2.0, 5.0)
		if leader and randf() < 0.5:
			_idle_look = leader.global_position + Vector3(0, 0.3, 0)
		else:
			_idle_look = global_position + Vector3(randf_range(-3, 3), randf_range(0.2, 2.0), randf_range(-3, 3))
	creature.look_target = _idle_look
