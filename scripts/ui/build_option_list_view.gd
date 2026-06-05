extends VBoxContainer
class_name BuildOptionListView

signal item_pressed(item_key: Variant)

const BUILD_LIST_ITEM_VIEW_SCENE := preload("res://scenes/ui/build_list_item_view.tscn")

var buttons: Array[Button] = []
var buttons_by_key: Dictionary = {}


func rebuild_items(items: Array, style_callback: Callable = Callable()) -> void:
	_clear_items()
	buttons.clear()
	buttons_by_key.clear()

	for index in items.size():
		var item: Dictionary = items[index]
		var item_key: Variant = item.get("key", index)
		var button: Button = BUILD_LIST_ITEM_VIEW_SCENE.instantiate()
		var display_text := str(item.get("text", ""))
		var min_height := float(item.get("min_height", 48.0))
		if button.has_method("setup"):
			button.setup(display_text, min_height)
		else:
			button.text = display_text
			button.custom_minimum_size = Vector2(0, min_height)
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		if style_callback.is_valid():
			style_callback.call(button, str(item.get("variant", "soft")))

		button.disabled = bool(item.get("disabled", false))
		button.pressed.connect(_emit_item_pressed.bind(item_key))
		add_child(button)
		buttons.append(button)
		buttons_by_key[item_key] = button


func get_button_for_key(item_key: Variant) -> Button:
	return buttons_by_key.get(item_key)


func _clear_items() -> void:
	for child in get_children():
		child.queue_free()


func _emit_item_pressed(item_key: Variant) -> void:
	item_pressed.emit(item_key)
