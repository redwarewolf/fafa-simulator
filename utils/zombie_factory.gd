class_name ZombieFactory

## Harvests stats ("organs") from sacrificed players and stitches them into a
## new "zombie" PlayerResource. Mirrors PlayerFactory's role but works
## backwards — stats come first (from whichever organs were socketed) and
## quality is inferred from them afterward, instead of quality being rolled
## first and stats sampled from its band.

const STAT_KEYS := ["pac", "sho", "pas", "dri", "def", "phy"]

## Unfilled slot = no body part at all — the zombie just has a stat of 1
## there, and (see assemble()) that slot counts as age 1 for the average too.
const FILLER_STAT_VALUE := 1

## Returns 1-2 organ dicts for the requested stats, capturing the donor's raw
## (unmodified) base stat and age — modifiers are per-player state that
## shouldn't transfer onto whatever gets stitched together later.
static func harvest(donor: PlayerResource, stat_keys: Array) -> Array[Dictionary]:
	var organs : Array[Dictionary] = []
	for key in stat_keys:
		organs.append({
			"id": Time.get_ticks_usec() + organs.size(),
			"stat": key,
			"value": int(donor.get(key)),
			"donor_name": donor.full_name,
			"donor_quality": donor.quality,
			"donor_age": donor.age,
		})
	return organs

## organs_by_stat: {String stat_key: Dictionary organ} for whichever slots the
## player chose to fill; any stat missing from this dict defaults to
## FILLER_STAT_VALUE. Age comes out as the average donor age across all 6
## slots — an unfilled slot has no donor, so it counts as age 1, same as its
## stat.
static func assemble(full_name: String, role: Positions.Role, organs_by_stat: Dictionary) -> PlayerResource:
	var stats : Array = []
	var age_sum := 0
	for key in STAT_KEYS:
		if organs_by_stat.has(key):
			var organ : Dictionary = organs_by_stat[key]
			stats.append(int(organ["value"]))
			age_sum += int(organ["donor_age"])
		else:
			stats.append(FILLER_STAT_VALUE)
			age_sum += FILLER_STAT_VALUE
	var age := roundi(float(age_sum) / STAT_KEYS.size())
	var quality := _infer_quality(stats)
	return PlayerResource.new(
		full_name, Player.SkinColor.RADIOACTIVE, Player.HairColor.values().pick_random(),
		role, age, quality,
		stats[0], stats[1], stats[2], stats[3], stats[4], stats[5],
		"default", "zombie"
	)

## Picks a quality label by matching the average stat to PlayerFactory's
## STAT_RANGE bands (same tiers scouting/squad-gen use), the highest tier
## whose floor the average clears. A patchwork of Epic+Legendary organs reads
## as Epic/Legendary even though it was never "rolled" as one.
static func _infer_quality(stats: Array) -> PlayerResource.Quality:
	var avg := 0.0
	for s in stats:
		avg += s
	avg /= stats.size()
	for i in range(PlayerFactory.STAT_RANGE.size() - 1, -1, -1):
		if avg >= PlayerFactory.STAT_RANGE[i][0]:
			return i as PlayerResource.Quality
	return PlayerResource.Quality.COMMON
