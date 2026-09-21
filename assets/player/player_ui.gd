extends CanvasLayer


@onready var money_label: Label = $UIContainer/HUD/MoneyLabel


var displayed_money: int = -1


func _ready() -> void:
	update_money_display()


func _process(_delta: float) -> void:
	update_money_display()


func update_money_display() -> void:

	var peer_id := multiplayer.get_unique_id()

	var player_id: int = Network.get_player_id(
		peer_id
	)

	if player_id <= 0:
		return

	var money: int = SaveManager.get_player_money(
		player_id
	)

	# Don't update the label if the amount hasn't changed.
	if money == displayed_money:
		return

	displayed_money = money

	money_label.text = "₡" + str(money)
