extends CanvasLayer


const CURRENT_VERSION := "0.0.8"
const VERSION_URL := "https://raw.githubusercontent.com/ripxenith/DEADWEIGHT/refs/heads/main/version.json"


var latest_version := ""
var update_url := ""
var update_available := false

var http_request: HTTPRequest


func _ready() -> void:
	print_debug("Main menu loaded.")

	_setup_update_checker()


# ============================================================
# GAME BUTTONS
# ============================================================

func _on_host_game_pressed() -> void:
	print_debug("Host Game pressed.")

	# Network handles:
	# Steam lobby creation
	# Steam host creation
	# Scene transition
	# Player spawning
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

	print_debug("Checking for updates...")

	var error := http_request.request(VERSION_URL)

	if error != OK:
		print_debug(
			"Failed to check for updates. Error: "
			+ str(error)
		)


func _on_version_request_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		print_debug("Update check failed.")
		return

	if response_code != 200:
		print_debug(
			"Update server returned HTTP "
			+ str(response_code)
		)
		return

	var text := body.get_string_from_utf8()

	var json := JSON.new()

	var parse_result := json.parse(text)

	if parse_result != OK:
		print_debug("Failed to parse version.json.")
		return

	var data = json.data

	if typeof(data) != TYPE_DICTIONARY:
		print_debug("Invalid version.json format.")
		return

	if not data.has("version"):
		print_debug("version.json has no version field.")
		return

	latest_version = str(data["version"])

	if data.has("url"):
		update_url = str(data["url"])

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


func _is_newer_version(
	new_version: String,
	old_version: String
) -> bool:
	var new_parts := new_version.split(".")
	var old_parts := old_version.split(".")

	var count: int = maxi(
		new_parts.size(),
		old_parts.size()
	)

	for i in range(count):
		var new_number := 0
		var old_number := 0

		if i < new_parts.size():
			new_number = int(new_parts[i])

		if i < old_parts.size():
			old_number = int(old_parts[i])

		if new_number > old_number:
			return true

		if new_number < old_number:
			return false

	return false


func _show_update_available() -> void:
	# Keep this function available for the existing UI.
	# If your menu has an update panel/button, enable it here.
	print_debug(
		"Update available: "
		+ latest_version
	)


# ============================================================
# UPDATE
# ============================================================

func download_update() -> void:
	if not update_available:
		return

	if update_url.is_empty():
		print_debug("No update URL was provided.")
		return

	print_debug(
		"Starting updater for version "
		+ latest_version
	)

	var updater_script := OS.get_user_data_dir() + "/update.ps1"

	var game_executable := OS.get_executable_path()

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

	OS.create_process(
		"powershell.exe",
		[
			"-NoProfile",
			"-ExecutionPolicy",
			"Bypass",
			"-File",
			updater_script
		]
	)

	get_tree().quit()


# ============================================================
# OPTIONAL UPDATE BUTTON
# ============================================================

func _on_update_pressed() -> void:
	download_update()
