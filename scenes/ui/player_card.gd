extends Control

const QUALITY_COLORS : Array[Color] = [
	Color("9e9e9e"),  # Common     – grey
	Color("4caf50"),  # Uncommon   – green
	Color("2196f3"),  # Rare       – blue
	Color("9c27b0"),  # Epic       – purple
	Color("ff9800"),  # Legendary  – gold
]
const QUALITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const ROLE_NAMES    := ["GK", "DEF", "MID", "FWD"]

const DEFAULT_PORTRAIT : Texture2D = preload("res://assets/art/characters/player_portrait_default.png")

@onready var background      : NinePatchRect  = $Background
@onready var portrait_border : NinePatchRect  = $VBox/Header/PortraitFrame/PortraitBorder
@onready var portrait        : TextureRect    = $VBox/Header/PortraitFrame/Portrait
@onready var player_name     : Label          = $VBox/Header/HeaderInfo/PlayerName
@onready var role_age      : Label          = $VBox/Header/HeaderInfo/RoleAge
@onready var quality_label : Label          = $VBox/Header/HeaderInfo/Quality
@onready var overall_label : Label          = $VBox/Header/HeaderInfo/Overall
@onready var pac_label     : Label          = $VBox/StatsGrid/PACLabel
@onready var sho_label     : Label          = $VBox/StatsGrid/SHOLabel
@onready var pas_label     : Label          = $VBox/StatsGrid/PASLabel
@onready var dri_label     : Label          = $VBox/StatsGrid/DRILabel
@onready var def_label     : Label          = $VBox/StatsGrid/DEFLabel
@onready var phy_label     : Label          = $VBox/StatsGrid/PHYLabel

func setup(p: PlayerResource) -> void:
	var qcolor : Color = QUALITY_COLORS[p.quality]

	background.modulate = qcolor
	portrait_border.modulate = qcolor
	portrait.texture = DEFAULT_PORTRAIT

	player_name.text = p.full_name
	player_name.add_theme_color_override("font_color", qcolor)

	role_age.text = "%s  •  Age %d" % [ROLE_NAMES[p.role], p.age]

	quality_label.text = QUALITY_NAMES[p.quality]
	quality_label.add_theme_color_override("font_color", qcolor)

	overall_label.text = "OVR  %d" % p.overall()

	pac_label.text = "PAC  %d" % p.pac
	sho_label.text = "SHO  %d" % p.sho
	pas_label.text = "PAS  %d" % p.pas
	dri_label.text = "DRI  %d" % p.dri
	def_label.text = "DEF  %d" % p.def
	phy_label.text = "PHY  %d" % p.phy
