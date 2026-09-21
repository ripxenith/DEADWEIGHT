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

var network_mode: NetworkMode = NetworkMode.LOCAL


# ============================================================
# PEERS
# ============================================================

var peer: MultiplayerPeer


# ============================================================
# STEAM
# ============================================================

# Steam host's SteamID64 when joining through Steam.
var steam_host_id: int = 0


# ============================================================
# SPAWN ASSIGNMENTS
# ============================================================

# IMPORTANT:
#
# LAN peer IDs are:
#
# 1
# 2
# 3
# 4
#
# Steam peer IDs can be huge numbers such as:
#
# 1566542925
#
# Therefore we CANNOT do:
#
#     peer_id - 1
#
# to determine a spawn point.
#
# The server keeps a separate spawn slot for every peer.
#
# 1 = first spawn
# 2 = second spawn
# 3 = third spawn
# 4 = fourth spawn
#
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
# HOST
# ============================================================

func host_game() -> void:
	print("NETWORK: Starting host...")

	_close_peer()

	# Clear old Steam host information.
	steam_host_id = 0

	# Clear old spawn assignments.
	spawn_assignments.clear()

	match network_mode:

		# --------------------------------------------------------
		# LOCAL / LAN
		# --------------------------------------------------------

		NetworkMode.LOCAL:
			_start_local_host()

		# --------------------------------------------------------
		# STEAM
		# --------------------------------------------------------

		NetworkMode.STEAM:
			_start_steam_host()


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

	# Host is always peer 1 with ENet.
	spawn_assignments[1] = 0

	print(
		"NETWORK: Local host started on port ",
		PORT
	)

	_load_world()


func _start_steam_host() -> void:
	print("NETWORK: Starting STEAM host...")

	# SteamMultiplayerPeer is provided by the GodotSteam
	# MultiplayerPeer implementation.
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

	# Steam host is still the server.
	#
	# Godot's Multiplayer API treats the server as peer 1,
	# even though the underlying Steam identity is different.
	spawn_assignments[1] = 0

	print("NETWORK: Steam host started.")

	_load_world()


# ============================================================
# LOCAL CLIENT
# ============================================================

func join_local_game() -> void:
	print("NETWORK: Connecting to local host...")

	_close_peer()

	network_mode = NetworkMode.LOCAL

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
	# IMPORTANT:
	#
	# This is intentionally kept the same as your working
	# network.gd.
	#
	# Every peer locally spawns its own player.
	_spawn_local_player()

	# Clients tell the host when their world is actually ready.
	if not multiplayer.is_server():
		client_world_ready.rpc_id(1)


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

	# Search the entire world recursively.
	#
	# Any node that has a function named
	# "send_existing_to_peer" is considered a network
	# spawn system.
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

	# Don't spawn ourselves twice.
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

	var spawn_index := _get_local_spawn_index(
		peer_id
	)

	spawn_player.rpc(
		peer_id,
		spawn_index
	)


func _get_local_spawn_index(peer_id: int) -> int:
	# --------------------------------------------------------
	# SERVER
	# --------------------------------------------------------

	if multiplayer.is_server():

		if spawn_assignments.has(peer_id):
			return int(spawn_assignments[peer_id])

		var new_index := _get_next_spawn_index()

		spawn_assignments[peer_id] = new_index

		return new_index

	# --------------------------------------------------------
	# CLIENT
	# --------------------------------------------------------
	#
	# The server should have already assigned us a slot when
	# we receive the connection/spawn RPC.
	#
	# However, because the working LAN version locally spawned
	# the player immediately, we need a deterministic fallback.
	#
	# For LAN this preserves the original behavior:
	#
	# peer 2 -> spawn 1
	# peer 3 -> spawn 2
	# peer 4 -> spawn 3
	#
	# Steam cannot use the Steam ID directly, so we use the
	# order in which peer IDs are currently known.
	# --------------------------------------------------------

	if spawn_assignments.has(peer_id):
		return int(spawn_assignments[peer_id])

	if network_mode == NetworkMode.LOCAL:
		return clampi(
			peer_id - 1,
			0,
			MAX_PLAYERS - 1
		)

	# Steam client fallback.
	#
	# Normally the server's spawn_player RPC will give the
	# correct position before this matters.
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

	# Already exists.
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

	# Remember the assignment locally too.
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

	player.global_transform = spawn_point.global_transform

	print(
		"NETWORK: Spawned player ",
		peer_id,
		" at spawn ",
		spawn_index,
		" | Authority: ",
		player.get_multiplayer_authority()
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

	# --------------------------------------------------------
	# Assign this peer a spawn slot.
	# --------------------------------------------------------

	var spawn_index := _get_next_spawn_index()

	spawn_assignments[peer_id] = spawn_index

	print(
		"NETWORK: Assigned peer ",
		peer_id,
		" spawn slot ",
		spawn_index
	)

	# --------------------------------------------------------
	# Spawn the new player on everyone.
	# --------------------------------------------------------

	spawn_player.rpc(
		peer_id,
		spawn_index
	)

	# --------------------------------------------------------
	# Tell the new player about players that already exist.
	# --------------------------------------------------------

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

	# --------------------------------------------------------
	# Spawn the host for the new client.
	# --------------------------------------------------------

	var host_spawn_index := 0

	if spawn_assignments.has(1):
		host_spawn_index = int(
			spawn_assignments[1]
		)

	spawn_player.rpc_id(
		peer_id,
		1,
		host_spawn_index
	)


func _on_peer_disconnected(peer_id: int) -> void:
	print(
		"NETWORK: Peer disconnected: ",
		peer_id
	)

	var world := get_tree().current_scene

	if world == null:
		return

	var player := world.get_node_or_null(
		str(peer_id)
	)

	if player != null:
		player.queue_free()

	# Free their spawn slot.
	if spawn_assignments.has(peer_id):
		spawn_assignments.erase(peer_id)


func _on_server_disconnected() -> void:
	print(
		"NETWORK: Server disconnected."
	)

	_close_peer()

	spawn_assignments.clear()

	get_tree().change_scene_to_file(
		MAIN_MENU_SCENE
	)


func _on_connection_failed() -> void:
	print(
		"NETWORK ERROR: Connection failed."
	)

	_close_peer()

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
