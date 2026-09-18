extends Control

## Lets the player name their club, pick a crest template + colors (with a
## live preview rendered through the same ClubLogo.apply() the Hub uses), and
## confirm to generate a brand-new Division E: their own club plus 7
## procedurally-generated AI clubs (see ClubFactory/SquadGenerator).

const BUTTON_SOUND_TRACK := "res://assets/music/ui-button-sound.mp3"
const DIVISION := "E"

@onready var name_edit : LineEdit = $Margin/Root/Body/LeftColumn/NameEdit
@onready var error_label : Label = $Margin/Root/Body/LeftColumn/ErrorLabel
@onready var template1_button : TextureButton = $Margin/Root/Body/LeftColumn/CrestRow/Template1Button
@onready var template2_button : TextureButton = $Margin/Root/Body/LeftColumn/CrestRow/Template2Button
@onready var primary_button : ColorPickerButton = $Margin/Root/Body/LeftColumn/ColorsGrid/PrimaryColorButton
@onready var secondary_button : ColorPickerButton = $Margin/Root/Body/LeftColumn/ColorsGrid/SecondaryColorButton
@onready var crest_preview : TextureRect = $Margin/Root/Body/RightColumn/PreviewCenter/CrestPreview
@onready var preview_name_label : Label = $Margin/Root/Body/RightColumn/PreviewNameLabel
@onready var button_sound : AudioStreamPlayer = $ButtonSound

var _selected_template : int = 1

func _ready() -> void:
	button_sound.stream = load(BUTTON_SOUND_TRACK)
	for button in _find_buttons(self):
		button.pressed.connect(_play_button_sound)
	error_label.add_theme_color_override("font_color", HubPalette.LOSS)
	_select_template(1)
	_refresh_preview()

func _find_buttons(node: Node) -> Array:
	var result : Array = []
	for child in node.get_children():
		if child is BaseButton:
			result.append(child)
		result.append_array(_find_buttons(child))
	return result

func _play_button_sound() -> void:
	button_sound.play()

func _on_template_selected(template: int) -> void:
	_select_template(template)
	_refresh_preview()

func _select_template(template: int) -> void:
	_selected_template = template
	# No dedicated "selected" art — dim whichever template isn't chosen.
	template1_button.modulate = Color.WHITE if template == 1 else Color(0.5, 0.5, 0.5)
	template2_button.modulate = Color.WHITE if template == 2 else Color(0.5, 0.5, 0.5)

func _on_color_changed(_color: Color) -> void:
	_refresh_preview()

func _on_name_changed(_new_text: String) -> void:
	_refresh_preview()
	if error_label.visible and not name_edit.text.strip_edges().is_empty():
		error_label.visible = false

func _refresh_preview() -> void:
	var scratch := ClubResource.new(
		"", "", "", DIVISION,
		primary_button.color, secondary_button.color,
		"", _selected_template, 0, 0
	)
	ClubLogo.apply(crest_preview, scratch)
	var typed := name_edit.text.strip_edges()
	preview_name_label.text = typed if not typed.is_empty() else "Tu Club"

func _on_randomize_pressed() -> void:
	_select_template(randi_range(1, 2))
	primary_button.color = Color.from_hsv(randf(), randf_range(0.55, 0.9), randf_range(0.6, 0.95))
	secondary_button.color = Color.from_hsv(randf(), randf_range(0.55, 0.9), randf_range(0.6, 0.95))
	_refresh_preview()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")

func _on_start_pressed() -> void:
	var display_name := name_edit.text.strip_edges()
	if display_name.is_empty():
		error_label.text = "Ingresá un nombre de club"
		error_label.visible = true
		return
	error_label.visible = false

	# Ids must stay unique across every division, not just E, since they're
	# all flat keys in the one DataLoader.clubs dictionary.
	var taken_ids : Array = []
	for existing : ClubResource in DataLoader.clubs.values():
		if existing.division != DIVISION:
			taken_ids.append(existing.id)
	var taken_names : Array = [display_name]

	var player_id := ClubFactory.unique_slug(display_name, taken_ids)
	taken_ids.append(player_id)

	var player_club := ClubResource.new(
		player_id, display_name, ClubFactory.team_key_for(display_name), DIVISION,
		primary_button.color, secondary_button.color,
		"", _selected_template,
		ClubFactory.starting_budget(DIVISION), 0
	)
	player_club.fans = FanEconomy.STARTING_FANS
	player_club.players = SquadGenerator.generate_squad(ClubFactory.own_odds_for(DIVISION))

	var ai_clubs := ClubFactory.generate_ai_clubs(DIVISION, 7, taken_names, taken_ids)

	GameState.start_new_career(player_club, ai_clubs)
	get_tree().change_scene_to_file("res://scenes/hub/hub.tscn")
