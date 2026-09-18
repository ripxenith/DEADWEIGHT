extends Node

const PLAYER = preload("res://assets/player/player.tscn")

var enet_peer := ENetMultiplayerPeer.new()

var PORT = 9999
var IP_ADDRESS = "127.0.0.1"

# Server keeps track of which spawn each player is using.
var player_spawn_indices: Dictionary = {}


func start_server():
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer

	if not multiplayer.peer_connected.is_connected(add_player):
		multiplayer.peer_connected.connect(add_player)

	if not multiplayer.peer_disconnected.is_connected(remove_player):
		multiplayer.peer_disconnected.connect(remove_player)


func join_server():
	enet_peer.create_client(IP_ADDRESS, PORT)

	if not multiplayer.peer_connected.is_connected(add_player):
		multiplayer.peer_connected.connect(add_player)

	if not multiplayer.peer_disconnected.is_connected(remove_player):
		multiplayer.peer_disconnected.connect(remove_player)

	if not multiplayer.connected_to_server.is_connected(on_connected_to_server):
		multiplayer.connected_to_server.connect(on_connected_to_server)

	if not multiplayer.server_disconnected.is_connected(on_server_disconnected):
		multiplayer.server_disconnected.connect(on_server_disconnected)

	multiplayer.multiplayer_peer = enet_peer


func on_connected_to_server():
	# The server handles spawning.
	pass


func on_server_disconnected():
	print_debug("Server disconnected. Returning to main menu.")

	# Stop the client from trying to use the dead ENet connection.
	clean_up_signals()

	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()

	multiplayer.multiplayer_peer = null

	player_spawn_indices.clear()

	# Return to the main menu.
	get_tree().change_scene_to_file("res://level/main menu.tscn")


func add_player(peer_id: int):
	# Only the server assigns spawn points.
	if not multiplayer.is_server():
		return

	# Don't assign the same player twice.
	if player_spawn_indices.has(peer_id):
		return

	# Find PlayerSpawns anywhere in the scene tree.
	var spawn_container: Node3D = null

	while spawn_container == null:
		spawn_container = get_tree().root.find_child(
			"PlayerSpawns",
			true,
			false
		)

		if spawn_container == null:
			await get_tree().process_frame

	var spawn_points := spawn_container.get_children()

	if spawn_points.is_empty():
		print_debug("ERROR: No spawn points found!")
		return

	# Find the first unused spawn point.
	var spawn_index := get_available_spawn_index(spawn_points.size())

	if spawn_index == -1:
		print_debug("ERROR: No available spawn points!")
		return

	# Remember the assignment on the server.
	player_spawn_indices[peer_id] = spawn_index

	print_debug(
		"Assigning Player "
		+ str(peer_id)
		+ " to "
		+ spawn_points[spawn_index].name
	)

	# Spawn the new player for EVERYONE.
	spawn_player.rpc(peer_id, spawn_index)

	# If this is a newly connected client, send them
	# all players that already existed before they joined.
	for existing_peer_id in player_spawn_indices:
		if existing_peer_id == peer_id:
			continue

		var existing_spawn_index: int = player_spawn_indices[existing_peer_id]

		spawn_player.rpc_id(
			peer_id,
			existing_peer_id,
			existing_spawn_index
		)


func get_available_spawn_index(spawn_count: int) -> int:
	for i in range(spawn_count):
		if not player_spawn_indices.values().has(i):
			return i

	return -1


@rpc("authority", "call_local", "reliable")
func spawn_player(peer_id: int, spawn_index: int):
	# Don't spawn the same player twice.
	var existing_players := get_tree().get_nodes_in_group("Players")

	for player in existing_players:
		if player.name == str(peer_id):
			return

	# Find PlayerSpawns.
	var spawn_container: Node3D = null

	while spawn_container == null:
		spawn_container = get_tree().root.find_child(
			"PlayerSpawns",
			true,
			false
		)

		if spawn_container == null:
			await get_tree().process_frame

	var spawn_points := spawn_container.get_children()

	if spawn_index < 0 or spawn_index >= spawn_points.size():
		print_debug("ERROR: Invalid spawn index!")
		return

	var spawn_point: Marker3D = spawn_points[spawn_index]

	# Create player.
	var new_player = PLAYER.instantiate()
	new_player.name = str(peer_id)

	# Add player to the world containing PlayerSpawns.
	var world = spawn_container.get_parent()
	world.add_child(new_player, true)

	# Teleport player to assigned spawn.
	new_player.global_position = spawn_point.global_position
	new_player.global_rotation = spawn_point.global_rotation

	print_debug(
		"Player "
		+ str(peer_id)
		+ " spawned at "
		+ spawn_point.name
	)


func remove_player(peer_id: int):
	# Only the server manages player assignments.
	if not multiplayer.is_server():
		return

	# Free the player's spawn point.
	if player_spawn_indices.has(peer_id):
		player_spawn_indices.erase(peer_id)

	# Tell everyone to remove this player.
	remove_player_rpc.rpc(peer_id)

	print_debug("Removing player " + str(peer_id))


@rpc("authority", "call_local", "reliable")
func remove_player_rpc(peer_id: int):
	var players: Array[Node] = get_tree().get_nodes_in_group("Players")

	for player in players:
		if player.name == str(peer_id):
			player.queue_free()
			return


func leave_server():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()

	multiplayer.multiplayer_peer = null

	player_spawn_indices.clear()

	clean_up_signals()

	get_tree().change_scene_to_file("res://level/main menu.tscn")


func clean_up_signals():
	if multiplayer.peer_connected.is_connected(add_player):
		multiplayer.peer_connected.disconnect(add_player)

	if multiplayer.peer_disconnected.is_connected(remove_player):
		multiplayer.peer_disconnected.disconnect(remove_player)

	if multiplayer.connected_to_server.is_connected(on_connected_to_server):
		multiplayer.connected_to_server.disconnect(on_connected_to_server)

	if multiplayer.server_disconnected.is_connected(on_server_disconnected):
		multiplayer.server_disconnected.disconnect(on_server_disconnected)
