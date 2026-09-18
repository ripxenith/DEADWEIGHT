class_name UpdateManager
extends Node

# ==============================
# CONFIG
# ==============================

const CURRENT_VERSION := "0.0.1"

const VERSION_URL := "https://raw.githubusercontent.com/ripxenith/DEADWEIGHT/main/version.json"

const UPDATER_NAME := "DEADWEIGHTUpdater.exe"


# ==============================
# STATE
# ==============================

var latest_version := ""
var download_url := ""

var update_available := false
var checking := false


signal update_check_finished(update_available: bool)
signal update_check_failed()


# ==============================
# CHECK FOR UPDATE
# ==============================

func check_for_update() -> void:
	if checking:
		return

	checking = true

	var http := HTTPRequest.new()
	add_child(http)

	http.request_completed.connect(
		_on_version_request_completed.bind(http)
	)

	var error := http.request(VERSION_URL)

	if error != OK:
		push_error("Failed to start update check: " + error_string(error))
		checking = false
		http.queue_free()
		update_check_failed.emit()


func _on_version_request_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray,
	http: HTTPRequest
) -> void:

	http.queue_free()

	checking = false

	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("Update check failed. Result: " + str(result))
		update_check_failed.emit()
		return

	if response_code != 200:
		push_error("Update server returned HTTP " + str(response_code))
		update_check_failed.emit()
		return

	var json: Variant = JSON.parse_string(
		body.get_string_from_utf8()
	)

	if json == null:
		push_error("Could not parse version.json")
		update_check_failed.emit()
		return

	if not json.has("version"):
		push_error("version.json is missing 'version'")
		update_check_failed.emit()
		return

	if not json.has("download"):
		push_error("version.json is missing 'download'")
		update_check_failed.emit()
		return

	latest_version = str(json["version"])
	download_url = str(json["download"])

	update_available = is_newer_version(
		CURRENT_VERSION,
		latest_version
	)

	update_check_finished.emit(update_available)


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
# START UPDATE
# ==============================

func start_update() -> void:
	if not update_available:
		return

	var game_executable := OS.get_executable_path()

	var updater_path := game_executable.get_base_dir().path_join(
		UPDATER_NAME
	)

	if not FileAccess.file_exists(updater_path):
		push_error(
			"Updater not found: " + updater_path
		)

		return

	var arguments := [
		game_executable,
		download_url
	]

	OS.create_process(
		updater_path,
		arguments
	)

	get_tree().quit()
