extends Node3D
## A static thing the player can use with E (plank, places to put things).
## The owning stage decides what happens; this only provides the prompt.

@export var prompt := ""
@export var reach := 1.0


func _ready() -> void:
	add_to_group("interactable")


func prompt_text() -> String:
	return prompt
