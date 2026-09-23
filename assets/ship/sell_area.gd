class_name SellArea
extends Activatable


@onready var detection_area: Area3D = $sellarea
@onready var haul_label: Label3D = $sellarea/HaulLabel


var current_haul: int = 0


func _ready() -> void:
	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)

	update_haul()


# ============================================================
# AREA DETECTION
# ============================================================

func _on_body_entered(_body: Node3D) -> void:
	update_haul()


func _on_body_exited(_body: Node3D) -> void:
	update_haul()


func update_haul() -> void:
	current_haul = 0

	for body in detection_area.get_overlapping_bodies():

		if body is SellableObject:
			current_haul += body.sell_value

	update_haul_label()


func update_haul_label() -> void:
	if haul_label == null:
		return

	haul_label.text = "₡" + str(current_haul)


# ============================================================
# ACTIVATE
# ============================================================

func activate() -> void:

	# --------------------------------------------------------
	# CLIENT
	# --------------------------------------------------------

	if not multiplayer.is_server():

		request_sell.rpc_id(1)

		return


	# --------------------------------------------------------
	# SERVER
	# --------------------------------------------------------

	_process_sale()


# ============================================================
# REQUEST SALE
# ============================================================

@rpc("any_peer", "reliable")
func request_sell() -> void:

	if not multiplayer.is_server():
		return

	_process_sale()


# ============================================================
# PROCESS SALE
# ============================================================

func _process_sale() -> void:

	# ========================================================
	# FIND ITEMS
	# ========================================================

	var items_to_sell: Array[SellableObject] = []

	for body in detection_area.get_overlapping_bodies():

		if body is SellableObject:
			items_to_sell.append(body)


	if items_to_sell.is_empty():

		print_debug(
			"SELL AREA: Nothing to sell."
		)

		return


	# ========================================================
	# CALCULATE TOTAL
	# ========================================================

	var total_value: int = 0

	for item in items_to_sell:
		total_value += item.sell_value


	print_debug(
		"SELL AREA: Selling "
		+ str(items_to_sell.size())
		+ " items for $"
		+ str(total_value)
	)


	# ========================================================
	# GET CONNECTED PLAYERS
	# ========================================================

	var player_ids: Array[int] = (
		Network.get_connected_player_ids()
	)


	var player_count: int = player_ids.size()


	if player_count <= 0:

		print_debug(
			"SELL AREA ERROR: No players found."
		)

		return


	# ========================================================
	# SPLIT MONEY
	# ========================================================

	var money_per_player: int = (
		total_value / player_count
	)

	var leftover: int = (
		total_value % player_count
	)


	# ========================================================
	# GET HOST PLAYER ID
	# ========================================================

	var host_player_id: int = (
		Network.get_player_id(1)
	)


	if host_player_id <= 0:

		print_debug(
			"SELL AREA ERROR: Could not resolve host player ID."
		)

		return


	# ========================================================
	# GIVE EVERY PLAYER THEIR SHARE
	# ========================================================

	for player_id in player_ids:

		var amount: int = money_per_player


		if player_id == host_player_id:
			amount += leftover


		if player_id == host_player_id:

			SaveManager.add_player_money(
				player_id,
				amount
			)

		else:

			var player_peer_id := _get_peer_id_from_player_id(
				player_id
			)

			if player_peer_id > 0:

				receive_money.rpc_id(
					player_peer_id,
					player_id,
					amount
				)


		print_debug(
			"SELL AREA: Player "
			+ str(player_id)
			+ " receives $"
			+ str(amount)
		)


	# ========================================================
	# TRACK TOTAL SALES
	# ========================================================

	SaveManager.add_total_sales(
		total_value
	)


	# ========================================================
	# GET ITEM PATHS BEFORE DELETING
	# ========================================================

	var sold_item_paths: Array[NodePath] = []

	for item in items_to_sell:

		if is_instance_valid(item):

			sold_item_paths.append(
				item.get_path()
			)


	# ========================================================
	# DELETE ITEMS ON SERVER
	# ========================================================

	for item in items_to_sell:

		if is_instance_valid(item):
			item.queue_free()


	# ========================================================
	# TELL CLIENTS TO DELETE ITEMS
	# ========================================================

	delete_sold_items.rpc(
		sold_item_paths
	)


	# ========================================================
	# SAVE
	# ========================================================

	SaveManager.save_game()


	# ========================================================
	# UPDATE HOST DISPLAY
	# ========================================================

	current_haul = 0

	update_haul_label()


	print_debug(
		"SELL AREA: Sale complete. Total: $"
		+ str(total_value)
	)


# ============================================================
# FIND PEER FROM UNIVERSAL PLAYER ID
# ============================================================

func _get_peer_id_from_player_id(
	player_id: int
) -> int:

	var peer_ids: Array[int] = (
		Network.get_connected_peer_ids()
	)

	for peer_id in peer_ids:

		var resolved_player_id: int = (
			Network.get_player_id(peer_id)
		)

		if resolved_player_id == player_id:
			return peer_id

	return 0


# ============================================================
# CLIENT MONEY UPDATE
# ============================================================

@rpc("authority", "call_remote", "reliable")
func receive_money(
	player_id: int,
	amount: int
) -> void:

	if multiplayer.is_server():
		return

	SaveManager.add_player_money(
		player_id,
		amount
	)

	print_debug(
		"SELL AREA: Received $"
		+ str(amount)
		+ " from sale."
	)


# ============================================================
# DELETE SOLD ITEMS ON CLIENT
# ============================================================

@rpc("authority", "call_remote", "reliable")
func delete_sold_items(
	item_paths: Array[NodePath]
) -> void:

	for item_path in item_paths:

		var item := get_node_or_null(
			item_path
		)

		if item != null and is_instance_valid(item):

			item.queue_free()


	current_haul = 0

	update_haul_label()
