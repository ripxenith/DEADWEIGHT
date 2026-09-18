class_name InteractableButton
extends StaticBody3D

@export var target: Activatable


func interact() -> void:
	print("BUTTON INTERACTED: ", name)

	if multiplayer.is_server():
		activate_target()
	else:
		request_activation.rpc_id(1)


@rpc("any_peer", "reliable")
func request_activation() -> void:
	if not multiplayer.is_server():
		return

	activate_target()


func activate_target() -> void:
	if target == null:
		push_warning("Button '%s' has no target assigned!" % name)
		return

	print("BUTTON ACTIVATING: ", target.name)

	target.activate()
