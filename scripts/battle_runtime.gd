extends Node

# BattleRuntime 是“技能拼图构筑”和“战斗场景”之间的桥梁。
# 构筑页负责编辑技能卡和角色装备；战斗页只消费这里保存的最终数据。
# 做成 Autoload 后，场景切换时当前构筑不会丢失。
const DATA_PATH := "res://data/demo_data.json"
const TEXT_DATABASE_SCRIPT := preload("res://scripts/database/text_database.gd")
const RELICS := {
	"empty_bag_battery": {
		"name_key": "RELIC_EMPTY_BAG_BATTERY_NAME",
		"desc_key": "RELIC_EMPTY_BAG_BATTERY_DESC"
	},
	"full_cell_battery": {
		"name_key": "RELIC_FULL_CELL_BATTERY_NAME",
		"desc_key": "RELIC_FULL_CELL_BATTERY_DESC"
	},
	"full_roster_banner": {
		"name_key": "RELIC_FULL_ROSTER_BANNER_NAME",
		"desc_key": "RELIC_FULL_ROSTER_BANNER_DESC"
	},
	"remnant_badge": {
		"name_key": "RELIC_REMNANT_BADGE_NAME",
		"desc_key": "RELIC_REMNANT_BADGE_DESC"
	}
}
const RELIC_ORDER := ["empty_bag_battery", "full_cell_battery", "full_roster_banner", "remnant_badge"]

# 从 JSON 读取的静态定义。
var cards: Dictionary = {}
var modules: Dictionary = {}
var characters: Array = []
var default_builds: Array = []

# 顺序表与运行时状态。
# card_states：每张技能卡上放了哪些模组。
# character_states：每名角色装备了哪些技能卡。
var card_order: Array = []
var module_order: Array = []
var card_states: Array = []
var character_states: Array = []
var card_index_by_id: Dictionary = {}
var character_index_by_id: Dictionary = {}
var runtime_module_inventory: Dictionary = {}
var exploration_state: Dictionary = {
	"current_step": 0,
	"current_node_type": "",
	"completed_nodes": [],
	"is_exploration_active": false,
	"shop_open": false,
	"boss_defeated": false
}
var gold := 0
var shop_offers: Array = []
var shop_refresh_cost := 10
var saved_morale := 80
var has_party_snapshot := false
var party_snapshot: Array = []
var has_battle_checkpoint := false
var battle_checkpoint: Dictionary = {}
var owned_relic_ids: Array = []
var fallback_text_database: Node

# 构筑页进入战斗准备页后会置为 true。
# 如果玩家返回构筑页，构筑页会用它恢复之前的编辑结果。
var has_builder_snapshot := false


func _ready() -> void:
	# 保证直接运行战斗相关场景时，也能有基础数据可用。
	ensure_ready()


func ensure_ready() -> void:
	# 防止重复加载。已经有 cards 就说明运行时已初始化。
	if not cards.is_empty():
		return
	load_data()
	initialize_states()
	load_default_builds()


func load_data() -> void:
	# 读取 Demo JSON，并把数组坐标转换成 Vector2i。
	# 后续格子校验、旋转、特殊格触发都会使用 Vector2i。
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error(_format_text("ERROR_OPEN_DATA_FILE", {"path": DATA_PATH}))
		return

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error(_format_text("ERROR_DATA_FILE_FORMAT", {"path": DATA_PATH}))
		return

	var raw: Dictionary = parsed
	cards.clear()
	modules.clear()
	characters.clear()
	default_builds.clear()
	card_order.clear()
	module_order.clear()
	card_index_by_id.clear()
	character_index_by_id.clear()

	for card_data in raw.get("cards", []):
		var card: Dictionary = card_data.duplicate(true)
		_resolve_text_fields(card, {
			"name_key": "name",
			"target_key": "target_type",
			"target_summary_key": "target_summary"
		})
		card["active_cells"] = _coords(card.get("active_cells", []))
		var special_slots: Array = []
		for slot_data in card.get("special_slots", []):
			var slot: Dictionary = slot_data.duplicate(true)
			_resolve_text_fields(slot, {"label_key": "label"})
			slot["pos"] = _pair_to_vector(slot["pos"])
			special_slots.append(slot)
		card["special_slots"] = special_slots
		card["allowed_professions"] = card.get("allowed_professions", []).duplicate(true)
		cards[card["id"]] = card
		card_order.append(card["id"])

	for module_data in raw.get("modules", []):
		var module: Dictionary = module_data.duplicate(true)
		_resolve_text_fields(module, {
			"name_key": "name",
			"short_key": "short",
			"desc_key": "description"
		})
		_resolve_text_array_field(module, "tag_keys", "tags")
		module["shape"] = _coords(module.get("shape", []))
		module["size"] = _pair_to_vector(module["size"])
		module["effects"] = module.get("effects", {}).duplicate(true)
		modules[module["id"]] = module
		module_order.append(module["id"])

	for character_data in raw.get("characters", []):
		var character: Dictionary = character_data.duplicate(true)
		_resolve_text_fields(character, {
			"name_key": "name",
			"profession_name_key": "profession_name",
			"role_key": "role"
		})
		character["allowed_card_slots"] = int(character.get("allowed_card_slots", 1))
		characters.append(character)

	default_builds = raw.get("default_builds", []).duplicate(true)


func initialize_states() -> void:
	# 根据静态定义创建空白运行时状态。
	# 注意：这里只建状态，不会自动装备技能，也不会自动放模组。
	card_states.clear()
	character_states.clear()
	card_index_by_id.clear()
	for index in card_order.size():
		var card_id: String = card_order[index]
		card_index_by_id[card_id] = index
		card_states.append({
			"card_id": card_id,
			"placements": []
		})

	for character in characters:
		character_index_by_id[character["id"]] = character_states.size()
		character_states.append({
			"character_id": character["id"],
			"equipped_card_ids": []
		})


func import_builder_state(source_cards: Dictionary, source_modules: Dictionary, source_characters: Array, source_card_order: Array, source_module_order: Array, source_card_states: Array, source_character_states: Array) -> void:
	# 构筑页点击“准备战斗”时调用。
	# duplicate(true) 是深拷贝，避免战斗场景和构筑场景互相误改同一个引用。
	cards = source_cards.duplicate(true)
	modules = source_modules.duplicate(true)
	characters = source_characters.duplicate(true)
	card_order = source_card_order.duplicate(true)
	module_order = source_module_order.duplicate(true)
	card_states = source_card_states.duplicate(true)
	character_states = source_character_states.duplicate(true)
	card_index_by_id.clear()
	character_index_by_id.clear()
	for index in card_order.size():
		card_index_by_id[card_order[index]] = index
	for index in characters.size():
		character_index_by_id[characters[index]["id"]] = index
	has_builder_snapshot = true


func load_default_builds() -> void:
	# 应用 JSON 中配置的推荐构筑。
	# 这样初学者打开项目后可以直接体验战斗，不需要先手动拼好所有技能。
	for state in card_states:
		state["placements"].clear()

	for build_data in default_builds:
		var card_id: String = build_data.get("card_id", "")
		if not card_index_by_id.has(card_id):
			continue
		var card_index: int = card_index_by_id[card_id]
		var validation := validate_placement(
			card_index,
			build_data["module_id"],
			_pair_to_vector(build_data["anchor"]),
			int(build_data.get("rotation", 0))
		)
		if validation["ok"]:
			card_states[card_index]["placements"].append({
				"module_id": build_data["module_id"],
				"anchor": _pair_to_vector(build_data["anchor"]),
				"rotation": int(build_data.get("rotation", 0)),
				"cells": validation["cells"]
			})


func ensure_runtime_inventory() -> void:
	ensure_ready()
	if not runtime_module_inventory.is_empty():
		return
	for module_id in module_order:
		runtime_module_inventory[module_id] = int(modules[module_id].get("count", 0))


func add_module_to_inventory(module_id: String, amount: int = 1) -> void:
	ensure_runtime_inventory()
	if not runtime_module_inventory.has(module_id):
		runtime_module_inventory[module_id] = 0
	runtime_module_inventory[module_id] = int(runtime_module_inventory[module_id]) + amount


func remove_module_from_inventory(module_id: String, amount: int = 1) -> bool:
	ensure_runtime_inventory()
	if int(runtime_module_inventory.get(module_id, 0)) < amount:
		return false
	runtime_module_inventory[module_id] = int(runtime_module_inventory[module_id]) - amount
	if int(runtime_module_inventory[module_id]) <= 0:
		runtime_module_inventory.erase(module_id)
	return true


func get_module_inventory() -> Dictionary:
	ensure_runtime_inventory()
	return runtime_module_inventory.duplicate(true)


func get_module_total_count(module_id: String) -> int:
	ensure_runtime_inventory()
	return int(runtime_module_inventory.get(module_id, 0))


func start_exploration() -> void:
	exploration_state = {
		"current_step": 0,
		"current_node_type": "",
		"completed_nodes": [],
		"is_exploration_active": true,
		"shop_open": false,
		"boss_defeated": false
	}
	gold = 100
	shop_offers.clear()
	shop_refresh_cost = 10
	saved_morale = 80
	has_party_snapshot = false
	party_snapshot.clear()
	owned_relic_ids.clear()
	clear_battle_checkpoint()


func advance_exploration(node_type: String) -> void:
	if not bool(exploration_state.get("is_exploration_active", false)):
		start_exploration()
	exploration_state["current_step"] = int(exploration_state.get("current_step", 0)) + 1
	exploration_state["current_node_type"] = node_type
	exploration_state["shop_open"] = node_type == "shop"
	var completed: Array = exploration_state.get("completed_nodes", [])
	completed.append(node_type)
	exploration_state["completed_nodes"] = completed


func create_battle_checkpoint() -> void:
	battle_checkpoint = {
		"exploration_state": exploration_state.duplicate(true),
		"gold": gold,
		"saved_morale": saved_morale,
		"has_party_snapshot": has_party_snapshot,
		"party_snapshot": party_snapshot.duplicate(true),
		"runtime_module_inventory": runtime_module_inventory.duplicate(true),
		"owned_relic_ids": owned_relic_ids.duplicate(true)
	}
	has_battle_checkpoint = true


func restore_battle_checkpoint() -> bool:
	if not has_battle_checkpoint:
		return false
	exploration_state = battle_checkpoint.get("exploration_state", exploration_state).duplicate(true)
	gold = int(battle_checkpoint.get("gold", gold))
	saved_morale = int(battle_checkpoint.get("saved_morale", saved_morale))
	has_party_snapshot = bool(battle_checkpoint.get("has_party_snapshot", has_party_snapshot))
	party_snapshot = battle_checkpoint.get("party_snapshot", []).duplicate(true)
	runtime_module_inventory = battle_checkpoint.get("runtime_module_inventory", runtime_module_inventory).duplicate(true)
	owned_relic_ids = battle_checkpoint.get("owned_relic_ids", owned_relic_ids).duplicate(true)
	return true


func clear_battle_checkpoint() -> void:
	has_battle_checkpoint = false
	battle_checkpoint.clear()


func end_exploration(success: bool) -> void:
	exploration_state["is_exploration_active"] = false
	exploration_state["boss_defeated"] = success


func add_gold(amount: int) -> void:
	gold += amount


func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	return true


func get_module_used_count(module_id: String) -> int:
	var used := 0
	for state in card_states:
		for placement in state.get("placements", []):
			if str(placement.get("module_id", "")) == module_id:
				used += 1
	return used


func get_module_available_count(module_id: String) -> int:
	return max(get_module_total_count(module_id) - get_module_used_count(module_id), 0)


func get_module_sell_price(module_id: String) -> int:
	var module: Dictionary = modules.get(module_id, {})
	return 30 if str(module.get("quality", "white")) == "green" else 15


func roll_shop_offers() -> void:
	var pool: Array = []
	for module_id in module_order:
		var module: Dictionary = modules[module_id]
		if bool(module.get("reward_excluded", false)):
			continue
		if str(module.get("quality", "white")) == "green":
			pool.append(module_id)
	pool.shuffle()
	shop_offers.clear()
	var choice_count: int = mini(3, pool.size())
	for module_id in pool.slice(0, choice_count):
		shop_offers.append({
			"module_id": module_id,
			"price": randi_range(40, 60),
			"sold": false
		})


func ensure_shop_offers() -> void:
	ensure_runtime_inventory()
	if shop_offers.is_empty():
		roll_shop_offers()


func save_party_state(allies: Array, morale_value: int) -> void:
	party_snapshot = allies.duplicate(true)
	saved_morale = morale_value
	has_party_snapshot = true


func get_party_snapshot() -> Array:
	return party_snapshot.duplicate(true)


func get_relic(relic_id: String) -> Dictionary:
	var relic: Dictionary = RELICS.get(relic_id, {}).duplicate(true)
	if relic.has("name_key"):
		relic["name"] = _text(str(relic["name_key"]))
	if relic.has("desc_key"):
		relic["description"] = _text(str(relic["desc_key"]))
	return relic


func has_relic(relic_id: String) -> bool:
	return owned_relic_ids.has(relic_id)


func add_relic(relic_id: String) -> bool:
	if not RELICS.has(relic_id) or owned_relic_ids.has(relic_id):
		return false
	owned_relic_ids.append(relic_id)
	return true


func remaining_relic_ids() -> Array:
	var result: Array = []
	for relic_id in RELIC_ORDER:
		if not owned_relic_ids.has(relic_id):
			result.append(relic_id)
	return result


func roll_relic_choices(count: int = 3) -> Array:
	var pool: Array = remaining_relic_ids()
	pool.shuffle()
	return pool.slice(0, mini(count, pool.size()))


func owned_relic_text() -> String:
	if owned_relic_ids.is_empty():
		return _text("RUNTIME_NONE")
	var names := PackedStringArray()
	for relic_id in owned_relic_ids:
		var relic: Dictionary = get_relic(str(relic_id))
		names.append(str(relic.get("name", relic_id)))
	return "、".join(names)


func build_character_runtime(character_index: int) -> Dictionary:
	# 把角色静态数据转换成战斗用的运行时单位。
	# battle_scene 会继续给它追加 row/col/field/dead 等战斗字段。
	var character: Dictionary = characters[character_index]
	var stats: Dictionary = character["stats"]
	var equipped_skills := []
	for card_id in character_states[character_index]["equipped_card_ids"]:
		equipped_skills.append(generate_skill_for_card(card_index_by_id[card_id]))
	return {
		"character_id": character["id"],
		"name": character["name"],
		"profession": character["profession"],
		"profession_name": character["profession_name"],
		"strength": int(stats["strength"]),
		"max_hp": int(stats["hp"]),
		"hp": int(stats["hp"]),
		"will": int(stats["will"]),
		"speed": int(stats["speed"]),
		"shield": 0,
		"energy": 3,
		"equipped_skills": equipped_skills,
		"status_effects": []
	}


func get_first_battle_ready_character_index() -> int:
	# 木桩测试场景使用：找第一个装备了非空技能的角色。
	ensure_ready()
	for index in character_states.size():
		for card_id in character_states[index]["equipped_card_ids"]:
			if card_index_by_id.has(card_id) and generate_skill_for_card(card_index_by_id[card_id])["occupied_cells"] > 0:
				return index
	return -1


func get_ready_character_count() -> int:
	# 战斗准备页使用：统计有多少角色已经装备了有效技能。
	var total := 0
	for index in character_states.size():
		var ready := false
		for card_id in character_states[index]["equipped_card_ids"]:
			if card_index_by_id.has(card_id) and generate_skill_for_card(card_index_by_id[card_id])["occupied_cells"] > 0:
				ready = true
		if ready:
			total += 1
	return total


func generate_skill_for_card(card_index: int) -> Dictionary:
	# 这是构筑系统最重要的输出函数：
	# 把技能卡上的模组摆放结果，转换成战斗可直接消费的技能数值。
	var state: Dictionary = card_states[card_index]
	var card: Dictionary = cards[state["card_id"]]
	var result := {
		"card_id": card["id"],
		"name": card["name"],
		"target": card["target_type"],
		"target_summary": card.get("target_summary", ""),
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
		"triggered_specials": [],
		"module_summaries": []
	}

	var special_map: Dictionary = _get_special_map(card)

	# 遍历技能卡上的全部模组。
	# 如果模组压中特殊格，就先增强该模组效果，再累加进最终技能。
	for placement in state["placements"]:
		var module: Dictionary = modules[placement["module_id"]]
		var effects: Dictionary = module["effects"].duplicate(true)
		var module_specials: Array = []
		var module_duration_bonus := 0
		for cell in placement["cells"]:
			var key := _coord_key(cell)
			if not special_map.has(key):
				continue
			var special: Dictionary = special_map[key]
			match special["type"]:
				"damage_boost":
					if effects.has("damage_pct"):
						effects["damage_pct"] *= 1.3
						module_specials.append(_format_text("BUILD_SPECIAL_TRIGGER", {"module": module["name"], "label": special["label"]}))
				"heal_boost":
					if effects.has("heal_pct"):
						effects["heal_pct"] *= 1.25
						module_specials.append(_format_text("BUILD_SPECIAL_TRIGGER", {"module": module["name"], "label": special["label"]}))
				"shield_boost":
					if effects.has("shield_pct"):
						effects["shield_pct"] *= 1.2
						module_specials.append(_format_text("BUILD_SPECIAL_TRIGGER", {"module": module["name"], "label": special["label"]}))
					if effects.has("morale_shield"):
						var morale_shield: Dictionary = effects["morale_shield"]
						morale_shield["shield_pct"] = float(morale_shield.get("shield_pct", 0.0)) * 1.2
						module_specials.append(_format_text("BUILD_SPECIAL_TRIGGER", {"module": module["name"], "label": special["label"]}))
				"support_duration":
					if effects.has("speed_buff") or effects.has("damage_reduction_pct"):
						module_duration_bonus += 1
						module_specials.append(_format_text("BUILD_SPECIAL_TRIGGER", {"module": module["name"], "label": special["label"]}))
				"anti_shield":
					if effects.has("damage_pct"):
						result["anti_shield_bonus"] = true
						module_specials.append(_format_text("BUILD_SPECIAL_TRIGGER", {"module": module["name"], "label": special["label"]}))

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
			result["speed_duration"] = max(int(result["speed_duration"]), 1 + module_duration_bonus)
		if effects.has("damage_reduction_pct"):
			result["damage_reduction_pct"] += int(effects.get("damage_reduction_pct", 0))
			result["damage_reduction_duration"] = max(int(result["damage_reduction_duration"]), 1 + module_duration_bonus)
		result["occupied_cells"] += placement["cells"].size()
		result["module_summaries"].append("%s | %s：%s" % [module["name"], module_shape_text(module["shape"], module["size"]), module["description"]])
		for text in module_specials:
			result["triggered_specials"].append(text)

	for placement in state["placements"]:
		var module: Dictionary = modules[placement["module_id"]]
		if str(module.get("id", "")).begins_with("burning_strike"):
			var adjacent_damage := 0.0
			for other in state["placements"]:
				if other == placement or not _placements_adjacent(placement, other):
					continue
				var other_module: Dictionary = modules[other["module_id"]]
				adjacent_damage += float(other_module.get("effects", {}).get("damage_pct", 0.0))
			if adjacent_damage > 0.0:
				var factor: float = float(module.get("effects", {}).get("burning_strike_factor", 0.5))
				var burn_pct: float = adjacent_damage * factor
				result["status_modules"].append({
					"id": "burn",
					"scale_stat": "strength",
					"scale_pct": burn_pct,
					"flat": 0,
					"module_name": module["name"]
				})
				result["triggered_specials"].append(_format_text("BUILD_BURNING_STRIKE_SPECIAL", {
					"module": module["name"],
					"value": "%.0f" % burn_pct
				}))

	if result["speed_buff"] > 0 or result["damage_reduction_pct"] > 0:
		result["support_duration"] = max(int(result["speed_duration"]), int(result["damage_reduction_duration"]))
	result["energy_cost"] = energy_cost_for(card["energy_curve"], result["occupied_cells"])
	return result


func skill_effect_summary(skill: Dictionary) -> String:
	# 将技能字典转换成一句摘要，供准备页、按钮悬停和角色装备列表显示。
	var parts := PackedStringArray()
	var morale_damage_pct := 0.0
	var morale_damage_cost := 0
	for morale_damage in skill.get("morale_damage_modules", []):
		morale_damage_pct += float(morale_damage.get("damage_pct", 0.0))
		morale_damage_cost += int(morale_damage.get("cost", 0))
	var total_damage_pct: float = float(skill["damage_pct"]) + morale_damage_pct
	if total_damage_pct > 0.0:
		var damage_text := _format_text("RUNTIME_SUMMARY_DAMAGE", {"value": "%.0f" % total_damage_pct})
		if morale_damage_pct > 0.0:
			damage_text += _format_text("BUILD_PREVIEW_MORALE_APPEND", {
				"cost": morale_damage_cost,
				"value": "%.0f" % morale_damage_pct
			})
		parts.append(damage_text)
	if skill["heal_pct"] > 0.0:
		parts.append(_format_text("RUNTIME_SUMMARY_HEAL", {"value": "%.0f" % skill["heal_pct"]}))
	var morale_shield_pct := 0.0
	var morale_shield_cost := 0
	for morale_shield in skill.get("morale_shield_modules", []):
		morale_shield_pct += float(morale_shield.get("shield_pct", 0.0))
		morale_shield_cost += int(morale_shield.get("cost", 0))
	var total_shield_pct: float = float(skill["shield_pct"]) + morale_shield_pct
	if total_shield_pct > 0.0:
		var shield_text := _format_text("RUNTIME_SUMMARY_SHIELD", {"value": "%.0f" % total_shield_pct})
		if morale_shield_pct > 0.0:
			shield_text += _format_text("BUILD_PREVIEW_MORALE_APPEND", {
				"cost": morale_shield_cost,
				"value": "%.0f" % morale_shield_pct
			})
		parts.append(shield_text)
	if skill["pierce_pct"] > 0.0:
		parts.append(_format_text("RUNTIME_SUMMARY_PIERCE", {"value": "%.0f" % skill["pierce_pct"]}))
	if skill["speed_buff"] > 0:
		parts.append(_format_text("RUNTIME_SUMMARY_SPEED", {
			"speed": skill["speed_buff"],
			"turns": int(skill.get("speed_duration", skill["support_duration"]))
		}))
	if skill["damage_reduction_pct"] > 0:
		parts.append(_format_text("RUNTIME_SUMMARY_REDUCTION", {
			"value": skill["damage_reduction_pct"],
			"turns": int(skill.get("damage_reduction_duration", skill["support_duration"]))
		}))
	if skill["anti_shield_bonus"]:
		parts.append(_text("RUNTIME_SUMMARY_ANTI_SHIELD"))
	for status in skill.get("status_modules", []):
		var status_id := str(status.get("id", ""))
		if status_id == "burn" and status.has("scale_pct"):
			var flat_layers: int = int(status.get("flat", 0))
			var flat_text: String = _format_text("BUILD_PREVIEW_FLAT_LAYER_APPEND", {"layers": flat_layers}) if flat_layers > 0 else ""
			parts.append(_format_text("RUNTIME_SUMMARY_BURN", {
				"value": "%.0f" % float(status.get("scale_pct", 0.0)),
				"stat": str(status.get("scale_stat", "strength")),
				"flat": flat_text
			}))
		else:
			parts.append(_format_text("RUNTIME_SUMMARY_STATUS", {
				"status": _status_display_name(status_id),
				"layers": int(status.get("layers", 0))
			}))
	return "、".join(parts) if not parts.is_empty() else _text("RUNTIME_NO_EFFECT")


func _status_display_name(status_id: String) -> String:
	match status_id:
		"vulnerable":
			return _text("STATUS_VULNERABLE")
		"weak":
			return _text("STATUS_WEAK")
		"burn":
			return _text("STATUS_BURN")
		"cold":
			return _text("STATUS_COLD")
		"freeze":
			return _text("STATUS_FREEZE")
	return status_id


func validate_placement(card_index: int, module_id: String, anchor: Vector2i, rotation: int) -> Dictionary:
	# 校验模组放置是否合法。推荐构筑和手动构筑都应该遵守同一套规则。
	var module: Dictionary = modules[module_id]
	var state: Dictionary = card_states[card_index]
	var card: Dictionary = cards[state["card_id"]]
	var rotated_cells: Array = get_rotated_shape(module["shape"], module["size"], rotation)
	var occupied: Dictionary = _get_occupied_map(card_index)
	var active_map: Dictionary = _get_active_map(card)
	var absolute_cells: Array = []
	for cell in rotated_cells:
		var absolute: Vector2i = anchor + cell
		if absolute.x < 0 or absolute.y < 0 or absolute.x >= card["width"] or absolute.y >= card["height"]:
			return {"ok": false}
		if not active_map.has(_coord_key(absolute)) or occupied.has(_coord_key(absolute)):
			return {"ok": false}
		absolute_cells.append(absolute)
	return {"ok": true, "cells": absolute_cells}


func energy_cost_for(curve: String, occupied_cells: int) -> int:
	# 根据技能卡能量曲线和占用格数计算能量消耗。
	# range 是横扫这类范围技能，single 是单体/支援技能。
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


func module_shape_text(shape: Array, size: Vector2i) -> String:
	# 把模组形状转成玩家可读文本，供准备页、地图宝箱、战斗奖励和技能说明复用。
	var rows := []
	for row in range(size.y):
		var row_text := ""
		for column in range(size.x):
			var filled := false
			for cell in shape:
				if cell == Vector2i(column, row):
					filled = true
					break
			row_text += "■" if filled else "□"
		rows.append(row_text)
	return "%dx%d：%s" % [size.x, size.y, "/".join(rows)]


func get_rotated_shape(shape: Array, size: Vector2i, rotation: int) -> Array:
	# 根据旋转次数返回新形状。rotation=1 表示顺时针 90 度。
	var current_cells: Array = shape.duplicate()
	var current_size := size
	for _i in range(rotation % 4):
		var rotated: Array = []
		for cell in current_cells:
			rotated.append(Vector2i(current_size.y - 1 - cell.y, cell.x))
		current_cells = rotated
		current_size = Vector2i(current_size.y, current_size.x)
	return current_cells


func _get_occupied_map(card_index: int) -> Dictionary:
	# 生成已占用格子的查询表，用于快速判断重叠。
	var occupied := {}
	for placement in card_states[card_index]["placements"]:
		for cell in placement["cells"]:
			occupied[_coord_key(cell)] = true
	return occupied


func _get_active_map(card: Dictionary) -> Dictionary:
	# 生成可用格子的查询表。
	var active := {}
	for cell in card["active_cells"]:
		active[_coord_key(cell)] = true
	return active


func _get_special_map(card: Dictionary) -> Dictionary:
	# 生成特殊格查询表，方便技能生成时判断特殊加成。
	var special := {}
	for slot in card["special_slots"]:
		special[_coord_key(slot["pos"])] = slot
	return special


func _coords(source: Array) -> Array:
	# JSON 中坐标是 [x, y] 数组，这里批量转为 Vector2i。
	var result := []
	for pair in source:
		result.append(_pair_to_vector(pair))
	return result


func _pair_to_vector(pair) -> Vector2i:
	# 单个 [x, y] 坐标转 Vector2i。
	return Vector2i(int(pair[0]), int(pair[1]))


func _resolve_text_fields(record: Dictionary, field_map: Dictionary) -> void:
	for key_field in field_map.keys():
		var output_field: String = str(field_map[key_field])
		if record.has(key_field):
			record[output_field] = _text(str(record[key_field]))


func _resolve_text_array_field(record: Dictionary, key_field: String, output_field: String) -> void:
	if not record.has(key_field):
		return
	var values: Array = []
	for text_key in record[key_field]:
		values.append(_text(str(text_key)))
	record[output_field] = values


func _text(key: String) -> String:
	var database := get_node_or_null("/root/TextDatabase")
	if database != null and database.has_method("get_text"):
		return str(database.call("get_text", key))
	if fallback_text_database == null:
		fallback_text_database = TEXT_DATABASE_SCRIPT.new()
		fallback_text_database.call("load_texts")
	if fallback_text_database.has_method("get_text"):
		return str(fallback_text_database.call("get_text", key))
	return key


func _format_text(key: String, params: Dictionary) -> String:
	var database := get_node_or_null("/root/TextDatabase")
	if database != null and database.has_method("format_text"):
		return str(database.call("format_text", key, params))
	var text := _text(key)
	for param_key in params.keys():
		text = text.replace("{%s}" % str(param_key), str(params[param_key]))
	return text


func _coord_key(coord: Vector2i) -> String:
	# Dictionary key 不能直接稳定使用 Vector2i 时，统一转成字符串。
	return "%d_%d" % [coord.x, coord.y]


func _placements_adjacent(a: Dictionary, b: Dictionary) -> bool:
	for acell in a.get("cells", []):
		for bcell in b.get("cells", []):
			var distance: int = abs(int(acell.x) - int(bcell.x)) + abs(int(acell.y) - int(bcell.y))
			if distance == 1:
				return true
	return false
