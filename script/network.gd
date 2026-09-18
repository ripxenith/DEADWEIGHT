extends Node


const PLAYER = preload("res://assets/player/player.tscn")
const WORLD_SCENE := "res://level/environment/open_world.tscn"
const MAIN_MENU_SCENE := "res://level/main menu.tscn"

const MAX_PLAYERS := 4


var steam_peer: SteamMultiplayerPeer = null

var current_lobby_id: int = 0
var host_steam_id: int = 0

var world_loaded := false
var is_host := false

# Stores which spawn point belongs to each peer.
# Example:
# 1 -> 0
# 1668488921 -> 1
var player_spawn_indices: Dictionary = {}


func _ready() -> void:
	print_debug("Network initialized.")

	_connect_steam_signals()
	_connect_multiplayer_signals()

	_check_command_line_lobby()


# ============================================================
# STEAM SIGNALS
# ============================================================

func _connect_steam_signals() -> void:
	if not Steam.is_connected("lobby_created", _on_lobby_created):
		Steam.connect("lobby_created", _on_lobby_created)

	if not Steam.is_connected("lobby_joined", _on_lobby_joined):
		Steam.connect("lobby_joined", _on_lobby_joined)

	if not Steam.is_connected("join_requested", _on_join_requested):
		Steam.connect("join_requested", _on_join_requested)


# ============================================================
# MULTIPLAYER SIGNALS
# ============================================================

func _connect_multiplayer_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)

	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)

	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)

	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


# ============================================================
# HOST GAME
# ============================================================

func host_game() -> void:
	print_debug("Host Game requested.")

	is_host = true
	world_loaded = false

	player_spawn_indices.clear()

	print_debug("Creating Steam friends-only lobby...")

	Steam.createLobby(
		Steam.LOBBY_TYPE_FRIENDS_ONLY,
		MAX_PLAYERS
	)


func _on_lobby_created(result: int, lobby_id: int) -> void:
	print_debug("Steam lobby created callback.")
	print_debug("Result: " + str(result))
	print_debug("Lobby ID: " + str(lobby_id))

	if result != 1:
		print_debug("ERROR: Failed to create Steam lobby.")
		is_host = false
		return

	current_lobby_id = lobby_id

	var steam_id: int = Steam.getSteamID()
	var player_name: String = Steam.getPersonaName()

	host_steam_id = steam_id

	Steam.setLobbyData(
		current_lobby_id,
		"name",
		player_name + "'s Lobby"
	)

	Steam.setLobbyData(
		current_lobby_id,
		"host_steam_id",
		str(steam_id)
	)

	Steam.setLobbyData(
		current_lobby_id,
		"game",
		"DEADWEIGHT"
	)

	print_debug("Steam lobby ready.")
	print_debug("Lobby ID: " + str(current_lobby_id))
	print_debug("Host Steam ID: " + str(host_steam_id))

	start_steam_host()

	if not multiplayer.has_multiplayer_peer():
		print_debug("ERROR: Steam host was not created.")
		return

	await transition_to_world()

	if not world_loaded:
		print_debug("ERROR: World failed to load.")
		return

	await get_tree().process_frame

	print_debug("Host world ready. Spawning host.")

	add_player(1)


# ============================================================
# START STEAM HOST
# ============================================================

func start_steam_host() -> void:
	print_debug("Starting Steam multiplayer host.")

	_close_existing_peer()

	steam_peer = SteamMultiplayerPeer.new()

	var error: Error = steam_peer.create_host(0)

	if error != OK:
		print_debug(
			"ERROR: Failed to create Steam host. Error: "
			+ str(error)
		)

		steam_peer = null
		return

	multiplayer.multiplayer_peer = steam_peer

	print_debug("Steam multiplayer host started.")
	print_debug(
		"Host peer ID: "
		+ str(multiplayer.get_unique_id())
	)


# ============================================================
# STEAM INVITES
# ============================================================

func _on_join_requested(
	requested_lobby_id: int,
	steam_id: int
) -> void:
	print_debug("Steam invite accepted!")
	print_debug("Lobby: " + str(requested_lobby_id))
	print_debug("Invited by: " + str(steam_id))

	join_lobby(requested_lobby_id)


func show_invite_dialog() -> void:
	if current_lobby_id == 0:
		print_debug("ERROR: No Steam lobby exists.")
		return

	print_debug("Opening Steam invite dialog.")

	Steam.activateGameOverlayInviteDialog(
		current_lobby_id
	)


# ============================================================
# JOIN LOBBY
# ============================================================

func join_lobby(lobby_id: int) -> void:
	if lobby_id <= 0:
		print_debug("ERROR: Invalid lobby ID.")
		return

	if lobby_id == current_lobby_id and is_host:
		print_debug("Already hosting this lobby.")
		return

	print_debug(
		"Joining Steam lobby: "
		+ str(lobby_id)
	)

	is_host = false
	world_loaded = false

	player_spawn_indices.clear()

	Steam.joinLobby(lobby_id)


func _on_lobby_joined(
	lobby_id: int,
	permissions: int,
	locked: bool,
	response: int
) -> void:
	print_debug("Steam lobby joined.")
	print_debug("Lobby ID: " + str(lobby_id))
	print_debug("Response: " + str(response))

	if is_host:
		print_debug(
			"Ignoring lobby_joined because we are the host."
		)
		return

	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		print_debug("ERROR: Failed to join Steam lobby.")
		return

	current_lobby_id = lobby_id

	host_steam_id = Steam.getLobbyOwner(
		current_lobby_id
	)

	print_debug(
		"Lobby owner: "
		+ str(host_steam_id)
	)

	var members := Steam.getNumLobbyMembers(
		current_lobby_id
	)

	print_debug(
		"Lobby members: "
		+ str(members)
	)

	for i in range(members):
		var member_id: int = Steam.getLobbyMemberByIndex(
			current_lobby_id,
			i
		)

		var member_name: String = Steam.getFriendPersonaName(
			member_id
		)

		print_debug(
			"Lobby member: "
			+ member_name
			+ " ("
			+ str(member_id)
			+ ")"
		)

	is_host = false
	world_loaded = false

	await transition_to_world()

	if not world_loaded:
		print_debug(
			"ERROR: World failed to load."
		)
		return

	await get_tree().process_frame

	print_debug(
		"Client world ready. Starting Steam client."
	)

	start_steam_client(host_steam_id)


# ============================================================
# START STEAM CLIENT
# ============================================================

func start_steam_client(
	target_host_steam_id: int
) -> void:
	print_debug("Starting Steam multiplayer client.")

	print_debug(
		"Host Steam ID: "
		+ str(target_host_steam_id)
	)

	_close_existing_peer()

	steam_peer = SteamMultiplayerPeer.new()

	var error: Error = steam_peer.create_client(
		target_host_steam_id,
		0
	)

	if error != OK:
		print_debug(
			"ERROR: Failed to create Steam client. Error: "
			+ str(error)
		)

		steam_peer = null
		return

	multiplayer.multiplayer_peer = steam_peer

	print_debug(
		"Steam multiplayer client started."
	)

	print_debug(
		"Host: "
		+ str(target_host_steam_id)
	)


# ============================================================
# SCENE TRANSITION
# ============================================================

func transition_to_world() -> void:
	var current_scene := get_tree().current_scene

	if current_scene != null:
		if current_scene.scene_file_path == WORLD_SCENE:
			print_debug(
				"Already in open_world."
			)

			world_loaded = true

			await get_tree().process_frame

			return

	print_debug(
		"Transitioning to open_world..."
	)

	world_loaded = false

	var error := get_tree().change_scene_to_file(
		WORLD_SCENE
	)

	if error != OK:
		print_debug(
			"ERROR: Failed to transition to open_world. Error: "
			+ str(error)
		)
		return

	await get_tree().scene_changed

	await get_tree().process_frame

	current_scene = get_tree().current_scene

	if current_scene == null:
		print_debug(
			"ERROR: Current scene is null after transition."
		)
		return

	print_debug(
		"World scene loaded: "
		+ current_scene.name
	)

	var spawn_container: Node3D = null

	while spawn_container == null:
		spawn_container = get_tree().root.find_child(
			"PlayerSpawns",
			true,
			false
		) as Node3D

		if spawn_container == null:
			await get_tree().process_frame

	print_debug(
		"PlayerSpawns found at: "
		+ str(spawn_container.get_path())
	)

	world_loaded = true

	print_debug(
		"World is fully ready."
	)


# ============================================================
# COMMAND LINE STEAM INVITE
# ============================================================

func _check_command_line_lobby() -> void:
	var arguments := OS.get_cmdline_args()

	for argument in arguments:
		if argument.begins_with("+connect_lobby"):
			var parts := argument.split(" ")

			if parts.size() > 1:
				var lobby_id := int(parts[1])

				if lobby_id > 0:
					print_debug(
						"Command line Steam lobby detected: "
						+ str(lobby_id)
					)

					join_lobby(lobby_id)


# ============================================================
# MULTIPLAYER CONNECTION
# ============================================================

func _on_peer_connected(peer_id: int) -> void:
	print_debug(
		"Peer connected: "
		+ str(peer_id)
	)

	if not is_host:
		return

	if peer_id == 1:
		return

	if not world_loaded:
		print_debug(
			"World isn't loaded yet. Waiting..."
		)

		while not world_loaded:
			await get_tree().process_frame

	# --------------------------------------------------------
	# SEND ALL EXISTING PLAYERS TO THE NEW PLAYER
	# --------------------------------------------------------

	print_debug(
		"Sending existing players to peer "
		+ str(peer_id)
	)

	for existing_peer_id in player_spawn_indices:
		var existing_id: int = int(existing_peer_id)

		if existing_id == peer_id:
			continue

		var existing_spawn_index: int = int(
			player_spawn_indices[existing_peer_id]
		)

		var existing_name := _get_player_name(
			existing_id
		)

		print_debug(
			"Sending existing player "
			+ str(existing_id)
			+ " to peer "
			+ str(peer_id)
		)

		spawn_player.rpc_id(
			peer_id,
			existing_id,
			existing_spawn_index,
			existing_name
		)

	# --------------------------------------------------------
	# NOW SPAWN THE NEW PLAYER FOR EVERYONE
	# --------------------------------------------------------

	print_debug(
		"World ready. Spawning peer "
		+ str(peer_id)
	)

	add_player(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print_debug(
		"Peer disconnected: "
		+ str(peer_id)
	)

	player_spawn_indices.erase(peer_id)

	if is_host:
		remove_player.rpc(peer_id)


func _on_connected_to_server() -> void:
	print_debug(
		"Connected to Steam host."
	)

	print_debug(
		"Our peer ID: "
		+ str(multiplayer.get_unique_id())
	)


func _on_connection_failed() -> void:
	print_debug(
		"ERROR: Steam multiplayer connection failed."
	)

	_close_existing_peer()


func _on_server_disconnected() -> void:
	print_debug(
		"Disconnected from Steam host."
	)

	_close_existing_peer()

	is_host = false
	world_loaded = false

	player_spawn_indices.clear()

	get_tree().change_scene_to_file(
		MAIN_MENU_SCENE
	)


# ============================================================
# PLAYER SPAWNING
# ============================================================

func add_player(peer_id: int) -> void:
	if not is_host:
		return

	if not world_loaded:
		print_debug(
			"ERROR: Tried to spawn player "
			+ str(peer_id)
			+ " before world was ready."
		)
		return

	# --------------------------------------------------------
	# Assign a spawn index only once.
	# --------------------------------------------------------

	if not player_spawn_indices.has(peer_id):
		var spawn_index := _get_next_spawn_index(peer_id)

		player_spawn_indices[peer_id] = spawn_index

	else:
		print_debug(
			"Peer "
			+ str(peer_id)
			+ " already has spawn index "
			+ str(player_spawn_indices[peer_id])
		)

	var spawn_index: int = int(
		player_spawn_indices[peer_id]
	)

	var player_name := _get_player_name(peer_id)

	print_debug(
		"========================================"
	)

	print_debug(
		"SPAWNING PLAYER: "
		+ str(peer_id)
	)

	print_debug(
		"Player name: "
		+ player_name
	)

	print_debug(
		"Spawn index: "
		+ str(spawn_index)
	)

	print_debug(
		"Is host: "
		+ str(is_host)
	)

	print_debug(
		"Local peer ID: "
		+ str(multiplayer.get_unique_id())
	)

	# Host creates itself directly.
	if peer_id == multiplayer.get_unique_id():
		spawn_player(
			peer_id,
			spawn_index,
			player_name
		)

	else:
		# Send the new player to EVERYONE.
		spawn_player.rpc(
			peer_id,
			spawn_index,
			player_name
		)

	print_debug(
		"========================================"
	)


# ============================================================
# GET PLAYER STEAM NAME
# ============================================================

func _get_player_name(peer_id: int) -> String:
	if steam_peer == null:
		return "Player"

	var steam_id: int = (
		steam_peer.get_steam64_from_peer_id(
			peer_id
		)
	)

	if steam_id <= 0:
		if peer_id == 1:
			return Steam.getPersonaName()

		return "Player"

	if steam_id == Steam.getSteamID():
		return Steam.getPersonaName()

	var player_name := Steam.getFriendPersonaName(
		steam_id
	)

	if player_name.is_empty():
		return "Player"

	return player_name


# ============================================================
# SPAWN PLAYER RPC
# ============================================================

@rpc("authority", "call_local", "reliable")
func spawn_player(
	peer_id: int,
	spawn_index: int,
	player_name: String
) -> void:
	print_debug(
		"SPAWN_PLAYER called for peer "
		+ str(peer_id)
		+ " on local peer "
		+ str(multiplayer.get_unique_id())
	)

	# --------------------------------------------------------
	# Prevent duplicates
	# --------------------------------------------------------

	var existing_players := get_tree().get_nodes_in_group(
		"Players"
	)

	for player in existing_players:
		if player.name == str(peer_id):
			print_debug(
				"Player "
				+ str(peer_id)
				+ " already exists. Skipping spawn."
			)

			return

	# --------------------------------------------------------
	# Find PlayerSpawns
	# --------------------------------------------------------

	var spawn_container: Node3D = null

	while spawn_container == null:
		spawn_container = get_tree().root.find_child(
			"PlayerSpawns",
			true,
			false
		) as Node3D

		if spawn_container == null:
			await get_tree().process_frame

	print_debug(
		"Found PlayerSpawns: "
		+ str(spawn_container.get_path())
	)

	var spawn_points := spawn_container.get_children()

	if spawn_points.is_empty():
		print_debug(
			"ERROR: PlayerSpawns has no children."
		)

		return

	if spawn_index < 0:
		print_debug(
			"ERROR: Spawn index is below zero."
		)

		return

	if spawn_index >= spawn_points.size():
		print_debug(
			"ERROR: Invalid spawn index "
			+ str(spawn_index)
			+ " / "
			+ str(spawn_points.size())
		)

		return

	var spawn_point := spawn_points[
		spawn_index
	] as Marker3D

	if spawn_point == null:
		print_debug(
			"ERROR: Spawn point "
			+ str(spawn_index)
			+ " is not a Marker3D."
		)

		return

	# --------------------------------------------------------
	# Find world
	# --------------------------------------------------------

	var world := get_tree().current_scene

	if world == null:
		print_debug(
			"ERROR: Current scene is null."
		)

		return

	print_debug(
		"Current scene: "
		+ str(world.name)
	)

	# --------------------------------------------------------
	# Create player
	# --------------------------------------------------------

	var new_player = PLAYER.instantiate()

	if new_player == null:
		print_debug(
			"ERROR: Failed to instantiate player."
		)

		return

	new_player.name = str(peer_id)

	new_player.set_multiplayer_authority(
		peer_id
	)

	# Give the player its actual owner's Steam name.
	new_player.player_display_name = player_name

	print_debug(
		"Adding player "
		+ str(peer_id)
		+ " to "
		+ str(world.get_path())
	)

	world.add_child(
		new_player,
		true
	)

	# --------------------------------------------------------
	# Position player
	# --------------------------------------------------------

	new_player.global_position = (
		spawn_point.global_position
	)

	new_player.global_rotation = (
		spawn_point.global_rotation
	)

	print_debug(
		"PLAYER CREATED"
	)

	print_debug(
		"Name: "
		+ str(new_player.name)
	)

	print_debug(
		"Display name: "
		+ player_name
	)

	print_debug(
		"Authority: "
		+ str(
			new_player.get_multiplayer_authority()
		)
	)

	print_debug(
		"Position: "
		+ str(
			new_player.global_position
		)
	)

	print_debug(
		"Spawn point: "
		+ str(
			spawn_point.global_position
		)
	)

	print_debug(
		"Is local authority: "
		+ str(
			new_player.is_multiplayer_authority()
		)
	)

	print_debug(
		"========================================"
	)


# ============================================================
# REMOVE PLAYER
# ============================================================

@rpc("authority", "call_local", "reliable")
func remove_player(peer_id: int) -> void:
	var players := get_tree().get_nodes_in_group(
		"Players"
	)

	for player in players:
		if player.name == str(peer_id):
			player.queue_free()

			print_debug(
				"Removed player "
				+ str(peer_id)
			)

			return


# ============================================================
# SPAWN INDEX
# ============================================================

func _get_next_spawn_index(peer_id: int) -> int:
	var spawn_container := get_tree().root.find_child(
		"PlayerSpawns",
		true,
		false
	) as Node3D

	if spawn_container == null:
		print_debug(
			"ERROR: Could not find PlayerSpawns."
		)

		return 0

	var spawn_points := spawn_container.get_children()

	if spawn_points.is_empty():
		print_debug(
			"ERROR: PlayerSpawns has no spawn points."
		)

		return 0

	# Host always gets spawn 0.
	if peer_id == 1:
		return 0

	var occupied := {}

	var players := get_tree().get_nodes_in_group(
		"Players"
	)

	for player in players:
		var closest_index: int = -1
		var closest_distance: float = INF

		for i in range(spawn_points.size()):
			var spawn_point := spawn_points[i] as Node3D

			if spawn_point == null:
				continue

			var distance: float = (
				player.global_position
				.distance_squared_to(
					spawn_point.global_position
				)
			)

			if distance < closest_distance:
				closest_distance = distance
				closest_index = i

		if closest_index >= 0:
			occupied[closest_index] = true

	for i in range(spawn_points.size()):
		if not occupied.has(i):
			return i

	return (
		(peer_id - 1)
		% spawn_points.size()
	)


# ============================================================
# LOBBY MEMBERS
# ============================================================

func print_lobby_members() -> void:
	if current_lobby_id == 0:
		return

	var member_count := Steam.getNumLobbyMembers(
		current_lobby_id
	)

	for i in range(member_count):
		var member_id := Steam.getLobbyMemberByIndex(
			current_lobby_id,
			i
		)

		var member_name := Steam.getFriendPersonaName(
			member_id
		)

		print_debug(
			"Lobby member: "
			+ member_name
			+ " ("
			+ str(member_id)
			+ ")"
		)


# ============================================================
# LEAVE GAME
# ============================================================

func leave_game() -> void:
	print_debug("Leaving game.")

	_close_existing_peer()

	if current_lobby_id != 0:
		Steam.leaveLobby(
			current_lobby_id
		)

	current_lobby_id = 0
	host_steam_id = 0

	is_host = false
	world_loaded = false

	player_spawn_indices.clear()

	get_tree().change_scene_to_file(
		MAIN_MENU_SCENE
	)


# ============================================================
# PEER CLEANUP
# ============================================================

func _close_existing_peer() -> void:
	if multiplayer.has_multiplayer_peer():
		print_debug(
			"Closing existing multiplayer peer."
		)

		var existing_peer := (
			multiplayer.multiplayer_peer
		)

		if existing_peer != null:
			existing_peer.close()

		multiplayer.multiplayer_peer = null

	steam_peer = null
