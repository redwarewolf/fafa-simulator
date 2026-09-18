extends Control


const PORTRAIT_SHADER : Shader = preload("res://shaders/replace_color.gdshader")
const TEAM_PALETTE : Texture2D = preload("res://assets/art/palettes/teams-color-palette.png")
const SKIN_PALETTE : Texture2D = preload("res://assets/art/palettes/skin-colors-palette.png")
const HAIR_PALETTE : Texture2D = preload("res://assets/art/palettes/hair-colors-palette.png")

## Two readings of the same six numbers. BARS suits a tall narrow panel — the
## market's detail column, where you compare a stat against its own scale. RADAR
## suits a wide short one and makes players comparable by SHAPE, which is what
## the squad screen is for.
enum Layout { BARS, RADAR }
@export var layout : Layout = Layout.BARS

const STAT_KEYS := {
	"PAC": "pac", "SHO": "sho", "PAS": "pas", "DRI": "dri", "DEF": "def", "PHY": "phy",
}

@onready var background      : NinePatchRect  = $Background
@onready var portrait_border : NinePatchRect  = $VBox/Header/PortraitFrame/PortraitBorder
@onready var portrait        : TextureRect    = $VBox/Header/PortraitFrame/Portrait
@onready var player_name     : Label          = $VBox/Header/HeaderInfo/PlayerName
@onready var role_age      : Label          = $VBox/Header/HeaderInfo/RoleAge
@onready var quality_label : Label          = $VBox/Header/HeaderInfo/Quality
@onready var overall_label : Label          = $VBox/Header/HeaderInfo/Overall
@onready var stats         : VBoxContainer = $VBox/Stats
@onready var header        : HBoxContainer = $VBox/Header
@onready var radar_row     : HBoxContainer = $VBox/Header/Radar
@onready var radar         : StatRadar     = $VBox/Header/Radar/StatRadar
@onready var position_map  : PositionMap   = $VBox/Header/Radar/PositionsColumn/PositionMap
@onready var modifier_badges     : HBoxContainer  = $VBox/ModifierBadges
@onready var _modifier_tooltip       : PanelContainer = $ModifierTooltip
@onready var _modifier_tooltip_label : Label         = $ModifierTooltip/TooltipLabel

func _ready() -> void:
	stats.visible = layout == Layout.BARS
	radar_row.visible = layout == Layout.RADAR
	# In radar mode the header row IS the card, so it takes the height. In bars
	# mode it stays compact and the bars below get the room.
	header.size_flags_vertical = SIZE_EXPAND_FILL if layout == Layout.RADAR else SIZE_FILL
	var portrait_material := ShaderMaterial.new()
	portrait_material.shader = PORTRAIT_SHADER
	portrait_material.set_shader_parameter("team_palette", TEAM_PALETTE)
	portrait_material.set_shader_parameter("skin_palette", SKIN_PALETTE)
	portrait_material.set_shader_parameter("hair_palette", HAIR_PALETTE)
	portrait.material = portrait_material

## team_key matches an entry in Player.TEAMS (e.g. a ClubResource.team_key) —
## left blank for players not currently on a team, which renders as the
## default kit colour.
func setup(p: PlayerResource, team_key: String = "") -> void:
	var qcolor : Color = QualityStyle.COLORS[p.quality]

	background.modulate = qcolor
	portrait_border.modulate = qcolor
	_set_portrait(p, team_key)

	player_name.text = p.full_name
	player_name.add_theme_color_override("font_color", qcolor)

	role_age.text = tr("%s  •  %d años") % [Positions.label(p.role), p.age]

	quality_label.text = QualityStyle.NAMES[p.quality]
	quality_label.add_theme_color_override("font_color", qcolor)

	overall_label.text = "OVR  %d" % p.overall()

	if layout == Layout.RADAR:
		var bases := [p.pac, p.sho, p.pas, p.dri, p.def, p.phy]
		var effs := [
			p.get_effective_stat("pac"), p.get_effective_stat("sho"), p.get_effective_stat("pas"),
			p.get_effective_stat("dri"), p.get_effective_stat("def"), p.get_effective_stat("phy"),
		]
		radar.set_stats(bases, effs, qcolor)
		position_map.set_player_role(p.role)
		_populate_modifier_badges(p)
		return

	for key in STAT_KEYS:
		var stat : String = STAT_KEYS[key]
		_set_stat(key, int(p.get(stat)), p.get_effective_stat(stat), qcolor)
	_populate_modifier_badges(p)


## Crops a random pose out of this player's actual body-type spritesheet
## (same grid the match uses) and recolours it with the same team/skin/hair
## shader a Player instance gets, so the card shows this player, not a
## generic stand-in.
func _set_portrait(p: PlayerResource, team_key: String) -> void:
	var body_def : Dictionary = BodyTypes.DATA.get(p.body_type, BodyTypes.DATA["default"])
	var sheet : Texture2D = body_def["texture"]
	var hframes : int = body_def["hframes"]
	var vframes : int = body_def["vframes"]
	var frame_size := Vector2(sheet.get_width() / float(hframes), sheet.get_height() / float(vframes))
	var frame := p.get_portrait_frame()

	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(Vector2(frame % hframes, frame / hframes) * frame_size, frame_size)
	portrait.texture = atlas

	var mat := portrait.material as ShaderMaterial
	mat.set_shader_parameter("skin_color", p.skin_color)
	mat.set_shader_parameter("hair_color", p.hair_color)
	var team_color := Player.TEAMS.find(team_key)
	mat.set_shader_parameter("team_color", clampi(team_color, 0, Player.TEAMS.size() - 1))

## Resets the card to its "nothing selected yet" placeholder — blank
## portrait, dashes for name/role/quality/overall, "--" for every stat.
## Screens that start with no row selected (Youth, Hiring, Market) call this
## from their _clear_selection() instead of leaving the .tscn's design-time
## placeholder values (a hardcoded "Lionel Messi") on screen.
func clear() -> void:
	background.modulate = Color.WHITE
	portrait_border.modulate = Color.WHITE
	portrait.texture = null

	player_name.text = "----"
	player_name.remove_theme_color_override("font_color")

	role_age.text = "--  •  -- años"

	quality_label.text = "----"
	quality_label.remove_theme_color_override("font_color")

	overall_label.text = "OVR  --"

	_clear_modifier_badges()

	if layout == Layout.RADAR:
		radar.set_stats([0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0], Color.WHITE)
		position_map.clear()
		return

	for key in STAT_KEYS:
		_clear_stat(key)

func _clear_stat(key: String) -> void:
	var row := stats.get_node(key)
	var bar := row.get_node("Bar") as ProgressBar
	bar.value = 0
	var fill := bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	fill.bg_color = Color(1, 1, 1, 0.25)
	bar.add_theme_stylebox_override("fill", fill)
	(row.get_node("Value") as Label).text = "--"
	var delta_label := row.get_node("Delta") as Label
	delta_label.visible = false
	delta_label.text = ""

## Fills one stat row. The bar fills to the EFFECTIVE (modified) value, since
## that's the player's real in-game strength; the Value label stays the base
## stat in the default/neutral color, and Delta shows the signed difference
## colored green/positive or red/negative (see StatModifierStyle), hidden when
## there's no active modifier on this stat.
func _set_stat(key: String, base: int, effective: int, bar_color: Color) -> void:
	var row := stats.get_node(key)
	var bar := row.get_node("Bar") as ProgressBar
	bar.value = effective
	var fill := bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	fill.bg_color = bar_color
	bar.add_theme_stylebox_override("fill", fill)

	var value_label := row.get_node("Value") as Label
	value_label.text = str(base)
	value_label.remove_theme_color_override("font_color")

	var delta_label := row.get_node("Delta") as Label
	var d := effective - base
	if d == 0:
		delta_label.visible = false
		delta_label.text = ""
	else:
		delta_label.visible = true
		delta_label.text = "%+d" % d
		delta_label.add_theme_color_override("font_color", StatModifierStyle.color_for_delta(d))

func _clear_modifier_badges() -> void:
	for child in modifier_badges.get_children():
		child.queue_free()
	modifier_badges.visible = false
	_hide_modifier_tooltip()

## One small colored badge per active modifier — green for a permanent boost
## or any positive-percent entry, red for a debuff. Hovering shows the exact
## source/magnitude/remaining duration via a floating tooltip, same
## Timer-less hover pattern as a plain control's mouse_entered/exited (the
## polling HoverTimer field_overlay.gd uses is for a custom-drawn canvas with
## no per-element nodes to hang signals off; badges here are real Controls).
func _populate_modifier_badges(p: PlayerResource) -> void:
	_clear_modifier_badges()
	if p.modifiers.is_empty():
		return
	modifier_badges.visible = true
	for m : Dictionary in p.modifiers:
		var badge := ColorRect.new()
		badge.custom_minimum_size = Vector2(14, 14)
		badge.color = StatModifierStyle.color_for_delta(1 if float(m["pct"]) >= 0 else -1)
		badge.mouse_filter = Control.MOUSE_FILTER_STOP
		var tip := _format_modifier_tooltip(m)
		badge.mouse_entered.connect(_on_badge_hover.bind(badge, tip))
		badge.mouse_exited.connect(_hide_modifier_tooltip)
		modifier_badges.add_child(badge)

func _format_modifier_tooltip(m: Dictionary) -> String:
	var stat_txt := tr("todos los stats") if m["stat"] == "all" else String(m["stat"]).to_upper()
	var pct : float = m["pct"]
	var sign_txt := "+" if pct >= 0 else ""
	var text := "%s: %s%d%% %s" % [tr(m["label"]), sign_txt, int(pct), stat_txt]
	if not bool(m["permanent"]):
		var left : int = int(m["matches_remaining"])
		text += (tr(" (queda %d partido)") % left) if left == 1 else (tr(" (quedan %d partidos)") % left)
	return text

func _on_badge_hover(badge: ColorRect, text: String) -> void:
	_modifier_tooltip_label.text = text
	_modifier_tooltip.visible = true
	_modifier_tooltip.reset_size()
	_modifier_tooltip.position = badge.global_position - global_position + Vector2(0, -_modifier_tooltip.size.y - 4)

func _hide_modifier_tooltip() -> void:
	_modifier_tooltip.visible = false
