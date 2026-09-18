extends Marker3D
class_name Sellable_Spawnpoint

@export_category("Spawn Settings")
@export var possible_items: Array[PackedScene] = []

var spawned_item: Node3D = null


func _ready() -> void:
	add_to_group("SellableSpawnpoints")

	# Only the host spawns items.
	if multiplayer.has_multiplayer_peer():
		if not multiplayer.is_server():
			return

	# Wait until the scene has finished adding all of its children.
	call_deferred("spawn_item")


func spawn_item() -> void:
	if possible_items.is_empty():
		push_warning(
			"Sellable_Spawnpoint has no possible items: "
			+ str(get_path())
		)
		return

	if is_instance_valid(spawned_item):
		return

	var valid_items: Array[PackedScene] = []

	for item_scene in possible_items:
		if item_scene != null:
			valid_items.append(item_scene)

	if valid_items.is_empty():
		push_warning(
			"Sellable_Spawnpoint has no valid item scenes: "
			+ str(get_path())
		)
		return

	var random_index: int = randi_range(
		0,
		valid_items.size() - 1
	)

	var item_scene: PackedScene = valid_items[random_index]

	spawned_item = item_scene.instantiate()

	if spawned_item == null:
		push_warning(
			"Failed to instantiate item at: "
			+ str(get_path())
		)
		return

	# Add the item after the parent has finished setting up.
	get_parent().add_child.call_deferred(spawned_item, true)

	# Host owns the spawned item.
	if multiplayer.has_multiplayer_peer():
		spawned_item.set_multiplayer_authority(1)

	# Set the transform after the item is added.
	spawned_item.global_transform = global_transform

	spawned_item.tree_exited.connect(
		_on_spawned_item_removed
	)

	print(
		"Spawned item: ",
		item_scene.resource_path,
		" at ",
		get_path()
	)


func _on_spawned_item_removed() -> void:
	spawned_item = null
