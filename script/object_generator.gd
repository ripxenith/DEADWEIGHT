extends Node
class_name ObjectGenerator


const RARITIES := {
	"Common": {
		"weight": 60.0,
		"multiplier_min": 0.85,
		"multiplier_max": 1.15
	},
	"Uncommon": {
		"weight": 25.0,
		"multiplier_min": 1.25,
		"multiplier_max": 1.75
	},
	"Rare": {
		"weight": 10.0,
		"multiplier_min": 2.0,
		"multiplier_max": 3.0
	},
	"Epic": {
		"weight": 4.0,
		"multiplier_min": 4.0,
		"multiplier_max": 6.0
	},
	"Legendary": {
		"weight": 1.0,
		"multiplier_min": 9.0,
		"multiplier_max": 13.0
	}
}


static func generate_rarity() -> String:
	var total_weight: float = 0.0

	for rarity in RARITIES:
		total_weight += RARITIES[rarity]["weight"]

	var roll: float = randf_range(0.0, total_weight)

	for rarity in RARITIES:
		roll -= RARITIES[rarity]["weight"]

		if roll <= 0.0:
			return rarity

	return "Common"


static func generate_value(base_value: int, rarity: String) -> int:
	var data: Dictionary = RARITIES[rarity]

	var multiplier: float = randf_range(
		data["multiplier_min"],
		data["multiplier_max"]
	)

	return roundi(base_value * multiplier)
