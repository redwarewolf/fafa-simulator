class_name PlayerWage

## Estimated WEEKLY wage for a player, paid every payday (GameState.
## PAY_PERIOD_DAYS). Always computed on the fly from quality/overall — never
## stored, so it can never go stale. Mirrors PlayerValue's transfer-value
## formula on an upkeep scale. Tuned with tools/economy_sim.tscn: a starting
## Division E squad costs ~$2k a week.

const QUALITY_BASE : Array[int] = [
	240,     # Common
	720,     # Uncommon
	1920,    # Rare
	4800,    # Epic
	12000,   # Legendary
]

static func estimate(p: PlayerResource) -> int:
	if SpecialPlayerTypes.DATA.has(p.special_type):
		return SpecialPlayerTypes.DATA[p.special_type].get("wage", 0)
	var base : int = QUALITY_BASE[p.quality]
	return maxi(0, roundi(base * (p.overall() / 60.0)))
