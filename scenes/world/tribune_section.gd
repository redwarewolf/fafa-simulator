class_name TribuneSection
extends Sprite2D

## One tribune stand: a base sprite plus 35 fixed seat slots. Seats start
## hidden; fill_seats() randomly occupies a fraction of them per match with a
## random fan variation, all in the neutral mood for now.

const FAN_IDLE_SHADER := preload("res://shaders/fan_idle_sway.gdshader")
const FRAME_SIZE := Vector2(164, 197) # one fan cell in tribune-fans.png
const FAN_VARIATIONS := 8             # columns = fan look
const MOOD_NEUTRAL := 0               # row 0; angry=1, happy=2 reserved for later

# Only these two columns have hair colorimetrically separable from skin in
# this art (see fan_idle_sway.gdshader) — brown/black-haired columns are left
# untouched rather than risk recoloring skin.
const HAIR_VARIANT_NONE := 0
const HAIR_VARIANT_BLONDE := 1
const HAIR_VARIANT_REDHEAD := 2
const BLONDE_COLUMN := 2
const REDHEAD_COLUMN := 4

const RANDOM_HAIR_COLORS : Array[Color] = [
	Color("e8c170"), # blonde
	Color("a97c50"), # light brown
	Color("4a3423"), # dark brown
	Color("1a1a1a"), # black
	Color("8b2e2e"), # dark red
	Color("888888"), # gray
	Color("2b3a67"), # dark blue
	Color("6fa8dc"), # light blue
	Color("4a8f4a"), # green
	Color("8855bb"), # purple
]

# Realistic skin tones, applied to every seat regardless of column — the
# shader isolates skin via a face/neck UV box rather than hair-specific hue
# ranges, so it doesn't need to know which variation is showing.
const RANDOM_SKIN_COLORS : Array[Color] = [
	Color("f2c9a1"),
	Color("e0ac69"),
	Color("c68642"),
	Color("8d5524"),
	Color("5c3a21"),
	Color("3b2314"),
]

@onready var seats : Array = get_children() # Array[Sprite2D], size 35


func _ready() -> void:
	for seat in seats:
		seat.visible = false
		var mat := ShaderMaterial.new()
		mat.shader = FAN_IDLE_SHADER
		mat.set_shader_parameter("pivot_y", FRAME_SIZE.y / 2.0)
		mat.set_shader_parameter("time_offset", randf() * TAU)
		seat.material = mat


## rate in [0,1]; randomly occupies round(rate * seats.size()) seats with a
## random fan variation. Not idempotent by design — call once per match.
func fill_seats(rate: float) -> void:
	rate = clampf(rate, 0.0, 1.0)
	var target := int(round(rate * seats.size()))
	var order := range(seats.size())
	order.shuffle()
	var occupied := {}
	for i in target:
		occupied[order[i]] = true

	for i in seats.size():
		var seat : Sprite2D = seats[i]
		seat.visible = occupied.has(i)
		if seat.visible:
			var column := randi() % FAN_VARIATIONS
			seat.region_rect = Rect2(
				column * FRAME_SIZE.x, MOOD_NEUTRAL * FRAME_SIZE.y,
				FRAME_SIZE.x, FRAME_SIZE.y)

			var hair_variant := HAIR_VARIANT_NONE
			if column == BLONDE_COLUMN:
				hair_variant = HAIR_VARIANT_BLONDE
			elif column == REDHEAD_COLUMN:
				hair_variant = HAIR_VARIANT_REDHEAD
			var mat := seat.material as ShaderMaterial
			mat.set_shader_parameter("hair_variant", hair_variant)
			if hair_variant != HAIR_VARIANT_NONE:
				mat.set_shader_parameter("hair_color", RANDOM_HAIR_COLORS.pick_random())
			mat.set_shader_parameter("skin_color", RANDOM_SKIN_COLORS.pick_random())


## Recolors every seat's kit (red stripes/scarf -> primary, white -> secondary)
## to match the home club, via fan_idle_sway.gdshader's HSV-range remap.
func set_fan_colors(primary: Color, secondary: Color) -> void:
	for seat in seats:
		var mat := seat.material as ShaderMaterial
		mat.set_shader_parameter("primary_color", primary)
		mat.set_shader_parameter("secondary_color", secondary)
