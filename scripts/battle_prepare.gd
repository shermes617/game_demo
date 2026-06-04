extends Control

@onready var roster_list: VBoxContainer = %RosterList
@onready var status_label: Label = %StatusLabel
@onready var start_button: Button = %StartButton
@onready var back_button: Button = %BackButton


func _ready() -> void:
	BattleRuntime.ensure_ready()
	_style_scene()
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
			card_lines.append("[color=#f1c27d]未装备技能卡[/color]")
			warnings.append("%s 未装备技能卡。" % character["name"])
		else:
			for card_id in state["equipped_card_ids"]:
				if not BattleRuntime.card_index_by_id.has(card_id):
					card_lines.append("[color=#f1c27d]未知技能卡：%s[/color]" % card_id)
					continue
				var skill: Dictionary = BattleRuntime.generate_skill_for_card(BattleRuntime.card_index_by_id[card_id])
				var summary := BattleRuntime.skill_effect_summary(skill)
				if skill["occupied_cells"] <= 0:
					card_lines.append("[color=#f1c27d]%s | 空技能 | %s[/color]" % [skill["name"], summary])
					warnings.append("%s 装备了空技能 %s。" % [character["name"], skill["name"]])
				else:
					card_lines.append("%s | %d 能量 | %s" % [skill["name"], skill["energy_cost"], summary])
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
		stats.text = "定位：%s | 力量 %d | 生命 %d | 意志 %d | 速度 %d" % [
			character["role"],
			character["stats"]["strength"],
			character["stats"]["hp"],
			character["stats"]["will"],
			character["stats"]["speed"]
		]
		content.add_child(stats)

		var skills := RichTextLabel.new()
		skills.bbcode_enabled = true
		skills.fit_content = true
		skills.scroll_active = false
		skills.add_theme_color_override("default_color", Color("dce5f4"))
		skills.text = "[b]已装备技能[/b]\n%s" % "\n".join(card_lines)
		content.add_child(skills)

	var ready_count := BattleRuntime.get_ready_character_count()
	var warning_text := ""
	if not warnings.is_empty():
		warning_text = "\n%s" % "\n".join(warnings)
	start_button.disabled = ready_count <= 0
	status_label.text = "可进入战斗验证的角色：%d/%d%s" % [
		ready_count,
		BattleRuntime.characters.size(),
		warning_text
	]


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
