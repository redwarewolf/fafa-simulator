class_name PlayerValue

## Estimated transfer value for a player. Always computed on the fly from
## quality/overall/age — never stored, so it can never go stale.

const QUALITY_BASE : Array[int] = [
	30000,    # Common
	90000,    # Uncommon
	250000,   # Rare
	600000,   # Epic
	1500000,  # Legendary
]

const AGE_DECLINE_START := 31
const AGE_DECLINE_PER_YEAR := 0.08  ## 8% value lost per year past AGE_DECLINE_START

static func estimate(p: PlayerResource) -> int:
	var base : int = QUALITY_BASE[p.quality]
	var value := base * (p.overall() / 60.0)

	if p.age > AGE_DECLINE_START:
		var years_over := p.age - AGE_DECLINE_START
		value *= clampf(1.0 - years_over * AGE_DECLINE_PER_YEAR, 0.25, 1.0)

	return maxi(5000, roundi(value))
