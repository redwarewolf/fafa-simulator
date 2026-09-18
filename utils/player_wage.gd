class_name PlayerWage

## Estimated monthly wage for a player. Always computed on the fly from
## quality/overall — never stored, so it can never go stale. Mirrors
## PlayerValue's transfer-value formula but on a monthly-upkeep scale.

const QUALITY_BASE : Array[int] = [
	40,    # Common
	120,   # Uncommon
	320,   # Rare
	800,   # Epic
	2000,  # Legendary
]

static func estimate(p: PlayerResource) -> int:
	if SpecialPlayerTypes.DATA.has(p.special_type):
		return SpecialPlayerTypes.DATA[p.special_type].get("wage", 0)
	var base : int = QUALITY_BASE[p.quality]
	return maxi(0, roundi(base * (p.overall() / 60.0)))
