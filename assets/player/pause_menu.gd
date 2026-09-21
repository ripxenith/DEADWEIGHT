extends MarginContainer

@onready var pause_menu = self

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_resume_btn_pressed() -> void:
		pause_menu.hide()
		get_viewport().gui_release_focus()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_settings_btn_pressed() -> void:
	pass # Replace with function body.


func _on_quit_to_menu_btn_pressed() -> void:
	get_tree().change_scene_to_file("res://level/main menu.tscn")


func _on_quit_game_btn_pressed() -> void:
	get_tree().quit()
