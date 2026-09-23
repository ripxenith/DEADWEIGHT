extends Node

# ============================================================
# NETWORK.GD
# ------------------------------------------------------------
# Autoload singleton that manages switching between Godot's
# built-in LOCAL (ENet) multiplayer and STEAM (GodotSteam)
# multiplayer, plus player spawning / player-id bookkeeping.
#
# USAGE FROM OTHER SCRIPTS:
#
#   if Network.LOCAL:
#       # do local-only stuff
#
#   if Network.STEAM:
#       # do steam-only stuff
#
# `Network.LOCAL` and `Network.STEAM` are live computed
# properties (not static consts) — they always reflect
# whatever `network_mode` currently is, so you never have to
# keep them in sync manually. Under the hood they just compare
# against `network_mode`, so `match network_mode:` still works
# too if you prefer that style.
# ============================================================

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

## Change this (or call use_local_network() / use_steam_network())
## to flip which backend the game uses. This is the single
## source of truth — everything else derives from it.
var network_mode: NetworkMode = NetworkMode.STEAM

## Live boolean, true when network_mode == NetworkMode.LOCAL.
## Lets other scripts write `if Network.LOCAL:`.
var LOCAL: bool:
	get:
		return network_mode == NetworkMode.LOCAL

## Live boolean, true when network_mode == NetworkMode.STEAM.
## Lets other scripts write `if Network.STEAM:`.
var STEAM: bool:
	get:
		return network_mode == NetworkMode.STEAM


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

	print(
		"NETWORK: Network manager ready. Mode: ",
		_mode_name()
	)


# ============================================================
# MODE HELPERS
# ============================================================

func _mode_name() -> String:
	match network_mode:
		NetworkMode.LOCAL:
			return "LOCAL"
		NetworkMode.STEAM:
			return "STEAM"

	return "UNKNOWN"


func set_network_mode(mode: NetworkMode) -> void:
	network_mode = mode
	print("NETWORK: Mode set to ", _mode_name(), ".")


## Switches the active backend to Godot's local ENet peer.
## Safe to call any time — does NOT start hosting/joining by
## itself, it only changes what host_game() / join_*_game()
## will do next. Useful for a debug toggle in a menu.
func use_local_network() -> void:
	set_network_mode(NetworkMode.LOCAL)


## Switches the active backend to Steam (GodotSteam).
func use_steam_network() -> void:
	set_network_mode(NetworkMode.STEAM)


## Kept for backwards compatibility with any existing code that
## already calls this. Equivalent to `Network.STEAM`.
func is_using_steam() -> bool:
	return STEAM


# ============================================================
# SERVER PEER ID
# ============================================================

func get_server_peer_id() -> int:
	# IMPORTANT:
	# This is the Godot MultiplayerPeer server ID.
	# It is NOT the Steam ID.
	#
	# SteamMultiplayerPeer.create_host(0) gives the host
	# Godot peer ID 1.

	return 1


# ============================================================
# LOCAL PEER ID
# ============================================================

func get_local_peer_id() -> int:
	return multiplayer.get_unique_id()


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

	if LOCAL:
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

	if LOCAL:
		var local_player_id := LOCAL_PLAYER_ID_OFFSET + local_peer_id

		peer_ids[local_peer_id] = local_player_id

		print(
			"NETWORK: Registered local player ID: ",
			local_player_id,
			" for peer ",
			local_peer_id
		)

		return

	# STEAM
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


@rpc("any_peer", "reliable")
func register_player_id(player_id: int) -> void:
	if not multiplayer.is_server():
		return

	if not STEAM:
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

	for peer_id in get_connected_peer_ids():
		var player_id := get_player_id(peer_id)

		if player_id <= 0:
			continue

		if not result.has(player_id):
			result.append(player_id)

	return result


# ============================================================
# CONNECTED PEERS
# ============================================================

func get_connected_peer_ids() -> Array[int]:
	var result: Array[int] = []

	# Server is always Godot peer 1.
	result.append(1)

	for peer_id in multiplayer.get_peers():
		if not result.has(peer_id):
			result.append(peer_id)

	return result


# ============================================================
# HOST
# ============================================================

## Starts hosting using whatever `network_mode` is currently
## set to. Flip modes with use_local_network() / use_steam_network()
## (or set network_mode directly) before calling this.
func host_game() -> void:
	print("NETWORK: Starting host in ", _mode_name(), " mode...")

	_close_peer()

	steam_host_id = 0
	peer_ids.clear()
	spawn_assignments.clear()

	if LOCAL:
		_start_local_host()
	elif STEAM:
		_start_steam_host()
	else:
		print("NETWORK ERROR: Unknown network mode, cannot host.")


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

## Joining always sets network_mode to match, so a client never
## ends up in a mismatched state relative to what it's actually
## connecting to.
func join_local_game() -> void:
	print("NETWORK: Connecting to local host...")

	_close_peer()

	use_local_network()

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

	use_steam_network()

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
	print(
		"NETWORK DEBUG: _world_ready() called.",
		" | Local Peer: ", multiplayer.get_unique_id(),
		" | Is Server: ", multiplayer.is_server(),
		" | Mode: ", _mode_name()
	)

	_register_local_player_id()

	if multiplayer.is_server():
		print("NETWORK DEBUG: THIS INSTANCE IS THE SERVER.")

		if not spawn_assignments.has(1):
			spawn_assignments[1] = 0

		print(
			"NETWORK DEBUG: Host spawn assignment = ",
			spawn_assignments[1]
		)

		_spawn_player_for_peer(1)
		return

	print(
		"NETWORK DEBUG: THIS INSTANCE IS A CLIENT.",
		" Waiting for server peer 1..."
	)

	var wait_time := 0.0
	const MAX_WAIT_TIME := 10.0

	while multiplayer.multiplayer_peer != null:
		if multiplayer.get_peers().has(1):
			break

		await get_tree().process_frame

		wait_time += get_process_delta_time()

		if wait_time >= MAX_WAIT_TIME:
			print(
				"NETWORK ERROR: Timed out waiting for server peer 1."
			)
			return

	if multiplayer.multiplayer_peer == null:
		print(
			"NETWORK ERROR: Multiplayer peer disappeared while waiting."
		)
		return

	print(
		"NETWORK DEBUG: Server peer 1 is connected.",
		" Sending client_world_ready."
	)

	var steam_id := 0

	if STEAM:
		steam_id = int(Steam.getSteamID())

	client_world_ready.rpc_id(1, steam_id)


# ============================================================
# CLIENT READY
# ============================================================

@rpc("any_peer", "reliable")
func client_world_ready(steam_id: int = 0) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()

	print(
		"NETWORK: Client world ready: ",
		peer_id
	)

	# Register Steam identity separately from Godot peer ID.
	if STEAM and steam_id > 0:
		peer_ids[peer_id] = steam_id

		print(
			"NETWORK: Registered Steam player: ",
			steam_id,
			" for peer ",
			peer_id
		)

	# Assign a spawn slot.
	if not spawn_assignments.has(peer_id):
		spawn_assignments[peer_id] = _get_next_spawn_index()

	# Spawn the client for everyone.
	_spawn_player_for_peer(peer_id)

	# Send all existing players to this client.
	for existing_peer_id in get_connected_peer_ids():
		if existing_peer_id == peer_id:
			continue

		if not world_has_player(existing_peer_id):
			continue

		var existing_spawn_index := 0

		if spawn_assignments.has(existing_peer_id):
			existing_spawn_index = int(
				spawn_assignments[existing_peer_id]
			)

		spawn_player.rpc_id(
			peer_id,
			existing_peer_id,
			existing_spawn_index
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
	
	# Send all existing players to this client.
	for existing_peer_id in get_connected_peer_ids():
		if existing_peer_id == peer_id:
			continue

		if not world_has_player(existing_peer_id):
			continue

		var existing_spawn_index := 0

		if spawn_assignments.has(existing_peer_id):
			existing_spawn_index = int(
				spawn_assignments[existing_peer_id]
			)

		spawn_player.rpc_id(
			peer_id,
			existing_peer_id,
			existing_spawn_index
		)

		# Make sure the existing player's synchronizer actually
		# pushes state to the newly connected peer.
		if world != null:
			var existing_player := world.get_node_or_null(
				str(existing_peer_id)
			)

			if existing_player != null:
				var sync := (
					existing_player.get_node_or_null(
						"MultiplayerSynchronizer"
					) as MultiplayerSynchronizer
				)

				if sync != null:
					sync.set_visibility_for(peer_id, true)
					sync.update_visibility(peer_id)
	
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

func _spawn_player_for_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		print(
			"NETWORK DEBUG: _spawn_player_for_peer() ignored because this is not the server."
		)
		return

	print(
		"NETWORK DEBUG: Server spawning peer ",
		peer_id
	)

	var world := get_tree().current_scene

	if world == null:
		print("NETWORK DEBUG: abort — current_scene is null.")
		return

	var player_spawns := world.get_node_or_null("PlayerSpawns")

	if player_spawns == null:
		print(
			"NETWORK ERROR: PlayerSpawns not found under ",
			world.get_path()
		)
		return

	if world.get_node_or_null(str(peer_id)) != null:
		print(
			"NETWORK DEBUG: Player ",
			peer_id,
			" already exists."
		)
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

	var spawn_index := _get_spawn_index(peer_id)

	print(
		"NETWORK DEBUG: Calling spawn_player.rpc(",
		peer_id,
		", ",
		spawn_index,
		")"
	)

	spawn_player.rpc(
		peer_id,
		spawn_index
	)


func _get_spawn_index(peer_id: int) -> int:
	if multiplayer.is_server():
		if spawn_assignments.has(peer_id):
			return int(spawn_assignments[peer_id])

		var new_index := _get_next_spawn_index()

		spawn_assignments[peer_id] = new_index

		return new_index

	if spawn_assignments.has(peer_id):
		return int(spawn_assignments[peer_id])

	if LOCAL:
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
	print("NETWORK DEBUG: spawn_player RPC received for peer ", peer_id)

	var world := get_tree().current_scene

	if world == null:
		print("NETWORK DEBUG: spawn_player abort — current_scene is null.")
		return

	var player_spawns := world.get_node_or_null(
		"PlayerSpawns"
	)

	if player_spawns == null:
		print("NETWORK DEBUG: spawn_player abort — PlayerSpawns not found.")
		return

	if world.get_node_or_null(str(peer_id)) != null:
		print(
			"NETWORK DEBUG: spawn_player abort — node '",
			peer_id,
			"' already exists."
		)
		return

	var spawn_points: Array[Node3D] = []

	for child in player_spawns.get_children():
		if child is Node3D:
			spawn_points.append(child)

	if spawn_points.is_empty():
		print("NETWORK DEBUG: spawn_player abort — no spawn points.")
		return

	spawn_index = clampi(
		spawn_index,
		0,
		spawn_points.size() - 1
	)

	spawn_assignments[peer_id] = spawn_index

	var player := PLAYER.instantiate()

	player.name = str(peer_id)

	player.set_multiplayer_authority(
		peer_id,
		true
	)

	world.add_child(
		player,
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

	# Peer 1 is the host.
	if peer_id == 1:
		return

	if not spawn_assignments.has(peer_id):
		var spawn_index := _get_next_spawn_index()

		spawn_assignments[peer_id] = spawn_index

		print(
			"NETWORK: Assigned peer ",
			peer_id,
			" spawn slot ",
			spawn_index
		)

	print(
		"NETWORK: Waiting for peer ",
		peer_id,
		" to report world ready."
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


func world_has_player(peer_id: int) -> bool:
	var world := get_tree().current_scene

	if world == null:
		return false

	return world.get_node_or_null(str(peer_id)) != null
