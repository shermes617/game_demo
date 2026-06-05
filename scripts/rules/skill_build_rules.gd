extends RefCounted
class_name SkillBuildRules


static func energy_cost_for(curve: String, occupied_cells: int) -> int:
	if occupied_cells <= 0:
		return 0
	if curve == "range":
		if occupied_cells <= 3:
			return 1
		if occupied_cells <= 6:
			return 2
		return 3
	if occupied_cells <= 5:
		return 1
	if occupied_cells <= 10:
		return 2
	return 3


static func create_empty_skill_result(card: Dictionary) -> Dictionary:
	return {
		"name": card["name"],
		"target": card["target_type"],
		"energy_cost": 0,
		"occupied_cells": 0,
		"damage_pct": 0.0,
		"heal_pct": 0.0,
		"shield_pct": 0.0,
		"pierce_pct": 0.0,
		"morale_gain": 0,
		"morale_damage_modules": [],
		"morale_shield_modules": [],
		"status_modules": [],
		"speed_buff": 0,
		"damage_reduction_pct": 0,
		"support_duration": 1,
		"speed_duration": 1,
		"damage_reduction_duration": 1,
		"anti_shield_bonus": false,
		"triggered_special_events": [],
		"module_summary_events": []
	}


static func finalize_skill_result(result: Dictionary, card: Dictionary) -> Dictionary:
	if result["speed_buff"] > 0 or result["damage_reduction_pct"] > 0:
		result["support_duration"] = max(int(result["speed_duration"]), int(result["damage_reduction_duration"]))
	result["energy_cost"] = energy_cost_for(card["energy_curve"], result["occupied_cells"])
	return result


static func rotated_shape(shape: Array, size: Vector2i, rotation: int) -> Array:
	var normalized_rotation := rotation % 4
	var current_cells: Array = shape.duplicate()
	var current_size := size
	for _i in range(normalized_rotation):
		var rotated: Array = []
		for cell in current_cells:
			rotated.append(Vector2i(current_size.y - 1 - cell.y, cell.x))
		current_cells = rotated
		current_size = Vector2i(current_size.y, current_size.x)
	return current_cells


static func shape_bounds(shape: Array) -> Vector2i:
	var max_x := 0
	var max_y := 0
	for cell in shape:
		max_x = max(max_x, cell.x)
		max_y = max(max_y, cell.y)
	return Vector2i(max_x + 1, max_y + 1)


static func card_allowed_for_profession(card: Dictionary, profession: String) -> bool:
	return card["allowed_professions"].has(profession)


static func coord_key(coord: Vector2i) -> String:
	return "%d_%d" % [coord.x, coord.y]


static func find_placement_covering(placements: Array, coord: Vector2i) -> int:
	for index in placements.size():
		for cell in placements[index]["cells"]:
			if cell == coord:
				return index
	return -1


static func occupied_map(placements: Array) -> Dictionary:
	var occupied := {}
	for placement in placements:
		for cell in placement["cells"]:
			occupied[coord_key(cell)] = true
	return occupied


static func active_map(card: Dictionary) -> Dictionary:
	var active := {}
	for cell in card["active_cells"]:
		active[coord_key(cell)] = true
	return active


static func special_map(card: Dictionary) -> Dictionary:
	var special := {}
	for slot in card["special_slots"]:
		special[coord_key(slot["pos"])] = slot
	return special


static func placements_adjacent(a: Dictionary, b: Dictionary) -> bool:
	for acell in a.get("cells", []):
		for bcell in b.get("cells", []):
			var distance: int = abs(int(acell.x) - int(bcell.x)) + abs(int(acell.y) - int(bcell.y))
			if distance == 1:
				return true
	return false


static func validate_placement(card: Dictionary, module: Dictionary, placements: Array, modules: Dictionary, available_count: int, compatible: bool, anchor: Vector2i, rotation: int) -> Dictionary:
	if available_count <= 0:
		return {"ok": false, "reason": "no_available_module"}
	if not compatible:
		return {"ok": false, "reason": "module_incompatible"}
	if module.get("is_unique", false):
		for placement in placements:
			if modules[placement["module_id"]].get("is_unique", false):
				return {"ok": false, "reason": "one_unique_limit"}

	var rotated_cells: Array = rotated_shape(module["shape"], module["size"], rotation)
	var occupied: Dictionary = occupied_map(placements)
	var active: Dictionary = active_map(card)
	var absolute_cells: Array = []

	for cell in rotated_cells:
		var absolute: Vector2i = anchor + cell
		if absolute.x < 0 or absolute.y < 0 or absolute.x >= card["width"] or absolute.y >= card["height"]:
			return {"ok": false, "reason": "out_of_bounds"}
		if not active.has(coord_key(absolute)):
			return {"ok": false, "reason": "inactive_cell"}
		if occupied.has(coord_key(absolute)):
			return {"ok": false, "reason": "overlap"}
		absolute_cells.append(absolute)

	return {"ok": true, "cells": absolute_cells}


static func apply_special_slot_effects(module: Dictionary, effects: Dictionary, placement: Dictionary, special_map: Dictionary) -> Dictionary:
	var applied_effects: Dictionary = effects.duplicate(true)
	var special_events: Array = []
	var duration_bonus := 0
	var anti_shield_bonus := false

	for cell in placement["cells"]:
		var key := coord_key(cell)
		if not special_map.has(key):
			continue
		var special: Dictionary = special_map[key]
		match special["type"]:
			"damage_boost":
				if applied_effects.has("damage_pct"):
					applied_effects["damage_pct"] *= 1.3
					special_events.append(special_trigger_event(module, special))
			"heal_boost":
				if applied_effects.has("heal_pct"):
					applied_effects["heal_pct"] *= 1.25
					special_events.append(special_trigger_event(module, special))
			"shield_boost":
				if applied_effects.has("shield_pct"):
					applied_effects["shield_pct"] *= 1.2
					special_events.append(special_trigger_event(module, special))
				if applied_effects.has("morale_shield"):
					var morale_shield: Dictionary = applied_effects["morale_shield"]
					morale_shield["shield_pct"] = float(morale_shield.get("shield_pct", 0.0)) * 1.2
					special_events.append(special_trigger_event(module, special))
			"support_duration":
				if applied_effects.has("speed_buff") or applied_effects.has("damage_reduction_pct"):
					duration_bonus += 1
					special_events.append(special_trigger_event(module, special))
			"anti_shield":
				if applied_effects.has("damage_pct"):
					anti_shield_bonus = true
					special_events.append(special_trigger_event(module, special))

	return {
		"effects": applied_effects,
		"duration_bonus": duration_bonus,
		"special_events": special_events,
		"anti_shield_bonus": anti_shield_bonus
	}


static func burning_strike_event(module: Dictionary, placement: Dictionary, placements: Array, modules: Dictionary) -> Dictionary:
	if not str(module.get("id", "")).begins_with("burning_strike"):
		return {}

	var adjacent_damage := 0.0
	for other in placements:
		if other == placement or not placements_adjacent(placement, other):
			continue
		var other_module: Dictionary = modules[other["module_id"]]
		adjacent_damage += float(other_module.get("effects", {}).get("damage_pct", 0.0))
	if adjacent_damage <= 0.0:
		return {}

	var factor: float = float(module.get("effects", {}).get("burning_strike_factor", 0.5))
	var burn_pct: float = adjacent_damage * factor
	return {
		"status": {
			"id": "burn",
			"scale_stat": "strength",
			"scale_pct": burn_pct,
			"flat": 0,
			"module_name": module["name"]
		},
		"event": {
			"type": "burning_strike",
			"module": module["name"],
			"value": burn_pct
		}
	}


static func special_trigger_event(module: Dictionary, special: Dictionary) -> Dictionary:
	return {
		"type": "special_trigger",
		"module": module["name"],
		"label": special["label"]
	}


static func apply_module_effects_to_result(result: Dictionary, module: Dictionary, effects: Dictionary, placement: Dictionary, duration_bonus: int) -> void:
	result["damage_pct"] += effects.get("damage_pct", 0.0)
	result["heal_pct"] += effects.get("heal_pct", 0.0)
	result["shield_pct"] += effects.get("shield_pct", 0.0)
	result["pierce_pct"] += effects.get("pierce_pct", 0.0)
	if effects.has("morale_gain"):
		result["morale_gain"] = max(int(result["morale_gain"]), int(effects["morale_gain"]))
	if effects.has("morale_damage"):
		result["morale_damage_modules"].append(effects["morale_damage"].duplicate(true))
	if effects.has("morale_shield"):
		result["morale_shield_modules"].append(effects["morale_shield"].duplicate(true))
	if effects.has("status"):
		var status_data: Dictionary = effects["status"].duplicate(true)
		status_data["module_name"] = module["name"]
		result["status_modules"].append(status_data)
	if effects.has("speed_buff"):
		result["speed_buff"] += int(effects.get("speed_buff", 0))
		result["speed_duration"] = max(int(result["speed_duration"]), 1 + duration_bonus)
	if effects.has("damage_reduction_pct"):
		result["damage_reduction_pct"] += int(effects.get("damage_reduction_pct", 0))
		result["damage_reduction_duration"] = max(int(result["damage_reduction_duration"]), 1 + duration_bonus)
	result["occupied_cells"] += placement["cells"].size()
