extends Node

var STEAM_APP_ID: int = 480
var STEAM_USERNAME: String = ""
var STEAM_ID: int = 0

var is_lobby_host: bool
var lobby_id: int
var lobby_memners: Array

func _init() -> void:
	OS.set_environment("SteamAppID", str(STEAM_APP_ID))
	OS.set_environment("SteamGameID", str(STEAM_APP_ID))

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Steam.steamInit()
	
	STEAM_ID = Steam.getSteamID()
	print(STEAM_ID)
	
	STEAM_USERNAME = Steam.getPersonaName()
	print(STEAM_USERNAME)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	Steam.run_callbacks()
