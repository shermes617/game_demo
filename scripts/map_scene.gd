extends Control

const MAP_STEPS: Array = [
	["normal"],
	["normal", "chest"],
	["elite"],
	["shop"],
	["elite"],
	["chest", "shop", "campfire"],
	["boss"]
]

var action_buttons: Array = []

@onready var title_label: Label = %TitleLabel
@onready var status_label: RichTextLabel = %StatusLabel
@onready var action_list: VBoxContainer = %ActionList
@onready var action_scroll: ScrollContainer = %ActionScroll
@onready var content_row: HBoxContainer = %ContentRow
@onready var map_list: HBoxContainer = %MapList
@onready var map_panel: PanelContainer = %MapPanel
@onready var map_title: Label = %MapTitle


func _ready() -> void:
	BattleRuntime.ensure_ready()
	BattleRuntime.ensure_runtime_inventory()
	if not bool(BattleRuntime.exploration_state.get("is_exploration_active", false)):
		BattleRuntime.start_exploration()
	_style_scene()
	if bool(BattleRuntime.exploration_state.get("shop_open", false)):
		_show_shop()
		return
	_refresh()


func _refresh() -> void:
	_clear_actions()
	_set_shop_layout(false)
	var current_step: int = int(BattleRuntime.exploration_state.get("current_step", 0))
	var display_step: int = mini(current_step + 1, MAP_STEPS.size())
	title_label.text = "探索地图"
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]探索进度[/b]：第 %d / %d 步" % [display_step, MAP_STEPS.size()])
	lines.append("士气：%d | 金币：%d" % [BattleRuntime.saved_morale, BattleRuntime.gold])
	lines.append("遗物：%s" % BattleRuntime.owned_relic_text())
	lines.append("")
	lines.append("[b]队伍状态[/b]")
	var snapshot: Array = BattleRuntime.get_party_snapshot()
	if snapshot.is_empty():
		lines.append("尚未经历战斗，队伍状态完整。")
	else:
		for unit in snapshot:
			lines.append("%s HP %d/%d 重伤 %d" % [unit["name"], int(unit["hp"]), int(unit["max_hp"]), int(unit.get("injury_marks", 0))])
	status_label.text = "\n".join(lines)

	var build: Button = _add_action("进入构筑调整")
	build.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/skill_build_scene.tscn")
	)

	if current_step >= MAP_STEPS.size():
		var end: Button = _add_action("探索已完成")
		end.disabled = true
		_rebuild_map(MAP_STEPS.size())
		return

	for raw_node_type in MAP_STEPS[current_step]:
		var node_type: String = str(raw_node_type)
		var button: Button = _add_action(_node_label(node_type))
		button.pressed.connect(_choose_node.bind(node_type))
	_rebuild_map(current_step)


func _choose_node(node_type: String) -> void:
	BattleRuntime.advance_exploration(node_type)
	match node_type:
		"normal", "elite", "boss":
			BattleRuntime.create_battle_checkpoint()
			get_tree().change_scene_to_file("res://scenes/battle_scene.tscn")
		"chest":
			_show_chest_rewards()
		"shop":
			BattleRuntime.ensure_shop_offers()
			_show_shop()
		"campfire":
			_use_campfire()


func _show_chest_rewards() -> void:
	_clear_actions()
	var pool: Array = []
	for module_id in BattleRuntime.module_order:
		var module: Dictionary = BattleRuntime.modules[module_id]
		if bool(module.get("reward_excluded", false)):
			continue
		if str(module.get("quality", "white")) == "green":
			pool.append(module_id)
	pool.shuffle()
	var choice_count: int = mini(3, pool.size())
	for module_id in pool.slice(0, choice_count):
		var module: Dictionary = BattleRuntime.modules[module_id]
		var button: Button = _add_action("%s\n%s\n%s" % [module["name"], BattleRuntime.module_shape_text(module["shape"], module["size"]), module["description"]])
		button.pressed.connect(_take_chest_reward.bind(module_id))
	_rebuild_map(int(BattleRuntime.exploration_state.get("current_step", 0)) - 1)


func _take_chest_reward(module_id: String) -> void:
	BattleRuntime.add_module_to_inventory(module_id, 1)
	_refresh()


func _show_shop(message: String = "") -> void:
	_clear_actions()
	_set_shop_layout(true)
	BattleRuntime.ensure_shop_offers()
	title_label.text = "商店"
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]商店[/b]")
	lines.append("金币：%d | 下次刷新：%d 金币" % [BattleRuntime.gold, BattleRuntime.shop_refresh_cost])
	lines.append("遗物：%s" % BattleRuntime.owned_relic_text())
	lines.append("")
	lines.append("可购买 3 个随机绿色模组。出售只能出售未安装在技能卡上的模组。")
	if not message.is_empty():
		lines.append("")
		lines.append("[color=#80d4ff]%s[/color]" % message)
	status_label.text = "\n".join(lines)

	var build: Button = _add_action("进入构筑调整")
	build.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/skill_build_scene.tscn")
	)

	for index in BattleRuntime.shop_offers.size():
		var offer: Dictionary = BattleRuntime.shop_offers[index]
		var module_id: String = str(offer.get("module_id", ""))
		if not BattleRuntime.modules.has(module_id):
			continue
		var module: Dictionary = BattleRuntime.modules[module_id]
		var sold: bool = bool(offer.get("sold", false))
		var price: int = int(offer.get("price", 0))
		var text := "%s%s\n价格：%d 金币\n%s\n%s" % [
			"已售出：" if sold else "购买：",
			module["name"],
			price,
			BattleRuntime.module_shape_text(module["shape"], module["size"]),
			module["description"]
		]
		var button: Button = _add_action(text)
		button.disabled = sold or BattleRuntime.gold < price
		button.pressed.connect(_buy_shop_offer.bind(index))

	var sell: Button = _add_action("出售模块")
	sell.pressed.connect(_show_sell_modules)

	var refresh: Button = _add_action("刷新商店（%d 金币）" % BattleRuntime.shop_refresh_cost)
	refresh.disabled = BattleRuntime.gold < BattleRuntime.shop_refresh_cost
	refresh.pressed.connect(_refresh_shop_offers)

	var leave: Button = _add_action("离开商店，继续探索")
	leave.pressed.connect(func() -> void:
		BattleRuntime.exploration_state["shop_open"] = false
		_refresh()
	)
	_rebuild_map(int(BattleRuntime.exploration_state.get("current_step", 0)) - 1)


func _buy_shop_offer(index: int) -> void:
	if index < 0 or index >= BattleRuntime.shop_offers.size():
		_show_shop("这个商品已经不存在。")
		return
	var offer: Dictionary = BattleRuntime.shop_offers[index]
	if bool(offer.get("sold", false)):
		_show_shop("这个模组已经售出。")
		return
	var module_id: String = str(offer.get("module_id", ""))
	var price: int = int(offer.get("price", 0))
	if not BattleRuntime.spend_gold(price):
		_show_shop("金币不足，无法购买。")
		return
	BattleRuntime.add_module_to_inventory(module_id, 1)
	offer["sold"] = true
	BattleRuntime.shop_offers[index] = offer
	var module: Dictionary = BattleRuntime.modules[module_id]
	_show_shop("购买成功：%s，花费 %d 金币。" % [module["name"], price])


func _refresh_shop_offers() -> void:
	var cost: int = BattleRuntime.shop_refresh_cost
	if not BattleRuntime.spend_gold(cost):
		_show_shop("金币不足，无法刷新。")
		return
	BattleRuntime.roll_shop_offers()
	BattleRuntime.shop_refresh_cost += 10
	_show_shop("商店已刷新，花费 %d 金币。" % cost)


func _show_sell_modules(message: String = "") -> void:
	_clear_actions()
	_set_shop_layout(true)
	title_label.text = "出售模块"
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]出售模块[/b]")
	lines.append("金币：%d" % BattleRuntime.gold)
	lines.append("白色模块售价 15 金币，绿色模块售价 30 金币。只能出售未安装在技能卡上的模块。")
	if not message.is_empty():
		lines.append("")
		lines.append("[color=#80d4ff]%s[/color]" % message)
	status_label.text = "\n".join(lines)

	var has_sellable := false
	for module_id in BattleRuntime.module_order:
		var available: int = BattleRuntime.get_module_available_count(module_id)
		if available <= 0:
			continue
		has_sellable = true
		var module: Dictionary = BattleRuntime.modules[module_id]
		var price: int = BattleRuntime.get_module_sell_price(module_id)
		var button: Button = _add_action("出售：%s x%d\n价格：%d 金币\n%s" % [module["name"], available, price, module["description"]])
		button.pressed.connect(_sell_module.bind(module_id))
	if not has_sellable:
		var empty: Button = _add_action("没有可出售的未安装模块")
		empty.disabled = true

	var back: Button = _add_action("返回商店")
	back.pressed.connect(_show_shop)
	var build: Button = _add_action("进入构筑调整")
	build.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/skill_build_scene.tscn")
	)
	_rebuild_map(int(BattleRuntime.exploration_state.get("current_step", 0)) - 1)


func _sell_module(module_id: String) -> void:
	if BattleRuntime.get_module_available_count(module_id) <= 0:
		_show_sell_modules("这个模组已安装或库存不足，无法出售。")
		return
	var price: int = BattleRuntime.get_module_sell_price(module_id)
	if not BattleRuntime.remove_module_from_inventory(module_id, 1):
		_show_sell_modules("出售失败：库存不足。")
		return
	BattleRuntime.add_gold(price)
	var module: Dictionary = BattleRuntime.modules[module_id]
	_show_sell_modules("出售成功：%s，获得 %d 金币。" % [module["name"], price])


func _use_campfire() -> void:
	var snapshot: Array = BattleRuntime.get_party_snapshot()
	for unit in snapshot:
		if bool(unit.get("dead", false)):
			continue
		var max_hp: int = int(unit.get("max_hp", 0))
		var heal: int = int(round(float(max_hp) * 0.3))
		unit["hp"] = mini(max_hp, int(unit.get("hp", max_hp)) + heal)
	BattleRuntime.party_snapshot = snapshot.duplicate(true)
	BattleRuntime.has_party_snapshot = true
	BattleRuntime.saved_morale = clamp(BattleRuntime.saved_morale + 20, 0, 100)
	_clear_actions()
	title_label.text = "火堆"
	status_label.text = "[b]火堆休整[/b]\n所有未死亡角色恢复 30% 最大生命值。\n士气 +20。\n\n当前士气：%d | 金币：%d" % [BattleRuntime.saved_morale, BattleRuntime.gold]
	var continue_button: Button = _add_action("继续探索")
	continue_button.pressed.connect(_refresh)
	_rebuild_map(int(BattleRuntime.exploration_state.get("current_step", 0)) - 1)


func _rebuild_map(current_step: int) -> void:
	_clear_container(map_list)
	var completed: Array = BattleRuntime.exploration_state.get("completed_nodes", [])
	for step_index in MAP_STEPS.size():
		var node_types: Array = MAP_STEPS[step_index]
		var column: VBoxContainer = VBoxContainer.new()
		column.custom_minimum_size = Vector2(120, 0)
		column.add_theme_constant_override("separation", 8)
		map_list.add_child(column)

		var step_label: Label = Label.new()
		step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		step_label.add_theme_font_size_override("font_size", 14)
		step_label.add_theme_color_override("font_color", Color("aeb9ca"))
		step_label.text = "%d" % (step_index + 1)
		column.add_child(step_label)

		var selected_type: String = str(completed[step_index]) if step_index < completed.size() else ""
		for row_index in range(3):
			var panel: PanelContainer = PanelContainer.new()
			panel.custom_minimum_size = Vector2(110, 50)
			var has_node: bool = row_index < node_types.size()
			var node_type: String = str(node_types[row_index]) if has_node else ""
			var is_completed: bool = step_index < completed.size() and node_type == selected_type
			var is_current: bool = step_index == current_step and has_node
			panel.add_theme_stylebox_override("panel", _map_node_style(has_node, is_completed, is_current))
			column.add_child(panel)

			var node_label: Label = Label.new()
			node_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			node_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			node_label.add_theme_font_size_override("font_size", 14)
			node_label.add_theme_color_override("font_color", Color("edf1f8") if has_node else Color("3a4250"))
			node_label.text = _node_short_label(node_type, is_current, is_completed) if has_node else ""
			panel.add_child(node_label)


func _node_short_label(node_type: String, is_current: bool, is_completed: bool) -> String:
	var prefix: String = "▶ " if is_current else "✓ " if is_completed else ""
	match node_type:
		"normal":
			return "%s小怪" % prefix
		"elite":
			return "%s精英" % prefix
		"boss":
			return "%sBoss" % prefix
		"chest":
			return "%s宝箱" % prefix
		"shop":
			return "%s商店" % prefix
		"campfire":
			return "%s火堆" % prefix
	return "%s%s" % [prefix, node_type]


func _node_label(node_type: String) -> String:
	match node_type:
		"normal":
			return "小怪"
		"elite":
			return "精英"
		"boss":
			return "Boss"
		"chest":
			return "宝箱：获得绿色模组"
		"shop":
			return "商店"
		"campfire":
			return "火堆：恢复生命与士气"
	return node_type


func _add_action(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 52)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_stylebox_override("normal", _button_style(Color("2e6ee6")))
	button.add_theme_stylebox_override("hover", _button_style(Color("3d7df0")))
	button.add_theme_stylebox_override("pressed", _button_style(Color("2059c8")))
	button.add_theme_stylebox_override("disabled", _button_style(Color("222936")))
	button.add_theme_color_override("font_color", Color("eff3fb"))
	action_list.add_child(button)
	action_buttons.append(button)
	return button


func _clear_actions() -> void:
	for button in action_buttons:
		if is_instance_valid(button):
			button.queue_free()
	action_buttons.clear()


func _clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


func _style_scene() -> void:
	title_label.add_theme_font_size_override("font_size", 36)
	title_label.add_theme_color_override("font_color", Color("f6f7fb"))
	status_label.bbcode_enabled = true
	status_label.fit_content = true
	status_label.scroll_active = false
	status_label.add_theme_font_size_override("normal_font_size", 18)
	status_label.add_theme_color_override("default_color", Color("dce5f4"))
	%MainPanel.add_theme_stylebox_override("panel", _panel_style())
	map_panel.add_theme_stylebox_override("panel", _panel_style())
	map_title.add_theme_font_size_override("font_size", 22)
	map_title.add_theme_color_override("font_color", Color("f6f7fb"))
	_set_shop_layout(false)


func _set_shop_layout(enabled: bool) -> void:
	if enabled:
		content_row.custom_minimum_size = Vector2(0, 520)
		status_label.custom_minimum_size = Vector2(420, 0)
		action_scroll.custom_minimum_size = Vector2(0, 0)
		map_panel.custom_minimum_size = Vector2(0, 260)
	else:
		content_row.custom_minimum_size = Vector2(0, 220)
		status_label.custom_minimum_size = Vector2(520, 0)
		action_scroll.custom_minimum_size = Vector2(0, 0)
		map_panel.custom_minimum_size = Vector2(0, 420)


func _panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("1b2029")
	style.border_color = Color("2a3342")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 24
	style.content_margin_top = 24
	style.content_margin_right = 24
	style.content_margin_bottom = 24
	return style


func _button_style(base: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = base
	style.border_color = base.lightened(0.18)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_top = 12
	style.content_margin_right = 16
	style.content_margin_bottom = 12
	return style


func _map_node_style(has_node: bool, completed: bool, current: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	if not has_node:
		style.bg_color = Color("141922")
		style.border_color = Color("1b2029")
	elif current:
		style.bg_color = Color("243b5c")
		style.border_color = Color("80d4ff")
	elif completed:
		style.bg_color = Color("23442e")
		style.border_color = Color("72d695")
	else:
		style.bg_color = Color("202733")
		style.border_color = Color("39475b")
	style.set_border_width_all(2 if current else 1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8
	style.content_margin_top = 8
	style.content_margin_right = 8
	style.content_margin_bottom = 8
	return style
