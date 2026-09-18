class_name Airlock
extends Activatable

@export var door1_distance := 1.75
@export var door2_distance := 1.75
@export var move_speed := 3.5

@onready var door1: Node3D = $Cyclops/Door1
@onready var door2: Node3D = $Cyclops/Door2

var door1_closed_position: Vector3
var door2_closed_position: Vector3

var is_open := false


func _ready() -> void:
	door1_closed_position = door1.position
	door2_closed_position = door2.position


func _process(delta: float) -> void:
	var door1_target := door1_closed_position
	var door2_target := door2_closed_position

	if is_open:
		door1_target += Vector3(-door1_distance, 0.0, 0.0)
		door2_target += Vector3(door2_distance, 0.0, 0.0)

	door1.position = door1.position.lerp(
		door1_target,
		move_speed * delta
	)

	door2.position = door2.position.lerp(
		door2_target,
		move_speed * delta
	)


func activate() -> void:
	if not multiplayer.is_server():
		return

	is_open = !is_open

	print("AIRLOCK ACTIVATED: ", is_open)

	sync_state.rpc(is_open)


@rpc("authority", "call_local", "reliable")
func sync_state(new_state: bool) -> void:
	is_open = new_state
