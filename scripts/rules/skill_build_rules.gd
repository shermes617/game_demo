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
