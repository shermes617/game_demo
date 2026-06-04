extends Control

const BOARD_COLUMNS := 4
const BOARD_ROWS := 4
const DATA_PATH := "res://data/demo_data.json"

# cards/modules/characters 保存从 JSON 读取的静态定义。
# card_states/character_states 保存玩家在场景中编辑后的运行时状态。
var cards: Dictionary = {}
var modules: Dictionary = {}
var characters: Array = []
var default_builds: Array = []

var card_order: Array = []
var module_order: Array = []
var character_order: Array = []

var card_states: Array = []
var character_states: Array = []
var card_index_by_id: Dictionary = {}
var character_index_by_id: Dictionary = {}

var current_view := "card"
var selected_card_index := 0
var selected_character_index := 0
var selected_module_id := ""
var selected_rotation := 0
var preview_message := ""
var cursor_preview_cells: Array = []

var primary_buttons: Array = []
var secondary_buttons: Dictionary = {}
var board_buttons: Dictionary = {}

@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var card_view_button: Button = %CardViewButton
@onready var character_view_button: Button = %CharacterViewButton
@onready var top_battle_prepare_button: Button = %TopBattlePrepareButton

@onready var left_panel: PanelContainer = %LeftPanel
@onready var left_header_label: Label = %LeftHeaderLabel
@onready var left_hint_label: Label = %LeftHintLabel
@onready var primary_list: VBoxContainer = %PrimaryList
@onready var secondary_section_label: Label = %SecondarySectionLabel
@onready var secondary_list: VBoxContainer = %SecondaryList
@onready var selection_label: Label = %SelectionLabel

@onready var center_panel: PanelContainer = %CenterPanel
@onready var workspace_title_label: Label = %WorkspaceTitleLabel
@onready var card_workspace: VBoxContainer = %CardWorkspace
@onready var board_title_label: Label = %BoardTitleLabel
@onready var board_hint_label: Label = %BoardHintLabel
@onready var board_grid: GridContainer = %BoardGrid
@onready var rotate_button: Button = %RotateButton
@onready var clear_button: Button = %ClearButton
@onready var defaults_button: Button = %DefaultsButton

@onready var character_workspace: VBoxContainer = %CharacterWorkspace
@onready var character_name_label: Label = %CharacterNameLabel
@onready var character_profession_label: Label = %CharacterProfessionLabel
@onready var character_stats_label: RichTextLabel = %CharacterStatsLabel
@onready var equipped_cards_label: RichTextLabel = %EquippedCardsLabel
@onready var equip_hint_label: Label = %EquipHintLabel
@onready var equip_selected_button: Button = %EquipSelectedButton
@onready var unequip_all_button: Button = %UnequipAllButton

@onready var right_panel: PanelContainer = %RightPanel
@onready var preview_title_label: Label = %PreviewTitleLabel
@onready var preview_body_label: RichTextLabel = %PreviewBodyLabel
@onready var simulation_label: RichTextLabel = %SimulationLabel

@onready var bottom_panel: PanelContainer = %BottomPanel
@onready var simulate_button: Button = %SimulateButton
@onready var battle_prepare_button: Button = %BattlePrepareButton
@onready var return_map_button: Button = %ReturnMapButton
@onready var next_button: Button = %NextButton
@onready var status_label: Label = %StatusLabel

@onready var cursor_preview: Control = %CursorPreview
@onready var cursor_preview_label: Label = %CursorPreviewLabel


## 场景启动入口：按顺序完成数据加载、状态初始化、样式设置、事件绑定和首次界面刷新。
func _ready() -> void:
	_load_data()
	if cards.is_empty() or characters.is_empty():
		return
	BattleRuntime.ensure_runtime_inventory()
	set_process(true)
	_initialize_states()
	_style_static_scene()
	_bind_static_actions()
	_build_dynamic_controls()
	if BattleRuntime.has_builder_snapshot:
		_import_runtime_builder_state()
	else:
		_load_default_builds()
	_refresh_ui("流程：技能卡页调整模组 → 角色页装备技能 → 点击【进入地图】。")


## 读取 JSON 数据文件，并把原始数据转换成脚本内更方便使用的结构。
func _load_data() -> void:
	# Demo 数据完全外置，这样调数值和改内容时不需要直接改脚本。
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("无法打开数据文件：%s" % DATA_PATH)
		return

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("数据文件格式不正确：%s" % DATA_PATH)
		return

	var raw: Dictionary = parsed
	cards.clear()
	modules.clear()
	characters.clear()
	default_builds.clear()
	card_order.clear()
	module_order.clear()
	character_order.clear()

	# 读取技能卡定义，并把可用格子/特殊格坐标转换成 Vector2i。
	for card_data in raw.get("cards", []):
		var card: Dictionary = card_data.duplicate(true)
		card["active_cells"] = _coords(card.get("active_cells", []))
		var special_slots: Array = []
		for slot_data in card.get("special_slots", []):
			var slot: Dictionary = slot_data.duplicate(true)
			slot["pos"] = _pair_to_vector(slot["pos"])
			special_slots.append(slot)
		card["special_slots"] = special_slots
		card["allowed_professions"] = card.get("allowed_professions", []).duplicate(true)
		cards[card["id"]] = card
		card_order.append(card["id"])

	# 读取模组定义，并把形状和尺寸转换成便于计算的结构。
	for module_data in raw.get("modules", []):
		var module: Dictionary = module_data.duplicate(true)
		module["shape"] = _coords(module.get("shape", []))
		module["size"] = _pair_to_vector(module["size"])
		module["effects"] = module.get("effects", {}).duplicate(true)
		modules[module["id"]] = module
		module_order.append(module["id"])

	# 读取角色定义。
	for character_data in raw.get("characters", []):
		var character: Dictionary = character_data.duplicate(true)
		character["allowed_card_slots"] = int(character.get("allowed_card_slots", 1))
		characters.append(character)
		character_order.append(character["id"])

	default_builds = raw.get("default_builds", []).duplicate(true)


## 根据静态定义创建运行时状态，分别维护技能卡构筑状态和角色装备状态。
func _initialize_states() -> void:
	# 运行时状态拆成两层：
	# 1. card_states 用于技能卡拼图构筑
	# 2. character_states 用于角色装备构筑完成后的技能卡
	card_states.clear()
	character_states.clear()
	card_index_by_id.clear()
	character_index_by_id.clear()

	for index in card_order.size():
		var card_id: String = card_order[index]
		card_index_by_id[card_id] = index
		card_states.append({
			"card_id": card_id,
			"placements": []
		})

	for index in characters.size():
		var character: Dictionary = characters[index]
		character_index_by_id[character["id"]] = index
		character_states.append({
			"character_id": character["id"],
			"equipped_card_ids": []
		})


## 给场景中已经存在的静态节点统一设置颜色、面板和按钮样式。
func _style_static_scene() -> void:
	title_label.add_theme_color_override("font_color", Color("f6f7fb"))
	title_label.add_theme_font_size_override("font_size", 36)
	subtitle_label.add_theme_color_override("font_color", Color("97a3b6"))
	subtitle_label.add_theme_font_size_override("font_size", 17)
	left_header_label.add_theme_color_override("font_color", Color("f6f7fb"))
	left_header_label.add_theme_font_size_override("font_size", 24)
	left_hint_label.add_theme_color_override("font_color", Color("93a0b4"))
	left_hint_label.add_theme_font_size_override("font_size", 16)
	secondary_section_label.add_theme_color_override("font_color", Color("d9e0eb"))
	secondary_section_label.add_theme_font_size_override("font_size", 20)
	selection_label.add_theme_color_override("font_color", Color("80d4ff"))
	selection_label.add_theme_font_size_override("font_size", 16)
	workspace_title_label.add_theme_color_override("font_color", Color("f6f7fb"))
	workspace_title_label.add_theme_font_size_override("font_size", 24)
	board_title_label.add_theme_color_override("font_color", Color("edf1f8"))
	board_title_label.add_theme_font_size_override("font_size", 25)
	board_hint_label.add_theme_color_override("font_color", Color("93a0b4"))
	board_hint_label.add_theme_font_size_override("font_size", 16)
	character_name_label.add_theme_color_override("font_color", Color("edf1f8"))
	character_name_label.add_theme_font_size_override("font_size", 28)
	character_profession_label.add_theme_color_override("font_color", Color("93a0b4"))
	character_profession_label.add_theme_font_size_override("font_size", 17)
	equip_hint_label.add_theme_color_override("font_color", Color("93a0b4"))
	equip_hint_label.add_theme_font_size_override("font_size", 17)
	preview_title_label.add_theme_color_override("font_color", Color("edf1f8"))
	preview_title_label.add_theme_font_size_override("font_size", 25)
	status_label.add_theme_color_override("font_color", Color("dce5f4"))
	status_label.add_theme_font_size_override("font_size", 17)

	preview_body_label.add_theme_font_size_override("normal_font_size", 17)
	simulation_label.add_theme_font_size_override("normal_font_size", 17)
	character_stats_label.add_theme_font_size_override("normal_font_size", 17)
	equipped_cards_label.add_theme_font_size_override("normal_font_size", 17)

	left_panel.add_theme_stylebox_override("panel", _create_panel_style())
	center_panel.add_theme_stylebox_override("panel", _create_panel_style())
	right_panel.add_theme_stylebox_override("panel", _create_panel_style())
	bottom_panel.add_theme_stylebox_override("panel", _create_panel_style())

	_style_button(card_view_button, "secondary")
	_style_button(character_view_button, "secondary")
	_style_button(top_battle_prepare_button, "primary")
	_style_button(rotate_button, "primary")
	_style_button(clear_button, "secondary")
	_style_button(defaults_button, "secondary")
	_style_button(equip_selected_button, "primary")
	_style_button(unequip_all_button, "secondary")
	_style_button(simulate_button, "primary")
	_style_button(battle_prepare_button, "primary")
	_style_button(return_map_button, "secondary")
	_style_button(next_button, "secondary")

	cursor_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_preview.visible = false
	simulate_button.visible = false
	battle_prepare_button.visible = false
	cursor_preview_label.add_theme_color_override("font_color", Color("eef4ff"))
	cursor_preview_label.add_theme_font_size_override("font_size", 15)
	preview_body_label.scroll_active = false
	character_stats_label.scroll_active = false
	equipped_cards_label.scroll_active = false


## 绑定场景里固定按钮的点击事件。
func _bind_static_actions() -> void:
	card_view_button.pressed.connect(_switch_to_card_view)
	character_view_button.pressed.connect(_switch_to_character_view)
	top_battle_prepare_button.pressed.connect(_go_to_battle_prepare)
	rotate_button.pressed.connect(_rotate_selected_module)
	clear_button.pressed.connect(_clear_current_skill)
	defaults_button.pressed.connect(_restore_defaults)
	equip_selected_button.pressed.connect(_toggle_equip_selected_card)
	unequip_all_button.pressed.connect(_unequip_all_cards)
	simulate_button.pressed.connect(_simulate_release)
	return_map_button.pressed.connect(_return_to_map)
	next_button.pressed.connect(_handle_next_button)


## 构建动态节点内容，比如棋盘按钮和运行时列表项。
func _build_dynamic_controls() -> void:
	# 场景负责提供可视化区域骨架，列表和棋盘里的重复内容仍然由代码动态生成。
	_clear_container(primary_list)
	_clear_container(secondary_list)
	_clear_container(board_grid)
	primary_buttons.clear()
	secondary_buttons.clear()
	board_buttons.clear()

	# 棋盘按钮固定为 4x4 容器，具体哪些格子可用由技能卡数据决定。
	for row in BOARD_ROWS:
		for column in BOARD_COLUMNS:
			var coord := Vector2i(column, row)
			var cell_button := Button.new()
			cell_button.custom_minimum_size = Vector2(104, 96)
			cell_button.clip_text = true
			cell_button.focus_mode = Control.FOCUS_NONE
			cell_button.add_theme_font_size_override("font_size", 24)
			cell_button.gui_input.connect(_on_board_cell_input.bind(coord))
			cell_button.pressed.connect(_on_board_cell_pressed.bind(coord))
			board_grid.add_child(cell_button)
			board_buttons[_coord_key(coord)] = cell_button


## 清空一个容器节点下的所有子节点，常用于重建列表。
func _clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


## 每帧更新鼠标跟随预览的位置。
func _process(_delta: float) -> void:
	if cursor_preview.visible:
		cursor_preview.position = get_local_mouse_position()


## 处理全局输入，目前主要用于按 R 旋转模组。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		if current_view == "card" and not selected_module_id.is_empty():
			_rotate_selected_module()
			get_viewport().set_input_as_handled()


## 切换到技能卡构筑页面。
func _switch_to_card_view() -> void:
	current_view = "card"
	selected_module_id = ""
	selected_rotation = 0
	preview_message = ""
	_refresh_ui("已切换到技能卡构筑界面。")


## 切换到角色装备页面。
func _switch_to_character_view() -> void:
	current_view = "character"
	selected_module_id = ""
	selected_rotation = 0
	preview_message = ""
	_refresh_ui("已切换到角色界面。只能装备职业允许使用的技能卡。")


## 创建统一的面板样式，供左中右和底部面板复用。
func _create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1b2029")
	style.border_color = Color("2a3342")
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_right = 14
	style.corner_radius_bottom_left = 14
	style.content_margin_left = 18
	style.content_margin_top = 18
	style.content_margin_right = 18
	style.content_margin_bottom = 18
	return style


## 给按钮应用统一样式，variant 用于区分主按钮、次按钮等语义。
func _style_button(button: Button, variant: String) -> void:
	button.add_theme_font_size_override("font_size", 16)
	button.custom_minimum_size.y = max(button.custom_minimum_size.y, 48.0)
	button.add_theme_stylebox_override("normal", _create_button_style(variant, 0.95))
	button.add_theme_stylebox_override("hover", _create_button_style(variant, 1.08))
	button.add_theme_stylebox_override("pressed", _create_button_style(variant, 0.82))
	button.add_theme_stylebox_override("disabled", _create_button_style("disabled", 0.75))
	button.add_theme_color_override("font_color", Color("eff3fb"))
	button.add_theme_color_override("font_disabled_color", Color("7f8897"))


## 根据按钮类型生成具体的 StyleBox 外观。
func _create_button_style(variant: String, brightness: float) -> StyleBoxFlat:
	var base := Color("293241")
	match variant:
		"primary":
			base = Color("2e6ee6")
		"secondary":
			base = Color("253040")
		"soft":
			base = Color("222a36")
		"module":
			base = Color("202733")
		"disabled":
			base = Color("171c24")

	var style := StyleBoxFlat.new()
	style.bg_color = Color(base.r * brightness, base.g * brightness, base.b * brightness, 1.0)
	style.border_color = Color(base.r * min(brightness + 0.12, 1.2), base.g * min(brightness + 0.12, 1.2), base.b * min(brightness + 0.12, 1.2), 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	style.content_margin_left = 14
	style.content_margin_top = 12
	style.content_margin_right = 14
	style.content_margin_bottom = 12
	return style


## 根据格子状态刷新棋盘按钮的样式。
func _apply_board_cell_style(button: Button, background: Color, border: Color, font_color: Color) -> void:
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


## 创建鼠标跟随预览的小格子样式。
func _create_cursor_cell_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(background.r, background.g, background.b, 0.75)
	style.border_color = Color(border.r, border.g, border.b, 0.95)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	return style


## 把技能卡恢复成默认推荐构筑。
func _load_default_builds() -> void:
	# Default builds only affect the standalone skill cards.
	for state in card_states:
		state["placements"].clear()

	for build_data in default_builds:
		var card_id: String = build_data.get("card_id", "")
		if not card_index_by_id.has(card_id):
			continue
		var card_index: int = card_index_by_id[card_id]
		_try_place_module(
			card_index,
			build_data["module_id"],
			_pair_to_vector(build_data["anchor"]),
			int(build_data.get("rotation", 0)),
			false
		)


## 用户点击“恢复推荐构筑”时调用。
func _restore_defaults() -> void:
	selected_module_id = ""
	selected_rotation = 0
	preview_message = ""
	_load_default_builds()
	_refresh_ui("已恢复为数据文件中的推荐技能卡构筑。")


## 左侧主列表点击事件：技能卡页选卡，角色页选角色。
func _on_primary_item_pressed(index: int) -> void:
	# 左侧主列表在两个页面里共用：
	# 技能卡页选择技能卡，角色页选择角色。
	if current_view == "card":
		selected_card_index = index
		selected_module_id = ""
		selected_rotation = 0
		_refresh_ui("已切换到技能卡：%s。" % cards[card_order[index]]["name"])
	else:
		selected_character_index = index
		_refresh_ui("已切换到角色：%s。" % characters[index]["name"])


## 左侧模组列表点击事件，只记录当前选中的模组。
func _on_module_selected(module_id: String) -> void:
	selected_module_id = module_id
	selected_rotation = 0
	_refresh_ui("已选中模组：%s。" % modules[module_id]["name"])


## 角色页右侧技能卡列表点击事件，用于切换当前选中的技能卡。
func _on_card_option_selected(card_id: String) -> void:
	selected_card_index = card_index_by_id[card_id]
	_refresh_ui("已选中技能卡：%s。" % cards[card_id]["name"])


## 旋转当前选中的模组。
func _rotate_selected_module() -> void:
	if selected_module_id.is_empty():
		_refresh_ui("请先选择一个模组。")
		return
	selected_rotation = (selected_rotation + 1) % 4
	_refresh_ui("已将 %s 旋转到 %d°。" % [modules[selected_module_id]["name"], selected_rotation * 90])


## 棋盘格左键点击事件，尝试把当前模组放进技能卡。
func _on_board_cell_pressed(coord: Vector2i) -> void:
	if current_view != "card" or selected_module_id.is_empty():
		return
	var success := _try_place_module(selected_card_index, selected_module_id, coord, selected_rotation, true)
	if success and _get_available_module_count(selected_module_id) <= 0:
		selected_module_id = ""
		selected_rotation = 0
		_refresh_ui("")


## 棋盘格输入事件，当前主要处理右键移除模组。
func _on_board_cell_input(event: InputEvent, coord: Vector2i) -> void:
	if current_view != "card":
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var placement_index := _find_placement_covering(selected_card_index, coord)
		if placement_index == -1:
			_refresh_ui("这个格子上没有模组。")
			return
		var placement: Dictionary = card_states[selected_card_index]["placements"][placement_index]
		card_states[selected_card_index]["placements"].remove_at(placement_index)
		preview_message = ""
		_refresh_ui("已移除 %s。" % modules[placement["module_id"]]["name"])


## 清空当前技能卡上的所有模组。
func _clear_current_skill() -> void:
	if current_view != "card":
		return
	card_states[selected_card_index]["placements"].clear()
	selected_module_id = ""
	selected_rotation = 0
	preview_message = ""
	_refresh_ui("当前技能卡已清空。")


## 在角色页为当前角色装备或卸下当前选中的技能卡。
func _toggle_equip_selected_card() -> void:
	if current_view != "character":
		return
	var character: Dictionary = characters[selected_character_index]
	var state: Dictionary = character_states[selected_character_index]
	var card_id: String = card_order[selected_card_index]
	var card: Dictionary = cards[card_id]

	# 装备动作在执行时一定会再次校验职业兼容性，避免只靠界面层限制。
	if not _card_allowed_for_profession(card, character["profession"]):
		_refresh_ui("%s 无法使用技能卡 %s。" % [character["name"], card["name"]])
		return

	var equipped: Array = state["equipped_card_ids"]
	# 如果已经装备了这张卡，再点一次就执行卸下逻辑。
	if equipped.has(card_id):
		equipped.erase(card_id)
		_refresh_ui("已从 %s 身上卸下 %s。" % [character["name"], card["name"]])
		return

	# 如果技能槽满了，就不能继续装备。
	if equipped.size() >= int(character["allowed_card_slots"]):
		_refresh_ui("%s 的技能槽已满，请先卸下一张技能卡。" % character["name"])
		return

	equipped.append(card_id)
	_refresh_ui("已为 %s 装备技能卡 %s。" % [character["name"], card["name"]])


## 清空当前角色装备的所有技能卡。
func _unequip_all_cards() -> void:
	if current_view != "character":
		return
	character_states[selected_character_index]["equipped_card_ids"].clear()
	_refresh_ui("已清空当前角色的技能装备。")


## 模拟释放当前技能卡，当前版本只提供文本反馈。
func _simulate_release() -> void:
	var generated := _generate_skill_for_card(selected_card_index)
	if generated["occupied_cells"] == 0:
		preview_message = "[color=#f1c27d]当前技能卡还是空的，先装入一些模组吧。[/color]"
		_refresh_ui("")
		return

	var lines := PackedStringArray()
	lines.append("[b]模拟释放：%s[/b]" % generated["name"])
	lines.append("目标：%s" % generated["target"])
	lines.append("当前构筑强度已记录到右侧预览。")
	preview_message = "[color=#a6e3a1]%s[/color]" % "\n".join(lines)
	_refresh_ui("")


## 底部“下一项”按钮：技能卡页切下一张卡，角色页切下一名角色。
func _handle_next_button() -> void:
	if current_view == "card":
		selected_card_index = (selected_card_index + 1) % card_order.size()
		_refresh_ui("已切换到下一张技能卡。")
	else:
		selected_character_index = (selected_character_index + 1) % characters.size()
		_refresh_ui("已切换到下一名角色。")


## 进入 V1 战斗验证前，把当前构筑结果和角色装备状态交给战斗运行时单例。
func _go_to_battle_prepare() -> void:
	BattleRuntime.import_builder_state(
		cards,
		modules,
		characters,
		card_order,
		module_order,
		card_states,
		character_states
	)
	get_tree().change_scene_to_file("res://scenes/battle_prepare.tscn")


func _return_to_map() -> void:
	BattleRuntime.import_builder_state(
		cards,
		modules,
		characters,
		card_order,
		module_order,
		card_states,
		character_states
	)
	get_tree().change_scene_to_file("res://scenes/map_scene.tscn")


## 从战斗准备页返回时，恢复离开构筑页之前的模组和角色装备状态。
func _import_runtime_builder_state() -> void:
	cards = BattleRuntime.cards.duplicate(true)
	modules = BattleRuntime.modules.duplicate(true)
	characters = BattleRuntime.characters.duplicate(true)
	card_order = BattleRuntime.card_order.duplicate(true)
	module_order = BattleRuntime.module_order.duplicate(true)
	card_states = BattleRuntime.card_states.duplicate(true)
	character_states = BattleRuntime.character_states.duplicate(true)
	card_index_by_id.clear()
	character_index_by_id.clear()
	for index in card_order.size():
		card_index_by_id[card_order[index]] = index
	for index in characters.size():
		character_index_by_id[characters[index]["id"]] = index


## 真正执行模组放置，前提是已经通过合法性校验。
func _try_place_module(card_index: int, module_id: String, anchor: Vector2i, rotation: int, show_feedback: bool) -> bool:
	var validation := _validate_placement(card_index, module_id, anchor, rotation)
	if not validation["ok"]:
		if show_feedback:
			_refresh_ui(validation["message"])
		return false

	var placement := {
		"module_id": module_id,
		"anchor": anchor,
		"rotation": rotation,
		"cells": validation["cells"]
	}
	card_states[card_index]["placements"].append(placement)

	if show_feedback:
		_refresh_ui("已放置 %s。" % modules[module_id]["name"])
	return true


## 校验一个模组能否放进当前技能卡。
func _validate_placement(card_index: int, module_id: String, anchor: Vector2i, rotation: int) -> Dictionary:
	# 放置校验刻意写得比较严格，因为它既影响当前交互反馈，
	# 也会影响后续接入战斗时的数据正确性。
	var module: Dictionary = modules[module_id]
	if _get_available_module_count(module_id) <= 0:
		return {"ok": false, "message": "库存里已经没有可用的 %s 了。" % module["name"]}

	var state: Dictionary = card_states[card_index]
	var card: Dictionary = cards[state["card_id"]]
	if not _module_allowed_for_card(module, card):
		return {"ok": false, "message": "%s 不适合装入这张技能卡。" % module["name"]}
	if module.get("is_unique", false):
		for placement in state["placements"]:
			if modules[placement["module_id"]].get("is_unique", false):
				return {"ok": false, "message": "每张技能卡最多只能装 1 个独行模组。"}

	var rotated_cells: Array = _get_rotated_shape(module["shape"], module["size"], rotation)
	var occupied: Dictionary = _get_occupied_map(card_index)
	var active_map: Dictionary = _get_active_map(card)
	var absolute_cells: Array = []

	for cell in rotated_cells:
		var absolute: Vector2i = anchor + cell
		if absolute.x < 0 or absolute.y < 0 or absolute.x >= card["width"] or absolute.y >= card["height"]:
			return {"ok": false, "message": "模组超出了技能卡边界。"}
		if not active_map.has(_coord_key(absolute)):
			return {"ok": false, "message": "这个位置不是技能卡可用格子。"}
		if occupied.has(_coord_key(absolute)):
			return {"ok": false, "message": "模组不能和已放置内容重叠。"}
		absolute_cells.append(absolute)

	return {"ok": true, "cells": absolute_cells}


## 统一刷新入口，所有状态变化尽量都回到这里集中刷新界面。
func _refresh_ui(status_message: String) -> void:
	if not status_message.is_empty():
		status_label.text = status_message

	# 所有状态变化最终都回到统一刷新入口，方便保证页面切换和数据修改后的表现一致。
	_update_nav_buttons()
	_update_left_panel()
	_update_workspace()
	_update_preview()
	_update_cursor_preview()


## 更新顶部两个页面切换按钮的高亮状态。
func _update_nav_buttons() -> void:
	_style_button(card_view_button, "primary" if current_view == "card" else "secondary")
	_style_button(character_view_button, "primary" if current_view == "character" else "secondary")
	_style_button(top_battle_prepare_button, "primary")


## 更新左侧面板的标题、提示、列表和当前选择信息。
func _update_left_panel() -> void:
	_rebuild_primary_list()
	_rebuild_secondary_list()

	if current_view == "card":
		left_header_label.text = "技能卡与模组"
		left_hint_label.text = "先选技能卡，再选择模组进行装配。"
		secondary_section_label.text = "模组库存  可用总数 %d" % _get_total_available_modules()
		selection_label.text = "当前技能卡：%s\n当前模组：%s\n旋转：%d°" % [
			cards[card_order[selected_card_index]]["name"],
			"未选择" if selected_module_id.is_empty() else modules[selected_module_id]["name"],
			selected_rotation * 90
		]
	else:
		var character: Dictionary = characters[selected_character_index]
		left_header_label.text = "角色与技能装备"
		left_hint_label.text = "选择角色后，只能装备职业允许使用的技能卡。"
		secondary_section_label.text = "可装备技能卡"
		selection_label.text = "当前角色：%s\n职业：%s\n选中技能卡：%s" % [
			character["name"],
			character["profession_name"],
			cards[card_order[selected_card_index]]["name"]
		]


## 重新构建左侧主列表。
func _rebuild_primary_list() -> void:
	_clear_container(primary_list)
	primary_buttons.clear()

	# 技能卡页：主列表显示技能卡
	# 角色页：主列表显示角色
	if current_view == "card":
		# 为每张技能卡显示名称、职业限制、能量和当前已用格数。
		for index in card_order.size():
			var card_id: String = card_order[index]
			var card: Dictionary = cards[card_id]
			var generated: Dictionary = _generate_skill_for_card(index)
			var button := Button.new()
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.custom_minimum_size = Vector2(0, 84)
			_style_button(button, "primary" if index == selected_card_index else "soft")
			button.text = "%s%s [%s]\n职业限制：%s | 能量 %d | 已用 %d 格" % [
				"● " if index == selected_card_index else "",
				card["name"],
				_card_type_label(card),
				"/".join(card["allowed_professions"]),
				generated["energy_cost"],
				generated["occupied_cells"]
			]
			button.pressed.connect(_on_primary_item_pressed.bind(index))
			primary_list.add_child(button)
			primary_buttons.append(button)
	else:
		# 角色页主列表显示角色概况和已装备技能数量。
		for index in characters.size():
			var character: Dictionary = characters[index]
			var equipped: Array = character_states[index]["equipped_card_ids"]
			var button := Button.new()
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.custom_minimum_size = Vector2(0, 90)
			_style_button(button, "primary" if index == selected_character_index else "soft")
			button.text = "%s%s [%s]\n%s | 已装备 %d/%d 张技能卡" % [
				"● " if index == selected_character_index else "",
				character["name"],
				character["profession_name"],
				character["role"],
				equipped.size(),
				character["allowed_card_slots"]
			]
			button.pressed.connect(_on_primary_item_pressed.bind(index))
			primary_list.add_child(button)
			primary_buttons.append(button)


## 重新构建左侧次级列表。
func _rebuild_secondary_list() -> void:
	_clear_container(secondary_list)
	secondary_buttons.clear()

	# 技能卡页：次级列表显示模组库存
	# 角色页：次级列表显示按职业过滤后的可装备技能卡
	if current_view == "card":
		# 模组列表显示库存、形状和效果说明。
		for module_id in module_order:
			var module: Dictionary = modules[module_id]
			var owned: int = BattleRuntime.get_module_total_count(module_id)
			if owned <= 0:
				continue
			var available: int = _get_available_module_count(module_id)
			var compatible: bool = _module_allowed_for_card(module, cards[card_order[selected_card_index]])
			var button := Button.new()
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.custom_minimum_size = Vector2(0, 108)
			_style_button(button, "primary" if selected_module_id == module_id else "module")
			button.text = "%s%s x%d%s\nTag：%s\n可用于：%s\n%s | %s" % [
				"▶ " if selected_module_id == module_id else "",
				module["name"],
				available,
				"" if compatible else " | 不适配",
				_module_tag_text(module),
				_module_allowed_type_label(module),
				_shape_to_text(module["shape"], module["size"]),
				module["description"]
			]
			button.disabled = (available <= 0 and selected_module_id != module_id) or not compatible
			button.pressed.connect(_on_module_selected.bind(module_id))
			secondary_list.add_child(button)
			secondary_buttons[module_id] = button
	else:
		var character: Dictionary = characters[selected_character_index]
		var profession: String = character["profession"]
		var equipped_ids: Array = character_states[selected_character_index]["equipped_card_ids"]
		# 角色页里，次级列表展示的是技能卡候选项，而不是模组。
		for card_id in card_order:
			var card: Dictionary = cards[card_id]
			var generated: Dictionary = _generate_skill_for_card(card_index_by_id[card_id])
			var allowed := _card_allowed_for_profession(card, profession)
			var button := Button.new()
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.custom_minimum_size = Vector2(0, 90)
			_style_button(button, "primary" if card_order[selected_card_index] == card_id else "soft")
			button.text = "%s%s [%s]\n%s | %s | 能量 %d" % [
				"已装备 " if equipped_ids.has(card_id) else "",
				card["name"],
				_card_type_label(card),
				"允许" if allowed else "不可用",
				card["target_type"],
				generated["energy_cost"]
			]
			button.disabled = not allowed
			button.pressed.connect(_on_card_option_selected.bind(card_id))
			secondary_list.add_child(button)
			secondary_buttons[card_id] = button


## 根据当前页面决定中间工作区显示技能卡构筑还是角色装备。
func _update_workspace() -> void:
	var show_card := current_view == "card"
	card_workspace.visible = show_card
	character_workspace.visible = not show_card
	simulate_button.visible = false
	rotate_button.disabled = not show_card
	clear_button.disabled = not show_card
	defaults_button.disabled = not show_card
	equip_selected_button.disabled = show_card
	unequip_all_button.disabled = show_card
	return_map_button.visible = bool(BattleRuntime.exploration_state.get("is_exploration_active", false))
	next_button.text = "下一张技能卡" if show_card else "下一名角色"

	if show_card:
		workspace_title_label.text = "技能卡装配"
		_update_card_workspace()
	else:
		workspace_title_label.text = "角色装备"
		_update_character_workspace()


## 更新技能卡构筑页中间工作区。
func _update_card_workspace() -> void:
	var card_id: String = card_order[selected_card_index]
	var card: Dictionary = cards[card_id]
	board_title_label.text = "%s [%s] | 职业限制：%s" % [card["name"], _card_type_label(card), "/".join(card["allowed_professions"])]
	board_hint_label.text = "作用对象：%s\n%s\n操作：先选模组，再点击棋盘格子放置；右键移除；按 R 可顺时针旋转。" % [card["target_type"], _energy_rule_text(card["energy_curve"])]
	_update_board()


## 更新角色页中间工作区，包括属性、已装备技能和职业匹配提示。
func _update_character_workspace() -> void:
	# 角色页是构筑结果的最终承载页：
	# 角色属性、职业限制、已装备技能卡都会在这里统一展示。
	var character: Dictionary = characters[selected_character_index]
	var state: Dictionary = character_states[selected_character_index]
	var selected_card: Dictionary = cards[card_order[selected_card_index]]
	var can_equip := _card_allowed_for_profession(selected_card, character["profession"])
	var equipped_lines := PackedStringArray()
	if state["equipped_card_ids"].is_empty():
		equipped_lines.append("尚未装备技能卡。")
	else:
		# 已装备技能列表会显示每张卡的作用对象和能量消耗，方便后续接战斗。
		for card_id in state["equipped_card_ids"]:
			var generated: Dictionary = _generate_skill_for_card(card_index_by_id[card_id])
			equipped_lines.append("%s | %s | 能量 %d" % [
				cards[card_id]["name"],
				cards[card_id]["target_type"],
				generated["energy_cost"]
			])

	character_name_label.text = character["name"]
	character_profession_label.text = "%s | %s" % [character["profession_name"], character["role"]]
	character_stats_label.text = "[b]角色属性[/b]\n力量 %d\n生命 %d\n意志 %d\n速度 %d" % [
		character["stats"]["strength"],
		character["stats"]["hp"],
		character["stats"]["will"],
		character["stats"]["speed"]
	]
	equipped_cards_label.text = "[b]已装备技能[/b]\n%s" % "\n".join(equipped_lines)
	equip_hint_label.text = "当前选中技能卡：%s\n职业匹配：%s" % [
		selected_card["name"],
		"可装备" if can_equip else "该职业不可使用"
	]
	equip_selected_button.text = "卸下选中技能卡" if state["equipped_card_ids"].has(selected_card["id"]) else "装备选中技能卡"
	equip_selected_button.disabled = not can_equip


## 根据当前技能卡状态刷新棋盘显示。
func _update_board() -> void:
	var state: Dictionary = card_states[selected_card_index]
	var card: Dictionary = cards[state["card_id"]]
	var active_map: Dictionary = _get_active_map(card)
	var special_map: Dictionary = _get_special_map(card)
	var placement_map := {}

	# 先把“哪个格子被哪个模组占用”整理成查询表，后面逐格刷新时就能快速判断。
	for placement in state["placements"]:
		for cell in placement["cells"]:
			placement_map[_coord_key(cell)] = placement

	for row in BOARD_ROWS:
		for column in BOARD_COLUMNS:
			var coord := Vector2i(column, row)
			var key := _coord_key(coord)
			var button: Button = board_buttons[key]
			button.disabled = false

			# 先处理超出技能卡尺寸的格子。
			if column >= int(card["width"]) or row >= int(card["height"]):
				button.text = ""
				button.disabled = true
				_apply_board_cell_style(button, Color("14181f"), Color("14181f"), Color("697386"))
				continue

			# 再处理技能卡形状中原本就不可用的格子。
			if not active_map.has(key):
				button.text = ""
				button.disabled = true
				_apply_board_cell_style(button, Color("1a1f28"), Color("202734"), Color("697386"))
				continue

			# 最后区分：已被模组占用 / 特殊空格 / 普通空格。
			if placement_map.has(key):
				var placement: Dictionary = placement_map[key]
				var module: Dictionary = modules[placement["module_id"]]
				var module_color: Color = _module_color(module)
				_apply_board_cell_style(button, module_color, module_color.lightened(0.25), Color("f7f9fc"))
				button.text = module["short"]
				button.tooltip_text = "%s\nTag：%s\n%s" % [module["name"], _module_tag_text(module), module["description"]]
			else:
				button.text = "★" if special_map.has(key) else "·"
				if special_map.has(key):
					_apply_board_cell_style(button, Color("5e4f28"), Color("c09a45"), Color("ffe6ad"))
					button.tooltip_text = special_map[key]["label"]
				else:
					_apply_board_cell_style(button, Color("283241"), Color("37465a"), Color("91a0b5"))
					button.tooltip_text = "可放置格子"


## 更新右侧预览区，始终围绕当前选中的技能卡展示结果。
func _update_preview() -> void:
	# 右侧预览始终围绕“当前选中的技能卡”展开，这样两个页面看到的是同一份构筑结果。
	var card_id: String = card_order[selected_card_index]
	var card: Dictionary = cards[card_id]
	var generated: Dictionary = _generate_skill_for_card(selected_card_index)

	preview_title_label.text = "%s 预览" % card["name"]

	var lines := PackedStringArray()
	lines.append("[b]职业限制[/b]")
	lines.append("/".join(card["allowed_professions"]))
	lines.append("[b]技能类型[/b]")
	lines.append(_card_type_label(card))
	lines.append("")
	lines.append("[b]目标与消耗[/b]")
	lines.append("作用对象：%s" % card["target_type"])
	lines.append("当前能量：%d" % generated["energy_cost"])
	lines.append("占用格数：%d" % generated["occupied_cells"])
	lines.append(_energy_rule_text(card["energy_curve"]))
	lines.append("")
	lines.append("[b]技能效果[/b]")
	if generated["occupied_cells"] == 0:
		lines.append("尚未装入模组。")
	else:
		# 这里把生成后的技能结果按类型分项展示出来。
		var morale_damage_pct := 0.0
		var morale_damage_cost := 0
		for morale_damage in generated.get("morale_damage_modules", []):
			morale_damage_pct += float(morale_damage.get("damage_pct", 0.0))
			morale_damage_cost += int(morale_damage.get("cost", 0))
		var total_damage_pct: float = float(generated["damage_pct"]) + morale_damage_pct
		if total_damage_pct > 0.0:
			var damage_text := "伤害：%.0f%% 力量" % total_damage_pct
			if morale_damage_pct > 0.0:
				damage_text += "（含耗 %d 士气的 %.0f%%）" % [morale_damage_cost, morale_damage_pct]
			lines.append(damage_text)
		if generated["heal_pct"] > 0.0:
			lines.append("治疗：%.0f%% 意志" % generated["heal_pct"])
		var morale_shield_pct := 0.0
		var morale_shield_cost := 0
		for morale_shield in generated.get("morale_shield_modules", []):
			morale_shield_pct += float(morale_shield.get("shield_pct", 0.0))
			morale_shield_cost += int(morale_shield.get("cost", 0))
		var total_shield_pct: float = float(generated["shield_pct"]) + morale_shield_pct
		if total_shield_pct > 0.0:
			var shield_text := "护盾：%.0f%% 意志" % total_shield_pct
			if morale_shield_pct > 0.0:
				shield_text += "（含耗 %d 士气的 %.0f%%）" % [morale_shield_cost, morale_shield_pct]
			lines.append(shield_text)
		if generated["pierce_pct"] > 0.0:
			lines.append("穿透：%.0f%%" % generated["pierce_pct"])
		if generated["morale_gain"] > 0:
			lines.append("士气：+%d" % generated["morale_gain"])
		for status in generated.get("status_modules", []):
			var status_id := str(status.get("id", ""))
			if status_id == "burn" and status.has("scale_pct"):
				var flat_layers: int = int(status.get("flat", 0))
				var flat_text := ""
				if flat_layers > 0:
					flat_text = " + %d 层" % flat_layers
				lines.append("灼烧：%.0f%% %s%s" % [float(status.get("scale_pct", 0.0)), str(status.get("scale_stat", "strength")), flat_text])
			else:
				lines.append("%s：%d 层" % [_status_display_name(status_id), int(status.get("layers", 0))])
		if generated["speed_buff"] > 0:
			lines.append("加速：+%d 速度，持续 %d 回合" % [generated["speed_buff"], int(generated.get("speed_duration", generated["support_duration"]))])
		if generated["damage_reduction_pct"] > 0:
			lines.append("稳固：受到伤害 -%d%%，持续 %d 回合" % [generated["damage_reduction_pct"], int(generated.get("damage_reduction_duration", generated["support_duration"]))])
		if generated["anti_shield_bonus"]:
			lines.append("额外效果：命中护盾目标时再提高 20% 伤害")

	lines.append("")
	lines.append("[b]特殊格利用[/b]")
	if generated["triggered_specials"].is_empty():
		lines.append("当前没有触发特殊格。")
	else:
		for special_text in generated["triggered_specials"]:
			lines.append(special_text)

	lines.append("")
	lines.append("[b]模组摘要[/b]")
	if generated["module_summaries"].is_empty():
		lines.append("无")
	else:
		for summary in generated["module_summaries"]:
			lines.append(summary)

	if current_view == "character":
		var character: Dictionary = characters[selected_character_index]
		# 角色页会额外给出当前角色和当前技能卡之间的职业匹配结论。
		lines.append("")
		lines.append("[b]角色装备检查[/b]")
		lines.append("%s %s 使用这张技能卡。" % [
			character["name"],
			"可以" if _card_allowed_for_profession(card, character["profession"]) else "不可以"
		])

	preview_body_label.text = "\n".join(lines)
	simulation_label.text = preview_message


## 更新鼠标跟随的模组预览。
func _update_cursor_preview() -> void:
	for cell in cursor_preview_cells:
		cell.queue_free()
	cursor_preview_cells.clear()

	# 鼠标跟随预览只在技能卡构筑页有意义。
	if current_view != "card" or selected_module_id.is_empty():
		cursor_preview.visible = false
		return

	var module: Dictionary = modules[selected_module_id]
	var rotated_cells: Array = _get_rotated_shape(module["shape"], module["size"], selected_rotation)
	var bounds: Vector2i = _shape_bounds(rotated_cells)
	var cell_size: Vector2 = Vector2(30, 30)
	var spacing: float = 4.0
	var width: float = bounds.x * cell_size.x + max(bounds.x - 1, 0) * spacing
	var height: float = bounds.y * cell_size.y + max(bounds.y - 1, 0) * spacing

	cursor_preview.visible = true
	cursor_preview.position = get_local_mouse_position()
	cursor_preview.size = Vector2(width, height + 26.0)
	cursor_preview_label.text = "%s  %d°" % [module["name"], selected_rotation * 90]

	# 根据旋转后的形状，动态生成鼠标下的“幽灵模组格子”。
	for cell_pos in rotated_cells:
		var cell := PanelContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.custom_minimum_size = cell_size
		cell.size = cell_size
		cell.position = Vector2(cell_pos.x * (cell_size.x + spacing), 24.0 + cell_pos.y * (cell_size.y + spacing))
		var color: Color = _module_color(module)
		cell.add_theme_stylebox_override("panel", _create_cursor_cell_style(color, color.lightened(0.25)))
		cursor_preview.add_child(cell)
		cursor_preview_cells.append(cell)


## 计算一个形状的包围盒大小，用于确定鼠标预览区域尺寸。
func _shape_bounds(shape: Array) -> Vector2i:
	var max_x := 0
	var max_y := 0
	for cell in shape:
		max_x = max(max_x, cell.x)
		max_y = max(max_y, cell.y)
	return Vector2i(max_x + 1, max_y + 1)


## 根据当前技能卡上的模组摆放结果，生成最终技能数据。
func _generate_skill_for_card(card_index: int) -> Dictionary:
	# 这里是“拼图摆放结果”到“玩法数值语义”的桥梁。
	# UI 中展示的派生结果，以及未来战斗中要消费的技能数值，都应该从这里统一生成。
	var state: Dictionary = card_states[card_index]
	var card: Dictionary = cards[state["card_id"]]
	var result := {
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
		"triggered_specials": [],
		"module_summaries": []
	}

	var special_map: Dictionary = _get_special_map(card)

	# 逐个读取当前技能卡上的模组，并叠加它们的效果。
	for placement in state["placements"]:
		var module: Dictionary = modules[placement["module_id"]]
		var effects: Dictionary = module["effects"].duplicate(true)
		var module_specials: Array = []
		var module_duration_bonus := 0

		# 模组如果压在特殊格上，会在这里对效果做二次修正。
		for cell in placement["cells"]:
			var key := _coord_key(cell)
			if not special_map.has(key):
				continue
			var special: Dictionary = special_map[key]
			match special["type"]:
				"damage_boost":
					if effects.has("damage_pct"):
						effects["damage_pct"] *= 1.3
						module_specials.append("%s 触发：%s" % [module["name"], special["label"]])
				"heal_boost":
					if effects.has("heal_pct"):
						effects["heal_pct"] *= 1.25
						module_specials.append("%s 触发：%s" % [module["name"], special["label"]])
				"shield_boost":
					if effects.has("shield_pct"):
						effects["shield_pct"] *= 1.2
						module_specials.append("%s 触发：%s" % [module["name"], special["label"]])
					if effects.has("morale_shield"):
						var morale_shield: Dictionary = effects["morale_shield"]
						morale_shield["shield_pct"] = float(morale_shield.get("shield_pct", 0.0)) * 1.2
						module_specials.append("%s 触发：%s" % [module["name"], special["label"]])
				"support_duration":
					if effects.has("speed_buff") or effects.has("damage_reduction_pct"):
						module_duration_bonus += 1
						module_specials.append("%s 触发：%s" % [module["name"], special["label"]])
				"anti_shield":
					if effects.has("damage_pct"):
						result["anti_shield_bonus"] = true
						module_specials.append("%s 触发：%s" % [module["name"], special["label"]])

		# 把这个模组最终生效的结果累加到技能总结果上。
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
		result["module_summaries"].append("%s [%s] | %s：%s" % [module["name"], _module_tag_text(module), _shape_to_text(module["shape"], module["size"]), module["description"]])
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
				result["triggered_specials"].append("%s 读取相邻伤害模组，施加 %.0f%% 力量灼烧" % [module["name"], burn_pct])

	if result["speed_buff"] > 0 or result["damage_reduction_pct"] > 0:
		result["support_duration"] = max(int(result["speed_duration"]), int(result["damage_reduction_duration"]))

	result["energy_cost"] = _energy_cost_for(card["energy_curve"], result["occupied_cells"])
	return result


## 按技能卡能量曲线和占用格数计算当前技能消耗。
func _energy_cost_for(curve: String, occupied_cells: int) -> int:
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


## 把技能卡的能量曲线转换成玩家能直接阅读的规则说明。
## 当前 Demo 有两套规则：
## 1. single：单体类技能可以塞更多模组，1/2/3 能量分别对应 1-5 / 6-10 / 11-16 格。
## 2. range：范围类技能影响面更大，所以同样能量允许的模组格数更少。
func _energy_rule_text(curve: String) -> String:
	if curve == "range":
		return "能量规则：1 能量=1-3 格，2 能量=4-6 格，3 能量=7-9 格"
	return "能量规则：1 能量=1-5 格，2 能量=6-10 格，3 能量=11-16 格"


## 统计当前所有技能卡还能使用多少模组。
func _get_total_available_modules() -> int:
	var total := 0
	for module_id in module_order:
		total += max(_get_available_module_count(module_id), 0)
	return total


## 统计某一种模组当前还剩多少库存。
func _get_available_module_count(module_id: String) -> int:
	# 当前 Demo 里模组库存是全技能卡共享的，所以剩余数量要扫描所有技能卡状态来计算。
	var total: int = BattleRuntime.get_module_total_count(module_id)
	var used := 0
	for state in card_states:
		for placement in state["placements"]:
			if placement["module_id"] == module_id:
				used += 1
	return total - used


## 根据旋转角度返回模组旋转后的形状坐标。
func _get_rotated_shape(shape: Array, size: Vector2i, rotation: int) -> Array:
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


## 找到某个棋盘格覆盖的是第几个模组，用于右键删除。
func _find_placement_covering(card_index: int, coord: Vector2i) -> int:
	var placements: Array = card_states[card_index]["placements"]
	for index in placements.size():
		for cell in placements[index]["cells"]:
			if cell == coord:
				return index
	return -1


## 生成当前技能卡已占用格子的查询表，便于快速判断重叠。
func _get_occupied_map(card_index: int) -> Dictionary:
	var occupied := {}
	for placement in card_states[card_index]["placements"]:
		for cell in placement["cells"]:
			occupied[_coord_key(cell)] = true
	return occupied


## 把技能卡的可用格子转成查询表。
func _get_active_map(card: Dictionary) -> Dictionary:
	var active := {}
	for cell in card["active_cells"]:
		active[_coord_key(cell)] = true
	return active


## 把技能卡的特殊格转成查询表。
func _get_special_map(card: Dictionary) -> Dictionary:
	var special := {}
	for slot in card["special_slots"]:
		special[_coord_key(slot["pos"])] = slot
	return special


## 把模组形状转换成文本，显示在左侧列表里帮助识别。
func _shape_to_text(shape: Array, size: Vector2i) -> String:
	return BattleRuntime.module_shape_text(shape, size)


## 判断某张技能卡是否允许某个职业使用。
func _card_allowed_for_profession(card: Dictionary, profession: String) -> bool:
	return card["allowed_professions"].has(profession)


func _module_allowed_for_card(module: Dictionary, card: Dictionary) -> bool:
	var effects: Dictionary = module.get("effects", {})
	var is_enemy_card: bool = _card_type_id(card) == "damage"
	var is_offensive: bool = effects.has("damage_pct") or effects.has("pierce_pct") or effects.has("morale_damage") or effects.has("burning_strike_factor")
	if effects.has("status"):
		var status_id := str(effects["status"].get("id", ""))
		is_offensive = is_offensive or ["vulnerable", "weak", "burn", "cold", "freeze"].has(status_id)
	var is_support: bool = effects.has("heal_pct") or effects.has("shield_pct") or effects.has("speed_buff") or effects.has("damage_reduction_pct") or effects.has("morale_gain") or effects.has("morale_shield")
	if is_enemy_card and is_support and not is_offensive:
		return false
	if not is_enemy_card and is_offensive and not is_support:
		return false
	return true


func _card_type_id(card: Dictionary) -> String:
	if ["precise_strike", "sweep"].has(str(card.get("id", ""))):
		return "damage"
	return "support"


func _card_type_label(card: Dictionary) -> String:
	return "伤害类" if _card_type_id(card) == "damage" else "辅助类"


func _module_allowed_type_label(module: Dictionary) -> String:
	var effects: Dictionary = module.get("effects", {})
	var offensive: bool = effects.has("damage_pct") or effects.has("pierce_pct") or effects.has("morale_damage") or effects.has("burning_strike_factor")
	if effects.has("status"):
		var status_id: String = str(effects["status"].get("id", ""))
		offensive = offensive or ["vulnerable", "weak", "burn", "cold", "freeze"].has(status_id)
	var support: bool = effects.has("heal_pct") or effects.has("shield_pct") or effects.has("speed_buff") or effects.has("damage_reduction_pct") or effects.has("morale_gain") or effects.has("morale_shield")
	if offensive and support:
		return "伤害类 / 辅助类"
	if offensive:
		return "伤害类技能"
	if support:
		return "辅助类技能"
	return "任意技能"


func _module_tag_text(module: Dictionary) -> String:
	var tags: Array = module.get("tags", [])
	if tags.is_empty():
		return "未标注"
	var text_parts := PackedStringArray()
	for tag in tags:
		text_parts.append(str(tag))
	return " / ".join(text_parts)


func _module_color(module: Dictionary) -> Color:
	var category := str(module.get("category", ""))
	match category:
		"damage":
			return Color("a64747")
		"heal":
			return Color("478a5f")
		"shield":
			return Color("4d6fa8")
		"support":
			return Color("8b6b2a")
		"status":
			return Color("7865a8")
	return Color("6b7280")


func _status_display_name(status_id: String) -> String:
	match status_id:
		"vulnerable":
			return "易伤"
		"weak":
			return "虚弱"
		"burn":
			return "灼烧"
		"cold":
			return "寒冷"
		"freeze":
			return "冻结"
	return status_id


## 把坐标转成字符串键，便于 Dictionary 查询。
func _coord_key(coord: Vector2i) -> String:
	return "%d_%d" % [coord.x, coord.y]


func _placements_adjacent(a: Dictionary, b: Dictionary) -> bool:
	for acell in a.get("cells", []):
		for bcell in b.get("cells", []):
			var distance: int = abs(int(acell.x) - int(bcell.x)) + abs(int(acell.y) - int(bcell.y))
			if distance == 1:
				return true
	return false


## 把 JSON 中的一组坐标数组批量转成 Vector2i。
func _coords(source: Array) -> Array:
	var result := []
	for pair in source:
		result.append(_pair_to_vector(pair))
	return result


## 把单个坐标数组转成 Vector2i。
func _pair_to_vector(pair) -> Vector2i:
	return Vector2i(int(pair[0]), int(pair[1]))
