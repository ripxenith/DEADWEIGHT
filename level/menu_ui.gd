extends CanvasLayer


const CURRENT_VERSION := "0.0.9"
const VERSION_URL := "https://raw.githubusercontent.com/ripxenith/DEADWEIGHT/refs/heads/main/version.json"


var latest_version := ""
var update_url := ""
var update_available := false

var http_request: HTTPRequest

@onready var update_button: Button = $"menu ui/UpdateButton"
@onready var update_label: Label = $"menu ui/UpdateStatus"


func _ready() -> void:
	print_debug("Main menu loaded.")

	# Make sure the update button is connected.
	if not update_button.pressed.is_connected(_on_update_pressed):
		update_button.pressed.connect(_on_update_pressed)

	# Hide the update button until we know an update exists.
	update_button.hide()

	update_label.text = (
		"DEADWEIGHT v"
		+ CURRENT_VERSION
		+ "\nChecking for updates..."
	)

	_setup_update_checker()


# ============================================================
# GAME BUTTONS
# ============================================================

func _on_host_game_pressed() -> void:
	print_debug("Host Game pressed.")

	Network.host_game()


func _on_join_game_pressed() -> void:
	print_debug(
		"Join Game is handled through Steam invites."
	)


func _on_invite_button_pressed() -> void:
	print_debug("Invite button pressed.")

	Network.show_invite_dialog()


func _on_quit_pressed() -> void:
	print_debug("Quit pressed.")

	get_tree().quit()


# ============================================================
# UPDATE CHECKING
# ============================================================

func _setup_update_checker() -> void:
	http_request = HTTPRequest.new()

	add_child(http_request)

	http_request.request_completed.connect(
		_on_version_request_completed
	)

	check_for_updates()


func check_for_updates() -> void:
	if http_request == null:
		return

	update_button.hide()

	update_label.text = (
		"DEADWEIGHT v"
		+ CURRENT_VERSION
		+ "\nChecking for updates..."
	)

	print_debug("Checking for updates...")

	var error: Error = http_request.request(VERSION_URL)

	if error != OK:
		print_debug(
			"Failed to check for updates. Error: "
			+ str(error)
		)

		update_label.text = (
			"DEADWEIGHT v"
			+ CURRENT_VERSION
			+ "\nUnable to check for updates."
		)


func _on_version_request_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray
) -> void:

	if result != HTTPRequest.RESULT_SUCCESS:
		print_debug("Update check failed.")

		update_button.hide()

		update_label.text = (
			"DEADWEIGHT v"
			+ CURRENT_VERSION
			+ "\nUnable to check for updates."
		)

		return

	if response_code != 200:
		print_debug(
			"Update server returned HTTP "
			+ str(response_code)
		)

		update_button.hide()

		update_label.text = (
			"DEADWEIGHT v"
			+ CURRENT_VERSION
			+ "\nUnable to check for updates."
		)

		return

	var text: String = body.get_string_from_utf8()

	var json := JSON.new()

	var parse_result: Error = json.parse(text)

	if parse_result != OK:
		print_debug("Failed to parse version.json.")

		update_button.hide()

		update_label.text = (
			"DEADWEIGHT v"
			+ CURRENT_VERSION
			+ "\nInvalid update information."
		)

		return

	var data: Variant = json.data

	if typeof(data) != TYPE_DICTIONARY:
		print_debug("Invalid version.json format.")

		update_button.hide()

		update_label.text = (
			"DEADWEIGHT v"
			+ CURRENT_VERSION
			+ "\nInvalid update information."
		)

		return

	var version_data: Dictionary = data

	if not version_data.has("version"):
		print_debug("version.json has no version field.")

		update_button.hide()

		update_label.text = (
			"DEADWEIGHT v"
			+ CURRENT_VERSION
			+ "\nInvalid update information."
		)

		return

	latest_version = str(version_data["version"])

	if version_data.has("download"):
		update_url = str(version_data["download"])

	print_debug(
		"Current version: "
		+ CURRENT_VERSION
	)

	print_debug(
		"Latest version: "
		+ latest_version
	)

	if _is_newer_version(latest_version, CURRENT_VERSION):
		update_available = true

		print_debug("A new version is available.")

		_show_update_available()

	else:
		update_available = false

		print_debug("Game is up to date.")

		_show_game_up_to_date()


# ============================================================
# VERSION COMPARISON
# ============================================================

func _is_newer_version(
	new_version: String,
	old_version: String
) -> bool:

	var new_parts: PackedStringArray = new_version.split(".")
	var old_parts: PackedStringArray = old_version.split(".")

	var count: int = maxi(
		new_parts.size(),
		old_parts.size()
	)

	for i in range(count):
		var new_number: int = 0
		var old_number: int = 0

		if i < new_parts.size():
			new_number = int(new_parts[i])

		if i < old_parts.size():
			old_number = int(old_parts[i])

		if new_number > old_number:
			return true

		if new_number < old_number:
			return false

	return false


# ============================================================
# UPDATE LABEL
# ============================================================

func _show_update_available() -> void:
	update_button.show()

	update_label.text = (
		"DEADWEIGHT v"
		+ CURRENT_VERSION
		+ "\nUpdate available: v"
		+ latest_version
	)

	print_debug(
		"Update available: "
		+ latest_version
	)


func _show_game_up_to_date() -> void:
	update_button.hide()

	update_label.text = (
		"DEADWEIGHT v"
		+ CURRENT_VERSION
		+ "\nUp to date"
	)


# ============================================================
# UPDATE
# ============================================================

func download_update() -> void:
	print_debug("UPDATE BUTTON PRESSED")

	if not update_available:
		print_debug("Update button pressed, but no update is available.")
		return

	if update_url.is_empty():
		print_debug("No update URL was provided.")
		return

	print_debug(
		"Starting updater for version "
		+ latest_version
	)

	var updater_script: String = (
		OS.get_user_data_dir()
		+ "/update.ps1"
	)

	var game_executable: String = OS.get_executable_path()

	var script := """
$ErrorActionPreference = "Stop"

$downloadUrl = "%s"
$gameDirectory = "%s"
$gameExecutable = "%s"

$tempFile = Join-Path $env:TEMP "DEADWEIGHT_update.zip"

Invoke-WebRequest `
    -Uri $downloadUrl `
    -OutFile $tempFile

Expand-Archive `
    -Path $tempFile `
    -DestinationPath $gameDirectory `
    -Force

Remove-Item $tempFile -Force

Start-Process -FilePath $gameExecutable

exit
""" % [
		update_url,
		ProjectSettings.globalize_path("res://"),
		game_executable
	]

	var file := FileAccess.open(
		updater_script,
		FileAccess.WRITE
	)

	if file == null:
		print_debug("Failed to create updater script.")
		return

	file.store_string(script)
	file.close()

	print_debug(
		"Updater script created at: "
		+ updater_script
	)

	var process_id: int = OS.create_process(
		"powershell.exe",
		[
			"-NoProfile",
			"-ExecutionPolicy",
			"Bypass",
			"-File",
			updater_script
		]
	)

	print_debug(
		"Updater process ID: "
		+ str(process_id)
	)

	if process_id == -1:
		print_debug("ERROR: Failed to start PowerShell updater.")
		return

	print_debug("Closing game for update.")

	get_tree().quit()


# ============================================================
# UPDATE BUTTON
# ============================================================

func _on_update_pressed() -> void:
	print_debug("Update button pressed!")

	download_update()
