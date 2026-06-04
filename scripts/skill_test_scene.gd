extends Control

var player: Dictionary
var dummy := {
	"name": "敌方木桩",
	"max_hp": 260,
	"hp": 260,
	"shield": 80
}

@onready var player_label: RichTextLabel = %PlayerLabel
@onready var dummy_label: RichTextLabel = %DummyLabel
@onready var skill_list: VBoxContainer = %SkillList
@onready var log_label: RichTextLabel = %LogLabel
@onready var end_turn_button: Button = %EndTurnButton
@onready var reset_button: Button = %ResetButton
@onready var prepare_button: Button = %PrepareButton
@onready var battle_button: Button = %BattleButton


func _ready() -> void:
	BattleRuntime.ensure_ready()
	_style_scene()
	prepare_button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/battle_prepare.tscn"))
	battle_button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/battle_scene.tscn"))
	reset_button.pressed.connect(_reset_sandbox)
	end_turn_button.pressed.connect(_end_turn)
	_reset_sandbox()


func _reset_sandbox() -> void:
	var character_index := BattleRuntime.get_first_battle_ready_character_index()
	if character_index == -1:
		log_label.text = "[color=#f1c27d]没有可测试的角色。请先返回确认页检查装备。[/color]"
		player = {}
		_refresh()
		return
	player = BattleRuntime.build_character_runtime(character_index)
	dummy["hp"] = dummy["max_hp"]
	dummy["shield"] = 80
	log_label.text = "沙盒已就绪：%s 对战敌方木桩。" % player["name"]
	_refresh()


func _end_turn() -> void:
	if player.is_empty():
		return
	player["energy"] = min(int(player["energy"]) + 1, 6)
	_tick_status_effects()
	log_label.text = "回合结束：能量 +1。"
	_refresh()


func _cast_skill(skill: Dictionary) -> void:
	if player.is_empty():
		return
	if int(player["energy"]) < int(skill["energy_cost"]):
		log_label.text = "[color=#f1c27d]能量不足：需要 %d，当前 %d。[/color]" % [skill["energy_cost"], player["energy"]]
		return

	player["energy"] -= int(skill["energy_cost"])
	var log_lines := PackedStringArray()
	log_lines.append("[b]%s 释放 %s[/b]" % [player["name"], skill["name"]])

	if skill["damage_pct"] > 0.0:
		var damage: int = int(round(float(player["strength"]) * float(skill["damage_pct"]) / 100.0))
		if skill["anti_shield_bonus"] and int(dummy["shield"]) > 0:
			damage = int(round(damage * 1.2))
		var pierce_damage: int = int(round(float(damage) * float(skill["pierce_pct"]) / 100.0))
		var normal_damage: int = max(damage - pierce_damage, 0)
		var shield_damage: int = min(int(dummy["shield"]), normal_damage)
		dummy["shield"] = max(int(dummy["shield"]) - shield_damage, 0)
		var hp_damage: int = pierce_damage + max(normal_damage - shield_damage, 0)
		dummy["hp"] = max(int(dummy["hp"]) - hp_damage, 0)
		log_lines.append("飘字：-%d" % damage)
		if pierce_damage > 0:
			log_lines.append("穿透造成生命伤害：%d" % pierce_damage)

	if skill["heal_pct"] > 0.0:
		var heal := int(round(player["will"] * skill["heal_pct"] / 100.0))
		var before_hp: int = player["hp"]
		player["hp"] = min(int(player["hp"]) + heal, int(player["max_hp"]))
		log_lines.append("飘字：+%d 生命" % (int(player["hp"]) - before_hp))

	if skill["shield_pct"] > 0.0:
		var shield_gain := int(round(player["will"] * skill["shield_pct"] / 100.0))
		player["shield"] = int(player["shield"]) + shield_gain
		log_lines.append("飘字：护盾 +%d" % shield_gain)

	if skill["speed_buff"] > 0:
		_add_status("加速", "speed", int(skill["speed_buff"]), int(skill["support_duration"]))
		log_lines.append("Buff：速度 +%d，持续 %d 回合" % [skill["speed_buff"], skill["support_duration"]])

	if skill["damage_reduction_pct"] > 0:
		_add_status("稳固", "damage_reduction", int(skill["damage_reduction_pct"]), int(skill["support_duration"]))
		log_lines.append("Buff：减伤 %d%%，持续 %d 回合" % [skill["damage_reduction_pct"], skill["support_duration"]])

	if dummy["hp"] <= 0:
		log_lines.append("[color=#a6e3a1]木桩被击破。构筑差异已经进入战斗结果。[/color]")

	log_label.text = "\n".join(log_lines)
	_refresh()


func _tick_status_effects() -> void:
	var remaining := []
	for effect in player["status_effects"]:
		effect["turns"] = int(effect["turns"]) - 1
		if int(effect["turns"]) > 0:
			remaining.append(effect)
	player["status_effects"] = remaining


func _add_status(status_name: String, stat: String, value: int, turns: int) -> void:
	for effect in player["status_effects"]:
		if str(effect.get("name", "")) == status_name and str(effect.get("stat", "")) == stat and int(effect.get("value", 0)) == value:
			effect["turns"] = int(effect.get("turns", 0)) + turns
			return
	player["status_effects"].append({
		"name": status_name,
		"stat": stat,
		"value": value,
		"turns": turns
	})


func _refresh() -> void:
	for child in skill_list.get_children():
		child.queue_free()

	if player.is_empty():
		player_label.text = "[b]玩家角色[/b]\n无"
		dummy_label.text = "[b]敌方木桩[/b]\n无"
		return

	var buff_lines := PackedStringArray()
	for effect in player["status_effects"]:
		buff_lines.append("%s +%d / %d 回合" % [effect["name"], effect["value"], effect["turns"]])
	if buff_lines.is_empty():
		buff_lines.append("无")

	player_label.text = "[b]%s [%s][/b]\nHP %d/%d\n护盾 %d\n能量 %d/6\n力量 %d | 意志 %d | 速度 %d\n状态：%s" % [
		player["name"],
		player["profession_name"],
		player["hp"],
		player["max_hp"],
		player["shield"],
		player["energy"],
		player["strength"],
		player["will"],
		player["speed"],
		"、".join(buff_lines)
	]
	dummy_label.text = "[b]%s[/b]\nHP %d/%d\n护盾 %d\n不行动" % [
		dummy["name"],
		dummy["hp"],
		dummy["max_hp"],
		dummy["shield"]
	]

	for skill in player["equipped_skills"]:
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(0, 72)
		button.text = "%s | %d 能量\n%s" % [
			skill["name"],
			skill["energy_cost"],
			BattleRuntime.skill_effect_summary(skill)
		]
		button.disabled = int(player["energy"]) < int(skill["energy_cost"]) or int(dummy["hp"]) <= 0
		_style_button(button, "primary")
		button.pressed.connect(_cast_skill.bind(skill))
		skill_list.add_child(button)


func _style_scene() -> void:
	%TitleLabel.add_theme_color_override("font_color", Color("f6f7fb"))
	%SubtitleLabel.add_theme_color_override("font_color", Color("97a3b6"))
	for panel in [%PlayerPanel, %DummyPanel, %SkillPanel, %LogPanel]:
		panel.add_theme_stylebox_override("panel", _panel_style())
	for label in [player_label, dummy_label, log_label]:
		label.bbcode_enabled = true
		label.fit_content = true
		label.scroll_active = false
		label.add_theme_color_override("default_color", Color("dce5f4"))
	for button in [end_turn_button, reset_button, prepare_button, battle_button]:
		_style_button(button, "secondary")


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


func _style_button(button: Button, variant: String) -> void:
	button.add_theme_font_size_override("font_size", 15)
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
