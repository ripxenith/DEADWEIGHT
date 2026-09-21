extends Node

const PLAYER = preload("res://assets/player/player.tscn")

const WORLD_SCENE := "res://level/environment/open_world.tscn"
const MAIN_MENU_SCENE := "res://level/main menu.tscn"

const PORT := 9999
const MAX_PLAYERS := 4


# ============================================================
# NETWORK MODE
# ============================================================

enum NetworkMode {
	LOCAL,
	STEAM
}

var network_mode: NetworkMode = NetworkMode.STEAM


# ============================================================
# PEER
# ============================================================

var peer: MultiplayerPeer


# ============================================================
# UNIVERSAL PLAYER IDS
# ============================================================

var peer_ids: Dictionary = {}


# ============================================================
# LOCAL PLAYER ID
# ============================================================

const LOCAL_PLAYER_ID_OFFSET: int = 90000000000000000


# ============================================================
# STEAM
# ============================================================

var steam_host_id: int = 0


# ============================================================
# SPAWN ASSIGNMENTS
# ============================================================

var spawn_assignments: Dictionary = {}


# ============================================================
# READY
# ============================================================

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)

	print("NETWORK: Network manager ready.")


# ============================================================
# SERVER PEER ID
# ============================================================

func get_server_peer_id() -> int:
	if network_mode == NetworkMode.LOCAL:
		return 1

	if multiplayer.is_server():
		return multiplayer.get_unique_id()

	if steam_host_id > 0:
		return steam_host_id

	var local_steam_id := int(Steam.getSteamID())

	if local_steam_id > 0:
		return local_steam_id

	return 0


# ============================================================
# LOCAL PEER ID
# ============================================================

func get_local_peer_id() -> int:
	return multiplayer.get_unique_id()


# ============================================================
# MODE
# ============================================================

func set_network_mode(mode: NetworkMode) -> void:
	network_mode = mode

	match network_mode:
		NetworkMode.LOCAL:
			print("NETWORK: Mode set to LOCAL.")

		NetworkMode.STEAM:
			print("NETWORK: Mode set to STEAM.")


func use_local_network() -> void:
	set_network_mode(NetworkMode.LOCAL)


func use_steam_network() -> void:
	set_network_mode(NetworkMode.STEAM)


func is_using_steam() -> bool:
	return network_mode == NetworkMode.STEAM


# ============================================================
# PLAYER ID SYSTEM
# ============================================================

func get_player_id(peer_id: int) -> int:
	if peer_ids.has(peer_id):
		return int(peer_ids[peer_id])

	for player_id_variant in peer_ids.values():
		var player_id := int(player_id_variant)

		if player_id == peer_id:
			return player_id

	if network_mode == NetworkMode.LOCAL:
		var local_player_id := LOCAL_PLAYER_ID_OFFSET + peer_id

		peer_ids[peer_id] = local_player_id

		return local_player_id

	if peer_id > 0:
		if peer_id == multiplayer.get_unique_id():
			var local_steam_id := int(Steam.getSteamID())

			if local_steam_id > 0:
				peer_ids[peer_id] = local_steam_id
				return local_steam_id

		peer_ids[peer_id] = peer_id
		return peer_id

	print(
		"NETWORK WARNING: No player ID registered for peer ",
		peer_id
	)

	return 0


# ============================================================
# REGISTER LOCAL PLAYER ID
# ============================================================

func _register_local_player_id() -> void:
	var local_peer_id := multiplayer.get_unique_id()

	if network_mode == NetworkMode.LOCAL:
		var local_player_id := LOCAL_PLAYER_ID_OFFSET + local_peer_id

		peer_ids[local_peer_id] = local_player_id

		print(
			"NETWORK: Registered local player ID: ",
			local_player_id,
			" for peer ",
			local_peer_id
		)

		return

	var steam_id := int(Steam.getSteamID())

	if steam_id <= 0:
		print("NETWORK ERROR: Could not get local Steam ID.")
		return

	peer_ids[local_peer_id] = steam_id

	print(
		"NETWORK: Registered Steam player: ",
		steam_id,
		" for peer ",
		local_peer_id
	)

	if multiplayer.is_server():
		return

	var server_peer_id := get_server_peer_id()

	if server_peer_id <= 0:
		print(
			"NETWORK ERROR: Could not determine Steam server peer ID."
		)
		return

	register_player_id.rpc_id(
		server_peer_id,
		steam_id
	)


@rpc("any_peer", "reliable")
func register_player_id(player_id: int) -> void:
	if not multiplayer.is_server():
		return

	if network_mode != NetworkMode.STEAM:
		return

	var sender_peer_id := multiplayer.get_remote_sender_id()

	if player_id <= 0:
		print(
			"NETWORK WARNING: Invalid player ID received from peer ",
			sender_peer_id
		)
		return

	peer_ids[sender_peer_id] = player_id

	print(
		"NETWORK: Registered Steam player ",
		player_id,
		" for peer ",
		sender_peer_id
	)


# ============================================================
# CONNECTED PLAYER IDS
# ============================================================

func get_connected_player_ids() -> Array[int]:
	var result: Array[int] = []
	var connected_peers: Array[int] = []

	var server_peer_id := get_server_peer_id()

	if server_peer_id > 0:
		connected_peers.append(server_peer_id)

	for connected_peer in multiplayer.get_peers():
		if not connected_peers.has(connected_peer):
			connected_peers.append(connected_peer)

	for peer_id in connected_peers:
		var player_id := get_player_id(peer_id)

		if player_id <= 0:
			print(
				"NETWORK WARNING: Could not resolve player ID for peer ",
				peer_id
			)
			continue

		if not result.has(player_id):
			result.append(player_id)

	return result


# ============================================================
# CONNECTED PEERS
# ============================================================

func get_connected_peer_ids() -> Array[int]:
	var result: Array[int] = []

	var server_peer_id := get_server_peer_id()

	if server_peer_id > 0:
		result.append(server_peer_id)

	for peer_id in multiplayer.get_peers():
		if not result.has(peer_id):
			result.append(peer_id)

	return result


# ============================================================
# HOST
# ============================================================

func host_game() -> void:
	print("NETWORK: Starting host...")

	_close_peer()

	steam_host_id = 0
	peer_ids.clear()
	spawn_assignments.clear()

	match network_mode:
		NetworkMode.LOCAL:
			_start_local_host()

		NetworkMode.STEAM:
			_start_steam_host()


# ============================================================
# LOCAL HOST
# ============================================================

func _start_local_host() -> void:
	print("NETWORK: Starting LOCAL host...")

	var local_peer := ENetMultiplayerPeer.new()

	var error := local_peer.create_server(
		PORT,
		MAX_PLAYERS - 1
	)

	if error != OK:
		print(
			"NETWORK ERROR: Could not create local server: ",
			error
		)
		return

	peer = local_peer
	multiplayer.multiplayer_peer = peer

	spawn_assignments[1] = 0

	print(
		"NETWORK: Local host started on port ",
		PORT,
		" | Peer ID: ",
		multiplayer.get_unique_id()
	)

	_load_world()


# ============================================================
# STEAM HOST
# ============================================================

func _start_steam_host() -> void:
	print("NETWORK: Starting STEAM host...")

	var steam_peer := SteamMultiplayerPeer.new()

	var error := steam_peer.create_host(0)

	if error != OK:
		print(
			"NETWORK ERROR: Could not create Steam host: ",
			error
		)
		return

	peer = steam_peer
	multiplayer.multiplayer_peer = peer

	var host_peer_id := multiplayer.get_unique_id()
	var host_steam_id := int(Steam.getSteamID())

	if host_steam_id <= 0:
		print("NETWORK ERROR: Invalid Steam host ID.")
		_close_peer()
		return

	steam_host_id = host_steam_id

	spawn_assignments[host_peer_id] = 0

	print(
		"NETWORK: Steam host started.",
		" | Steam ID: ",
		host_steam_id,
		" | Peer ID: ",
		host_peer_id
	)

	_load_world()


# ============================================================
# LOCAL CLIENT
# ============================================================

func join_local_game() -> void:
	print("NETWORK: Connecting to local host...")

	_close_peer()

	network_mode = NetworkMode.LOCAL

	peer_ids.clear()
	spawn_assignments.clear()

	var local_peer := ENetMultiplayerPeer.new()

	var error := local_peer.create_client(
		"127.0.0.1",
		PORT
	)

	if error != OK:
		print(
			"NETWORK ERROR: Could not create local client: ",
			error
		)
		return

	peer = local_peer
	multiplayer.multiplayer_peer = peer

	print(
		"NETWORK: Connecting to 127.0.0.1:",
		PORT
	)

	_load_world()


# ============================================================
# STEAM CLIENT
# ============================================================

func join_steam_game(host_steam_id: int) -> void:
	print(
		"NETWORK: Connecting to Steam host: ",
		host_steam_id
	)

	_close_peer()

	network_mode = NetworkMode.STEAM

	steam_host_id = host_steam_id

	peer_ids.clear()
	spawn_assignments.clear()

	var steam_peer := SteamMultiplayerPeer.new()

	var error := steam_peer.create_client(
		host_steam_id,
		0
	)

	if error != OK:
		print(
			"NETWORK ERROR: Could not create Steam client: ",
			error
		)

		steam_host_id = 0
		return

	peer = steam_peer
	multiplayer.multiplayer_peer = peer

	print(
		"NETWORK: Connecting to Steam host: ",
		host_steam_id
	)

	_load_world()


# ============================================================
# WORLD
# ============================================================

func _load_world() -> void:
	if get_tree().current_scene != null:
		if get_tree().current_scene.scene_file_path == WORLD_SCENE:
			call_deferred("_world_ready")
			return

	get_tree().change_scene_to_file(WORLD_SCENE)

	call_deferred("_wait_for_world")


func _wait_for_world() -> void:
	while true:
		await get_tree().process_frame

		var world := get_tree().current_scene

		if world == null:
			continue

		if world.get_node_or_null("PlayerSpawns") == null:
			continue

		break

	_world_ready()


func _world_ready() -> void:
	_register_local_player_id()
	_spawn_local_player()

	if not multiplayer.is_server():
		var server_peer_id := get_server_peer_id()

		if server_peer_id > 0:
			client_world_ready.rpc_id(server_peer_id)


# ============================================================
# CLIENT READY
# ============================================================

@rpc("any_peer", "reliable")
func client_world_ready() -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()

	print(
		"NETWORK: Client world ready: ",
		peer_id
	)

	_send_existing_network_objects(peer_id)


func _send_existing_network_objects(peer_id: int) -> void:
	var world := get_tree().current_scene

	if world == null:
		print(
			"NETWORK ERROR: Cannot send objects. World is null."
		)
		return

	var network_objects: Array[Node] = []

	_find_network_spawnpoints(
		world,
		network_objects
	)

	print(
		"NETWORK: Found ",
		network_objects.size(),
		" network spawn systems for peer ",
		peer_id
	)

	for spawnpoint in network_objects:
		if not is_instance_valid(spawnpoint):
			continue

		print(
			"NETWORK: Sending existing objects from ",
			spawnpoint.get_path(),
			" to peer ",
			peer_id
		)

		spawnpoint.send_existing_to_peer(peer_id)


func _find_network_spawnpoints(
	node: Node,
	result: Array[Node]
) -> void:
	if node.has_method("send_existing_to_peer"):
		result.append(node)

	for child in node.get_children():
		_find_network_spawnpoints(
			child,
			result
		)


# ============================================================
# PLAYER SPAWNING
# ============================================================

func _spawn_local_player() -> void:
	var world := get_tree().current_scene

	if world == null:
		return

	var player_spawns := world.get_node_or_null(
		"PlayerSpawns"
	)

	if player_spawns == null:
		print(
			"NETWORK ERROR: PlayerSpawns not found."
		)
		return

	var peer_id := multiplayer.get_unique_id()

	if world.get_node_or_null(str(peer_id)) != null:
		return

	var spawn_points: Array[Node3D] = []

	for child in player_spawns.get_children():
		if child is Node3D:
			spawn_points.append(child)

	if spawn_points.is_empty():
		print(
			"NETWORK ERROR: No player spawn points."
		)
		return

	var spawn_index := _get_local_spawn_index(peer_id)

	spawn_player.rpc(
		peer_id,
		spawn_index
	)


func _get_local_spawn_index(peer_id: int) -> int:
	if multiplayer.is_server():
		if spawn_assignments.has(peer_id):
			return int(spawn_assignments[peer_id])

		var new_index := _get_next_spawn_index()

		spawn_assignments[peer_id] = new_index

		return new_index

	if spawn_assignments.has(peer_id):
		return int(spawn_assignments[peer_id])

	if network_mode == NetworkMode.LOCAL:
		return clampi(
			peer_id - 1,
			0,
			MAX_PLAYERS - 1
		)

	var used_slots: Dictionary = {}

	for value in spawn_assignments.values():
		used_slots[int(value)] = true

	for index in range(MAX_PLAYERS):
		if not used_slots.has(index):
			spawn_assignments[peer_id] = index
			return index

	return 0


func _get_next_spawn_index() -> int:
	var used_slots: Dictionary = {}

	for value in spawn_assignments.values():
		used_slots[int(value)] = true

	for index in range(MAX_PLAYERS):
		if not used_slots.has(index):
			return index

	return 0


# ============================================================
# SPAWN PLAYER
# ============================================================

@rpc("authority", "call_local", "reliable")
func spawn_player(
	peer_id: int,
	spawn_index: int
) -> void:
	var world := get_tree().current_scene

	if world == null:
		return

	var player_spawns := world.get_node_or_null(
		"PlayerSpawns"
	)

	if player_spawns == null:
		return

	if world.get_node_or_null(str(peer_id)) != null:
		return

	var spawn_points: Array[Node3D] = []

	for child in player_spawns.get_children():
		if child is Node3D:
			spawn_points.append(child)

	if spawn_points.is_empty():
		return

	spawn_index = clampi(
		spawn_index,
		0,
		spawn_points.size() - 1
	)

	spawn_assignments[peer_id] = spawn_index

	var player := PLAYER.instantiate()

	player.name = str(peer_id)

	world.add_child(
		player,
		true
	)

	player.set_multiplayer_authority(
		peer_id,
		true
	)

	var spawn_point := spawn_points[spawn_index]

	player.global_transform = (
		spawn_point.global_transform
	)

	print(
		"NETWORK: Spawned player ",
		peer_id,
		" at spawn ",
		spawn_index,
		" | Authority: ",
		player.get_multiplayer_authority(),
		" | Local Peer: ",
		multiplayer.get_unique_id(),
		" | Server Peer: ",
		get_server_peer_id()
	)


# ============================================================
# CONNECTION
# ============================================================

func _on_peer_connected(peer_id: int) -> void:
	print(
		"NETWORK: Peer connected: ",
		peer_id
	)

	if not multiplayer.is_server():
		return

	var spawn_index := _get_next_spawn_index()

	spawn_assignments[peer_id] = spawn_index

	print(
		"NETWORK: Assigned peer ",
		peer_id,
		" spawn slot ",
		spawn_index
	)

	spawn_player.rpc(
		peer_id,
		spawn_index
	)

	for existing_peer_id in multiplayer.get_peers():
		if existing_peer_id == peer_id:
			continue

		var existing_spawn_index := 0

		if spawn_assignments.has(existing_peer_id):
			existing_spawn_index = int(
				spawn_assignments[existing_peer_id]
			)
		else:
			existing_spawn_index = _get_next_spawn_index()

			spawn_assignments[existing_peer_id] = (
				existing_spawn_index
			)

		spawn_player.rpc_id(
			peer_id,
			existing_peer_id,
			existing_spawn_index
		)

	var host_peer_id := get_server_peer_id()

	var host_spawn_index := 0

	if spawn_assignments.has(host_peer_id):
		host_spawn_index = int(
			spawn_assignments[host_peer_id]
		)

	spawn_player.rpc_id(
		peer_id,
		host_peer_id,
		host_spawn_index
	)


# ============================================================
# DISCONNECTION
# ============================================================

func _on_peer_disconnected(peer_id: int) -> void:
	print(
		"NETWORK: Peer disconnected: ",
		peer_id
	)

	var world := get_tree().current_scene

	if world != null:
		var player := world.get_node_or_null(
			str(peer_id)
		)

		if player != null:
			player.queue_free()

	if peer_ids.has(peer_id):
		peer_ids.erase(peer_id)

	if spawn_assignments.has(peer_id):
		spawn_assignments.erase(peer_id)


# ============================================================
# SERVER DISCONNECTED
# ============================================================

func _on_server_disconnected() -> void:
	print(
		"NETWORK: Server disconnected."
	)

	_close_peer()

	peer_ids.clear()
	spawn_assignments.clear()

	get_tree().change_scene_to_file(
		MAIN_MENU_SCENE
	)


# ============================================================
# CONNECTION FAILED
# ============================================================

func _on_connection_failed() -> void:
	print(
		"NETWORK ERROR: Connection failed."
	)

	_close_peer()

	peer_ids.clear()
	spawn_assignments.clear()


# ============================================================
# CLEANUP
# ============================================================

func _close_peer() -> void:
	if peer != null:
		peer.close()

	peer = null

	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
