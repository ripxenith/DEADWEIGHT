extends Node

const PLAYER = preload("res://assets/player/player.tscn")
const LOBBY_LEVEL = preload("res://level/environment/open_world.tscn")

const MAX_PLAYERS := 4

var lobby_id: int = 0
var lobby_members: Dictionary = {}

var steam_peer: SteamMultiplayerPeer
var world_loaded := false

# Server keeps track of which spawn each player is using.
var player_spawn_indices: Dictionary = {}


func _ready() -> void:
	
	# Steam lobby signals.
	if not Steam.lobby_created.is_connected(_on_lobby_created):
		Steam.lobby_created.connect(_on_lobby_created)

	if not Steam.lobby_joined.is_connected(_on_lobby_joined):
		Steam.lobby_joined.connect(_on_lobby_joined)

	if not Steam.lobby_chat_update.is_connected(_on_lobby_chat_update):
		Steam.lobby_chat_update.connect(_on_lobby_chat_update)

	# Fired when somebody accepts a Steam lobby invite.
	if not Steam.is_connected("join_requested", _on_join_requested):
		Steam.connect("join_requested", _on_join_requested)

	# Allows Steam to launch the game directly into an invited lobby.
	_check_command_line_lobby()



# ============================================================
# HOST GAME
# ============================================================

func host_game() -> void:
	if lobby_id != 0:
		print_debug("Already in a Steam lobby.")
		return

	print_debug("Creating Steam lobby...")

	Steam.createLobby(
		Steam.LOBBY_TYPE_FRIENDS_ONLY,
		MAX_PLAYERS
	)


func _on_lobby_created(connect: int, created_lobby_id: int) -> void:
	if connect != 1:
		print_debug(
			"ERROR: Failed to create Steam lobby. Result: "
			+ str(connect)
		)
		return

	lobby_id = created_lobby_id

	print_debug(
		"Steam lobby created: "
		+ str(lobby_id)
	)

	Steam.setLobbyJoinable(lobby_id, true)

	Steam.setLobbyData(
		lobby_id,
		"name",
		Steam.getPersonaName() + "'s Lobby"
	)

	Steam.setLobbyData(
		lobby_id,
		"game",
		"DEADWEIGHT"
	)

	Steam.setLobbyData(
		lobby_id,
		"version",
		"1"
	)

	update_lobby_members()

	print_debug(
		"Lobby owner: "
		+ str(Steam.getLobbyOwner(lobby_id))
	)

	# Start the actual Steam networking host.
	start_steam_host()

	# Host loads the world immediately.
	load_world()

	# Spawn the host.
	add_player(1)

	print_debug("Host game started.")


func start_steam_host() -> void:
	if multiplayer.has_multiplayer_peer():
		print_debug("Steam multiplayer peer already exists.")
		return

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

	_connect_multiplayer_signals()

	print_debug("Steam multiplayer host started.")


# ============================================================
# STEAM INVITES
# ============================================================

func open_invite_dialog() -> void:
	if lobby_id == 0:
		print_debug("Cannot invite players. No lobby exists.")
		return

	print_debug("Opening Steam invite dialog.")

	Steam.activateGameOverlayInviteDialog(lobby_id)


func _on_join_requested(
	requested_lobby_id: int,
	steam_id: int
) -> void:

	print_debug(
		"Steam invite accepted!"
	)

	print_debug(
		"Lobby: "
		+ str(requested_lobby_id)
	)

	print_debug(
		"Invited by: "
		+ str(steam_id)
	)

	join_lobby(requested_lobby_id)


func _check_command_line_lobby() -> void:
	var args := OS.get_cmdline_args()

	for i in range(args.size()):
		if args[i] == "+connect_lobby" and i + 1 < args.size():
			var command_lobby_id := int(args[i + 1])

			if command_lobby_id != 0:
				print_debug(
					"Steam launched game with lobby: "
					+ str(command_lobby_id)
				)

				join_lobby(command_lobby_id)

			return


# ============================================================
# JOIN LOBBY
# ============================================================

func join_lobby(target_lobby_id: int) -> void:
	if target_lobby_id == 0:
		print_debug("ERROR: Invalid Steam lobby ID.")
		return

	print_debug(
		"Joining Steam lobby: "
		+ str(target_lobby_id)
	)

	Steam.joinLobby(target_lobby_id)


func _on_lobby_joined(
	joined_lobby_id: int,
	_permissions: int,
	_locked: bool,
	response: int
) -> void:

	if response != 1:
		print_debug(
			"ERROR: Failed to join Steam lobby. Response: "
			+ str(response)
		)
		return

	lobby_id = joined_lobby_id

	print_debug(
		"Successfully joined Steam lobby: "
		+ str(lobby_id)
	)

	var owner_id := Steam.getLobbyOwner(lobby_id)

	print_debug(
		"Lobby owner: "
		+ str(owner_id)
	)

	update_lobby_members()

	# If we are the owner, we are already the host.
	if owner_id == Steam.getSteamID():
		return

	# Clients load the world BEFORE connecting to the host.
	#
	# This is important because the host can immediately send
	# player spawn RPCs once the Steam connection is established.
	load_world()

	start_steam_client(owner_id)


func start_steam_client(host_steam_id: int) -> void:
	if multiplayer.has_multiplayer_peer():
		print_debug("Steam multiplayer peer already exists.")
		return

	steam_peer = SteamMultiplayerPeer.new()

	var error: Error = steam_peer.create_client(
		host_steam_id,
		0
	)

	if error != OK:
		print_debug(
			"ERROR: Failed to create Steam client. Error: "
			+ str(error)
		)

		steam_peer = null
		return

	_connect_multiplayer_signals()

	multiplayer.multiplayer_peer = steam_peer

	print_debug(
		"Connecting to Steam host: "
		+ str(host_steam_id)
	)


# ============================================================
# MULTIPLAYER CONNECTION
# ============================================================

func _connect_multiplayer_signals() -> void:
	if not multiplayer.peer_connected.is_connected(add_player):
		multiplayer.peer_connected.connect(add_player)

	if not multiplayer.peer_disconnected.is_connected(remove_player):
		multiplayer.peer_disconnected.connect(remove_player)

	if not multiplayer.connected_to_server.is_connected(on_connected_to_server):
		multiplayer.connected_to_server.connect(on_connected_to_server)

	if not multiplayer.server_disconnected.is_connected(on_server_disconnected):
		multiplayer.server_disconnected.connect(on_server_disconnected)


func on_connected_to_server() -> void:
	print_debug("Connected to Steam host.")


func on_server_disconnected() -> void:
	print_debug("Steam host disconnected.")

	leave_game()


# ============================================================
# WORLD
# ============================================================

func load_world() -> void:
	if world_loaded:
		return

	var current_world := get_tree().root.find_child(
		"open_world",
		true,
		false
	)

	if current_world != null:
		world_loaded = true
		print_debug("World already exists.")
		return

	var new_world = LOBBY_LEVEL.instantiate()

	get_tree().current_scene.add_child(new_world)

	world_loaded = true

	print_debug("World loaded.")


# ============================================================
# PLAYER SPAWNING
# ============================================================

func add_player(peer_id: int) -> void:
	# Only the host controls player spawning.
	if not multiplayer.is_server():
		return

	if player_spawn_indices.has(peer_id):
		return

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

	var spawn_index := get_available_spawn_index(
		spawn_points.size()
	)

	if spawn_index == -1:
		print_debug("ERROR: No available spawn points!")
		return

	player_spawn_indices[peer_id] = spawn_index

	print_debug(
		"Assigning Player "
		+ str(peer_id)
		+ " to "
		+ spawn_points[spawn_index].name
	)

	# Tell everyone to spawn the new player.
	spawn_player.rpc(
		peer_id,
		spawn_index
	)

	# If this is a new client, tell them about all players
	# who were already in the world.
	for existing_peer_id in player_spawn_indices:
		if existing_peer_id == peer_id:
			continue

		var existing_spawn_index: int = (
			player_spawn_indices[existing_peer_id]
		)

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
func spawn_player(
	peer_id: int,
	spawn_index: int
) -> void:

	var existing_players := get_tree().get_nodes_in_group(
		"Players"
	)

	for player in existing_players:
		if player.name == str(peer_id):
			return

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

	var new_player = PLAYER.instantiate()

	new_player.name = str(peer_id)

	var world = spawn_container.get_parent()

	world.add_child(new_player, true)

	new_player.global_position = spawn_point.global_position
	new_player.global_rotation = spawn_point.global_rotation

	print_debug(
		"Player "
		+ str(peer_id)
		+ " spawned at "
		+ spawn_point.name
	)


func remove_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if player_spawn_indices.has(peer_id):
		player_spawn_indices.erase(peer_id)

	remove_player_rpc.rpc(peer_id)

	print_debug(
		"Removing player "
		+ str(peer_id)
	)


@rpc("authority", "call_local", "reliable")
func remove_player_rpc(peer_id: int) -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group(
		"Players"
	)

	for player in players:
		if player.name == str(peer_id):
			player.queue_free()
			return


# ============================================================
# LOBBY MEMBERS
# ============================================================

func update_lobby_members() -> void:
	if lobby_id == 0:
		return

	lobby_members.clear()

	var member_count := Steam.getNumLobbyMembers(
		lobby_id
	)

	for i in range(member_count):
		var member_steam_id := Steam.getLobbyMemberByIndex(
			lobby_id,
			i
		)

		var member_name := Steam.getFriendPersonaName(
			member_steam_id
		)

		lobby_members[member_steam_id] = member_name

		print_debug(
			"Lobby member: "
			+ member_name
			+ " ("
			+ str(member_steam_id)
			+ ")"
		)


func _on_lobby_chat_update(
	changed_lobby_id: int,
	changed_user_id: int,
	making_change_user_id: int,
	chat_state: int
) -> void:

	if changed_lobby_id != lobby_id:
		return

	print_debug(
		"Lobby member state changed. User: "
		+ str(changed_user_id)
		+ " State: "
		+ str(chat_state)
	)

	update_lobby_members()


# ============================================================
# LOBBY INFO
# ============================================================

func is_in_lobby() -> bool:
	return lobby_id != 0


func is_lobby_owner() -> bool:
	if lobby_id == 0:
		return false

	return Steam.getLobbyOwner(lobby_id) == Steam.getSteamID()


func get_lobby_owner() -> int:
	if lobby_id == 0:
		return 0

	return Steam.getLobbyOwner(lobby_id)


func get_lobby_player_count() -> int:
	if lobby_id == 0:
		return 0

	return Steam.getNumLobbyMembers(lobby_id)


# ============================================================
# LEAVING
# ============================================================

func leave_game() -> void:
	print_debug("Leaving game.")

	# Stop Godot multiplayer first.
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()

	multiplayer.multiplayer_peer = null

	steam_peer = null

	# Leave Steam lobby.
	if lobby_id != 0:
		Steam.leaveLobby(lobby_id)

	lobby_id = 0
	lobby_members.clear()

	player_spawn_indices.clear()
	world_loaded = false

	# Return to main menu.
	get_tree().change_scene_to_file(
		"res://level/main menu.tscn"
	)


func leave_lobby() -> void:
	leave_game()
