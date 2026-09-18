class_name ClubLogo

## Applies the correct logo texture (and shader if needed) to a TextureRect.
## Single source of truth — call this from any scene instead of duplicating logic.

const _SHADER    := preload("res://shaders/logo_color.gdshader")
const _PORTRAIT  := preload("res://assets/art/football_club_logos/fc_portrait.png")
const _TMPL_BASE := "res://assets/art/football_club_logos/fc_template_%d.png"
const _SHEET_BASE := "res://assets/art/football_club_logos/fc_template_%d_pixelsheet.png"

static func apply(target: TextureRect, club: ClubResource) -> void:
	if club == null:
		target.texture        = _PORTRAIT
		target.material       = null
		target.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		return

	if club.logo_template > 0:
		var tmpl_tex  := load(_TMPL_BASE  % club.logo_template) as Texture2D
		var sheet_tex := load(_SHEET_BASE % club.logo_template) as Texture2D
		var mat := ShaderMaterial.new()
		mat.shader = _SHADER
		mat.set_shader_parameter("pixelsheet",      sheet_tex)
		mat.set_shader_parameter("primary_color",   club.primary_color)
		mat.set_shader_parameter("secondary_color", club.secondary_color)
		target.texture        = tmpl_tex
		target.material       = mat
		target.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
		target.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		target.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	elif not club.logo_path.is_empty() and ResourceLoader.exists(club.logo_path):
		target.texture        = load(club.logo_path)
		target.material       = null
		target.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
		target.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		target.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	else:
		target.texture        = _PORTRAIT
		target.material       = null
		target.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
		target.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		target.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
