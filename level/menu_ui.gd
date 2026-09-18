extends CanvasLayer

const LOBBY_LEVEL = preload("res://level/environment/open_world.tscn")
const PLAYER = preload("res://assets/player/player.tscn")

# ==============================
# UPDATE SETTINGS
# ==============================

const CURRENT_VERSION := "0.0.1"

const VERSION_URL := "https://raw.githubusercontent.com/ripxenith/DEADWEIGHT/refs/heads/main/version.json"

var latest_version := ""
var download_url := ""
var update_available := false
var checking_for_update := false
var downloading_update := false

@onready var update_button: Button = $"menu ui/UpdateButton"
@onready var update_status: Label = $"menu ui/UpdateStatus"


# ==============================
# READY
# ==============================

func _ready() -> void:
	# Connect update button
	if not update_button.pressed.is_connected(_on_update_button_pressed):
		update_button.pressed.connect(_on_update_button_pressed)

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
		print_debug(
			"Failed to start update check: "
			+ error_string(error)
		)

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
		print_debug(
			"Update check failed. Result: "
			+ str(result)
		)

		update_button.text = "RETRY"
		update_button.disabled = false
		update_status.text = "Could not check for updates."

		return

	# Server returned something other than 200 OK
	if response_code != 200:
		print_debug(
			"Update server returned HTTP "
			+ str(response_code)
		)

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
			"Update available: v"
			+ latest_version
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
			"Version "
			+ CURRENT_VERSION
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

	if downloading_update:
		return

	update_button.disabled = true
	update_button.text = "DOWNLOADING..."

	update_status.text = (
		"Downloading v"
		+ latest_version
		+ "..."
	)

	download_update()


# ==============================
# DOWNLOAD UPDATE
# ==============================

func download_update() -> void:
	downloading_update = true

	var update_zip_path := OS.get_user_data_dir().path_join(
		"DEADWEIGHT_update.zip"
	)

	# Delete an old update ZIP if one exists.
	if FileAccess.file_exists(update_zip_path):
		DirAccess.remove_absolute(update_zip_path)

	var http := HTTPRequest.new()
	add_child(http)

	http.download_file = update_zip_path

	http.request_completed.connect(
		_on_update_download_completed.bind(
			http,
			update_zip_path
		)
	)

	var error := http.request(download_url)

	if error != OK:
		print_debug(
			"Failed to start update download: "
			+ error_string(error)
		)

		downloading_update = false

		http.queue_free()

		update_button.text = "UPDATE"
		update_button.disabled = false

		update_status.text = "Download failed."


# ==============================
# DOWNLOAD FINISHED
# ==============================

func _on_update_download_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray,
	http: HTTPRequest,
	update_zip_path: String
) -> void:

	http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		print_debug(
			"Update download failed. Result: "
			+ str(result)
		)

		downloading_update = false

		update_button.text = "UPDATE"
		update_button.disabled = false

		update_status.text = "Download failed."

		return

	if response_code != 200:
		print_debug(
			"Update download returned HTTP "
			+ str(response_code)
		)

		downloading_update = false

		update_button.text = "UPDATE"
		update_button.disabled = false

		update_status.text = "Download failed."

		return

	print_debug(
		"Update downloaded successfully:"
		+ update_zip_path
	)

	update_status.text = "Installing update..."

	create_update_script(update_zip_path)


# ==============================
# CREATE POWERSHELL UPDATER
# ==============================

func create_update_script(update_zip_path: String) -> void:
	var game_executable := OS.get_executable_path()
	var game_directory := game_executable.get_base_dir()
	var game_pid := OS.get_process_id()

	var script_path := OS.get_user_data_dir().path_join(
		"DEADWEIGHT_update.ps1"
	)

	var extract_directory := OS.get_user_data_dir().path_join(
		"DEADWEIGHT_update_extracted"
	)

	var escaped_game_executable := powershell_escape(game_executable)
	var escaped_game_directory := powershell_escape(game_directory)
	var escaped_zip_path := powershell_escape(update_zip_path)
	var escaped_extract_directory := powershell_escape(extract_directory)
	var escaped_script_path := powershell_escape(script_path)

	var script := """
$ErrorActionPreference = "Stop"

$GamePID = %d
$GameExecutable = '%s'
$GameDirectory = '%s'
$ZipPath = '%s'
$ExtractDirectory = '%s'
$ScriptPath = '%s'

Write-Host "======================================"
Write-Host "DEADWEIGHT UPDATER"
Write-Host "======================================"
Write-Host "Game: $GameExecutable"
Write-Host "Game directory: $GameDirectory"
Write-Host "ZIP: $ZipPath"
Write-Host ""

# Wait until the game process is actually gone.
Write-Host "Waiting for DEADWEIGHT to close..."

while (Get-Process -Id $GamePID -ErrorAction SilentlyContinue) {
    Start-Sleep -Milliseconds 250
}

Write-Host "DEADWEIGHT has closed."
Start-Sleep -Seconds 1

# Verify ZIP exists.
if (!(Test-Path $ZipPath)) {
    Write-Host "ERROR: Update ZIP does not exist!"
    Read-Host "Press Enter to close"
    exit
}

Write-Host "Update ZIP found."
Write-Host ""

# Remove previous extraction directory.
if (Test-Path $ExtractDirectory) {
    Write-Host "Removing old extraction directory..."
    Remove-Item $ExtractDirectory -Recurse -Force
}

New-Item -ItemType Directory -Path $ExtractDirectory -Force | Out-Null

Write-Host "Extracting update..."

Expand-Archive `
    -Path $ZipPath `
    -DestinationPath $ExtractDirectory `
    -Force

Write-Host "Extraction complete."
Write-Host ""

# Determine whether the ZIP contains a DEADWEIGHT folder.
$Items = Get-ChildItem -Path $ExtractDirectory -Force

if ($Items.Count -eq 1 -and $Items[0].PSIsContainer) {
    $SourceDirectory = $Items[0].FullName
}
else {
    $SourceDirectory = $ExtractDirectory
}

Write-Host "Source directory:"
Write-Host $SourceDirectory
Write-Host ""

Write-Host "Installing files..."

Copy-Item `
    -Path (Join-Path $SourceDirectory "*") `
    -Destination $GameDirectory `
    -Recurse `
    -Force

Write-Host "Files copied successfully."
Write-Host ""

# Clean up.
Write-Host "Cleaning up..."

if (Test-Path $ExtractDirectory) {
    Remove-Item $ExtractDirectory -Recurse -Force
}

if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}

Write-Host "Cleanup complete."
Write-Host ""

Write-Host "Starting DEADWEIGHT..."

Start-Process `
    -FilePath $GameExecutable `
    -WorkingDirectory $GameDirectory

Write-Host "DEADWEIGHT started."
Write-Host ""

Start-Sleep -Seconds 2

# Delete updater script.
Remove-Item $ScriptPath -Force
""" % [
		game_pid,
		escaped_game_executable,
		escaped_game_directory,
		escaped_zip_path,
		escaped_extract_directory,
		escaped_script_path
	]

	var file := FileAccess.open(
		script_path,
		FileAccess.WRITE
	)

	if file == null:
		print_debug("ERROR: Could not create PowerShell script.")

		downloading_update = false
		update_button.text = "UPDATE"
		update_button.disabled = false
		update_status.text = "Could not create updater."

		return

	file.store_string(script)
	file.close()

	print_debug("PowerShell updater created:")
	print_debug(script_path)

	start_powershell_updater(script_path)


func start_powershell_updater(script_path: String) -> void:
	print_debug("Starting PowerShell...")
	print_debug("Script: " + script_path)

	var arguments := [
		"-NoProfile",
		"-ExecutionPolicy",
		"Bypass",
		"-File",
		script_path
	]

	var pid := OS.create_process(
		"powershell.exe",
		arguments,
		true
	)

	if pid == -1:
		print_debug("ERROR: Could not start PowerShell.")

		downloading_update = false
		update_button.text = "UPDATE"
		update_button.disabled = false
		update_status.text = "Could not start updater."

		return

	print_debug(
		"PowerShell started. PID: "
		+ str(pid)
	)

	# Give PowerShell a moment to start before closing.
	await get_tree().create_timer(0.5).timeout

	get_tree().quit()


# ==============================
# POWERSHELL STRING ESCAPING
# ==============================

func powershell_escape(value: String) -> String:
	return value.replace(
		"'",
		"''"
	)


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
