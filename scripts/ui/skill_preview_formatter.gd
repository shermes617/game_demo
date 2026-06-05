extends RefCounted
class_name SkillPreviewFormatter

var text_callback: Callable
var format_callback: Callable
var card_type_callback: Callable
var energy_rule_callback: Callable
var status_name_callback: Callable
var card_allowed_callback: Callable
var special_event_callback: Callable
var module_summary_callback: Callable


func _init(callbacks: Dictionary) -> void:
	text_callback = callbacks.get("text", Callable())
	format_callback = callbacks.get("format", Callable())
	card_type_callback = callbacks.get("card_type", Callable())
	energy_rule_callback = callbacks.get("energy_rule", Callable())
	status_name_callback = callbacks.get("status_name", Callable())
	card_allowed_callback = callbacks.get("card_allowed", Callable())
	special_event_callback = callbacks.get("special_event", Callable())
	module_summary_callback = callbacks.get("module_summary", Callable())


func build_preview(card: Dictionary, generated: Dictionary, current_view: String, character: Dictionary) -> Dictionary:
	var title := _format_text("BUILD_PREVIEW_TITLE", {"name": card["name"]})
	var lines := PackedStringArray()
	lines.append(_text("BUILD_PREVIEW_PROFESSION_LIMIT"))
	lines.append("/".join(card["allowed_professions"]))
	lines.append(_text("BUILD_PREVIEW_SKILL_TYPE"))
	lines.append(_card_type_label(card))
	lines.append("")
	lines.append(_text("BUILD_PREVIEW_TARGET_AND_COST"))
	lines.append(_format_text("BUILD_PREVIEW_TARGET", {"target": card["target_type"]}))
	lines.append(_format_text("BUILD_PREVIEW_ENERGY", {"energy": generated["energy_cost"]}))
	lines.append(_format_text("BUILD_PREVIEW_OCCUPIED_CELLS", {"cells": generated["occupied_cells"]}))
	lines.append(_energy_rule_text(card["energy_curve"]))
	lines.append("")
	lines.append(_text("BUILD_PREVIEW_SKILL_EFFECT"))
	_append_effect_lines(lines, generated)
	_append_special_lines(lines, generated)
	_append_module_summary_lines(lines, generated)
	if current_view == "character":
		_append_character_check(lines, card, character)
	return {
		"title": title,
		"body": "\n".join(lines)
	}


func _append_effect_lines(lines: PackedStringArray, generated: Dictionary) -> void:
	if generated["occupied_cells"] == 0:
		lines.append(_text("BUILD_PREVIEW_NO_MODULES"))
		return

	var morale_damage_pct := 0.0
	var morale_damage_cost := 0
	for morale_damage in generated.get("morale_damage_modules", []):
		morale_damage_pct += float(morale_damage.get("damage_pct", 0.0))
		morale_damage_cost += int(morale_damage.get("cost", 0))
	var total_damage_pct: float = float(generated["damage_pct"]) + morale_damage_pct
	if total_damage_pct > 0.0:
		var damage_text := _format_text("BUILD_PREVIEW_DAMAGE", {"value": "%.0f" % total_damage_pct})
		if morale_damage_pct > 0.0:
			damage_text += _format_text("BUILD_PREVIEW_MORALE_APPEND", {
				"cost": morale_damage_cost,
				"value": "%.0f" % morale_damage_pct
			})
		lines.append(damage_text)
	if generated["heal_pct"] > 0.0:
		lines.append(_format_text("BUILD_PREVIEW_HEAL", {"value": "%.0f" % generated["heal_pct"]}))

	var morale_shield_pct := 0.0
	var morale_shield_cost := 0
	for morale_shield in generated.get("morale_shield_modules", []):
		morale_shield_pct += float(morale_shield.get("shield_pct", 0.0))
		morale_shield_cost += int(morale_shield.get("cost", 0))
	var total_shield_pct: float = float(generated["shield_pct"]) + morale_shield_pct
	if total_shield_pct > 0.0:
		var shield_text := _format_text("BUILD_PREVIEW_SHIELD", {"value": "%.0f" % total_shield_pct})
		if morale_shield_pct > 0.0:
			shield_text += _format_text("BUILD_PREVIEW_MORALE_APPEND", {
				"cost": morale_shield_cost,
				"value": "%.0f" % morale_shield_pct
			})
		lines.append(shield_text)
	if generated["pierce_pct"] > 0.0:
		lines.append(_format_text("BUILD_PREVIEW_PIERCE", {"value": "%.0f" % generated["pierce_pct"]}))
	if generated["morale_gain"] > 0:
		lines.append(_format_text("BUILD_PREVIEW_MORALE_GAIN", {"value": generated["morale_gain"]}))
	for status in generated.get("status_modules", []):
		var status_id := str(status.get("id", ""))
		if status_id == "burn" and status.has("scale_pct"):
			var flat_layers: int = int(status.get("flat", 0))
			var flat_text := ""
			if flat_layers > 0:
				flat_text = _format_text("BUILD_PREVIEW_FLAT_LAYER_APPEND", {"layers": flat_layers})
			lines.append(_format_text("BUILD_PREVIEW_BURN", {
				"value": "%.0f" % float(status.get("scale_pct", 0.0)),
				"stat": str(status.get("scale_stat", "strength")),
				"flat": flat_text
			}))
		else:
			lines.append(_format_text("BUILD_PREVIEW_STATUS_LAYERS", {
				"status": _status_display_name(status_id),
				"layers": int(status.get("layers", 0))
			}))
	if generated["speed_buff"] > 0:
		lines.append(_format_text("BUILD_PREVIEW_SPEED", {
			"speed": generated["speed_buff"],
			"turns": int(generated.get("speed_duration", generated["support_duration"]))
		}))
	if generated["damage_reduction_pct"] > 0:
		lines.append(_format_text("BUILD_PREVIEW_GUARD", {
			"value": generated["damage_reduction_pct"],
			"turns": int(generated.get("damage_reduction_duration", generated["support_duration"]))
		}))
	if generated["anti_shield_bonus"]:
		lines.append(_text("BUILD_PREVIEW_ANTI_SHIELD"))


func _append_special_lines(lines: PackedStringArray, generated: Dictionary) -> void:
	lines.append("")
	lines.append(_text("BUILD_PREVIEW_SPECIALS"))
	if generated["triggered_special_events"].is_empty():
		lines.append(_text("BUILD_PREVIEW_NO_SPECIALS"))
	else:
		for special_event in generated["triggered_special_events"]:
			lines.append(_special_event_text(special_event))


func _append_module_summary_lines(lines: PackedStringArray, generated: Dictionary) -> void:
	lines.append("")
	lines.append(_text("BUILD_PREVIEW_MODULE_SUMMARY"))
	if generated["module_summary_events"].is_empty():
		lines.append(_text("BUILD_PREVIEW_NONE"))
	else:
		for summary_event in generated["module_summary_events"]:
			lines.append(_module_summary_text(summary_event))


func _append_character_check(lines: PackedStringArray, card: Dictionary, character: Dictionary) -> void:
	lines.append("")
	lines.append(_text("BUILD_PREVIEW_EQUIP_CHECK"))
	lines.append(_format_text("BUILD_PREVIEW_CHARACTER_CAN_USE", {
		"name": character["name"],
		"allowed": _text("BUILD_PREVIEW_CAN") if _card_allowed_for_profession(card, character["profession"]) else _text("BUILD_PREVIEW_CANNOT")
	}))


func _text(key: String) -> String:
	return text_callback.call(key)


func _format_text(key: String, values: Dictionary) -> String:
	return format_callback.call(key, values)


func _card_type_label(card: Dictionary) -> String:
	return card_type_callback.call(card)


func _energy_rule_text(curve: String) -> String:
	return energy_rule_callback.call(curve)


func _status_display_name(status_id: String) -> String:
	return status_name_callback.call(status_id)


func _card_allowed_for_profession(card: Dictionary, profession: String) -> bool:
	return bool(card_allowed_callback.call(card, profession))


func _special_event_text(event: Dictionary) -> String:
	return special_event_callback.call(event)


func _module_summary_text(event: Dictionary) -> String:
	return module_summary_callback.call(event)
