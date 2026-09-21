extends Node


# ============================================================
# STEAM CONFIGURATION
# ============================================================

const STEAM_APP_ID: int = 480

var STEAM_USERNAME: String = ""
var STEAM_ID: int = 0

var steam_initialized: bool = false


# ============================================================
# LOBBY
# ============================================================

var is_lobby_host: bool = false
var lobby_id: int = 0
var lobby_members: Array[int] = []


# ============================================================
# INITIALIZATION
# ============================================================

func _init() -> void:
	OS.set_environment(
		"SteamAppID",
		str(STEAM_APP_ID)
	)

	OS.set_environment(
		"SteamGameID",
		str(STEAM_APP_ID)
	)


func _ready() -> void:

	var init_result = Steam.steamInit()

	print(
		"STEAM: Init result: ",
		init_result
	)

	# GodotSteam versions can return different values here,
	# so verify Steam itself is actually running.
	if not Steam.isSteamRunning():

		print(
			"STEAM ERROR: Steam is not running."
		)

		steam_initialized = false
		return


	steam_initialized = true

	STEAM_ID = int(
		Steam.getSteamID()
	)

	STEAM_USERNAME = Steam.getPersonaName()

	print(
		"STEAM: Initialized."
	)

	print(
		"STEAM: ID: ",
		STEAM_ID
	)

	print(
		"STEAM: Username: ",
		STEAM_USERNAME
	)


	# --------------------------------------------------------
	# Lobby callbacks
	# --------------------------------------------------------

	Steam.lobby_created.connect(
		_on_lobby_created
	)

	Steam.lobby_joined.connect(
		_on_lobby_joined
	)

	Steam.lobby_chat_update.connect(
		_on_lobby_chat_update
	)

	Steam.join_requested.connect(
		_on_join_requested
	)


# ============================================================
# PROCESS
# ============================================================

func _process(_delta: float) -> void:

	if not steam_initialized:
		return

	Steam.run_callbacks()


# ============================================================
# STEAM STATUS
# ============================================================

func is_ready() -> bool:
	return steam_initialized and Steam.isSteamRunning()


# ============================================================
# CREATE LOBBY
# ============================================================

func create_lobby() -> void:

	if not is_ready():
		print(
			"STEAM ERROR: Cannot create lobby. Steam is not initialized."
		)
		return

	if lobby_id != 0:
		print(
			"STEAM: Already in lobby: ",
			lobby_id
		)
		return

	print(
		"STEAM: Creating lobby..."
	)

	Steam.createLobby(
		Steam.LOBBY_TYPE_PUBLIC,
		4
	)


# ============================================================
# LOBBY CREATED
# ============================================================

func _on_lobby_created(
	connect: int,
	created_lobby_id: int
) -> void:

	print(
		"STEAM: Lobby created callback."
	)

	if connect != 1:

		print(
			"STEAM ERROR: Lobby creation failed. Result: ",
			connect
		)

		return


	lobby_id = created_lobby_id
	is_lobby_host = true

	print(
		"STEAM: Lobby created: ",
		lobby_id
	)


	# --------------------------------------------------------
	# Lobby metadata
	# --------------------------------------------------------

	Steam.setLobbyJoinable(
		lobby_id,
		true
	)

	Steam.setLobbyData(
		lobby_id,
		"name",
		STEAM_USERNAME + "'s DEADWEIGHT Lobby"
	)

	Steam.setLobbyData(
		lobby_id,
		"game",
		"DEADWEIGHT"
	)

	Steam.setLobbyData(
		lobby_id,
	"version",
		"0.1.1"
	)


	# --------------------------------------------------------
	# Start the actual Godot Steam network host.
	# --------------------------------------------------------

	if Network != null:

		Network.use_steam_network()
		Network.host_game()


# ============================================================
# JOIN LOBBY
# ============================================================

func join_lobby(target_lobby_id: int) -> void:

	if not is_ready():
		print(
			"STEAM ERROR: Cannot join lobby. Steam is not initialized."
		)
		return

	if target_lobby_id <= 0:
		print(
			"STEAM ERROR: Invalid lobby ID."
		)
		return

	print(
		"STEAM: Joining lobby: ",
		target_lobby_id
	)

	Steam.joinLobby(
		target_lobby_id
	)


# ============================================================
# LOBBY JOINED
# ============================================================

func _on_lobby_joined(
	joined_lobby_id: int,
	_permissions: int,
	_locked: bool,
	response: int
) -> void:

	print(
		"STEAM: Lobby joined callback."
	)

	if response != 1:

		print(
			"STEAM ERROR: Failed to join lobby. Response: ",
			response
		)

		return


	lobby_id = joined_lobby_id
	is_lobby_host = false

	print(
		"STEAM: Joined lobby: ",
		lobby_id
	)


	# --------------------------------------------------------
	# Get lobby owner
	# --------------------------------------------------------

	var owner_id := int(
		Steam.getLobbyOwner(lobby_id)
	)

	print(
		"STEAM: Lobby owner: ",
		owner_id
	)


	# --------------------------------------------------------
	# Connect to the Steam network host.
	# --------------------------------------------------------

	if Network != null:

		Network.join_steam_game(
			owner_id
		)


# ============================================================
# INVITE / JOIN REQUEST
# ============================================================

func _on_join_requested(
	requested_lobby_id: int,
	friend_id: int
) -> void:

	print(
		"STEAM: Lobby invite received."
	)

	print(
		"STEAM: Lobby: ",
		requested_lobby_id
	)

	print(
		"STEAM: Invited by: ",
		friend_id
	)

	join_lobby(
		requested_lobby_id
	)


# ============================================================
# LOBBY MEMBER UPDATE
# ============================================================

func _on_lobby_chat_update(
	changed_lobby_id: int,
	changed_user_id: int,
	_making_change_user_id: int,
	chat_state: int
) -> void:

	if changed_lobby_id != lobby_id:
		return

	print(
		"STEAM: Lobby member update: ",
		changed_user_id,
		" | State: ",
		chat_state
	)

	_update_lobby_members()


# ============================================================
# UPDATE LOBBY MEMBERS
# ============================================================

func _update_lobby_members() -> void:

	lobby_members.clear()

	if lobby_id <= 0:
		return

	var member_count := Steam.getNumLobbyMembers(
		lobby_id
	)

	for index in range(member_count):

		var member_id := int(
			Steam.getLobbyMemberByIndex(
				lobby_id,
				index
			)
		)

		if member_id > 0:
			lobby_members.append(
				member_id
			)

	print(
		"STEAM: Lobby members: ",
		lobby_members
	)


# ============================================================
# LEAVE LOBBY
# ============================================================

func leave_lobby() -> void:

	if lobby_id <= 0:
		return

	print(
		"STEAM: Leaving lobby: ",
		lobby_id
	)

	Steam.leaveLobby(
		lobby_id
	)

	lobby_id = 0
	is_lobby_host = false
	lobby_members.clear()


# ============================================================
# INVITE FRIEND
# ============================================================

func invite_friend(friend_steam_id: int) -> void:

	if lobby_id <= 0:
		print(
			"STEAM ERROR: No active lobby."
		)
		return

	if friend_steam_id <= 0:
		return

	print(
		"STEAM: Inviting friend ",
		friend_steam_id,
		" to lobby."
	)

	Steam.inviteUserToLobby(
		lobby_id,
		friend_steam_id
	)
