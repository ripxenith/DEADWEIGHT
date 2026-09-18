extends Node3D


func _ready() -> void:
	# The server owns level objects by default.
	if multiplayer.is_server():
		set_multiplayer_authority(1)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
