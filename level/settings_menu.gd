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
	set_tab(SettingsTab.GAMEPLAY)


# ============================================================
# TAB MANAGEMENT
# ============================================================

func set_tab(tab: SettingsTab) -> void:
	current_tab = tab

	# Hide every panel first.
	gameplay.hide()
	controls.hide()
	graphics.hide()
	audio.hide()

	# Show the selected panel.
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
	restore_defaults()


func restore_defaults() -> void:
	# Reset settings here.
	#
	# Example:
	# graphics_quality = DEFAULT_GRAPHICS_QUALITY
	# master_volume = DEFAULT_MASTER_VOLUME
	# mouse_sensitivity = DEFAULT_MOUSE_SENSITIVITY
	#
	# Then update the UI controls.
	pass


# ============================================================
# APPLY
# ============================================================

func _on_btn_apply_pressed() -> void:
	handle_gameplay()
	handle_controls()
	handle_graphics()
	handle_audio()


# ============================================================
# SETTINGS HANDLERS
# ============================================================

func handle_gameplay() -> void:
	pass


func handle_controls() -> void:
	pass


func handle_graphics() -> void:
	pass


func handle_audio() -> void:
	pass
