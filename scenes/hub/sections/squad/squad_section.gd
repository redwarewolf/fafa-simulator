extends Control

const QUALITY_COLORS : Array[Color] = [
	Color("9e9e9e"),  # Common     – grey
	Color("4caf50"),  # Uncommon   – green
	Color("2196f3"),  # Rare       – blue
	Color("9c27b0"),  # Epic       – purple
	Color("ff9800"),  # Legendary  – gold
]

const COL_NAME := 0
const COL_OVR  := 1

# All available preset templates (cycled when pressing + New)
const PRESET_TEMPLATES : Array[String] = ["4-3-3", "4-4-2", "3-5-2", "4-2-3-1", "5-3-2", "3-4-3"]

@onready var roster_tree   : Tree           = $HBox/LeftColumn/RosterPanel/VBox/RosterTree
@onready var player_card   : Control        = $HBox/LeftColumn/PlayerCard
@onready var tactics_list  : VBoxContainer  = $HBox/RightColumn/TacticsPanel/TacticsLayout/TacticsListColumn/TacticsScrollContainer/TacticsList
@onready var tactics_scroll : ScrollContainer = $HBox/RightColumn/TacticsPanel/TacticsLayout/TacticsListColumn/TacticsScrollContainer
@onready var rename_button : Button         = $HBox/RightColumn/TacticsPanel/TacticsLayout/ButtonsColumn/RenameButton
@onready var lock_button   : Button         = $HBox/RightColumn/TacticsPanel/TacticsLayout/ButtonsColumn/LockButton
@onready var delete_button : Button         = $HBox/RightColumn/TacticsPanel/TacticsLayout/ButtonsColumn/DeleteTacticButton
@onready var field_overlay : Control        = $HBox/RightColumn/FieldAspect/FieldBorder/FieldInnerMargin/FieldOverlay

var players       : Array = []
var _sort_col     : int   = COL_OVR
var _sort_asc     : bool  = false
var _active_index : int   = 0  # local mirror of GameState.active_tactic_index

# Player currently being dragged from the roster
var _dragged_player : PlayerResource = null

func _ready() -> void:
	roster_tree.set_column_title(COL_NAME, "Name")
	roster_tree.set_column_title(COL_OVR,  "OVR")
	roster_tree.set_column_expand(COL_NAME, true)
	roster_tree.set_column_expand(COL_OVR, false)
	roster_tree.set_column_custom_minimum_width(COL_OVR, 48)
	# Forward drag events from the Tree back to this script
	roster_tree.set_drag_forwarding(_tree_get_drag_data, _tree_can_drop_data, _tree_drop_data)
	players = GameState.player_club.players
	_populate_tree()
	_active_index = GameState.active_tactic_index
	_populate_tactics()
	field_overlay.set_tactic(GameState.get_active_tactic())
	field_overlay.player_dropped.connect(_on_player_dropped)
	# Auto-select first row
	var first := roster_tree.get_root().get_first_child()
	if first:
		roster_tree.set_selected(first, COL_NAME)
		_show_player(first.get_metadata(COL_NAME))

# ── Roster tree ───────────────────────────────────────────────────────────────

func _populate_tree() -> void:
	roster_tree.clear()
	var root := roster_tree.create_item()

	var sorted := players.duplicate()
	if _sort_col == COL_NAME:
		sorted.sort_custom(func(a, b):
			return a.full_name < b.full_name if _sort_asc else a.full_name > b.full_name)
	else:
		sorted.sort_custom(func(a, b):
			return a.overall() < b.overall() if _sort_asc else a.overall() > b.overall())

	for p in sorted:
		var item := roster_tree.create_item(root)
		item.set_text(COL_NAME, p.full_name)
		item.set_text(COL_OVR,  str(p.overall()))
		item.set_text_alignment(COL_OVR, HORIZONTAL_ALIGNMENT_CENTER)
		item.set_metadata(COL_NAME, p)
		var qcolor : Color = QUALITY_COLORS[p.quality]
		item.set_custom_color(COL_NAME, qcolor)
		item.set_custom_color(COL_OVR,  qcolor)

func _show_player(p: PlayerResource) -> void:
	player_card.setup(p)

func _on_roster_tree_item_selected() -> void:
	var item := roster_tree.get_selected()
	if item == null:
		return
	_show_player(item.get_metadata(COL_NAME) as PlayerResource)

func _on_roster_tree_column_title_clicked(column: int, _mouse_button_index: int) -> void:
	if _sort_col == column:
		_sort_asc = !_sort_asc
	else:
		_sort_col = column
		_sort_asc = (column == COL_NAME)
	_populate_tree()
	var first := roster_tree.get_root().get_first_child()
	if first:
		roster_tree.set_selected(first, COL_NAME)
		_show_player(first.get_metadata(COL_NAME))

# ── Roster drag → field drop ──────────────────────────────────────────────────
# These are forwarded from roster_tree via set_drag_forwarding().

func _tree_get_drag_data(at_position: Vector2) -> Variant:
	var item := roster_tree.get_item_at_position(at_position)
	if item == null:
		return null
	var player := item.get_metadata(COL_NAME) as PlayerResource
	if player == null:
		return null
	_dragged_player = player

	# Drag preview: styled panel with player name in quality colour
	var preview := PanelContainer.new()
	var label   := Label.new()
	label.text = player.full_name
	label.add_theme_color_override("font_color", QUALITY_COLORS[player.quality])
	label.add_theme_font_size_override("font_size", 11)
	preview.add_child(label)
	preview.custom_minimum_size = Vector2(120, 24)
	roster_tree.set_drag_preview(preview)

	return { "type": "player", "player": player }

func _tree_can_drop_data(_at_position: Vector2, _data: Variant) -> bool:
	# The tree itself is never a drop target
	return false

func _tree_drop_data(_at_position: Vector2, _data: Variant) -> void:
	pass

func _on_player_dropped(_slot_index: int, _player: PlayerResource) -> void:
	_dragged_player = null
	GameState.save_tactics()

# ── Tactics ───────────────────────────────────────────────────────────────────

func _populate_tactics() -> void:
	for child in tactics_list.get_children():
		child.queue_free()
	for i in GameState.tactics.size():
		_add_tactic_button(i)
	delete_button.disabled = GameState.tactics.size() <= 1

func _add_tactic_button(index: int) -> void:
	var btn := Button.new()
	btn.text = GameState.tactics[index].tactic_name
	btn.toggle_mode = true
	btn.button_pressed = (index == _active_index)
	btn.pressed.connect(_on_tactic_selected.bind(index))
	tactics_list.add_child(btn)

func _on_tactic_selected(index: int) -> void:
	_active_index = index
	GameState.set_active_tactic(index)
	field_overlay.set_tactic(GameState.get_active_tactic())
	# Reset lock
	lock_button.button_pressed = false
	field_overlay.set_locked(false)
	# Refresh toggle state
	for i in tactics_list.get_child_count():
		var b := tactics_list.get_child(i) as Button
		if b:
			b.button_pressed = (i == index)

func _on_add_tactic_pressed() -> void:
	var used_templates : Array[String] = []
	for t in GameState.tactics:
		used_templates.append(t.template)

	var chosen_template : String = ""
	for tmpl in PRESET_TEMPLATES:
		if tmpl not in used_templates:
			chosen_template = tmpl
			break
	if chosen_template.is_empty():
		chosen_template = PRESET_TEMPLATES[GameState.tactics.size() % PRESET_TEMPLATES.size()]

	var base_name    := chosen_template
	var display_name := base_name
	var existing_names : Array[String] = []
	for t in GameState.tactics:
		existing_names.append(t.tactic_name)
	var copy_num := 2
	while display_name in existing_names:
		display_name = base_name + " #" + str(copy_num)
		copy_num += 1

	GameState.add_tactic(display_name, chosen_template)
	var new_index := GameState.tactics.size() - 1
	_add_tactic_button(new_index)
	_on_tactic_selected(new_index)

func _on_rename_tactic_pressed() -> void:
	if GameState.tactics.is_empty():
		return
	var dialog := AcceptDialog.new()
	dialog.title = "Rename Tactic"
	dialog.dialog_text = ""

	var edit := LineEdit.new()
	edit.text = GameState.tactics[_active_index].tactic_name
	edit.placeholder_text = "Tactic name"
	edit.select_all_on_focus = true
	dialog.add_child(edit)

	dialog.confirmed.connect(func():
		var new_name := edit.text.strip_edges()
		if new_name.is_empty():
			return
		GameState.rename_tactic(_active_index, new_name)
		var btn := tactics_list.get_child(_active_index) as Button
		if btn:
			btn.text = new_name
		dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2(300, 100))
	edit.grab_focus()

func _on_lock_toggled(pressed: bool) -> void:
	field_overlay.set_locked(pressed)

func _on_save_tactic_pressed() -> void:
	GameState.save_tactics()

func _on_delete_tactic_pressed() -> void:
	if GameState.tactics.size() <= 1:
		return
	GameState.remove_tactic(_active_index)
	_active_index = GameState.active_tactic_index
	_populate_tactics()
	field_overlay.set_tactic(GameState.get_active_tactic())
	lock_button.button_pressed = false
	field_overlay.set_locked(false)
