extends Node


const PLAYER = preload("res://assets/player/player.tscn")

const WORLD_SCENE := "res://level/environment/open_world.tscn"
const MAIN_MENU_SCENE := "res://level/main menu.tscn"

const PORT := 9999
const MAX_PLAYERS := 4


var peer: ENetMultiplayerPeer


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)


# ============================================================
# HOST
# ============================================================

func host_game() -> void:
	print("NETWORK: Starting host...")

	_close_peer()

	peer = ENetMultiplayerPeer.new()

	var error := peer.create_server(
		PORT,
		MAX_PLAYERS - 1
	)

	if error != OK:
		print("NETWORK ERROR: Could not create server: ", error)
		return

	multiplayer.multiplayer_peer = peer

	print("NETWORK: Host started on port ", PORT)

	_load_world()


# ============================================================
# CLIENT
# ============================================================

func join_local_game() -> void:
	print("NETWORK: Connecting to host...")

	_close_peer()

	peer = ENetMultiplayerPeer.new()

	var error := peer.create_client(
		"127.0.0.1",
		PORT
	)

	if error != OK:
		print("NETWORK ERROR: Could not create client: ", error)
		return

	multiplayer.multiplayer_peer = peer

	print("NETWORK: Connecting to 127.0.0.1:", PORT)

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
		print("NETWORK ERROR: Cannot send objects. World is null.")
		return

	var network_objects: Array[Node] = []

	# Search the entire world recursively.
	#
	# Any node that has a function named
	# "send_existing_to_peer" is considered a network
	# spawn system.
	#
	# This means network.gd does NOT need to know about
	# sellables, enemies, loot, etc.
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
		print("NETWORK ERROR: PlayerSpawns not found.")
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
		print("NETWORK ERROR: No player spawn points.")
		return

	var spawn_index := peer_id - 1

	spawn_index = clampi(
		spawn_index,
		0,
		spawn_points.size() - 1
	)

	spawn_player.rpc(
		peer_id,
		spawn_index
	)


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
	print("NETWORK: Peer connected: ", peer_id)

	if not multiplayer.is_server():
		return

	# Spawn the new player on everyone.
	var spawn_index := peer_id - 1

	spawn_player.rpc(
		peer_id,
		spawn_index
	)

	# Tell the new player about players that already exist.
	for existing_peer_id in multiplayer.get_peers():
		if existing_peer_id == peer_id:
			continue

		spawn_player.rpc_id(
			peer_id,
			existing_peer_id,
			existing_peer_id - 1
		)

	# Spawn the host for the new client.
	spawn_player.rpc_id(
		peer_id,
		1,
		0
	)


func _on_peer_disconnected(peer_id: int) -> void:
	print("NETWORK: Peer disconnected: ", peer_id)

	var world := get_tree().current_scene

	if world == null:
		return

	var player := world.get_node_or_null(
		str(peer_id)
	)

	if player != null:
		player.queue_free()


func _on_server_disconnected() -> void:
	print("NETWORK: Server disconnected.")

	_close_peer()

	get_tree().change_scene_to_file(
		MAIN_MENU_SCENE
	)


func _on_connection_failed() -> void:
	print("NETWORK ERROR: Connection failed.")

	_close_peer()


# ============================================================
# CLEANUP
# ============================================================

func _close_peer() -> void:
	if peer != null:
		peer.close()

	peer = null

	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
