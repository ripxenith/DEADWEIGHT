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

	haul_label.text = "$" + str(current_haul)


# ============================================================
# SELL
# ============================================================

func activate() -> void:
	if not multiplayer.is_server():
		return

	var items_to_sell: Array[SellableObject] = []

	for body in detection_area.get_overlapping_bodies():
		if body is SellableObject:
			items_to_sell.append(body)

	if items_to_sell.is_empty():
		print_debug("SELL AREA: Nothing to sell.")
		return

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

	var player_count: int = multiplayer.get_peers().size() + 1 #Network.player_steam_ids.size()

	if player_count <= 0:
		print_debug("SELL AREA ERROR: No players found.")
		return

	# ========================================================
	# SPLIT MONEY
	# ========================================================

	var money_per_player: int = total_value / player_count
	var leftover: int = total_value % player_count

	print_debug(
		"SELL AREA: "
		+ str(player_count)
		+ " players"
	)

	print_debug(
		"SELL AREA: $"
		+ str(money_per_player)
		+ " per player"
	)

	# ========================================================
	# GIVE EVERY PLAYER THEIR SHARE
	# ========================================================

	for peer_id_variant in Network.player_steam_ids:
		var peer_id: int = int(peer_id_variant)

		var steam_id: int = int(
			Network.player_steam_ids[peer_id_variant]
		)

		var amount: int = money_per_player

		# Give any remainder to the host.
		if peer_id == 1:
			amount += leftover

		SaveManager.add_player_money(
			steam_id,
			amount
		)

		print_debug(
			"SELL AREA: "
			+ Network._get_player_name(peer_id)
			+ " receives $"
			+ str(amount)
		)

	# ========================================================
	# TRACK TOTAL SALES
	# ========================================================

	SaveManager.add_total_sales(total_value)

	# ========================================================
	# DELETE SOLD ITEMS
	# ========================================================

	for item in items_to_sell:
		if is_instance_valid(item):
			item.queue_free()

	# ========================================================
	# SAVE
	# ========================================================

	SaveManager.save_game()

	# ========================================================
	# UPDATE DISPLAY
	# ========================================================

	current_haul = 0
	update_haul_label()

	print_debug(
		"SELL AREA: Sale complete. Total: $"
		+ str(total_value)
	)
