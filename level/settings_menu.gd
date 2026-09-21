extends Panel


# ============================================================
# SETTINGS PANELS
# ============================================================

@onready var gameplay: ScrollContainer = $CNT_Gameplay
@onready var controls: ScrollContainer = $CNT_Controls
@onready var graphics: ScrollContainer = $CNT_Graphics
@onready var audio: ScrollContainer = $CNT_Audio
@onready var confirm: Panel = $CNT_Confirm


# ============================================================
# TAB BUTTONS
# ============================================================

@onready var gameplay_button: Button = $VBOX_LeftSide/BTN_Gameplay
@onready var controls_button: Button = $VBOX_LeftSide/BTN_Controls
@onready var graphics_button: Button = $VBOX_LeftSide/BTN_Graphics
@onready var audio_button: Button = $VBOX_LeftSide/BTN_Audio


# ============================================================
# SETTINGS CONTROLS
# ============================================================

@onready var sld_sensitivity: HSlider = $CNT_Gameplay/MarginContainer/VBoxContainer/HBOX_Sensitivity/SLD_Sensitivity

@onready var lne_sensitivity: LineEdit = $CNT_Gameplay/MarginContainer/VBoxContainer/HBOX_Sensitivity/LNE_Sensitivity

@onready var optb_window: OptionButton = $CNT_Graphics/MarginContainer/VBoxContainer/HBOX_Window/OPTB_Window

@onready var sld_master_volume: HSlider = $CNT_Audio/MarginContainer/VBoxContainer/HBOX_Sensitivity/SLD_MasterVolume


# ============================================================
# STATE
# ============================================================

enum SettingsTab {
	GAMEPLAY,
	CONTROLS,
	GRAPHICS,
	AUDIO
}

var current_tab: SettingsTab = SettingsTab.GAMEPLAY


# ============================================================
# INITIALIZATION
# ============================================================

func _ready() -> void:
	confirm.hide()

	# Connect sensitivity controls.
	sld_sensitivity.value_changed.connect(_on_sensitivity_slider_changed)
	lne_sensitivity.text_submitted.connect(_on_sensitivity_text_submitted)
	lne_sensitivity.focus_exited.connect(_on_sensitivity_focus_exited)

	_load_settings_into_ui()

	set_tab(SettingsTab.GAMEPLAY)


# ============================================================
# LOAD SETTINGS INTO UI
# ============================================================

func _load_settings_into_ui() -> void:
	# Mouse sensitivity
	var sensitivity := Settings.get_mouse_sensitivity()

	sld_sensitivity.value = sensitivity
	lne_sensitivity.text = _format_number(sensitivity)

	# Master volume
	sld_master_volume.value = Settings.get_master_volume()

	# Window mode
	_set_window_option(Settings.get_window_mode())


# ============================================================
# SENSITIVITY
# ============================================================

func _on_sensitivity_slider_changed(value: float) -> void:
	lne_sensitivity.text = _format_number(value)


func _on_sensitivity_text_submitted(_text: String) -> void:
	_apply_sensitivity_text()


func _on_sensitivity_focus_exited() -> void:
	_apply_sensitivity_text()


func _apply_sensitivity_text() -> void:
	var text := lne_sensitivity.text.strip_edges()

	# If the field is empty or invalid, restore the current slider value.
	if text.is_empty() or not text.is_valid_float():
		lne_sensitivity.text = _format_number(sld_sensitivity.value)
		return

	var sensitivity := text.to_float()

	# Keep the typed value within the slider's configured range.
	sensitivity = clamp(
		sensitivity,
		sld_sensitivity.min_value,
		sld_sensitivity.max_value
	)

	sld_sensitivity.value = sensitivity
	lne_sensitivity.text = _format_number(sensitivity)


func _format_number(value: float) -> String:
	# Show whole numbers without ".0".
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))

	return str(snapped(value, 0.01))


# ============================================================
# WINDOW MODE
# ============================================================

func _set_window_option(window_mode: int) -> void:
	match window_mode:
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			optb_window.select(0)

		DisplayServer.WINDOW_MODE_FULLSCREEN:
			optb_window.select(1)

		DisplayServer.WINDOW_MODE_WINDOWED:
			optb_window.select(2)

		_:
			optb_window.select(2)


func _get_selected_window_mode() -> int:
	match optb_window.selected:
		0:
			return DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

		1:
			return DisplayServer.WINDOW_MODE_FULLSCREEN

		2:
			return DisplayServer.WINDOW_MODE_WINDOWED

	return DisplayServer.WINDOW_MODE_WINDOWED


# ============================================================
# TAB MANAGEMENT
# ============================================================

func set_tab(tab: SettingsTab) -> void:
	current_tab = tab

	gameplay.hide()
	controls.hide()
	graphics.hide()
	audio.hide()

	match tab:
		SettingsTab.GAMEPLAY:
			gameplay.show()

		SettingsTab.CONTROLS:
			controls.show()

		SettingsTab.GRAPHICS:
			graphics.show()

		SettingsTab.AUDIO:
			audio.show()

	update_tab_buttons()


func update_tab_buttons() -> void:
	gameplay_button.button_pressed = current_tab == SettingsTab.GAMEPLAY
	controls_button.button_pressed = current_tab == SettingsTab.CONTROLS
	graphics_button.button_pressed = current_tab == SettingsTab.GRAPHICS
	audio_button.button_pressed = current_tab == SettingsTab.AUDIO


# ============================================================
# TAB BUTTONS
# ============================================================

func _on_btn_gameplay_pressed() -> void:
	set_tab(SettingsTab.GAMEPLAY)


func _on_btn_controls_pressed() -> void:
	set_tab(SettingsTab.CONTROLS)


func _on_btn_graphics_pressed() -> void:
	set_tab(SettingsTab.GRAPHICS)


func _on_btn_audio_pressed() -> void:
	set_tab(SettingsTab.AUDIO)


# ============================================================
# RESTORE DEFAULTS
# ============================================================

func _on_btn_restore_defaults_pressed() -> void:
	confirm.show()


func _on_btn_no_pressed() -> void:
	confirm.hide()


func _on_btn_yes_pressed() -> void:
	confirm.hide()

	Settings.restore_defaults()
	_load_settings_into_ui()


# ============================================================
# APPLY
# ============================================================

func _on_btn_apply_pressed() -> void:
	# Make sure a manually typed sensitivity value is processed
	# before saving.
	_apply_sensitivity_text()

	handle_gameplay()
	handle_controls()
	handle_graphics()
	handle_audio()

	Settings.save_settings()


# ============================================================
# SETTINGS HANDLERS
# ============================================================

func handle_gameplay() -> void:
	Settings.set_mouse_sensitivity(
		sld_sensitivity.value
	)


func handle_controls() -> void:
	pass


func handle_graphics() -> void:
	var window_mode := _get_selected_window_mode()

	Settings.set_window_mode(window_mode)

	DisplayServer.window_set_mode(window_mode)


func handle_audio() -> void:
	var volume := sld_master_volume.value

	Settings.set_master_volume(volume)

	# Apply to the Master audio bus.
	var db := linear_to_db(volume)

	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("Master"),
		db
	)
