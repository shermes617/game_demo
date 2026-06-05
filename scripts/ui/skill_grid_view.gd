extends GridContainer
class_name SkillGridView

signal cell_pressed(coord: Vector2i)
signal cell_right_pressed(coord: Vector2i)

var cell_buttons: Dictionary = {}


func setup_grid(column_count: int, row_count: int, cell_size: Vector2) -> void:
	_clear_cells()
	cell_buttons.clear()
	columns = column_count

	for row in row_count:
		for column in column_count:
			var coord := Vector2i(column, row)
			var button := Button.new()
			button.custom_minimum_size = cell_size
			button.clip_text = true
			button.focus_mode = Control.FOCUS_NONE
			button.add_theme_font_size_override("font_size", 24)
			button.gui_input.connect(_on_cell_input.bind(coord))
			button.pressed.connect(_emit_cell_pressed.bind(coord))
			add_child(button)
			cell_buttons[_coord_key(coord)] = button


func set_cell_state(coord: Vector2i, display_text: String, tooltip: String, disabled: bool, background: Color, border: Color, font_color: Color) -> void:
	var button: Button = cell_buttons.get(_coord_key(coord))
	if button == null:
		return
	button.text = display_text
	button.tooltip_text = tooltip
	button.disabled = disabled
	_apply_cell_style(button, background, border, font_color)


func _clear_cells() -> void:
	for child in get_children():
		child.queue_free()


func _on_cell_input(event: InputEvent, coord: Vector2i) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		cell_right_pressed.emit(coord)


func _emit_cell_pressed(coord: Vector2i) -> void:
	cell_pressed.emit(coord)


func _apply_cell_style(button: Button, background: Color, border: Color, font_color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("disabled", style)
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_disabled_color", font_color.darkened(0.2))


func _coord_key(coord: Vector2i) -> String:
	return "%d,%d" % [coord.x, coord.y]
