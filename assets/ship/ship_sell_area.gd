extends Area3D

@onready var haul_label: Label3D = $HaulLabel

var current_haul: int = 0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	update_haul_label()


func _on_body_entered(body: Node3D) -> void:
	update_haul()


func _on_body_exited(body: Node3D) -> void:
	update_haul()


func update_haul() -> void:
	current_haul = 0

	for body in get_overlapping_bodies():
		if body is RigidBody3D:
			if "sell_value" in body:
				current_haul += body.sell_value

	update_haul_label()


func update_haul_label() -> void:
	haul_label.text = "$" + str(current_haul)
