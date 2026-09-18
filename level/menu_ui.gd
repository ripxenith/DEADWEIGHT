extends CanvasLayer

const LOBBY_LEVEL = preload("res://level/environment/open_world.tscn")
const PLAYER = preload("res://assets/player/player.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if OS.has_feature('server'):
		Network.start_server()
		add_world()
		hide()
		print_debug("ready")


# Called every frame. 'delta' is the elapsed time since the previous frame.
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
