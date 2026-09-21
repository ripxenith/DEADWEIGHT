extends CanvasLayer

signal back_pressed


func _ready() -> void:
	$SettingsMenu/VBOX_LeftSide/BTN_Back.pressed.connect(_on_back_pressed)


func _on_back_pressed() -> void:
	back_pressed.emit()

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			back_pressed.emit()
			get_viewport().set_input_as_handled()
