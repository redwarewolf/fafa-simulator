@tool
extends AspectRatioContainer

# Keeps custom_minimum_size.y in sync with the actual width / ratio,
# so the VBoxContainer never collapses or over-expands this node.
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_READY:
		custom_minimum_size.y = size.x / ratio
