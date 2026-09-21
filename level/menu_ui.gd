extends CanvasLayer


const CURRENT_VERSION := "0.1.2"
const VERSION_URL := "https://raw.githubusercontent.com/ripxenith/DEADWEIGHT/refs/heads/main/version.json"


var latest_version := ""
var update_url := ""
var update_available := false

var http_request: HTTPRequest

@onready var update_button: Button = $CTRL_MenuUI/BTN_Update
@onready var update_label: Label = $CTRL_MenuUI/LBL_UpdateStatus


func _ready() -> void:
	$CTRL_MenuUI/Settings.hide()
	$CTRL_MenuUI/Settings.back_pressed.connect(_on_settings_back_pressed)
	print_debug("Main menu loaded.")
	if not update_button.pressed.is_connected(_on_update_pressed):
		update_button.pressed.connect(_on_update_pressed)

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

	if not SteamManager.is_ready():
		print_debug("Steam is not ready. Cannot create lobby.")
		return

	print_debug("Creating Steam lobby...")

	SteamManager.create_lobby()


func _on_join_game_pressed() -> void:
	print_debug("Join Game is handled through Steam invites.")


func _on_invite_button_pressed() -> void:
	print_debug("Invite button pressed.")

	if not SteamManager.is_ready():
		print_debug("Steam is not ready.")
		return

	if SteamManager.lobby_id <= 0:
		print_debug("No Steam lobby exists yet.")
		return

	# Opens Steam's overlay to invite friends to the lobby.
	Steam.activateGameOverlayInviteDialog(
		SteamManager.lobby_id
	)


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
	else:
		update_url = ""

	print_debug(
		"Current version: "
		+ CURRENT_VERSION
	)

	print_debug(
		"Latest version: "
		+ latest_version
	)

	print_debug(
		"Download URL: "
		+ update_url
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
		print_debug(
			"Update button pressed, but no update is available."
		)
		return

	if update_url.is_empty():
		print_debug("No update URL was provided.")
		return

	print_debug(
		"Starting updater for version "
		+ latest_version
	)

	var game_executable: String = OS.get_executable_path()
	var game_directory: String = game_executable.get_base_dir()

	print_debug(
		"Game executable: "
		+ game_executable
	)

	print_debug(
		"Game directory: "
		+ game_directory
	)

	var updater_script: String = (
		OS.get_user_data_dir()
		+ "/update.ps1"
	)

	var update_log: String = (
		OS.get_user_data_dir()
		+ "/update_log.txt"
	)

	var script := """
$ErrorActionPreference = "Stop"

$downloadUrl = "%s"
$gameDirectory = "%s"
$gameExecutable = "%s"
$updateLog = "%s"

function Write-Log($message) {
    Add-Content -Path $updateLog -Value (
		("[" + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "] " + $message)
    )
}

try {
	Write-Log "========================================"
	Write-Log "DEADWEIGHT updater started"
	Write-Log "Download URL: $downloadUrl"
	Write-Log "Game directory: $gameDirectory"
	Write-Log "Game executable: $gameExecutable"

	$tempFile = Join-Path $env:TEMP "DEADWEIGHT_update.zip"

	Write-Log "Downloading update..."

    Invoke-WebRequest `
        -Uri $downloadUrl `
        -OutFile $tempFile `
        -UseBasicParsing

	Write-Log "Download complete."

    if (!(Test-Path $tempFile)) {
		throw "Downloaded ZIP file does not exist."
    }

	Write-Log "Waiting for DEADWEIGHT processes to close..."

    # Wait for both Godot executables to completely exit.
    for ($i = 0; $i -lt 60; $i++) {

		$gameProcess = Get-Process -Name "DEADWEIGHT" -ErrorAction SilentlyContinue
		$consoleProcess = Get-Process -Name "DEADWEIGHT.console" -ErrorAction SilentlyContinue

        if ($null -eq $gameProcess -and $null -eq $consoleProcess) {
			Write-Log "All DEADWEIGHT processes have closed."
            break
        }

		Write-Log "DEADWEIGHT is still running. Waiting..."

        Start-Sleep -Milliseconds 500
    }

    # Make absolutely sure the processes are gone.
	$gameProcess = Get-Process -Name "DEADWEIGHT" -ErrorAction SilentlyContinue
	$consoleProcess = Get-Process -Name "DEADWEIGHT.console" -ErrorAction SilentlyContinue

    if ($null -ne $gameProcess -or $null -ne $consoleProcess) {
		throw "DEADWEIGHT is still running after waiting 30 seconds."
    }

	Write-Log "Extracting update..."

    # Retry extraction several times in case Windows is still releasing a file.
    $extracted = $false

    for ($attempt = 1; $attempt -le 10; $attempt++) {

        try {
			Write-Log "Extraction attempt $attempt..."

            Expand-Archive `
                -Path $tempFile `
                -DestinationPath $gameDirectory `
                -Force

            $extracted = $true
			Write-Log "Extraction successful."
            break
        }
        catch {
			Write-Log "Extraction attempt $attempt failed: $($_.Exception.Message)"

            if ($attempt -lt 10) {
                Start-Sleep -Seconds 1
            }
        }
    }

    if (!$extracted) {
		throw "Failed to extract update after 10 attempts."
    }

    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

	Write-Log "Starting updated game..."

    Start-Process -FilePath $gameExecutable

	Write-Log "Update completed successfully."

}
catch {
	Write-Log "========================================"
	Write-Log "UPDATE FAILED"
    Write-Log $_.Exception.Message
    Write-Log $_.ScriptStackTrace
}

exit
""" % [
		_escape_powershell_string(update_url),
		_escape_powershell_string(game_directory),
		_escape_powershell_string(game_executable),
		_escape_powershell_string(update_log)
	]

	var file := FileAccess.open(
		updater_script,
		FileAccess.WRITE
	)

	if file == null:
		print_debug(
			"Failed to create updater script."
		)
		return

	file.store_string(script)
	file.close()

	print_debug(
		"Updater script created at: "
		+ updater_script
	)

	print_debug(
		"Updater log will be written to: "
		+ update_log
	)

	var process_id: int = OS.create_process(
		"powershell.exe",
		[
			"-NoProfile",
			"-ExecutionPolicy",
			"Bypass",
			"-WindowStyle",
			"Hidden",
			"-File",
			updater_script
		]
	)

	print_debug(
		"Updater process ID: "
		+ str(process_id)
	)

	if process_id == -1:
		print_debug(
			"ERROR: Failed to start PowerShell updater."
		)
		return

	print_debug(
		"Closing game for update."
	)

	get_tree().quit()


# ============================================================
# POWERSHELL STRING ESCAPING
# ============================================================

func _escape_powershell_string(value: String) -> String:
	return value.replace("`", "``").replace("\"", "`\"")


# ============================================================
# UPDATE BUTTON
# ============================================================

func _on_update_pressed() -> void:
	print_debug("Update button pressed!")

	download_update()



func _on_settings_pressed() -> void:
	$CTRL_MenuUI/Settings.visible = true
	$CTRL_MenuUI/CTRL_Main.visible = false
	$CTRL_MenuUI/BTN_Update.visible = false
	$CTRL_MenuUI/LBL_UpdateStatus.visible = false

func _on_settings_back_pressed() -> void:
	$CTRL_MenuUI/Settings.visible = false
	$CTRL_MenuUI/CTRL_Main.visible = true
	$CTRL_MenuUI/BTN_Update.visible = true
	$CTRL_MenuUI/LBL_UpdateStatus.visible = true
