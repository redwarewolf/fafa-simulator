class_name PlayerResource
extends Resource

enum Quality { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

# Identity
@export var full_name : String
@export var skin_color : Player.SkinColor
@export var role : Player.Role
@export var age : int
@export var quality : Quality

# Base stats (1-100)
@export var pac : int  # Pace
@export var sho : int  # Shooting
@export var pas : int  # Passing
@export var dri : int  # Dribbling
@export var def : int  # Defending
@export var phy : int  # Physicality

# Hidden runtime attributes (not saved to JSON, managed at runtime)
var stamina : float = 100.0
var morale : float = 100.0

func _init(
	p_name: String,
	p_skin: Player.SkinColor,
	p_role: Player.Role,
	p_age: int,
	p_quality: Quality,
	p_pac: int, p_sho: int, p_pas: int,
	p_dri: int, p_def: int, p_phy: int
) -> void:
	full_name = p_name
	skin_color = p_skin
	role = p_role
	age = p_age
	quality = p_quality
	pac = p_pac
	sho = p_sho
	pas = p_pas
	dri = p_dri
	def = p_def
	phy = p_phy

func overall() -> int:
	match role:
		Player.Role.GOALIE:
			return int(pac * 0.1 + sho * 0.05 + pas * 0.1 + dri * 0.1 + def * 0.4 + phy * 0.25)
		Player.Role.DEFENSE:
			return int(pac * 0.15 + sho * 0.05 + pas * 0.15 + dri * 0.1 + def * 0.35 + phy * 0.2)
		Player.Role.MIDFIELD:
			return int(pac * 0.15 + sho * 0.15 + pas * 0.25 + dri * 0.2 + def * 0.15 + phy * 0.1)
		Player.Role.OFFENSE:
			return int(pac * 0.25 + sho * 0.3 + pas * 0.15 + dri * 0.2 + def * 0.05 + phy * 0.05)
		_:
			return int((pac + sho + pas + dri + def + phy) / 6.0)

func quality_label() -> String:
	match quality:
		Quality.COMMON:    return "Common"
		Quality.UNCOMMON:  return "Uncommon"
		Quality.RARE:      return "Rare"
		Quality.EPIC:      return "Epic"
		Quality.LEGENDARY: return "Legendary"
		_:                 return "Unknown"

func training_cap() -> int:
	match quality:
		Quality.COMMON:    return 20
		Quality.UNCOMMON:  return 40
		Quality.RARE:      return 60
		Quality.EPIC:      return 80
		Quality.LEGENDARY: return 90
		_:                 return 20
