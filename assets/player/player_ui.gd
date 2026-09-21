extends CanvasLayer


@onready var money_label: Label = $UIContainer/HUD/MoneyLabel


#func _ready() -> void:
	#update_money_display()


#func _process(_delta: float) -> void:
	#update_money_display()


#func update_money_display() -> void:
	#var player_id: int = Network.get_local_or_steam_player_id()
	#var money: int = SaveManager.get_player_money(player_id)

	#money_label.text = "$" + str(money)
