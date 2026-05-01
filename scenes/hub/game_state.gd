extends Node

const TacticResourceClass = preload("res://resources/tactic_resource.gd")
const TacticSlotClass     = preload("res://resources/tactic_slot.gd")

const TACTICS_SAVE_PATH := "user://tactics.json"

# Formation position templates — half-field normalised (x: goal→halfway, y: top→bottom)
# Must stay in sync with field_overlay.gd FORMATIONS
const FORMATIONS : Dictionary = {
	"4-3-3": [
		Vector2(0.06, 0.50),
		Vector2(0.26, 0.12), Vector2(0.26, 0.37), Vector2(0.26, 0.63), Vector2(0.26, 0.88),
		Vector2(0.55, 0.22), Vector2(0.55, 0.50), Vector2(0.55, 0.78),
		Vector2(0.82, 0.12), Vector2(0.82, 0.50), Vector2(0.82, 0.88),
	],
	"4-4-2": [
		Vector2(0.06, 0.50),
		Vector2(0.26, 0.12), Vector2(0.26, 0.37), Vector2(0.26, 0.63), Vector2(0.26, 0.88),
		Vector2(0.55, 0.12), Vector2(0.55, 0.37), Vector2(0.55, 0.63), Vector2(0.55, 0.88),
		Vector2(0.82, 0.33), Vector2(0.82, 0.67),
	],
	"3-5-2": [
		Vector2(0.06, 0.50),
		Vector2(0.26, 0.20), Vector2(0.26, 0.50), Vector2(0.26, 0.80),
		Vector2(0.52, 0.08), Vector2(0.52, 0.30), Vector2(0.52, 0.50), Vector2(0.52, 0.70), Vector2(0.52, 0.92),
		Vector2(0.82, 0.33), Vector2(0.82, 0.67),
	],
	"4-2-3-1": [
		Vector2(0.06, 0.50),
		Vector2(0.26, 0.12), Vector2(0.26, 0.37), Vector2(0.26, 0.63), Vector2(0.26, 0.88),
		Vector2(0.46, 0.33), Vector2(0.46, 0.67),
		Vector2(0.67, 0.12), Vector2(0.67, 0.50), Vector2(0.67, 0.88),
		Vector2(0.84, 0.50),
	],
	"5-3-2": [
		Vector2(0.06, 0.50),
		Vector2(0.22, 0.08), Vector2(0.22, 0.29), Vector2(0.22, 0.50), Vector2(0.22, 0.71), Vector2(0.22, 0.92),
		Vector2(0.55, 0.22), Vector2(0.55, 0.50), Vector2(0.55, 0.78),
		Vector2(0.82, 0.33), Vector2(0.82, 0.67),
	],
	"3-4-3": [
		Vector2(0.06, 0.50),
		Vector2(0.26, 0.20), Vector2(0.26, 0.50), Vector2(0.26, 0.80),
		Vector2(0.55, 0.12), Vector2(0.55, 0.37), Vector2(0.55, 0.63), Vector2(0.55, 0.88),
		Vector2(0.82, 0.12), Vector2(0.82, 0.50), Vector2(0.82, 0.88),
	],
}

# Club info
var club_name : String = "Saca Chispas"
var club_team_key : String = "SACA CHISPAS"
var division : String = "E"

# Finances
var budget : int = 50000

# Calendar
var day : int = 1
var month : int = 3
var year : int = 2026

# Tactics – Array of TacticResource
var tactics : Array = []
var active_tactic_index : int = 0

func _ready() -> void:
	if not _load_tactics():
		_init_default_tactics()

func _init_default_tactics() -> void:
	tactics.clear()
	for tmpl in ["4-3-3", "4-4-2", "3-5-2"]:
		tactics.append(_make_tactic(tmpl, tmpl))

func _make_tactic(p_name: String, p_template: String) -> Resource:
	var t : Resource = TacticResourceClass.new(p_name, p_template)
	var positions : Array = FORMATIONS.get(p_template, FORMATIONS["4-3-3"])
	t.init_slots_from_positions(positions)
	return t

func get_active_tactic() -> Resource:
	return tactics[active_tactic_index]

func set_active_tactic(index: int) -> void:
	active_tactic_index = clampi(index, 0, tactics.size() - 1)
	save_tactics()

func add_tactic(tactic_name: String, template: String) -> void:
	tactics.append(_make_tactic(tactic_name, template))
	save_tactics()

func rename_tactic(index: int, new_name: String) -> void:
	if index >= 0 and index < tactics.size():
		tactics[index].tactic_name = new_name
	save_tactics()

func remove_tactic(index: int) -> void:
	if tactics.size() <= 1:
		return  # always keep at least one tactic
	tactics.remove_at(index)
	active_tactic_index = clampi(active_tactic_index, 0, tactics.size() - 1)
	save_tactics()

const MONTH_NAMES := [
	"", "January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"
]

func get_date_string() -> String:
	return "%s %d, %d" % [MONTH_NAMES[month], day, year]

func advance_day() -> void:
	day += 1
	var days_in_month := _days_in_month(month, year)
	if day > days_in_month:
		day = 1
		month += 1
		if month > 12:
			month = 1
			year += 1

func _days_in_month(m: int, y: int) -> int:
	match m:
		2:
			return 29 if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) else 28
		4, 6, 9, 11:
			return 30
		_:
			return 31

# ── Tactic persistence ────────────────────────────────────────────────────────

## Serialize all tactics to JSON and write to disk.
func save_tactics() -> void:
	var data : Array = []
	for t in tactics:
		var slots_arr : Array = []
		for s in t.slots:
			var entry : Dictionary = {
				"pos_x": s.position.x,
				"pos_y": s.position.y,
				"player": null
			}
			if s.player != null:
				entry["player"] = {
					"full_name": s.player.full_name,
					"skin_color": s.player.skin_color,
					"role": s.player.role,
					"age": s.player.age,
					"quality": s.player.quality,
					"pac": s.player.pac,
					"sho": s.player.sho,
					"pas": s.player.pas,
					"dri": s.player.dri,
					"def": s.player.def,
					"phy": s.player.phy,
				}
			slots_arr.append(entry)
		data.append({
			"tactic_name": t.tactic_name,
			"template": t.template,
			"slots": slots_arr,
		})
	var json_text := JSON.stringify(data, "\t")
	var file := FileAccess.open(TACTICS_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		printerr("GameState: could not open %s for writing" % TACTICS_SAVE_PATH)
		return
	file.store_string(json_text)
	file.close()

## Load tactics from disk. Returns true on success, false if no save file exists.
func _load_tactics() -> bool:
	if not FileAccess.file_exists(TACTICS_SAVE_PATH):
		return false
	var file := FileAccess.open(TACTICS_SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		printerr("GameState: failed to parse %s" % TACTICS_SAVE_PATH)
		return false
	file.close()
	var data : Array = json.data
	if data.is_empty():
		return false
	tactics.clear()
	for td in data:
		var t : Resource = TacticResourceClass.new(td["tactic_name"], td["template"])
		for sd in td["slots"]:
			var slot : Resource = TacticSlotClass.new(Vector2(sd["pos_x"], sd["pos_y"]))
			if sd["player"] != null:
				var pd : Dictionary = sd["player"]
				slot.player = PlayerResource.new(
					pd["full_name"],
					pd["skin_color"] as Player.SkinColor,
					pd["role"] as Player.Role,
					pd["age"],
					pd["quality"] as PlayerResource.Quality,
					pd["pac"], pd["sho"], pd["pas"],
					pd["dri"], pd["def"], pd["phy"]
				)
			t.slots.append(slot)
		tactics.append(t)
	active_tactic_index = clampi(active_tactic_index, 0, tactics.size() - 1)
	return true
