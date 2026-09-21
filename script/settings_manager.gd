extends Node


# ============================================================
# SETTINGS CONFIGURATION
# ============================================================

const SETTINGS_FILE := "user://settings.json"


# ============================================================
# DEFAULT SETTINGS
# ============================================================

const DEFAULT_SETTINGS := {
	"mouse_sensitivity": 50,
	"fov": 75.0,
	"master_volume": 1.0,
	"fps_limit": 0,
	"window_mode": DisplayServer.WINDOW_MODE_WINDOWED
}


# ============================================================
# SETTINGS DATA
# ============================================================

var settings: Dictionary = {}


# ============================================================
# INITIALIZATION
# ============================================================

func _ready() -> void:
	load_settings()


# ============================================================
# GET / SET
# ============================================================

func get_setting(setting_name: String) -> Variant:
	if settings.has(setting_name):
		return settings[setting_name]

	return DEFAULT_SETTINGS.get(setting_name, null)


func set_setting(setting_name: String, value: Variant) -> void:
	settings[setting_name] = value


# ============================================================
# SAVE / LOAD
# ============================================================

func save_settings() -> void:
	var file := FileAccess.open(
		SETTINGS_FILE,
		FileAccess.WRITE
	)

	if file == null:
		push_error("SETTINGS: Failed to open settings file for writing.")
		return

	file.store_string(
		JSON.stringify(settings, "\t")
	)

	file.close()

	print("SETTINGS: Settings saved.")


func load_settings() -> void:
	settings = {}

	if not FileAccess.file_exists(SETTINGS_FILE):
		print("SETTINGS: No settings file found. Using defaults.")
		return

	var file := FileAccess.open(
		SETTINGS_FILE,
		FileAccess.READ
	)

	if file == null:
		push_error("SETTINGS: Failed to open settings file.")
		return

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(text)

	if parse_result != OK:
		push_error("SETTINGS: Failed to parse settings file.")
		return

	var data: Variant = json.data

	if typeof(data) != TYPE_DICTIONARY:
		push_error("SETTINGS: Settings file is invalid.")
		return

	settings = data

	print("SETTINGS: Settings loaded.")


# ============================================================
# RESTORE DEFAULTS
# ============================================================

func restore_defaults() -> void:
	settings = DEFAULT_SETTINGS.duplicate(true)

	print("SETTINGS: Defaults restored.")


# ============================================================
# MOUSE SENSITIVITY
# ============================================================

func get_mouse_sensitivity() -> float:
	return float(
		get_setting("mouse_sensitivity")
	)


func set_mouse_sensitivity(value: float) -> void:
	set_setting(
		"mouse_sensitivity",
		value
	)


# ============================================================
# FOV
# ============================================================

func get_fov() -> float:
	return float(
		get_setting("fov")
	)


func set_fov(value: float) -> void:
	set_setting(
		"fov",
		value
	)


# ============================================================
# MASTER VOLUME
# ============================================================

func get_master_volume() -> float:
	return float(
		get_setting("master_volume")
	)


func set_master_volume(value: float) -> void:
	set_setting(
		"master_volume",
		value
	)


# ============================================================
# FPS LIMIT
# ============================================================

func get_fps_limit() -> int:
	return int(
		get_setting("fps_limit")
	)


func set_fps_limit(value: int) -> void:
	set_setting(
		"fps_limit",
		value
	)


# ============================================================
# WINDOW MODE
# ============================================================

func get_window_mode() -> int:
	return int(
		get_setting("window_mode")
	)


func set_window_mode(value: int) -> void:
	set_setting(
		"window_mode",
		value
	)
