class_name Player
extends Hero
## Busik, controlled by the player. Movement is relative to the camera yaw.

signal interacted(target: Node)

var camera_rig: CameraRig
var focus: Node3D = null        # nearest interactable within reach
var force_crouch := false       # cutscenes and automated tests


func _ready() -> void:
	_init_body(preload("res://assets/characters/busik.glb"), Color(0.12, 0.35, 0.85), Color(0.16, 0.36, 0.93))
	creature.footsteps = true


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if camera_rig and not frozen:
		var yaw := camera_rig.yaw
		wish_dir = Vector3(input.x, 0, input.y).rotated(Vector3.UP, yaw)
		wants_run = Input.is_action_pressed("run")
		wants_crouch = Input.is_action_pressed("crouch") or force_crouch
		if Input.is_action_just_pressed("jump"):
			wants_jump = true
	super(delta)
	if camera_rig and camera_rig.first_person:
		rotation.y = camera_rig.yaw
	_update_focus()


func set_first_person(on: bool) -> void:
	creature.set_body_visible(not on)


func _update_focus() -> void:
	var best: Node3D = null
	var best_d := 99.0
	for n: Node3D in get_tree().get_nodes_in_group("interactable"):
		if not n.visible:
			continue
		var d := n.global_position.distance_to(global_position + Vector3(0, 0.2, 0))
		var reach: float = n.get("reach") if n.get("reach") != null else 1.0
		if d < reach and d < best_d:
			best_d = d
			best = n
	focus = best
	creature.look_target = focus.global_position if focus else Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and focus and not frozen:
		interacted.emit(focus)
		get_viewport().set_input_as_handled()


func _face_camera() -> bool:
	return camera_rig != null and camera_rig.first_person
