class_name LockedHint

## Call-to-action under a "hire X to unlock this" message (Youth, Lab,
## Training, Hiring): a button straight to Club › Personal, where that hire
## happens, instead of leaving the player to go find it. The button follows
## the message's visibility, so each screen's existing lock logic still
## decides when it shows.

static func attach(message: Label) -> Button:
	var btn := Button.new()
	btn.text = TranslationServer.translate("Ir a Club > Personal")
	btn.theme_type_variation = &"PrimaryButton"
	btn.focus_mode = Control.FOCUS_NONE
	btn.anchor_left = 0.5
	btn.anchor_right = 0.5
	btn.anchor_top = 0.5
	btn.anchor_bottom = 0.5
	btn.offset_left = -110.0
	btn.offset_right = 110.0
	btn.offset_top = 22.0
	btn.offset_bottom = 54.0
	btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	btn.visible = message.visible
	message.visibility_changed.connect(func() -> void: btn.visible = message.visible)
	btn.pressed.connect(func() -> void:
		message.get_tree().call_group("hub", "open_club_panel", "staff"))
	message.get_parent().add_child.call_deferred(btn)
	return btn
