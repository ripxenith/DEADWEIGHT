extends RigidBody3D

@export var object_definition: ObjectDefinition

@onready var price_label: Label3D = $price

var rarity: String = "Common"
var sell_value: int = 0

var normal_gravity_scale: float = 1.0


func _ready() -> void:
	normal_gravity_scale = gravity_scale

	if object_definition:
		rarity = ObjectGenerator.generate_rarity()

		sell_value = ObjectGenerator.generate_value(
			object_definition.base_value,
			rarity
		)

		price_label.text = str("$", sell_value)
		price_label.modulate = get_rarity_color(rarity)


func get_rarity_color(rarity_name: String) -> Color:
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


func set_zero_gravity(enabled: bool) -> void:
	if enabled:
		gravity_scale = 0.0
	else:
		gravity_scale = normal_gravity_scale
