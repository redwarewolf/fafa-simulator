extends TextureRect

@export var actors_container : ActorsContainer
@export var world_size := Vector2(2350.0, 1225.0)

@export var left_team_color := Color(0.2, 0.8, 1.0) # Cyan-ish
@export var right_team_color := Color(1.0, 0.3, 0.3) # Red-ish
@export var ball_color := Color.WHITE

@onready var markers : Control = $Markers

var player_markers : Dictionary = {}
var ball_marker : ColorRect

func _process(_delta: float) -> void:
	if not is_instance_valid(actors_container):
		return
		
	sync_team(actors_container.left_team, left_team_color)
	sync_team(actors_container.right_team, right_team_color)
	
	if is_instance_valid(actors_container.ball):
		if not is_instance_valid(ball_marker):
			ball_marker = create_marker(ball_color, Vector2(6, 6))
			
		# Map ball position
		update_marker_position(ball_marker, actors_container.ball.global_position)

func sync_team(team: Array[Player], color: Color) -> void:
	for player in team:
		if not is_instance_valid(player):
			continue
			
		if not player_markers.has(player) or not is_instance_valid(player_markers[player]):
			var marker = create_marker(color, Vector2(4, 4))
			player_markers[player] = marker
			
		update_marker_position(player_markers[player], player.global_position)

func create_marker(color: Color, m_size: Vector2) -> ColorRect:
	var rect = ColorRect.new()
	rect.color = color
	rect.custom_minimum_size = m_size
	rect.size = m_size
	markers.add_child(rect)
	return rect

func update_marker_position(marker: ColorRect, real_pos: Vector2) -> void:
	var nx = clamp(real_pos.x / world_size.x, 0.0, 1.0)
	var ny = clamp(real_pos.y / world_size.y, 0.0, 1.0)
	
	var mx = nx * size.x
	var my = ny * size.y
	
	# Center the visual dot exactly on the coordinate
	marker.position = Vector2(mx - marker.size.x / 2.0, my - marker.size.y / 2.0)
