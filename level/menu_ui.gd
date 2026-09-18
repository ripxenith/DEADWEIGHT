extends CanvasLayer

const LOBBY_LEVEL = preload("res://level/environment/open_world.tscn")
const PLAYER = preload("res://assets/player/player.tscn")

# ==============================
# UPDATE SETTINGS
# ==============================

const CURRENT_VERSION := "0.0.1"

const VERSION_URL := "https://raw.githubusercontent.com/ripxenith/DEADWEIGHT/main/version.json"

const UPDATER_NAME := "DEADWEIGHTUpdater.exe"

var latest_version := ""
var download_url := ""
var update_available := false
var checking_for_update := false

@onready var update_button: Button = $"menu ui/UpdateButton"
@onready var update_status: Label = $"menu ui/UpdateStatus"

# ==============================
# READY
# ==============================

func _ready() -> void:
	# Server setup
	if OS.has_feature("server"):
		Network.start_server()
		add_world()
		hide()
		print_debug("ready")

	# Update system
	_setup_update_system()


# ==============================
# UPDATE SYSTEM
# ==============================

func _setup_update_system() -> void:
	update_button.disabled = true
	update_button.text = "CHECKING..."

	update_status.text = "Checking for updates..."

	check_for_update()


func check_for_update() -> void:
	if checking_for_update:
		return

	checking_for_update = true

	var http := HTTPRequest.new()
	add_child(http)

	http.request_completed.connect(
		_on_version_request_completed.bind(http)
	)

	var error := http.request(VERSION_URL)

	if error != OK:
		print_debug("Failed to start update check: " + error_string(error))

		checking_for_update = false

		http.queue_free()

		update_button.text = "RETRY"
		update_button.disabled = false
		update_status.text = "Could not check for updates."


func _on_version_request_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray,
	http: HTTPRequest
) -> void:

	http.queue_free()

	checking_for_update = false

	# HTTP request failed
	if result != HTTPRequest.RESULT_SUCCESS:
		print_debug("Update check failed. Result: " + str(result))

		update_button.text = "RETRY"
		update_button.disabled = false
		update_status.text = "Could not check for updates."

		return

	# Server returned something other than 200 OK
	if response_code != 200:
		print_debug("Update server returned HTTP " + str(response_code))

		update_button.text = "RETRY"
		update_button.disabled = false
		update_status.text = "Could not check for updates."

		return

	# Parse JSON
	var json: Variant = JSON.parse_string(
		body.get_string_from_utf8()
	)

	if json == null:
		print_debug("Could not parse version.json")

		update_button.text = "RETRY"
		update_button.disabled = false
		update_status.text = "Invalid update information."

		return

	# Make sure version exists
	if not json.has("version"):
		print_debug("version.json is missing 'version'")

		update_button.text = "RETRY"
		update_button.disabled = false
		update_status.text = "Invalid update information."

		return

	# Make sure download URL exists
	if not json.has("download"):
		print_debug("version.json is missing 'download'")

		update_button.text = "RETRY"
		update_button.disabled = false
		update_status.text = "Invalid update information."

		return

	latest_version = str(json["version"])
	download_url = str(json["download"])

	update_available = is_newer_version(
		CURRENT_VERSION,
		latest_version
	)

	# ==============================
	# UPDATE AVAILABLE
	# ==============================

	if update_available:
		update_button.text = "UPDATE"
		update_button.disabled = false

		update_status.text = (
			"Update available: v" + latest_version
		)

		print_debug(
			"Update available: "
			+ CURRENT_VERSION
			+ " -> "
			+ latest_version
		)

	# ==============================
	# ALREADY UP TO DATE
	# ==============================

	else:
		update_button.text = "UP TO DATE"
		update_button.disabled = true

		update_status.text = (
			"Version " + CURRENT_VERSION
		)

		print_debug(
			"Game is up to date: "
			+ CURRENT_VERSION
		)


# ==============================
# VERSION COMPARISON
# ==============================

func is_newer_version(current: String, latest: String) -> bool:
	var current_parts := current.split(".")
	var latest_parts := latest.split(".")

	var count: int = max(
		current_parts.size(),
		latest_parts.size()
	)

	for i in range(count):
		var current_number := 0
		var latest_number := 0

		if i < current_parts.size():
			current_number = int(current_parts[i])

		if i < latest_parts.size():
			latest_number = int(latest_parts[i])

		if latest_number > current_number:
			return true

		if latest_number < current_number:
			return false

	return false


# ==============================
# UPDATE BUTTON
# ==============================

func _on_update_button_pressed() -> void:
	if not update_available:
		return

	update_button.disabled = true
	update_button.text = "UPDATING..."

	update_status.text = "Starting updater..."

	start_update()


func start_update() -> void:
	var game_executable := OS.get_executable_path()

	var updater_path := game_executable.get_base_dir().path_join(
		UPDATER_NAME
	)

	# Make sure updater exists
	if not FileAccess.file_exists(updater_path):
		print_debug(
			"Updater not found: "
			+ updater_path
		)

		update_button.text = "UPDATE ERROR"
		update_button.disabled = false

		update_status.text = (
			"Updater not found."
		)

		return

	# Arguments passed to XenthosUpdater.exe
	var arguments := [
		game_executable,
		download_url
	]

	print_debug("Starting updater...")
	print_debug("Game: " + game_executable)
	print_debug("Download: " + download_url)

	OS.create_process(
		updater_path,
		arguments
	)

	# Close the game so the updater can replace its files.
	get_tree().quit()


# ==============================
# GAME FUNCTIONS
# ==============================

func _process(delta: float) -> void:
	pass


func on_join():
	Network.join_server()

	#var new_player = PLAYER.instantiate()
	#get_tree().current_scene.add_child(new_player)

	add_world()
	hide()


func add_world():
	var new_world = LOBBY_LEVEL.instantiate()
	get_tree().current_scene.add_child(new_world)


func exit_game():
	get_tree().quit()


func _on_host_game_pressed() -> void:
	pass


func _on_join_game_pressed() -> void:
	on_join()


func _on_settings_pressed() -> void:
	pass # Replace with function body.


func _on_exit_pressed() -> void:
	exit_game()
