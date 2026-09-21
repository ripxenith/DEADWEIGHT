extends MarginContainer

@onready var pause_menu = $CNT_PauseMenu
@onready var settings: CanvasLayer = $Settings
@onready var player: CharacterBody3D = get_parent().get_parent().get_parent() as CharacterBody3D

@onready var settings_back_button = $Settings/SettingsMenu/VBOX_LeftSide/BTN_Back

var escape_was_pressed := false


func _ready() -> void:
	pause_menu.hide()
	settings.hide()

	if player != null:
		player.pause_menu_open = false

	# Connect the Settings Back button directly.
	if not settings_back_button.pressed.is_connected(_on_settings_back_pressed):
		settings_back_button.pressed.connect(_on_settings_back_pressed)

	call_deferred("_initialize_mouse")


func _initialize_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(_delta: float) -> void:
	var escape_pressed := Input.is_key_pressed(KEY_ESCAPE)

	if escape_pressed and not escape_was_pressed:
		_handle_escape()

	escape_was_pressed = escape_pressed


func _handle_escape() -> void:
	# Settings -> Pause Menu
	if settings.visible:
		_on_settings_back_pressed()
		return

	# Pause Menu -> Gameplay
	if pause_menu.visible:
		_close_pause_menu()
		return

	# Gameplay -> Pause Menu
	_open_pause_menu()


func _open_pause_menu() -> void:
	pause_menu.show()

	if player != null:
		player.pause_menu_open = true

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _close_pause_menu() -> void:
	pause_menu.hide()

	if player != null:
		player.pause_menu_open = false

	get_viewport().gui_release_focus()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_settings_btn_pressed() -> void:
	pause_menu.hide()
	settings.show()

	if player != null:
		player.pause_menu_open = true

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_settings_back_pressed() -> void:
	settings.hide()
	pause_menu.show()

	if player != null:
		player.pause_menu_open = true

	# We are still paused, so keep the mouse visible.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
