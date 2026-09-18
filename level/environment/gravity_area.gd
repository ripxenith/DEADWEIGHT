extends Area3D

@export var zero_gravity := true

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("set_zero_gravity"):
		body.set_zero_gravity(false)


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("set_zero_gravity"):
		body.set_zero_gravity(zero_gravity)
