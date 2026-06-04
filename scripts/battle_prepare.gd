extends Control

@onready var roster_list: VBoxContainer = %RosterList
@onready var status_label: Label = %StatusLabel
@onready var start_button: Button = %StartButton
@onready var back_button: Button = %BackButton


func _ready() -> void:
	BattleRuntime.ensure_ready()
	_style_scene()
	_apply_static_texts()
	_build_roster()
	start_button.pressed.connect(_start_skill_sandbox)
	back_button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/skill_build_scene.tscn"))


func _style_scene() -> void:
	%TitleLabel.add_theme_color_override("font_color", Color("f6f7fb"))
	%SubtitleLabel.add_theme_color_override("font_color", Color("97a3b6"))
	status_label.add_theme_color_override("font_color", Color("dce5f4"))
	for panel in [%MainPanel, %BottomPanel]:
		panel.add_theme_stylebox_override("panel", _panel_style())
	for button in [start_button, back_button]:
		_style_button(button, "primary" if button == start_button else "secondary")


func _apply_static_texts() -> void:
	%TitleLabel.text = _text("UI_BATTLE_PREPARE_TITLE")
	%SubtitleLabel.text = _text("UI_BATTLE_PREPARE_SUBTITLE")
	start_button.text = _text("UI_START_BATTLE")
	back_button.text = _text("UI_RETURN_TO_EQUIP")
	status_label.text = _text("UI_WAITING_FOR_CONFIRMATION")


func _build_roster() -> void:
	for child in roster_list.get_children():
		child.queue_free()

	var warnings := PackedStringArray()
	for index in BattleRuntime.characters.size():
		var character: Dictionary = BattleRuntime.characters[index]
		var state: Dictionary = BattleRuntime.character_states[index]
		var card_lines := PackedStringArray()
		var has_valid_skill := false

		if state["equipped_card_ids"].is_empty():
			card_lines.append("[color=#f1c27d]%s[/color]" % _text("PREP_NO_SKILL_CARD"))
			warnings.append(_format_text("PREP_WARNING_NO_SKILL_CARD", {"character": character["name"]}))
		else:
			for card_id in state["equipped_card_ids"]:
				if not BattleRuntime.card_index_by_id.has(card_id):
					card_lines.append("[color=#f1c27d]%s[/color]" % _format_text("PREP_UNKNOWN_SKILL_CARD", {"card_id": card_id}))
					continue
				var skill: Dictionary = BattleRuntime.generate_skill_for_card(BattleRuntime.card_index_by_id[card_id])
				var summary := BattleRuntime.skill_effect_summary(skill)
				if skill["occupied_cells"] <= 0:
					card_lines.append("[color=#f1c27d]%s[/color]" % _format_text("PREP_EMPTY_SKILL_CARD_LINE", {
						"skill": skill["name"],
						"summary": summary
					}))
					warnings.append(_format_text("PREP_WARNING_EMPTY_SKILL", {
						"character": character["name"],
						"skill": skill["name"]
					}))
				else:
					card_lines.append(_format_text("PREP_SKILL_LINE", {
						"skill": skill["name"],
						"energy": skill["energy_cost"],
						"summary": summary
					}))
					has_valid_skill = true

		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", _card_style(has_valid_skill))
		roster_list.add_child(box)

		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 8)
		box.add_child(content)

		var title := Label.new()
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", Color("edf1f8"))
		title.text = "%s [%s]" % [character["name"], character["profession_name"]]
		content.add_child(title)

		var stats := Label.new()
		stats.add_theme_color_override("font_color", Color("aeb9ca"))
		stats.text = _format_text("PREP_CHARACTER_STATS", {
			"role": character["role"],
			"strength": character["stats"]["strength"],
			"hp": character["stats"]["hp"],
			"will": character["stats"]["will"],
			"speed": character["stats"]["speed"]
		})
		content.add_child(stats)

		var skills := RichTextLabel.new()
		skills.bbcode_enabled = true
		skills.fit_content = true
		skills.scroll_active = false
		skills.add_theme_color_override("default_color", Color("dce5f4"))
		skills.text = _format_text("PREP_EQUIPPED_SKILLS_HEADER", {"skills": "\n".join(card_lines)})
		content.add_child(skills)

	var ready_count := BattleRuntime.get_ready_character_count()
	var warning_text := ""
	if not warnings.is_empty():
		warning_text = "\n%s" % "\n".join(warnings)
	start_button.disabled = ready_count <= 0
	status_label.text = _format_text("PREP_READY_STATUS", {
		"ready": ready_count,
		"total": BattleRuntime.characters.size(),
		"warnings": warning_text
	})


func _start_skill_sandbox() -> void:
	if not bool(BattleRuntime.exploration_state.get("is_exploration_active", false)):
		BattleRuntime.start_exploration()
	get_tree().change_scene_to_file("res://scenes/map_scene.tscn")


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1b2029")
	style.border_color = Color("2a3342")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_top = 16
	style.content_margin_right = 16
	style.content_margin_bottom = 16
	return style


func _card_style(is_ready: bool) -> StyleBoxFlat:
	var style := _panel_style()
	style.bg_color = Color("202838") if is_ready else Color("241f26")
	style.border_color = Color("37628f") if is_ready else Color("6d5540")
	return style


func _style_button(button: Button, variant: String) -> void:
	button.custom_minimum_size = Vector2(180, 44)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_stylebox_override("normal", _button_style(variant, 0.95))
	button.add_theme_stylebox_override("hover", _button_style(variant, 1.08))
	button.add_theme_stylebox_override("pressed", _button_style(variant, 0.82))
	button.add_theme_stylebox_override("disabled", _button_style("disabled", 0.7))
	button.add_theme_color_override("font_color", Color("eff3fb"))
	button.add_theme_color_override("font_disabled_color", Color("7f8897"))


func _button_style(variant: String, brightness: float) -> StyleBoxFlat:
	var base := Color("253040")
	if variant == "primary":
		base = Color("2e6ee6")
	elif variant == "disabled":
		base = Color("171c24")
	var style := StyleBoxFlat.new()
	style.bg_color = Color(base.r * brightness, base.g * brightness, base.b * brightness)
	style.border_color = style.bg_color.lightened(0.18)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_top = 10
	style.content_margin_right = 12
	style.content_margin_bottom = 10
	return style


func _text(key: String) -> String:
	var database := get_node_or_null("/root/TextDatabase")
	if database != null and database.has_method("get_text"):
		return str(database.call("get_text", key))
	return key


func _format_text(key: String, params: Dictionary) -> String:
	var database := get_node_or_null("/root/TextDatabase")
	if database != null and database.has_method("format_text"):
		return str(database.call("format_text", key, params))
	var text := _text(key)
	for param_key in params.keys():
		text = text.replace("{%s}" % str(param_key), str(params[param_key]))
	return text
