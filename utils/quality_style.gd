class_name QualityStyle

## Player rarity → display color/name. Single source of truth — call this
## instead of duplicating the tables in every screen that shows a player.

const COLORS : Array[Color] = [
	Color("9e9e9e"),  # Common     – grey
	Color("4caf50"),  # Uncommon   – green
	Color("2196f3"),  # Rare       – blue
	Color("9c27b0"),  # Epic       – purple
	Color("ff9800"),  # Legendary  – gold
]
const NAMES := ["Común", "Poco Común", "Raro", "Épico", "Legendario"]
