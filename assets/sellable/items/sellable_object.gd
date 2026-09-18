extends RigidBody3D
class_name SellableObject


@export var object_definition: ObjectDefinition


@onready var price_label: Label3D = $price


@export_category("Generated Item Data")

@export var rarity: String = "Common":
	set(value):
		rarity = value

		if is_node_ready():
			update_price_display()


@export var sell_value: int = 0:
	set(value):
		sell_value = value

		if is_node_ready():
			update_price_display()


var normal_gravity_scale: float = 1.0


func _ready() -> void:
	normal_gravity_scale = gravity_scale

	print(
		"SELLABLE OBJECT READY: ",
		get_path()
	)

	print(
		"PRICE LABEL: ",
		price_label
	)

	print(
		"OBJECT DEFINITION: ",
		object_definition
	)

	# Only the server generates random item data.
	if multiplayer.is_server():
		if rarity == "Common" and sell_value == 0:
			generate_value()

	call_deferred("update_price_display")


func generate_value() -> void:
	if object_definition == null:
		print(
			"SELLABLE OBJ ERROR: "
			+ "object_definition is NULL"
		)
		return

	rarity = ObjectGenerator.generate_rarity()

	sell_value = ObjectGenerator.generate_value(
		object_definition.base_value,
		rarity
	)

	print(
		"GENERATED ITEM: ",
		rarity,
		" $",
		sell_value
	)


func update_price_display() -> void:
	if price_label == null:
		return

	price_label.text = "$" + str(sell_value)

	price_label.modulate = get_rarity_color(
		rarity
	)


func get_rarity_color(
	rarity_name: String
) -> Color:

	match rarity_name:

		"Common":
			return Color.WHITE

		"Uncommon":
			return Color("#55FF55")

		"Rare":
			return Color("#5599FF")

		"Epic":
			return Color("#CC55FF")

		"Legendary":
			return Color("#FFAA00")

		_:
			return Color.WHITE


func set_zero_gravity(
	enabled: bool
) -> void:

	if enabled:
		gravity_scale = 0.0
	else:
		gravity_scale = normal_gravity_scale
