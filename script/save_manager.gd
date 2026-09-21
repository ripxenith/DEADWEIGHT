extends Node


const SAVE_VERSION: int = 1

const SAVE_DIRECTORY: String = "user://saves/"
const SAVE_FILE: String = "user://saves/save.json"

# Used when running completely offline without a
# multiplayer peer or Network autoload.
const OFFLINE_PLAYER_ID: int = 90000000000000001


var save_data: Dictionary = {
	"save_version": SAVE_VERSION,

	"players": {},

	"world": {
		"ship_upgrades": {},
		"unlocked_areas": []
	},

	"progression": {
		"total_sales": 0,
		"missions_completed": 0
	}
}


func _ready() -> void:
	load_save()


# ============================================================
# PLAYER ID
# ============================================================

# Returns this instance's universal player ID.
#
# IMPORTANT:
#
# SaveManager does NOT care whether this is:
#
# - a Steam ID
# - a local multiplayer ID
# - an offline ID
#
# Network is responsible for resolving that.
#
func get_local_player_id() -> int:

	var network_node := get_node_or_null(
		"/root/Network"
	)

	# --------------------------------------------------------
	# NETWORK
	# --------------------------------------------------------

	if network_node != null:

		if network_node.has_method(
			"get_player_id"
		):

			var peer_id := multiplayer.get_unique_id()

			var player_id := int(
				network_node.get_player_id(
					peer_id
				)
			)

			if player_id > 0:
				return player_id


	# --------------------------------------------------------
	# OFFLINE
	# --------------------------------------------------------

	return OFFLINE_PLAYER_ID


# ============================================================
# SAVE / LOAD
# ============================================================

func load_save() -> void:

	if not FileAccess.file_exists(SAVE_FILE):

		print(
			"SAVE MANAGER: No save found. Creating new save."
		)

		save_game()

		return


	var file := FileAccess.open(
		SAVE_FILE,
		FileAccess.READ
	)

	if file == null:

		push_error(
			"SAVE MANAGER: Failed to open save file."
		)

		return


	var text: String = file.get_as_text()

	file.close()


	var json := JSON.new()

	var parse_result: Error = json.parse(
		text
	)

	if parse_result != OK:

		push_error(
			"SAVE MANAGER: Failed to parse save file."
		)

		return


	var data: Variant = json.data

	if typeof(data) != TYPE_DICTIONARY:

		push_error(
			"SAVE MANAGER: Save file does not contain "
			+ "a Dictionary."
		)

		return


	save_data = data

	_ensure_save_structure()

	_migrate_save()


	print(
		"SAVE MANAGER: Save loaded successfully."
	)


func save_game() -> void:

	# --------------------------------------------------------
	# MULTIPLAYER
	# --------------------------------------------------------
	#
	# Only the server/host writes the campaign save.
	#
	# This works identically for:
	#
	# LOCAL
	# STEAM
	#
	# --------------------------------------------------------

	if multiplayer.has_multiplayer_peer():

		if not multiplayer.is_server():

			print(
				"SAVE MANAGER: Client attempted to save. "
				+ "Ignoring request."
			)

			return


	# --------------------------------------------------------
	# MAKE SURE SAVE DIRECTORY EXISTS
	# --------------------------------------------------------

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(
			SAVE_DIRECTORY
		)
	)


	# --------------------------------------------------------
	# WRITE SAVE
	# --------------------------------------------------------

	var file := FileAccess.open(
		SAVE_FILE,
		FileAccess.WRITE
	)

	if file == null:

		push_error(
			"SAVE MANAGER: Failed to open save file "
			+ "for writing."
		)

		return


	file.store_string(
		JSON.stringify(
			save_data,
			"\t"
		)
	)

	file.close()


	print(
		"SAVE MANAGER: Game saved."
	)


# ============================================================
# SAVE STRUCTURE
# ============================================================

func _ensure_save_structure() -> void:

	if not save_data.has("save_version"):

		save_data["save_version"] = SAVE_VERSION


	if not save_data.has("players"):

		save_data["players"] = {}


	if not save_data.has("world"):

		save_data["world"] = {}


	if not save_data["world"].has(
		"ship_upgrades"
	):

		save_data["world"]["ship_upgrades"] = {}


	if not save_data["world"].has(
		"unlocked_areas"
	):

		save_data["world"]["unlocked_areas"] = []


	if not save_data.has("progression"):

		save_data["progression"] = {}


	if not save_data["progression"].has(
		"total_sales"
	):

		save_data["progression"]["total_sales"] = 0


	if not save_data["progression"].has(
		"missions_completed"
	):

		save_data["progression"]["missions_completed"] = 0


# ============================================================
# SAVE MIGRATION
# ============================================================

func _migrate_save() -> void:

	var current_version: int = int(
		save_data.get(
			"save_version",
			1
		)
	)


	if current_version < SAVE_VERSION:

		print(
			"SAVE MANAGER: Migrating save from version ",
			current_version,
			" to ",
			SAVE_VERSION
		)


		# Future save migrations go here.


		save_data["save_version"] = SAVE_VERSION

		save_game()


# ============================================================
# PLAYER MONEY
# ============================================================

func get_player_money(
	player_id: int
) -> int:

	var player_id_string: String = str(
		player_id
	)

	var players: Dictionary = save_data[
		"players"
	]


	if not players.has(
		player_id_string
	):

		return 0


	var player_data: Variant = players[
		player_id_string
	]


	if typeof(player_data) != TYPE_DICTIONARY:

		return 0


	var player_dictionary: Dictionary = player_data


	return int(
		player_dictionary.get(
			"money",
			0
		)
	)


func set_player_money(
	player_id: int,
	amount: int
) -> void:

	var player_id_string: String = str(
		player_id
	)

	var players: Dictionary = save_data[
		"players"
	]


	if not players.has(
		player_id_string
	):

		players[player_id_string] = {
			"money": 0
		}


	var player_data: Variant = players[
		player_id_string
	]


	if typeof(player_data) != TYPE_DICTIONARY:

		player_data = {
			"money": 0
		}


	var player_dictionary: Dictionary = player_data


	player_dictionary["money"] = maxi(
		amount,
		0
	)


	players[player_id_string] = (
		player_dictionary
	)


func add_player_money(
	player_id: int,
	amount: int
) -> void:

	var current_money: int = get_player_money(
		player_id
	)


	set_player_money(
		player_id,
		current_money + amount
	)


# ============================================================
# PROGRESSION
# ============================================================

func get_total_sales() -> int:

	return int(
		save_data["progression"].get(
			"total_sales",
			0
		)
	)


func add_total_sales(
	amount: int
) -> void:

	var progression: Dictionary = save_data[
		"progression"
	]


	var current_total: int = int(
		progression.get(
			"total_sales",
			0
		)
	)


	progression["total_sales"] = (
		current_total + amount
	)


func get_missions_completed() -> int:

	return int(
		save_data["progression"].get(
			"missions_completed",
			0
		)
	)


func add_mission_completed() -> void:

	var progression: Dictionary = save_data[
		"progression"
	]


	var current_count: int = int(
		progression.get(
			"missions_completed",
			0
		)
	)


	progression["missions_completed"] = (
		current_count + 1
	)


# ============================================================
# WORLD DATA
# ============================================================

func set_ship_upgrade(
	upgrade_name: String,
	level: int
) -> void:

	var world: Dictionary = save_data[
		"world"
	]


	var upgrades: Dictionary = world[
		"ship_upgrades"
	]


	upgrades[upgrade_name] = maxi(
		level,
		0
	)


func get_ship_upgrade(
	upgrade_name: String
) -> int:

	var world: Dictionary = save_data[
		"world"
	]


	var upgrades: Dictionary = world[
		"ship_upgrades"
	]


	return int(
		upgrades.get(
			upgrade_name,
			0
		)
	)


func unlock_area(
	area_name: String
) -> void:

	var world: Dictionary = save_data[
		"world"
	]


	var unlocked_areas: Array = world[
		"unlocked_areas"
	]


	if not unlocked_areas.has(
		area_name
	):

		unlocked_areas.append(
			area_name
		)


func is_area_unlocked(
	area_name: String
) -> bool:

	var world: Dictionary = save_data[
		"world"
	]


	var unlocked_areas: Array = world[
		"unlocked_areas"
	]


	return unlocked_areas.has(
		area_name
	)


# ============================================================
# PLAYER UPGRADES
# ============================================================

func get_player_upgrade(
	player_id: int,
	upgrade_name: String
) -> int:

	var player_id_string: String = str(
		player_id
	)


	var players: Dictionary = save_data[
		"players"
	]


	if not players.has(
		player_id_string
	):

		return 0


	var player_data: Variant = players[
		player_id_string
	]


	if typeof(player_data) != TYPE_DICTIONARY:

		return 0


	var player_dictionary: Dictionary = player_data


	var upgrades: Variant = player_dictionary.get(
		"upgrades",
		{}
	)


	if typeof(upgrades) != TYPE_DICTIONARY:

		return 0


	var upgrade_dictionary: Dictionary = upgrades


	return int(
		upgrade_dictionary.get(
			upgrade_name,
			0
		)
	)


func set_player_upgrade(
	player_id: int,
	upgrade_name: String,
	level: int
) -> void:

	var player_id_string: String = str(
		player_id
	)


	var players: Dictionary = save_data[
		"players"
	]


	if not players.has(
		player_id_string
	):

		players[player_id_string] = {
			"money": 0,
			"upgrades": {}
		}


	var player_data: Variant = players[
		player_id_string
	]


	if typeof(player_data) != TYPE_DICTIONARY:

		player_data = {
			"money": 0,
			"upgrades": {}
		}


	var player_dictionary: Dictionary = player_data


	if not player_dictionary.has(
		"upgrades"
	):

		player_dictionary["upgrades"] = {}


	var upgrades_variant: Variant = (
		player_dictionary["upgrades"]
	)


	if typeof(upgrades_variant) != TYPE_DICTIONARY:

		upgrades_variant = {}


	var upgrades: Dictionary = upgrades_variant


	upgrades[upgrade_name] = maxi(
		level,
		0
	)


	player_dictionary["upgrades"] = upgrades

	players[player_id_string] = (
		player_dictionary
	)


func get_player_upgrade_level(
	upgrade_name: String
) -> int:

	var player_id: int = (
		get_local_player_id()
	)


	return get_player_upgrade(
		player_id,
		upgrade_name
	)
