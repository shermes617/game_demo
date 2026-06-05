extends Button
class_name BuildListItemView


func setup(display_text: String, min_height: float) -> void:
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	custom_minimum_size = Vector2(0, min_height)
	text = display_text
