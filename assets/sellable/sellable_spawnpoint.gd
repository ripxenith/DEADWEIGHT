extends Marker3D
class_name Sellable_Spawnpoint


@export_category("Spawn Settings")

@export var possible_items: Array[PackedScene] = []


var spawned_item: Node3D = null


func _ready() -> void:
	add_to_group("SellableSpawnpoints")

	# Only the host creates the initial objects.
	if multiplayer.has_multiplayer_peer():
		if not multiplayer.is_server():
			return

	call_deferred("spawn_item")


func spawn_item() -> void:
	if not multiplayer.is_server():
		return

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

	# --------------------------------------------------------
	# HOST CHOOSES THE ITEM
	# --------------------------------------------------------

	var random_index: int = randi_range(
		0,
		valid_items.size() - 1
	)

	var item_scene: PackedScene = (
		valid_items[random_index]
	)

	# --------------------------------------------------------
	# CREATE ITEM ON HOST
	# --------------------------------------------------------

	var new_item: Node = (
		item_scene.instantiate()
	)

	if new_item == null:
		push_warning(
			"Failed to instantiate item at: "
			+ str(get_path())
		)
		return

	var sellable := new_item as SellableObject

	if sellable == null:
		push_warning(
			"Spawned scene is not a SellableObject: "
			+ item_scene.resource_path
		)

		new_item.queue_free()
		return

	# Server is peer 1 and therefore the authority.
	sellable.set_multiplayer_authority(1)

	# Add it to the world.
	get_parent().add_child(
		sellable,
		true
	)

	sellable.global_transform = global_transform

	# --------------------------------------------------------
	# GENERATE RANDOM DATA ONCE
	# --------------------------------------------------------

	sellable.generate_value()

	var generated_rarity: String = (
		sellable.rarity
	)

	var generated_value: int = (
		sellable.sell_value
	)

	# --------------------------------------------------------
	# TRACK HOST COPY
	# --------------------------------------------------------

	spawned_item = sellable

	spawned_item.tree_exited.connect(
		_on_spawned_item_removed
	)

	# --------------------------------------------------------
	# TELL CLIENTS TO CREATE THE SAME OBJECT
	# --------------------------------------------------------

	spawn_sellable.rpc(
		item_scene.resource_path,
		global_transform,
		generated_rarity,
		generated_value
	)

	print(
		"SPAWNED SELLABLE: ",
		item_scene.resource_path,
		" | ",
		generated_rarity,
		" | $",
		generated_value
	)


@rpc(
	"authority",
	"call_remote",
	"reliable"
)
func spawn_sellable(
	scene_path: String,
	item_transform: Transform3D,
	item_rarity: String,
	item_value: int
) -> void:

	# Host already created its own copy.
	if multiplayer.is_server():
		return

	# --------------------------------------------------------
	# PREVENT DUPLICATES
	# --------------------------------------------------------

	if is_instance_valid(spawned_item):
		return

	# --------------------------------------------------------
	# LOAD THE EXACT SAME SCENE
	# --------------------------------------------------------

	var item_scene: PackedScene = (
		load(scene_path) as PackedScene
	)

	if item_scene == null:
		push_warning(
			"Could not load networked sellable: "
			+ scene_path
		)
		return

	var new_item: Node = (
		item_scene.instantiate()
	)

	if new_item == null:
		push_warning(
			"Failed to instantiate networked sellable."
		)
		return

	var sellable := new_item as SellableObject

	if sellable == null:
		push_warning(
			"Networked scene is not a SellableObject: "
			+ scene_path
		)

		new_item.queue_free()
		return

	# --------------------------------------------------------
	# ADD TO WORLD
	# --------------------------------------------------------

	get_parent().add_child(
		sellable,
		true
	)

	# --------------------------------------------------------
	# USE HOST-GENERATED DATA
	# --------------------------------------------------------

	sellable.rarity = item_rarity
	sellable.sell_value = item_value

	sellable.global_transform = item_transform

	spawned_item = sellable

	spawned_item.tree_exited.connect(
		_on_spawned_item_removed
	)

	print(
		"RECEIVED NETWORKED SELLABLE: ",
		scene_path,
		" | ",
		item_rarity,
		" | $",
		item_value
	)


func _on_spawned_item_removed() -> void:
	spawned_item = null
