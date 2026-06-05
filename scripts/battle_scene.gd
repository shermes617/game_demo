extends Control

# 这个脚本承载当前 Demo 的“搜打撤战斗”核心。
# 设计目标不是做完整商业战斗系统，而是把文档中的关键闭环跑通：
# 准备阶段部署/撤退 -> 战斗阶段按速度行动 -> 胜利后搜刮/撤离/深入。
const ENERGY_MAX := 10
const START_MORALE := 80
const ROW_NAME_KEYS := ["BATTLE_ROW_TOP", "BATTLE_ROW_MIDDLE", "BATTLE_ROW_BOTTOM"]
const ENEMY_DATABASE := preload("res://scripts/database/enemy_database.gd")

# 战斗单位数据都用 Dictionary 保存，方便 Demo 阶段快速迭代字段。
# allies/enemies 内的单位会共享相同字段：hp、shield、row、col、field、dead 等。
var allies: Array = []
var enemies: Array = []
var turn_queue: Array = []
var current_actor: Dictionary = {}

# 队伍级资源：能量和士气。
# 能量用于部署角色和释放技能；士气影响我方速度，并用于失败判定。
var player_energy := 0
var morale := START_MORALE
var round_number := 0
var encounter_index := 1
var current_node_type := "normal"
var reward_choices: Array = []
var pending_summons: Array = []
var next_round_energy_bonus := 0

# phase 是当前战斗状态机的核心字段。
# 常用值：prepare / battle / player_action / target_enemy / target_ally / loot / choice / demo_end。
var phase := "battle"
var battle_log := PackedStringArray()
var action_buttons: Array = []

# 准备阶段部署、精准打击选敌方目标、守护祷言选我方目标都需要二段交互。
var selected_deploy_index := -1
var pending_target_actor: Dictionary = {}
var pending_target_skill: Dictionary = {}
var pending_move_actor: Dictionary = {}

# 鼠标悬停时显示的临时信息面板。
var info_popup: PanelContainer
var info_label: RichTextLabel

@onready var ally_list: VBoxContainer = %AllyList
@onready var enemy_list: VBoxContainer = %EnemyList
@onready var order_label: RichTextLabel = %OrderLabel
@onready var log_label: RichTextLabel = %LogLabel
@onready var next_action_button: Button = %NextActionButton
@onready var back_button: Button = %SandboxButton
@onready var actions_row: HBoxContainer = %NextActionButton.get_parent()


func _ready() -> void:
	# BattleRuntime 保存了从技能拼图页带来的角色、技能卡、模组和生成技能数据。
	BattleRuntime.ensure_ready()
	randomize()
	_style_scene()
	_apply_static_texts()
	next_action_button.pressed.connect(_advance_turn)
	_start_demo()


func _start_demo() -> void:
	current_node_type = str(BattleRuntime.exploration_state.get("current_node_type", "normal"))
	var current_step: int = int(BattleRuntime.exploration_state.get("current_step", 0))
	encounter_index = 4 if current_node_type == "boss" else 3 if current_node_type == "elite" and current_step >= 5 else 2 if current_node_type == "elite" else 1
	morale = BattleRuntime.saved_morale if bool(BattleRuntime.exploration_state.get("is_exploration_active", false)) else START_MORALE
	player_energy = 0
	_setup_allies_from_build()
	_start_encounter(encounter_index)


func _setup_allies_from_build() -> void:
	# 将构筑页的 4 名角色转换为战斗单位。
	# 注意：根据最新规则，进入战斗后我方半场是空的，所以 field 初始为 false。
	allies.clear()
	var default_positions: Dictionary = {}
	default_positions["ranger"] = Vector2i(0, 0)
	default_positions["priest"] = Vector2i(0, 1)
	default_positions["warrior"] = Vector2i(1, 1)
	default_positions["guardian"] = Vector2i(2, 1)
	for index in BattleRuntime.characters.size():
		var unit: Dictionary = BattleRuntime.build_character_runtime(index)
		var saved_dead := false
		var saved_injury_marks := 0
		if BattleRuntime.has_party_snapshot:
			for saved in BattleRuntime.get_party_snapshot():
				if str(saved.get("character_id", "")) == str(unit.get("character_id", "")):
					unit["hp"] = int(saved.get("hp", unit["hp"]))
					saved_injury_marks = int(saved.get("injury_marks", 0))
					saved_dead = bool(saved.get("dead", false))
		var pos: Vector2i = default_positions.get(unit["profession"], Vector2i(0, index % 3))
		unit["team"] = "ally"
		unit["col"] = pos.x
		unit["row"] = pos.y
		unit["field"] = false
		unit["retreated"] = false
		unit["deployed_this_turn"] = false
		unit["dead"] = saved_dead
		unit["injury_marks"] = saved_injury_marks
		unit["skill_cooldowns"] = {}
		allies.append(unit)


func _start_encounter(index: int) -> void:
	# 开始一场具体遭遇。第一场是普通盗匪，第二场是精英盗匪。
	# 每场战斗开始时敌方重新生成，我方角色回到待部署区。
	encounter_index = index
	round_number = 0
	player_energy = 0
	next_round_energy_bonus = 0
	current_actor = {}
	pending_summons.clear()
	enemies = _make_encounter_enemies(index)
	for enemy in enemies:
		if str(enemy.get("role", "")) == "guard":
			enemy["shield"] = int(enemy.get("shield", 0)) + 20
	for ally in allies:
		ally["shield"] = 0
		ally["retreated"] = false
		ally["field"] = false
		ally["deployed_this_turn"] = false
	_log(_format_text("BATTLE_LOG_ENTER_ENCOUNTER", {"index": encounter_index, "name": _encounter_name()}))
	_start_round()


func _make_encounter_enemies(index: int) -> Array:
	# 根据遭遇编号返回敌人列表。
	# col/row 使用敌方 3x3 半场坐标：敌方第 0 列是前排。
	if index == 3:
		return [
			_enemy("bandit_leader", 0, 0),
			_enemy("elite_guard", 0, 1),
			_enemy("oil_bomber", 2, 0),
			_enemy("shaman", 2, 2)
		]
	if index == 4:
		return [
			_enemy("elite_guard", 0, 1),
			_enemy("summoner", 2, 1),
			_enemy("bandit_healer", 2, 2)
		]
	if index == 2:
		return [
			_enemy("elite_archer", 2, 0),
			_enemy("elite_guard", 0, 1),
			_enemy("assassin", 1, 2),
			_enemy("captain", 0, 0)
		]
	return _make_normal_encounter_enemies()


func _make_normal_encounter_enemies() -> Array:
	var roles: Array = ["bruiser", "guard", "archer", "healer", "bomber", "demoralizer"]
	roles.shuffle()
	var selected_roles: Array = roles.slice(0, 4)
	var positions_by_role: Dictionary = _choose_enemy_positions(selected_roles)
	var result: Array = []
	for index in selected_roles.size():
		var role: String = str(selected_roles[index])
		var pos: Vector2i = positions_by_role[role]
		result.append(_normal_enemy(role, pos))
	return result


func _choose_enemy_positions(roles: Array) -> Dictionary:
	# 敌方普通遭遇的站位规则。
	# 过去这里会随机打乱位置，容易出现“盾卫缩在后排、弩手站到前排”的怪情况。
	# 现在先保留敌人类型的随机性，再按职责分配站位：
	# - 盾卫/打手优先前排；
	# - 弩手/药师/火油投手优先后排；
	# - 如果有盾卫，就尽量放到最高威胁后排单位所在行的前排，形成保护关系。
	var positions: Dictionary = {}
	var occupied: Dictionary = {}
	var protected_role: String = _highest_threat_role(roles)
	var guard_row: int = 1
	if not protected_role.is_empty():
		guard_row = _preferred_enemy_row(protected_role)

	if roles.has("guard"):
		_reserve_enemy_position(positions, occupied, "guard", [
			Vector2i(0, guard_row),
			Vector2i(0, 1),
			Vector2i(0, 0),
			Vector2i(0, 2)
		])

	for role_value in roles:
		var role: String = str(role_value)
		if role == "guard":
			continue
		_reserve_enemy_position(positions, occupied, role, _enemy_position_candidates(role, protected_role, guard_row))
	_ensure_frontline_count(positions, occupied, roles, 2)
	return positions


func _highest_threat_role(roles: Array) -> String:
	# 后排保护优先级：群攻和高输出最高，其次治疗/士气压制，最后才是普通近战。
	var threat_order: Array = ["bomber", "archer", "shaman", "healer", "captain", "demoralizer", "assassin", "bruiser"]
	for threat_value in threat_order:
		var role: String = str(threat_value)
		if roles.has(role):
			return role
	return ""


func _enemy_position_candidates(role: String, protected_role: String, guard_row: int) -> Array:
	# 给每种敌人生成一串“从最理想到可接受”的候选格。
	# 敌方第 0 列是前排，第 2 列是后排；同一行前排单位能挡住玩家按行普攻。
	var row: int = _preferred_enemy_row(role)
	if role == protected_role:
		row = guard_row
	match role:
		"guard":
			return [Vector2i(0, row), Vector2i(0, 1), Vector2i(0, 0), Vector2i(0, 2)]
		"bruiser", "assassin":
			return [
				Vector2i(0, row),
				Vector2i(0, 1),
				Vector2i(0, 0),
				Vector2i(0, 2),
				Vector2i(1, row),
				Vector2i(1, 1)
			]
		"archer", "healer", "bomber", "demoralizer", "captain", "shaman":
			return [
				Vector2i(2, row),
				Vector2i(2, 1),
				Vector2i(2, 0),
				Vector2i(2, 2),
				Vector2i(1, row),
				Vector2i(1, 1),
				Vector2i(1, 0),
				Vector2i(1, 2)
			]
	return [Vector2i(1, row), Vector2i(0, row), Vector2i(2, row)]


func _preferred_enemy_row(role: String) -> int:
	# 固定一个“偏好行”可以让保护关系更稳定，也能减少敌人挤在同一个角落。
	match role:
		"bomber":
			return 0
		"archer", "guard", "bruiser", "captain", "demoralizer":
			return 1
		"healer", "shaman", "assassin":
			return 2
	return 1


func _reserve_enemy_position(positions: Dictionary, occupied: Dictionary, role: String, candidates: Array) -> void:
	# 按候选顺序占位；如果理想位置都被占用，再扫描整个 3x3 找空格，避免生成失败。
	for candidate_value in candidates:
		var candidate: Vector2i = candidate_value
		var key: String = _enemy_grid_key(candidate)
		if not occupied.has(key):
			positions[role] = candidate
			occupied[key] = true
			return

	for col in range(3):
		for row in range(3):
			var fallback := Vector2i(col, row)
			var fallback_key: String = _enemy_grid_key(fallback)
			if not occupied.has(fallback_key):
				positions[role] = fallback
				occupied[fallback_key] = true
				return


func _ensure_frontline_count(positions: Dictionary, occupied: Dictionary, roles: Array, minimum_count: int) -> void:
	var frontline_count: int = 0
	for role_value in roles:
		var role: String = str(role_value)
		var pos: Vector2i = positions.get(role, Vector2i(2, 1))
		if pos.x == 0:
			frontline_count += 1
	if frontline_count >= minimum_count:
		return

	var empty_front_rows: Array = []
	for row in range(3):
		var front_pos := Vector2i(0, row)
		if not occupied.has(_enemy_grid_key(front_pos)):
			empty_front_rows.append(row)

	var movable_roles: Array = roles.duplicate()
	movable_roles.sort_custom(_compare_role_frontline_priority)
	for role_value in movable_roles:
		if frontline_count >= minimum_count or empty_front_rows.is_empty():
			return
		var role: String = str(role_value)
		var current_pos: Vector2i = positions.get(role, Vector2i(2, 1))
		if current_pos.x == 0:
			continue
		var target_row: int = _take_frontline_row(empty_front_rows, _preferred_enemy_row(role))
		var target_pos := Vector2i(0, target_row)
		occupied.erase(_enemy_grid_key(current_pos))
		positions[role] = target_pos
		occupied[_enemy_grid_key(target_pos)] = true
		frontline_count += 1


func _compare_role_frontline_priority(a: String, b: String) -> bool:
	var hp_a: int = _normal_enemy_max_hp(a)
	var hp_b: int = _normal_enemy_max_hp(b)
	if hp_a != hp_b:
		return hp_a > hp_b
	return _preferred_enemy_row(a) < _preferred_enemy_row(b)


func _take_frontline_row(rows: Array, preferred_row: int) -> int:
	var best_index := 0
	var best_distance: int = 99
	for index in rows.size():
		var row: int = int(rows[index])
		var distance: int = abs(row - preferred_row)
		if distance < best_distance:
			best_index = index
			best_distance = distance
	var selected_row: int = int(rows[best_index])
	rows.remove_at(best_index)
	return selected_row


func _enemy_grid_key(pos: Vector2i) -> String:
	# 把敌方半场坐标转成字典 key，用来判断某个格子是否已经被站位占用。
	return "%d,%d" % [pos.x, pos.y]


func _normal_enemy(role: String, pos: Vector2i) -> Dictionary:
	return _enemy(_normal_enemy_id_for_role(role), pos.x, pos.y)


func _normal_enemy_max_hp(role: String) -> int:
	var enemy_data: EnemyData = ENEMY_DATABASE.get_enemy(_normal_enemy_id_for_role(role))
	return enemy_data.max_hp if enemy_data != null else 0


func _normal_enemy_id_for_role(role: String) -> String:
	match role:
		"guard":
			return "bandit_guard"
		"archer":
			return "bandit_archer"
		"healer":
			return "bandit_healer"
		"bomber":
			return "oil_bomber"
		"demoralizer":
			return "demoralizer"
	return "bandit_bruiser"


func _elite_enemy_id_for_role(role: String) -> String:
	match role:
		"captain":
			return "captain"
		"guard":
			return "elite_guard"
		"archer":
			return "elite_archer"
		"assassin":
			return "assassin"
		"leader":
			return "bandit_leader"
		"shaman":
			return "shaman"
	return "elite_guard"


func _encounter_name() -> String:
	match current_node_type:
		"elite":
			return _text("ENCOUNTER_ELITE_BANDITS_NAME")
		"boss":
			return _text("ENCOUNTER_SUMMONER_NAME")
		"summoner":
			return _text("ENCOUNTER_SUMMONER_NAME")
	return _text("ENCOUNTER_RUIN_BANDITS_NAME")


func _enemy(enemy_id: String, col: int, row: int) -> Dictionary:
	# 创建敌方单位数据。role 会被 AI 用来决定行动倾向。
	var enemy_data: EnemyData = ENEMY_DATABASE.get_enemy(enemy_id)
	if enemy_data == null:
		push_error("Unknown enemy id: %s" % enemy_id)
		enemy_data = ENEMY_DATABASE.get_enemy("bandit_bruiser")
	return enemy_data.to_runtime_dict(
		col,
		row,
		_text(enemy_data.name_key),
		_enemy_attack_desc(enemy_data.role),
		_enemy_trait_desc(enemy_data.role)
	)


func _enemy_attack_desc(role: String) -> String:
	match role:
		"bruiser":
			return _text("BATTLE_ATTACK_BRUISER")
		"guard":
			return _text("BATTLE_ATTACK_GUARD")
		"archer":
			return _text("BATTLE_ATTACK_ARCHER")
		"healer":
			return _text("BATTLE_ATTACK_HEALER")
		"bomber":
			return _text("BATTLE_ATTACK_BOMBER")
		"demoralizer":
			return _text("BATTLE_ATTACK_DEMORALIZER")
		"assassin":
			return _text("BATTLE_ATTACK_ASSASSIN")
		"captain":
			return _text("BATTLE_ATTACK_CAPTAIN")
		"shaman":
			return _text("BATTLE_ATTACK_SHAMAN")
		"leader":
			return _text("BATTLE_ATTACK_LEADER")
		"summoner":
			return _text("BATTLE_ATTACK_SUMMONER")
	return _text("BATTLE_ATTACK_DEFAULT")


func _enemy_trait_desc(role: String) -> String:
	match role:
		"guard":
			return _text("BATTLE_TRAIT_GUARD")
		"bomber":
			return _text("BATTLE_TRAIT_BOMBER")
		"demoralizer":
			return _text("BATTLE_TRAIT_DEMORALIZER")
		"assassin":
			return _text("BATTLE_TRAIT_ASSASSIN")
		"captain":
			return _text("BATTLE_TRAIT_CAPTAIN")
		"shaman":
			return _text("BATTLE_TRAIT_SHAMAN")
		"leader":
			return _text("BATTLE_TRAIT_LEADER")
		"summoner":
			return _text("BATTLE_TRAIT_SUMMONER")
	return _text("BATTLE_TRAIT_DEFAULT")


func _start_round() -> void:
	# 每回合一定先进入准备阶段。
	# 第一回合给 6 能量，后续回合给 3 能量；准备阶段可以部署/撤退。
	_clear_action_buttons()
	selected_deploy_index = -1
	pending_target_actor = {}
	pending_target_skill = {}
	pending_move_actor = {}
	_log(_format_text("BATTLE_LOG_ROUND_START", {"round": round_number + 1}))
	round_number += 1
	_process_pending_summons_at_prepare_start()
	if _check_battle_end():
		return
	var energy_gain: int = (6 if round_number == 1 else 3) + next_round_energy_bonus
	if next_round_energy_bonus > 0:
		_log(_format_text("BATTLE_LOG_RELIC_NEXT_ENERGY", {"energy": next_round_energy_bonus}))
	next_round_energy_bonus = 0
	player_energy = min(player_energy + energy_gain, ENERGY_MAX)
	for ally in allies:
		ally["deployed_this_turn"] = false
	phase = "prepare"
	_show_prepare_actions()
	_refresh()


func _show_prepare_actions() -> void:
	# 准备阶段 UI：
	# 1. 待部署区角色会生成“选择部署”按钮；
	# 2. 已上场角色会生成“撤退”按钮；
	# 3. 即使场上没有我方角色，也允许开始战斗阶段。
	_clear_action_buttons()
	next_action_button.text = _text("BATTLE_ACTION_START_PHASE")
	next_action_button.disabled = false
	_add_reload_battle_button()
	var deployable_count := 0
	for index in allies.size():
		var ally: Dictionary = allies[index]
		if _can_deploy(ally):
			deployable_count += 1
			var deploy_button := _add_action_button(_format_text("BATTLE_ACTION_DEPLOY", {"name": ally["name"]}))
			deploy_button.disabled = player_energy < 2
			deploy_button.pressed.connect(_select_deploy_ally.bind(index))
	for ally in _living_field(allies):
		var retreat_button := _add_action_button(_format_text("BATTLE_ACTION_RETREAT", {"name": ally["name"]}))
		retreat_button.pressed.connect(_prepare_retreat.bind(ally))
	if deployable_count == 0 and _living_field(allies).is_empty():
		_log(_text("BATTLE_LOG_NO_DEPLOYABLE"))


func _rebuild_turn_queue() -> void:
	# 战斗阶段开始时，根据当前速度生成行动队列。
	# 当前速度会受到士气和 Buff 影响。
	turn_queue.clear()
	for unit in allies + enemies:
		if _is_active(unit):
			turn_queue.append(unit)
	turn_queue.sort_custom(_compare_turn_order)


func _compare_turn_order(a: Dictionary, b: Dictionary) -> bool:
	var speed_a: int = _effective_speed(a)
	var speed_b: int = _effective_speed(b)
	if speed_a != speed_b:
		return speed_a > speed_b
	var team_a: String = str(a.get("team", ""))
	var team_b: String = str(b.get("team", ""))
	if team_a != team_b:
		return team_a == "ally"
	if int(a.get("row", 0)) != int(b.get("row", 0)):
		return int(a.get("row", 0)) < int(b.get("row", 0))
	return int(a.get("col", 0)) < int(b.get("col", 0))


func _advance_turn() -> void:
	# 主推进按钮的入口。不同 phase 下含义不同：
	# prepare：开始战斗阶段；battle：推进到下一个单位行动；demo_end：重开 Demo。
	if phase == "demo_end":
		BattleRuntime.start_exploration()
		get_tree().change_scene_to_file("res://scenes/skill_build_scene.tscn")
		return
	if phase == "choice":
		return
	if phase == "battle_end":
		_start_demo()
		return
	if phase == "prepare":
		selected_deploy_index = -1
		_rebuild_turn_queue()
		phase = "battle"
		_clear_action_buttons()
		_add_reload_battle_button()
		_log(_text("BATTLE_LOG_ENTER_BATTLE_PHASE"))
		_refresh()
		return
	if phase == "target_enemy" or phase == "target_ally" or phase == "move_target":
		_log(_text("BATTLE_LOG_SELECT_HIGHLIGHTED_TARGET"))
		_refresh()
		return
	if phase == "player_action":
		_log(_format_text("BATTLE_LOG_SELECT_ACTION_FIRST", {"name": current_actor["name"]}))
		_refresh()
		return
	if _check_battle_end():
		return
	if turn_queue.is_empty():
		_end_round()
		return

	var actor: Dictionary = turn_queue.pop_front()
	if not _is_active(actor):
		_advance_turn()
		return
	current_actor = actor
	if _try_consume_freeze(actor):
		_refresh()
		return
	if actor["team"] == "ally":
		phase = "player_action"
		_log(_format_text("BATTLE_LOG_PLAYER_TURN", {"name": actor["name"]}))
		_show_player_actions(actor)
	else:
		_run_enemy_action(actor)
		_check_battle_end()
	_refresh()


func _show_player_actions(actor: Dictionary) -> void:
	# 玩家角色行动菜单。
	# 普攻按“行”选择；精准打击进入选目标模式；横扫会直接打敌方第一列。
	_clear_action_buttons()
	_add_reload_battle_button()
	for row in range(3):
		var button := _add_action_button(_format_text("BATTLE_ACTION_BASIC_ATTACK", {"row": _row_name(row)}))
		button.disabled = _front_enemy_in_row(row).is_empty()
		button.pressed.connect(_player_basic_attack.bind(actor, row))

	var defend_button := _add_action_button(_text("BATTLE_ACTION_DEFEND"))
	defend_button.pressed.connect(_player_defend.bind(actor))

	var move_button := _add_action_button(_text("BATTLE_ACTION_MOVE"))
	move_button.pressed.connect(_begin_move_action.bind(actor))

	for skill in actor["equipped_skills"]:
		if int(skill["occupied_cells"]) <= 0:
			continue
		# 伤害技能和支援技能的交互不完全一样：
		# 精准打击需要玩家点选敌方单位；横扫直接打敌方第一列。
		if _skill_is_offensive(skill):
			var skill_button := _add_action_button(skill["name"])
			skill_button.disabled = _skill_cost(skill) > player_energy or _skill_cd(actor, skill) > 0
			_bind_skill_hover(skill_button, actor, skill)
			if skill["card_id"] == "precise_strike":
				skill_button.disabled = skill_button.disabled or _living_field(enemies).is_empty()
				skill_button.pressed.connect(_begin_enemy_target_skill.bind(actor, skill))
			else:
				skill_button.disabled = skill_button.disabled or (skill["card_id"] == "sweep" and _enemy_front_column_targets().is_empty())
				skill_button.pressed.connect(_player_use_skill.bind(actor, skill, -1))
		else:
			# 守护祷言是“点选我方中心目标 + 相邻扩散”的支援技能。
			# 其他支援技能目前直接按自身/相邻规则结算。
			var skill_button := _add_action_button(skill["name"])
			skill_button.disabled = _skill_cost(skill) > player_energy or _skill_cd(actor, skill) > 0
			_bind_skill_hover(skill_button, actor, skill)
			if skill["card_id"] == "guardian_prayer":
				skill_button.disabled = skill_button.disabled or _living_field(allies).is_empty()
				skill_button.pressed.connect(_begin_ally_target_skill.bind(actor, skill))
			else:
				skill_button.pressed.connect(_player_use_skill.bind(actor, skill, actor["row"]))

	next_action_button.text = _text("BATTLE_ACTION_WAIT_SELECTION")
	next_action_button.disabled = true


func _select_deploy_ally(index: int) -> void:
	# 准备阶段第一步：选择待部署区中的角色。
	# 选择后，我方 3x3 空格会高亮，等待玩家点击部署位置。
	selected_deploy_index = index
	_log(_format_text("BATTLE_LOG_DEPLOY_SELECTED", {"name": allies[index]["name"]}))
	_refresh()


func _deploy_selected_ally(col: int, row: int) -> void:
	# 准备阶段第二步：把已选择角色放到我方 3x3 的空格上。
	# 部署消耗 2 能量；同一回合撤退后的角色不能马上重新部署。
	if phase != "prepare" or selected_deploy_index < 0:
		return
	if player_energy < 2:
		_log(_text("BATTLE_LOG_DEPLOY_NOT_ENOUGH_ENERGY"))
		return
	if not _unit_at(allies, col, row).is_empty():
		return
	var ally: Dictionary = allies[selected_deploy_index]
	if not _can_deploy(ally):
		return
	ally["col"] = col
	ally["row"] = row
	ally["field"] = true
	ally["deployed_this_turn"] = true
	ally["retreated"] = false
	player_energy -= 2
	_log(_format_text("BATTLE_LOG_DEPLOY_DONE", {"name": ally["name"], "row": _row_name(row), "col": col + 1}))
	selected_deploy_index = -1
	_show_prepare_actions()
	_refresh()


func _prepare_retreat(actor: Dictionary) -> void:
	# 撤退只允许在准备阶段执行。
	# 撤退后角色回到待部署区，返还 1 能量，并标记本回合不能重新部署。
	actor["field"] = false
	actor["retreated"] = true
	actor["deployed_this_turn"] = true
	_clear_unit_statuses(actor)
	player_energy = min(player_energy + 1, ENERGY_MAX)
	_log(_format_text("BATTLE_LOG_RETREAT_DONE", {"name": actor["name"]}))
	_show_prepare_actions()
	_refresh()


func _begin_enemy_target_skill(actor: Dictionary, skill: Dictionary) -> void:
	# 精准打击使用二段式目标选择：
	# 先点击技能按钮进入 target_enemy，再点击一个高亮敌方单位结算。
	pending_target_actor = actor
	pending_target_skill = skill
	phase = "target_enemy"
	_clear_action_buttons()
	_add_reload_battle_button()
	next_action_button.text = _text("BATTLE_ACTION_TARGET_ENEMY")
	next_action_button.disabled = true
	_log(_format_text("BATTLE_LOG_BEGIN_ENEMY_TARGET", {"actor": actor["name"], "skill": skill["name"]}))
	_refresh()


func _begin_ally_target_skill(actor: Dictionary, skill: Dictionary) -> void:
	# 守护祷言使用二段式目标选择：
	# 先点击技能按钮进入 target_ally，再点击一个高亮我方单位作为中心目标。
	# pending_target_actor / pending_target_skill 用来暂存“谁在施法、施放哪个技能”。
	# 玩家真正点中我方格子后，_use_pending_skill_on_ally 会继续完成结算。
	pending_target_actor = actor
	pending_target_skill = skill
	phase = "target_ally"
	_clear_action_buttons()
	_add_reload_battle_button()
	next_action_button.text = _text("BATTLE_ACTION_TARGET_ALLY")
	next_action_button.disabled = true
	_log(_format_text("BATTLE_LOG_BEGIN_ALLY_TARGET", {"actor": actor["name"], "skill": skill["name"]}))
	_refresh()


func _use_pending_skill_on_enemy(target: Dictionary) -> void:
	# 精准打击的第二步：玩家点击敌方单位后，使用挂起的技能打这个目标。
	if phase != "target_enemy" or pending_target_actor.is_empty() or pending_target_skill.is_empty():
		return
	_player_use_skill_on_targets(pending_target_actor, pending_target_skill, [target])


func _use_pending_skill_on_ally(target: Dictionary) -> void:
	# 守护祷言的第二步：玩家点击我方单位后，目标和上下左右相邻单位一起获得效果。
	# 这里把被点击的单位作为 selected_targets 传入，后续由 _apply_support_skill 扩展出相邻目标。
	if phase != "target_ally" or pending_target_actor.is_empty() or pending_target_skill.is_empty():
		return
	_player_use_skill_on_targets(pending_target_actor, pending_target_skill, [target])


func _player_basic_attack(actor: Dictionary, row: int) -> void:
	# 我方普攻：玩家选择敌方某一行，攻击该行最左侧单位。
	var target := _front_enemy_in_row(row)
	if target.is_empty():
		return
	var damage_result: Dictionary = _apply_damage(target, int(actor["strength"]), 0.0, actor)
	_log(_format_text("BATTLE_LOG_BASIC_ATTACK", {
		"actor": actor["name"],
		"row": _row_name(row),
		"target": target["name"],
		"damage": int(damage_result["final_damage"])
	}))
	_finish_player_action()


func _player_defend(actor: Dictionary) -> void:
	_add_status(actor, "defend", "BATTLE_STATUS_DEFEND", "next_damage_reduction", 30, -1)
	_log(_format_text("BATTLE_LOG_DEFEND", {"name": actor["name"]}))
	_finish_player_action()


func _begin_move_action(actor: Dictionary) -> void:
	pending_move_actor = actor
	phase = "move_target"
	_clear_action_buttons()
	_add_reload_battle_button()
	next_action_button.text = _text("BATTLE_ACTION_TARGET_MOVE")
	next_action_button.disabled = true
	_log(_format_text("BATTLE_LOG_BEGIN_MOVE", {"name": actor["name"]}))
	_refresh()


func _move_actor_to_cell(col: int, row: int) -> void:
	if phase != "move_target" or pending_move_actor.is_empty() or not _is_active(pending_move_actor):
		return
	if not _is_adjacent_cell(pending_move_actor, col, row):
		return
	var occupant: Dictionary = _unit_at(allies, col, row)
	var old_col: int = int(pending_move_actor["col"])
	var old_row: int = int(pending_move_actor["row"])
	if occupant.is_empty():
		pending_move_actor["col"] = col
		pending_move_actor["row"] = row
		_log(_format_text("BATTLE_LOG_MOVE_DONE", {"name": pending_move_actor["name"], "row": _row_name(row), "col": col + 1}))
	else:
		occupant["col"] = old_col
		occupant["row"] = old_row
		pending_move_actor["col"] = col
		pending_move_actor["row"] = row
		_log(_format_text("BATTLE_LOG_SWAP_DONE", {"actor": pending_move_actor["name"], "target": occupant["name"]}))
	pending_move_actor = {}
	_finish_player_action()


func _player_use_skill(actor: Dictionary, skill: Dictionary, row: int) -> void:
	# 技能入口：根据技能卡 id 决定目标规则。
	# 横扫不再按行选择，而是直接攻击敌方第一列所有存活单位。
	var targets: Array = []
	if skill["card_id"] == "sweep":
		targets = _enemy_front_column_targets()
	else:
		targets = _skill_damage_targets(skill, row)
	_player_use_skill_on_targets(actor, skill, targets)


func _skill_is_offensive(skill: Dictionary) -> bool:
	if float(skill.get("damage_pct", 0.0)) > 0.0 or not skill.get("morale_damage_modules", []).is_empty():
		return true
	for status in skill.get("status_modules", []):
		if ["vulnerable", "weak", "burn", "cold", "freeze"].has(str(status.get("id", ""))):
			return true
	return false


func _player_use_skill_on_targets(actor: Dictionary, skill: Dictionary, targets: Array) -> void:
	# 真正的技能结算函数。所有技能最终都会走到这里。
	# 先扣能量和设置 CD，再分别结算伤害、治疗、护盾、Buff、士气。
	# 对于精准打击，targets 是玩家点击的单个敌人。
	# 对于守护祷言，targets 是玩家点击的中心友方，实际扩散在 _apply_support_skill 中完成。
	var cost := _skill_cost(skill)
	if player_energy < cost:
		_log(_format_text("BATTLE_LOG_SKILL_NOT_ENOUGH_ENERGY", {"skill": skill["name"], "cost": cost}))
		_refresh()
		return
	player_energy -= cost
	actor["skill_cooldowns"][skill["card_id"]] = 1
	var lines := PackedStringArray()
	lines.append(_format_text("BATTLE_LOG_SKILL_USE", {"actor": actor["name"], "skill": skill["name"], "cost": cost}))

	var total_damage_pct: float = float(skill["damage_pct"])
	for morale_damage in skill.get("morale_damage_modules", []):
		var morale_cost := int(morale_damage.get("cost", 0))
		if morale < morale_cost:
			lines.append(_text("BATTLE_LOG_MORALE_STRIKE_SKIPPED"))
			continue
		_change_morale(-morale_cost, _text("BATTLE_REASON_MORALE_STRIKE"))
		total_damage_pct += float(morale_damage.get("damage_pct", 0.0))
	if total_damage_pct > 0.0:
		for target in targets:
			var damage := int(round(float(actor["strength"]) * total_damage_pct / 100.0))
			if bool(skill["anti_shield_bonus"]) and int(target["shield"]) > 0:
				damage = int(round(float(damage) * 1.2))
			var damage_result: Dictionary = _apply_damage(target, damage, float(skill["pierce_pct"]), actor)
			lines.append(_format_text("BATTLE_LOG_HIT_DAMAGE", {"target": target["name"], "damage": int(damage_result["final_damage"])}))

	if float(skill["heal_pct"]) > 0.0 or float(skill["shield_pct"]) > 0.0 or int(skill["speed_buff"]) > 0 or int(skill["damage_reduction_pct"]) > 0 or not skill.get("morale_shield_modules", []).is_empty():
		for line in _apply_support_skill(actor, skill, targets):
			lines.append(line)

	for status in skill.get("status_modules", []):
		for target in targets:
			var layers := _status_layers_from_skill(actor, status)
			_add_layered_status(target, str(status.get("id", "")), layers)
			lines.append(_format_text("BATTLE_LOG_STATUS_GAIN", {
				"target": target["name"],
				"layers": layers,
				"status": _status_display_name(str(status.get("id", "")))
			}))

	if int(skill["morale_gain"]) > 0:
		_change_morale(int(skill["morale_gain"]), _text("BATTLE_REASON_MORALE_GAIN_MODULE"))
		lines.append(_format_text("BATTLE_LOG_MORALE_GAIN", {"value": int(skill["morale_gain"])}))

	for line in lines:
		_log(line)
	pending_target_actor = {}
	pending_target_skill = {}
	_finish_player_action()


func _skill_damage_targets(skill: Dictionary, row: int) -> Array:
	# 普通伤害技能的默认目标逻辑：取目标行最前方单位。
	# 精准打击现在会绕过这里，直接传入玩家点选的目标。
	var row_targets := _living_in_row(enemies, row)
	if row < 0:
		row_targets = _living_field(enemies)
	row_targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["col"]) == int(b["col"]):
			return int(a["row"]) < int(b["row"])
		return int(a["col"]) < int(b["col"])
	)
	if row_targets.is_empty():
		return []
	return [row_targets[0]]


func _enemy_front_column_targets() -> Array:
	# 横扫专用：返回敌方第一列，也就是敌方前排的所有存活单位。
	var targets := []
	for enemy in enemies:
		if _is_active(enemy) and int(enemy["col"]) == 0:
			targets.append(enemy)
	return targets


func _ally_front_column_targets() -> Array:
	var targets: Array = []
	for ally in allies:
		if _is_active(ally) and int(ally["col"]) == 2:
			targets.append(ally)
	return targets


func _ally_forward_column_targets() -> Array:
	# 敌人视角下，我方 col 越大越靠前；若最右列没人，就攻击下一列。
	var best_col: int = -1
	for ally in allies:
		if _is_active(ally):
			best_col = maxi(best_col, int(ally["col"]))
	var targets: Array = []
	if best_col < 0:
		return targets
	for ally in allies:
		if _is_active(ally) and int(ally["col"]) == best_col:
			targets.append(ally)
	return targets


func _apply_support_skill(actor: Dictionary, skill: Dictionary, selected_targets: Array = []) -> PackedStringArray:
	# 结算治疗/护盾/加速/减伤类技能。
	# 守护祷言会作用于玩家点选目标，以及该目标上下左右相邻友方。
	# 战术支援会影响自身和上下左右相邻友方。
	var lines := PackedStringArray()
	var targets: Array = []
	if skill["card_id"] == "tactical_support":
		# 战术支援围绕施法者自己展开：自身 + 上下左右相邻友方。
		targets = _adjacent_allies(actor)
		targets.append(actor)
	elif skill["card_id"] == "guardian_prayer" and not selected_targets.is_empty():
		# 守护祷言围绕玩家点击的中心目标展开：
		# 中心目标 + 上下左右相邻友方都吃到完整技能效果。
		var center: Dictionary = selected_targets[0]
		targets.append(center)
		for adjacent in _adjacent_allies(center):
			targets.append(adjacent)
	else:
		# 兜底逻辑：如果未来某个支援技能没有特殊目标规则，就自动给血量最低友方。
		var lowest := _lowest_hp_ally()
		if not lowest.is_empty():
			targets.append(lowest)

	var total_shield_pct: float = float(skill["shield_pct"])
	for morale_shield in skill.get("morale_shield_modules", []):
		var morale_cost := int(morale_shield.get("cost", 0))
		if morale < morale_cost:
			lines.append(_text("BATTLE_LOG_MORALE_SHIELD_SKIPPED"))
			continue
		_change_morale(-morale_cost, _text("BATTLE_REASON_MORALE_SHIELD"))
		total_shield_pct += float(morale_shield.get("shield_pct", 0.0))

	for target in targets:
		# 同一个目标集合会依次吃治疗、护盾、加速、减伤。
		# 这些数值都来自 BattleRuntime 根据拼图实时生成的 skill 字典。
		if float(skill["heal_pct"]) > 0.0:
			var heal := int(round(float(actor["will"]) * float(skill["heal_pct"]) / 100.0))
			_heal(target, heal)
			lines.append(_format_text("BATTLE_LOG_SUPPORT_HEAL", {"target": target["name"], "value": heal}))
		if total_shield_pct > 0.0:
			var shield_gain := int(round(float(actor["will"]) * total_shield_pct / 100.0))
			target["shield"] = int(target["shield"]) + shield_gain
			lines.append(_format_text("BATTLE_LOG_SUPPORT_SHIELD", {"target": target["name"], "value": shield_gain}))
		if int(skill["speed_buff"]) > 0:
			_add_status(target, "haste", "BATTLE_STATUS_HASTE", "speed", int(skill["speed_buff"]), int(skill.get("speed_duration", skill["support_duration"])))
			lines.append(_format_text("BATTLE_LOG_SUPPORT_SPEED", {"target": target["name"], "value": skill["speed_buff"]}))
		if int(skill["damage_reduction_pct"]) > 0:
			_add_status(target, "sturdy", "BATTLE_STATUS_STURDY", "damage_reduction", int(skill["damage_reduction_pct"]), int(skill.get("damage_reduction_duration", skill["support_duration"])))
			lines.append(_format_text("BATTLE_LOG_SUPPORT_REDUCTION", {"target": target["name"], "value": skill["damage_reduction_pct"]}))
	return lines


func _finish_player_action() -> void:
	# 玩家行动完成后，回到 battle phase，等待“下一行动”继续推进队列。
	phase = "battle"
	current_actor = {}
	pending_move_actor = {}
	pending_target_actor = {}
	pending_target_skill = {}
	next_action_button.disabled = false
	next_action_button.text = _text("UI_NEXT_ACTION")
	_clear_action_buttons()
	_add_reload_battle_button()
	_check_battle_end()
	_refresh()


func _run_enemy_action(actor: Dictionary) -> void:
	# 敌方 AI 极简实现：
	# 药师优先治疗受伤友方；其他敌人根据 role 选择攻击目标。
	var role: String = str(actor.get("role", "bruiser"))
	if role == "summoner":
		_run_summoner_action(actor)
		return
	if _living_field(allies).is_empty():
		_log(_format_text("BATTLE_LOG_NO_ATTACK_TARGET", {"name": actor["name"]}))
		return
	if role == "healer":
		var target := _lowest_hp_from(_living_field(enemies))
		if not target.is_empty() and int(target["hp"]) < int(target["max_hp"]):
			var heal := int(round(float(actor["will"]) * 0.75))
			_heal(target, heal)
			_log(_format_text("BATTLE_LOG_ENEMY_HEAL", {"actor": actor["name"], "target": target["name"], "value": heal}))
			return
	if role == "captain":
		for enemy in _living_field(enemies):
			enemy["shield"] = int(enemy["shield"]) + int(actor["will"])
			_add_status(enemy, "war_drum", "BATTLE_STATUS_DRUM", "speed", 2, 1)
		_log(_format_text("BATTLE_LOG_CAPTAIN_DRUM", {"actor": actor["name"], "shield": actor["will"]}))
		return
	if role == "shaman":
		var weak_target: Dictionary = _lowest_hp_from(_living_field(allies))
		if weak_target.is_empty():
			return
		_add_layered_status(weak_target, "cold", 2)
		_add_layered_status(weak_target, "vulnerable", 1)
		_log(_format_text("BATTLE_LOG_SHAMAN_CURSE", {"actor": actor["name"], "target": weak_target["name"]}))
		return
	if role == "bomber":
		var center_target: Dictionary = _enemy_target(actor)
		if center_target.is_empty():
			return
		var row_targets: Array = _living_in_row(allies, int(center_target["row"]))
		var splash_damage: int = int(actor["strength"])
		var actual_damages := PackedInt32Array()
		for target in row_targets:
			var damage_result: Dictionary = _apply_damage(target, splash_damage, 0.0, actor)
			actual_damages.append(int(damage_result["final_damage"]))
		_log(_format_text("BATTLE_LOG_BOMBER_ATTACK", {
			"actor": actor["name"],
			"row": _row_name(int(center_target["row"])),
			"damages": _damage_values_text(actual_damages)
		}))
		return
	if role == "assassin":
		var mark: Dictionary = _lowest_hp_from(_living_field(allies))
		if mark.is_empty():
			return
		var stab_damage: int = int(round(float(actor["strength"]) * 1.15))
		var damage_result: Dictionary = _apply_damage(mark, stab_damage, 30.0, actor)
		_log(_format_text("BATTLE_LOG_ASSASSIN_ATTACK", {
			"actor": actor["name"],
			"target": mark["name"],
			"damage": int(damage_result["final_damage"])
		}))
		return
	if role == "demoralizer":
		var morale_target: Dictionary = _enemy_target(actor)
		if morale_target.is_empty():
			return
		var scare_damage: int = int(actor["strength"])
		var damage_result: Dictionary = _apply_damage(morale_target, scare_damage, 0.0, actor)
		_change_morale(-4, _format_text("BATTLE_REASON_DEMORALIZE", {"name": actor["name"]}))
		_log(_format_text("BATTLE_LOG_DEMORALIZER_ATTACK", {
			"actor": actor["name"],
			"target": morale_target["name"],
			"damage": int(damage_result["final_damage"])
		}))
		return
	if role == "leader":
		var front_targets: Array = _ally_forward_column_targets()
		var leader_damage: int = int(actor["strength"])
		if morale < 40:
			leader_damage = int(round(float(leader_damage) * 1.35))
		var actual_damages := PackedInt32Array()
		for target in front_targets:
			var damage_result: Dictionary = _apply_damage(target, leader_damage, 0.0, actor)
			actual_damages.append(int(damage_result["final_damage"]))
		_log(_format_text("BATTLE_LOG_LEADER_ATTACK", {
			"actor": actor["name"],
			"count": front_targets.size(),
			"damages": _damage_values_text(actual_damages)
		}))
		return
	var target := _enemy_target(actor)
	if target.is_empty():
		return
	var damage := int(actor["strength"])
	var damage_result: Dictionary = _apply_damage(target, damage, 0.0, actor)
	_log(_format_text("BATTLE_LOG_ENEMY_ATTACK", {
		"actor": actor["name"],
		"target": target["name"],
		"damage": int(damage_result["final_damage"])
	}))


func _run_summoner_action(actor: Dictionary) -> void:
	var summon_pos: Vector2i = _choose_summon_marker_position()
	if summon_pos.x >= 0:
		var summon_pool: String = "normal" if round_number % 2 == 1 else "elite"
		_place_summon_marker(summon_pos, summon_pool)
		_log(_format_text("BATTLE_LOG_SUMMON_MARKER", {
			"actor": actor["name"],
			"row": _row_name(summon_pos.y),
			"col": summon_pos.x + 1,
			"pool": _text("BATTLE_LOG_SUMMON_POOL_NORMAL") if summon_pool == "normal" else _text("BATTLE_LOG_SUMMON_POOL_ELITE")
		}))
		return
	var front_targets: Array = _ally_front_column_targets()
	if front_targets.is_empty():
		front_targets = _ally_forward_column_targets()
	if front_targets.is_empty():
		_log(_format_text("BATTLE_LOG_NO_ATTACK_TARGET", {"name": actor["name"]}))
		return
	var damage_result: Dictionary = _apply_damage(front_targets[0], int(actor["strength"]), 0.0, actor)
	_log(_format_text("BATTLE_LOG_SUMMON_FALLBACK", {
		"actor": actor["name"],
		"target": front_targets[0]["name"],
		"damage": int(damage_result["final_damage"])
	}))


func _choose_summon_marker_position() -> Vector2i:
	var front_empty: Array = _empty_enemy_cells_in_columns([0])
	var back_empty: Array = _empty_enemy_cells_in_columns([1, 2])
	if front_empty.is_empty() and back_empty.is_empty():
		return Vector2i(-1, -1)
	if not front_empty.is_empty() and (back_empty.is_empty() or randf() < 0.5):
		var front_pos: Vector2i = front_empty.pick_random()
		return front_pos
	var back_pos: Vector2i = back_empty.pick_random()
	return back_pos


func _empty_enemy_cells_in_columns(columns: Array) -> Array:
	var result: Array = []
	for col_value in columns:
		var col: int = int(col_value)
		for row in range(3):
			if _unit_at(enemies, col, row).is_empty():
				result.append(Vector2i(col, row))
	return result


func _place_summon_marker(pos: Vector2i, summon_pool: String) -> void:
	var marker: Dictionary = {
		"name": _text("BATTLE_UI_SUMMON_MARKER_NAME"),
		"role": "summon_marker",
		"team": "enemy",
		"col": pos.x,
		"row": pos.y,
		"strength": 0,
		"max_hp": 0,
		"hp": 0,
		"will": 0,
		"speed": 0,
		"shield": 0,
		"field": true,
		"dead": false,
		"status_effects": [],
		"attack_desc": _text("BATTLE_UI_SUMMON_MARKER_ATTACK"),
		"trait_desc": _text("BATTLE_UI_SUMMON_MARKER_TRAIT"),
		"summon_pool": summon_pool
	}
	enemies.append(marker)
	pending_summons.append(marker)


func _process_pending_summons_at_prepare_start() -> void:
	if pending_summons.is_empty():
		return
	var summoner: Dictionary = _summoner_unit()
	if summoner.is_empty() or not _is_active(summoner):
		_clear_summon_markers()
		return
	var markers: Array = pending_summons.duplicate()
	pending_summons.clear()
	for marker_value in markers:
		var marker: Dictionary = marker_value
		if bool(marker.get("dead", false)) or not bool(marker.get("field", false)):
			continue
		var pos := Vector2i(int(marker.get("col", 0)), int(marker.get("row", 0)))
		var summon_pool: String = str(marker.get("summon_pool", "normal"))
		var summoned: Dictionary = _make_summoned_enemy(summon_pool, pos)
		var marker_index: int = enemies.find(marker)
		if marker_index >= 0:
			enemies[marker_index] = summoned
		else:
			enemies.append(summoned)
		if str(summoned.get("role", "")) == "guard":
			summoned["shield"] = int(summoned.get("shield", 0)) + 20
		_log(_format_text("BATTLE_LOG_SUMMON_DONE", {
			"summoner": summoner["name"],
			"summoned": summoned["name"],
			"row": _row_name(pos.y),
			"col": pos.x + 1
		}))


func _make_summoned_enemy(summon_pool: String, pos: Vector2i) -> Dictionary:
	var role: String = _pick_summoned_role(summon_pool, pos.x == 0)
	if summon_pool == "elite":
		return _elite_summon_enemy(role, pos)
	return _normal_enemy(role, pos)


func _pick_summoned_role(summon_pool: String, frontline: bool) -> String:
	var roles: Array
	if summon_pool == "elite":
		roles = ["guard", "captain", "leader"] if frontline else ["archer", "assassin", "shaman"]
	else:
		roles = ["bruiser", "guard"] if frontline else ["archer", "healer", "bomber", "demoralizer"]
	return str(roles.pick_random())


func _elite_summon_enemy(role: String, pos: Vector2i) -> Dictionary:
	return _enemy(_elite_enemy_id_for_role(role), pos.x, pos.y)


func _clear_summon_markers() -> void:
	pending_summons.clear()
	for enemy in enemies:
		if str(enemy.get("role", "")) == "summon_marker":
			enemy["dead"] = true
			enemy["field"] = false


func _enemy_target(actor: Dictionary) -> Dictionary:
	# 敌方目标选择：
	# 弩手攻击我方后排血量最低单位；普通敌人优先攻击同一行最靠前的我方单位。
	if actor["role"] == "archer":
		var backline := _living_field(allies)
		backline.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["col"]) == int(b["col"]):
				return int(a["hp"]) < int(b["hp"])
			return int(a["col"]) < int(b["col"])
		)
		return backline[0] if not backline.is_empty() else {}
	var same_row := _living_in_row(allies, int(actor["row"]))
	same_row.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["col"]) > int(b["col"]))
	if not same_row.is_empty():
		return same_row[0]
	var candidates := _living_field(allies)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["col"]) == int(b["col"]):
			return abs(int(a["row"]) - int(actor["row"])) < abs(int(b["row"]) - int(actor["row"]))
		return int(a["col"]) > int(b["col"])
	)
	return candidates[0] if not candidates.is_empty() else {}


func _apply_damage(target: Dictionary, damage: int, pierce_pct: float, source: Dictionary) -> Dictionary:
	# 统一伤害入口。
	# 所有倍率先合并成一个式子，最后只四舍五入一次，再拆分穿透伤害和普通伤害。
	var weak_reduction: int = _weak_damage_reduction(source)
	var reduction: int = _damage_reduction(target)
	var defense_multiplier: float = _consume_next_damage_multiplier(target)
	var vulnerable_multiplier: float = _vulnerable_damage_multiplier(target)
	var final_damage: int = int(round(float(damage) * (1.0 - float(weak_reduction) / 100.0) * (1.0 - float(reduction) / 100.0) * defense_multiplier * vulnerable_multiplier))
	var pierce_damage: int = int(round(float(final_damage) * pierce_pct / 100.0))
	var normal_damage: int = max(final_damage - pierce_damage, 0)
	var shield_damage: int = min(int(target["shield"]), normal_damage)
	var hp_damage: int = pierce_damage + max(normal_damage - shield_damage, 0)
	target["shield"] = max(int(target["shield"]) - shield_damage, 0)
	target["hp"] = max(int(target["hp"]) - hp_damage, 0)
	if int(target["hp"]) <= 0:
		_handle_unit_down(target, source)
	return {
		"raw_damage": damage,
		"weak_reduction": weak_reduction,
		"final_damage": final_damage,
		"reduction": reduction,
		"defense_reduction": int(round((1.0 - defense_multiplier) * 100.0)),
		"pierce_damage": pierce_damage,
		"shield_damage": shield_damage,
		"hp_damage": hp_damage
	}


func _damage_values_text(values: PackedInt32Array) -> String:
	if values.is_empty():
		return "0"
	var first_value: int = values[0]
	var same_value := true
	for index in values.size():
		if int(values[index]) != first_value:
			same_value = false
			break
	if same_value:
		return str(first_value)
	var parts := PackedStringArray()
	for value in values:
		parts.append(str(value))
	return "/".join(parts)


func _handle_unit_down(unit: Dictionary, source: Dictionary) -> void:
	# 单位倒下后的处理。
	# 敌人直接死亡；我方第一次倒下变重伤离场，带重伤再次倒下则死亡。
	unit["field"] = false
	if unit["team"] == "enemy":
		unit["dead"] = true
		_log(_format_text("BATTLE_LOG_UNIT_DOWN", {"name": unit["name"]}))
		return
	if int(unit["injury_marks"]) > 0:
		unit["dead"] = true
		_log(_format_text("BATTLE_LOG_UNIT_DEAD", {"name": unit["name"]}))
	else:
		unit["injury_marks"] = int(unit["injury_marks"]) + 1
		_change_morale(-25, _format_text("BATTLE_REASON_INJURED", {"name": unit["name"]}))
		_log(_format_text("BATTLE_LOG_UNIT_INJURED", {"name": unit["name"]}))


func _end_round() -> void:
	# 回合结束阶段自动执行：状态持续时间减少、技能 CD 减少、撤退角色回血。
	_process_layered_statuses_at_turn_end()
	_decay_shields()
	_tick_statuses()
	_reduce_cooldowns()
	_heal_retreated_allies()
	if _check_battle_end():
		return
	_apply_relic_end_round_effects()
	var round_morale_loss: int = mini(round_number, 5)
	_change_morale(-round_morale_loss, _format_text("BATTLE_REASON_ROUND_END", {"round": round_number}))
	if _living_field(allies).is_empty():
		_change_morale(-40, _text("BATTLE_REASON_NO_ALLY_ON_FIELD"))
	_log(_format_text("BATTLE_LOG_ROUND_END", {"round": round_number}))
	if morale <= 0:
		_demo_failed(_text("BATTLE_FAIL_NO_MORALE"))
		return
	_start_round()


func _decay_shields() -> void:
	for unit in allies + enemies:
		if int(unit.get("shield", 0)) > 0:
			unit["shield"] = int(round(float(unit["shield"]) * 0.5))


func _apply_relic_end_round_effects() -> void:
	if BattleRuntime.has_relic("empty_bag_battery") and player_energy == 0:
		next_round_energy_bonus += 1
		_log(_text("BATTLE_LOG_RELIC_EMPTY_BAG_TRIGGER"))
	if BattleRuntime.has_relic("full_cell_battery") and player_energy != 0:
		next_round_energy_bonus += 1
		_log(_text("BATTLE_LOG_RELIC_FULL_CELL_TRIGGER"))
	var alive_count: int = _alive_ally_count()
	if BattleRuntime.has_relic("full_roster_banner") and alive_count >= 4:
		_change_morale(4, _text("BATTLE_REASON_FULL_ROSTER_BANNER"))
	if BattleRuntime.has_relic("remnant_badge") and alive_count < 4:
		_change_morale(3, _text("BATTLE_REASON_REMNANT_BADGE"))


func _alive_ally_count() -> int:
	var count := 0
	for ally in allies:
		if not bool(ally.get("dead", false)) and int(ally.get("hp", 0)) > 0:
			count += 1
	return count


func _check_battle_end() -> bool:
	# 胜负检查。
	# 敌方全灭进入搜刮/结算；士气 0 或无可用角色则探索失败。
	if current_node_type == "boss" and _summoner_defeated():
		for enemy in enemies:
			if str(enemy.get("role", "")) != "summoner":
				enemy["dead"] = true
				enemy["field"] = false
		_clear_summon_markers()
		_log(_text("BATTLE_LOG_SUMMONER_DOWN"))
	if _living_field(enemies).is_empty():
		if current_node_type == "elite":
			_change_morale(15, _text("BATTLE_REASON_ELITE_WIN"))
		else:
			_change_morale(10, _text("BATTLE_REASON_BATTLE_WIN"))
		if current_node_type == "normal":
			BattleRuntime.add_gold(15)
			_log(_format_text("BATTLE_LOG_LOOT_GOLD", {"gold": 15}))
		elif current_node_type == "elite":
			BattleRuntime.add_gold(30)
			_log(_format_text("BATTLE_LOG_LOOT_GOLD", {"gold": 30}))
		elif current_node_type == "boss":
			BattleRuntime.add_gold(50)
			_log(_format_text("BATTLE_LOG_LOOT_GOLD", {"gold": 50}))
		_heal_surviving_allies_after_battle()
		BattleRuntime.save_party_state(allies, morale)
		if current_node_type == "boss":
			BattleRuntime.end_exploration(true)
			BattleRuntime.clear_battle_checkpoint()
			phase = "demo_end"
			_log(_text("BATTLE_LOG_DEMO_CLEAR"))
			_show_demo_end_actions()
		else:
			BattleRuntime.clear_battle_checkpoint()
			phase = "reward_select"
			if current_node_type == "elite":
				_log(_text("BATTLE_LOG_ELITE_REWARD_FIRST"))
				_show_reward_choices("elite")
			else:
				_log(_text("BATTLE_LOG_NORMAL_REWARD_FIRST"))
				_show_reward_choices("normal")
		_refresh()
		return true
	if phase != "prepare" and _living_field(allies).is_empty():
		return false
	if morale <= 0 or _available_allies().is_empty():
		_demo_failed(_text("BATTLE_FAIL_NO_AVAILABLE_ALLY"))
		return true
	return false


func _summoner_unit() -> Dictionary:
	for enemy in enemies:
		if str(enemy.get("role", "")) == "summoner":
			return enemy
	return {}


func _summoner_defeated() -> bool:
	var summoner: Dictionary = _summoner_unit()
	return not summoner.is_empty() and (bool(summoner.get("dead", false)) or int(summoner.get("hp", 0)) <= 0 or not bool(summoner.get("field", false)))


func _show_loot_action() -> void:
	# 第一场胜利后的中间步骤：先搜刮战利品，再决定结束或深入。
	_clear_action_buttons()
	next_action_button.disabled = true
	var loot := _add_action_button(_text("BATTLE_ACTION_LOOT"))
	loot.pressed.connect(func() -> void:
		phase = "choice"
		_log(_text("BATTLE_LOG_LOOT_COMPLETE"))
		_show_post_battle_choice()
		_refresh()
	)


func _show_reward_choices(reward_type: String) -> void:
	_clear_action_buttons()
	next_action_button.disabled = true
	reward_choices = _generate_module_reward_choices(reward_type)
	if reward_choices.is_empty():
		_log(_text("BATTLE_LOG_NO_MODULE_REWARD"))
		if current_node_type == "elite":
			_show_relic_reward_choices()
		else:
			_show_after_reward_actions()
		_refresh()
		return
	for module_id in reward_choices:
		var module: Dictionary = BattleRuntime.modules[module_id]
		var button := _add_action_button(_format_text("BATTLE_REWARD_MODULE_BUTTON", {
			"name": module["name"],
			"shape": BattleRuntime.module_shape_text(module["shape"], module["size"]),
			"description": module["description"]
		}))
		button.pressed.connect(_select_module_reward.bind(module_id))


func _show_relic_reward_choices() -> void:
	_clear_action_buttons()
	next_action_button.disabled = true
	reward_choices = BattleRuntime.roll_relic_choices(3)
	if reward_choices.is_empty():
		_log(_text("BATTLE_LOG_NO_RELIC_REWARD"))
		_show_after_reward_actions()
		_refresh()
		return
	for relic_id in reward_choices:
		var relic: Dictionary = BattleRuntime.get_relic(str(relic_id))
		var button := _add_action_button(_format_text("BATTLE_REWARD_RELIC_BUTTON", {
			"name": relic.get("name", relic_id),
			"description": relic.get("description", "")
		}))
		button.pressed.connect(_select_relic_reward.bind(str(relic_id)))


func _select_module_reward(module_id: String) -> void:
	BattleRuntime.add_module_to_inventory(module_id, 1)
	var module: Dictionary = BattleRuntime.modules[module_id]
	_log(_format_text("BATTLE_LOG_MODULE_GAIN", {"name": module["name"]}))
	if current_node_type == "elite":
		_log(_text("BATTLE_LOG_SELECT_RELIC_REWARD"))
		_show_relic_reward_choices()
	else:
		_show_after_reward_actions()
	_refresh()


func _select_relic_reward(relic_id: String) -> void:
	if BattleRuntime.add_relic(relic_id):
		var relic: Dictionary = BattleRuntime.get_relic(relic_id)
		_log(_format_text("BATTLE_LOG_RELIC_GAIN", {"name": relic.get("name", relic_id)}))
	else:
		_log(_text("BATTLE_LOG_RELIC_INVALID"))
	_show_after_reward_actions()
	_refresh()


func _show_after_reward_actions() -> void:
	_clear_action_buttons()
	next_action_button.disabled = true
	var build := _add_action_button(_text("UI_RETURN_TO_BUILD"))
	build.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/skill_build_scene.tscn")
	)
	var map := _add_action_button(_text("MAP_CONTINUE_EXPLORATION"))
	map.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/map_scene.tscn")
	)


func _generate_module_reward_choices(reward_type: String) -> Array:
	var quality := "green" if reward_type in ["elite", "chest"] else "white"
	var pool := []
	for module_id in BattleRuntime.module_order:
		var module: Dictionary = BattleRuntime.modules[module_id]
		if bool(module.get("reward_excluded", false)):
			continue
		if str(module.get("quality", "white")) == quality:
			pool.append(module_id)
	pool.shuffle()
	return pool.slice(0, min(3, pool.size()))


func _show_post_battle_choice() -> void:
	# 搜刮完成后的搜打撤选择：
	# 带着白色奖励结束，或者挑战精英敌人换更高风险/奖励。
	_clear_action_buttons()
	next_action_button.disabled = true
	var safe := _add_action_button(_text("BATTLE_ACTION_SAFE_END"))
	safe.pressed.connect(func() -> void:
		phase = "demo_end"
		_log(_text("BATTLE_LOG_SAFE_END"))
		_show_demo_end_actions()
		_refresh()
	)
	var deep := _add_action_button(_text("BATTLE_ACTION_CHALLENGE_ELITE"))
	deep.pressed.connect(func() -> void:
		_clear_action_buttons()
		_start_encounter(2)
	)


func _show_demo_end_actions() -> void:
	# Demo 结束后的操作。战斗内不再允许返回战斗准备，只允许重开 Demo。
	_clear_action_buttons()
	_add_reload_battle_button()
	next_action_button.disabled = false
	next_action_button.text = _text("BATTLE_ACTION_RESTART_DEMO")


func _demo_failed(reason: String) -> void:
	# 探索失败会丢失本次奖励，并进入 Demo 结束状态。
	BattleRuntime.end_exploration(false)
	phase = "demo_end"
	_log(_format_text("BATTLE_LOG_DEMO_FAILED", {"reason": reason}))
	_show_demo_end_actions()
	_refresh()


func _refresh() -> void:
	# 统一刷新入口。任何战斗状态改变后都尽量走这里。
	# 它会刷新双方棋盘、行动队列、能量士气显示和日志。
	_rebuild_grid(ally_list, allies, true)
	_rebuild_grid(enemy_list, enemies, false)
	var order_lines := PackedStringArray()
	order_lines.append(_format_text("BATTLE_UI_ORDER_TITLE", {"encounter": encounter_index, "round": max(round_number, 1)}))
	order_lines.append(_format_text("BATTLE_UI_RESOURCES", {
		"energy": player_energy,
		"energy_max": ENERGY_MAX,
		"morale": morale,
		"morale_text": _morale_text()
	}))
	order_lines.append(_format_text("BATTLE_UI_RELICS", {"relics": BattleRuntime.owned_relic_text()}))
	order_lines.append("")
	order_lines.append(_text("BATTLE_UI_TURN_QUEUE"))
	if turn_queue.is_empty():
		order_lines.append(_text("BATTLE_UI_WAITING_QUEUE"))
	else:
		for unit in turn_queue:
			order_lines.append(_format_text("BATTLE_UI_QUEUE_UNIT", {"name": unit["name"], "speed": _effective_speed(unit)}))
	if phase == "player_action" and not current_actor.is_empty():
		order_lines.append("")
		order_lines.append(_format_text("BATTLE_UI_CURRENT_ACTOR", {"name": current_actor["name"]}))
	if phase == "prepare":
		order_lines.append("")
		order_lines.append(_text("BATTLE_UI_PHASE_PREPARE"))
	if phase == "target_enemy":
		order_lines.append("")
		order_lines.append(_text("BATTLE_UI_PHASE_TARGET_ENEMY"))
	if phase == "target_ally":
		# target_ally 目前给守护祷言使用，提示玩家点击我方中心目标。
		order_lines.append("")
		order_lines.append(_text("BATTLE_UI_PHASE_TARGET_ALLY"))
	if phase == "move_target":
		order_lines.append("")
		order_lines.append(_text("BATTLE_UI_PHASE_MOVE"))
	order_label.text = "\n".join(order_lines)
	log_label.text = "\n".join(battle_log)
	if battle_log.size() > 0:
		log_label.scroll_to_line(battle_log.size() - 1)


func _rebuild_grid(container: VBoxContainer, units: Array, is_ally: bool) -> void:
	# 重建一侧 3x3 半场。
	# 准备阶段我方空格会变成可点击部署格。
	# 精准打击选目标时敌方单位会变成可点击目标。
	# 守护祷言选目标时我方单位会变成可点击目标。
	for child in container.get_children():
		child.queue_free()
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("edf1f8"))
	title.text = _text("BATTLE_UI_ALLY_GRID_TITLE") if is_ally else _text("BATTLE_UI_ENEMY_GRID_TITLE")
	container.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	container.add_child(grid)
	for row in range(3):
		for col in range(3):
			var unit := _unit_at(units, col, row)
			var is_deploy_cell := is_ally and phase == "prepare" and selected_deploy_index >= 0 and unit.is_empty()
			var is_enemy_target_cell := not is_ally and phase == "target_enemy" and not unit.is_empty() and _is_active(unit)
			var is_ally_target_cell := is_ally and phase == "target_ally" and not unit.is_empty()
			var is_move_cell := is_ally and phase == "move_target" and _can_move_to_cell(col, row)
			var is_target_cell := is_enemy_target_cell or is_ally_target_cell or is_move_cell
			var cell := PanelContainer.new()
			cell.custom_minimum_size = Vector2(156, 114)
			cell.add_theme_stylebox_override("panel", _cell_style(not unit.is_empty(), is_ally, is_deploy_cell or is_target_cell))
			# 不把目标格改成 Button，而是在 PanelContainer 上监听 gui_input。
			# 这样高亮只影响边框，不会让 Button 的绘制逻辑盖住角色名、HP 等文本。
			if is_deploy_cell:
				cell.mouse_filter = Control.MOUSE_FILTER_STOP
				cell.gui_input.connect(_on_deploy_cell_input.bind(col, row))
			elif is_target_cell:
				cell.mouse_filter = Control.MOUSE_FILTER_STOP
				if is_enemy_target_cell:
					cell.gui_input.connect(_on_target_cell_input.bind(unit))
				elif is_move_cell:
					cell.gui_input.connect(_on_move_cell_input.bind(col, row))
				else:
					cell.gui_input.connect(_on_ally_target_cell_input.bind(unit))
			var label := RichTextLabel.new()
			label.bbcode_enabled = true
			label.fit_content = true
			label.scroll_active = false
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.add_theme_font_size_override("normal_font_size", 15)
			label.add_theme_color_override("default_color", Color("dce5f4"))
			if unit.is_empty():
				label.text = _text("BATTLE_UI_CELL_MOVABLE") if is_move_cell else _text("BATTLE_UI_CELL_DEPLOYABLE") if is_deploy_cell else _text("BATTLE_UI_CELL_EMPTY")
			elif str(unit.get("role", "")) == "summon_marker":
				label.text = _format_text("BATTLE_UI_SUMMON_MARKER_CELL", {
					"pool": _text("BATTLE_UI_SUMMON_NORMAL_ENEMY") if str(unit.get("summon_pool", "normal")) == "normal" else _text("BATTLE_UI_SUMMON_ELITE_ENEMY")
				})
			else:
				var status_text := _status_summary_text(unit)
				label.text = _format_text("BATTLE_UI_UNIT_CELL", {
					"name": unit["name"],
					"hp": unit["hp"],
					"max_hp": unit["max_hp"],
					"shield": unit["shield"],
					"speed": _effective_speed(unit),
					"injury": _format_text("BATTLE_UI_UNIT_INJURY_LINE", {"marks": int(unit.get("injury_marks", 0))}) if is_ally and int(unit.get("injury_marks", 0)) > 0 else "",
					"status": _format_text("BATTLE_UI_UNIT_STATUS_LINE", {"status": status_text}) if status_text != _text("BATTLE_UI_NONE") else ""
				})
				cell.mouse_entered.connect(_show_unit_info.bind(unit))
				cell.mouse_exited.connect(_hide_info_popup)
			cell.add_child(label)
			grid.add_child(cell)
	var bench := PackedStringArray()
	for unit in units:
		if is_ally and _can_show_in_bench(unit):
			var state := _text("BATTLE_UI_BENCH_READY")
			if bool(unit["retreated"]):
				state = _text("BATTLE_UI_BENCH_RETREATED")
			if int(unit.get("injury_marks", 0)) > 0:
				state = _text("BATTLE_UI_BENCH_INJURED")
			bench.append(_format_text("BATTLE_UI_BENCH_UNIT", {
				"name": unit["name"],
				"state": state,
				"hp": unit["hp"],
				"max_hp": unit["max_hp"]
			}))
	if not bench.is_empty():
		var bench_label := Label.new()
		bench_label.add_theme_font_size_override("font_size", 16)
		bench_label.add_theme_color_override("font_color", Color("aeb9ca"))
		bench_label.text = _format_text("BATTLE_UI_BENCH_PREFIX", {"units": "、".join(bench)})
		container.add_child(bench_label)


func _clear_action_buttons() -> void:
	# 清理动态生成的动作按钮，避免阶段切换后旧按钮还留在界面上。
	for button in action_buttons:
		if is_instance_valid(button):
			button.queue_free()
	action_buttons.clear()
	next_action_button.disabled = false
	next_action_button.text = _text("UI_NEXT_ACTION")


func _add_reload_battle_button() -> void:
	if not BattleRuntime.has_battle_checkpoint:
		return
	var reload_button := _add_action_button(_text("BATTLE_ACTION_RELOAD_BATTLE"))
	reload_button.pressed.connect(_reload_current_battle)


func _reload_current_battle() -> void:
	if not BattleRuntime.restore_battle_checkpoint():
		_log(_text("BATTLE_LOG_NO_CHECKPOINT"))
		_refresh()
		return
	get_tree().change_scene_to_file("res://scenes/battle_scene.tscn")


func _add_action_button(text: String) -> Button:
	# 创建一颗底部动作按钮，并统一登记到 action_buttons 方便后续清理。
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(182, 48)
	_style_button(button)
	actions_row.add_child(button)
	action_buttons.append(button)
	return button


func _bind_skill_hover(button: Button, actor: Dictionary, skill: Dictionary) -> void:
	# 给技能按钮绑定悬停说明。鼠标移入显示技能详情，移出隐藏。
	button.mouse_entered.connect(_show_skill_info.bind(actor, skill))
	button.mouse_exited.connect(_hide_info_popup)


func _on_deploy_cell_input(event: InputEvent, col: int, row: int) -> void:
	# 可部署格仍然使用普通面板显示，点击事件在这里统一处理。
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_deploy_selected_ally(col, row)


func _on_target_cell_input(event: InputEvent, unit: Dictionary) -> void:
	# 精准打击目标格只做边框高亮，点击事件不再依赖 Button，避免覆盖单位文字。
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_use_pending_skill_on_enemy(unit)


func _on_ally_target_cell_input(event: InputEvent, unit: Dictionary) -> void:
	# 守护祷言目标格同样只做边框高亮，点击后以该单位为中心扩散到相邻友方。
	# 这里不直接计算效果，只负责把“被点击的目标”交给挂起技能流程。
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_use_pending_skill_on_ally(unit)


func _on_move_cell_input(event: InputEvent, col: int, row: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_move_actor_to_cell(col, row)


func _unit_at(units: Array, col: int, row: int) -> Dictionary:
	# 查询某个半场坐标上是否有存活上场单位。
	for unit in units:
		if bool(unit["field"]) and int(unit["col"]) == col and int(unit["row"]) == row and not bool(unit["dead"]):
			return unit
	return {}


func _can_move_to_cell(col: int, row: int) -> bool:
	if pending_move_actor.is_empty():
		return false
	return _is_adjacent_cell(pending_move_actor, col, row)


func _is_adjacent_cell(unit: Dictionary, col: int, row: int) -> bool:
	if col < 0 or col >= 3 or row < 0 or row >= 3:
		return false
	var distance: int = abs(int(unit.get("col", 0)) - col) + abs(int(unit.get("row", 0)) - row)
	return distance == 1


func _is_active(unit: Dictionary) -> bool:
	# “可行动/可被选中”的统一判断：在场、未死亡、HP 大于 0。
	if str(unit.get("role", "")) == "summon_marker":
		return false
	return bool(unit.get("field", false)) and not bool(unit.get("dead", false)) and int(unit.get("hp", 0)) > 0


func _living_field(units: Array) -> Array:
	# 返回某一方当前在场的所有存活单位。
	var result := []
	for unit in units:
		if _is_active(unit):
			result.append(unit)
	return result


func _living_in_row(units: Array, row: int) -> Array:
	# 返回某一行的所有存活单位，普攻和敌方同排攻击会使用。
	var result := []
	for unit in units:
		if _is_active(unit) and int(unit["row"]) == row:
			result.append(unit)
	return result


func _front_enemy_in_row(row: int) -> Dictionary:
	# 我方普攻目标规则：敌方某一行最左侧单位。
	var row_targets := _living_in_row(enemies, row)
	row_targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["col"]) < int(b["col"]))
	return row_targets[0] if not row_targets.is_empty() else {}


func _lowest_hp_ally() -> Dictionary:
	# 取我方在场血量比例最低的角色，治疗技能默认会优先照顾它。
	return _lowest_hp_from(_living_field(allies))


func _lowest_hp_from(units: Array) -> Dictionary:
	# 从任意单位列表中取 HP 百分比最低的单位。
	if units.is_empty():
		return {}
	units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ar := float(a["hp"]) / float(a["max_hp"])
		var br := float(b["hp"]) / float(b["max_hp"])
		return ar < br
	)
	return units[0]


func _adjacent_allies(unit: Dictionary) -> Array:
	# 上下左右相邻友方，用于牧师相邻治疗和坦克战术支援。
	var result := []
	for ally in _living_field(allies):
		var distance: int = abs(int(ally["col"]) - int(unit["col"])) + abs(int(ally["row"]) - int(unit["row"]))
		if distance == 1:
			result.append(ally)
	return result


func _available_allies() -> Array:
	# 仍可继续探索的我方角色：未死亡且没有重伤印记。
	var result := []
	for ally in allies:
		if not bool(ally["dead"]) and int(ally["injury_marks"]) == 0:
			result.append(ally)
	return result


func _can_deploy(ally: Dictionary) -> bool:
	# 准备阶段部署条件。
	# 重伤/死亡/已在场/本回合刚撤退或刚部署过的角色都不能部署。
	return not bool(ally["field"]) and not bool(ally["dead"]) and int(ally["injury_marks"]) == 0 and int(ally["hp"]) > 0 and not bool(ally.get("deployed_this_turn", false))


func _can_show_in_bench(ally: Dictionary) -> bool:
	# 是否显示在待部署区/场外区。
	return not bool(ally["field"]) and not bool(ally["dead"])


func _heal(unit: Dictionary, amount: int) -> void:
	# 简单治疗：不会超过最大生命。
	unit["hp"] = min(int(unit["max_hp"]), int(unit["hp"]) + amount)


func _layered_statuses(unit: Dictionary) -> Dictionary:
	if not unit.has("layered_statuses"):
		unit["layered_statuses"] = {}
	var statuses: Dictionary = unit["layered_statuses"]
	return statuses


func _clear_unit_statuses(unit: Dictionary) -> void:
	unit["status_effects"] = []
	_layered_statuses(unit).clear()


func _get_status_layers(unit: Dictionary, status_id: String) -> int:
	return int(_layered_statuses(unit).get(status_id, 0))


func _add_layered_status(unit: Dictionary, status_id: String, layers: int) -> void:
	if layers <= 0 or status_id.is_empty():
		return
	if status_id == "cold":
		_add_cold(unit, layers)
		return
	var statuses := _layered_statuses(unit)
	var next_layers: int = int(statuses.get(status_id, 0)) + layers
	if status_id == "weak":
		next_layers = mini(next_layers, 10)
	statuses[status_id] = next_layers


func _reduce_layered_status(unit: Dictionary, status_id: String, amount: int) -> void:
	var statuses := _layered_statuses(unit)
	var current := int(statuses.get(status_id, 0)) - amount
	if current <= 0:
		statuses.erase(status_id)
	else:
		statuses[status_id] = current


func _remove_layered_status(unit: Dictionary, status_id: String) -> void:
	_layered_statuses(unit).erase(status_id)


func _add_cold(unit: Dictionary, layers: int) -> void:
	if _get_status_layers(unit, "freeze") > 0:
		return
	var statuses := _layered_statuses(unit)
	statuses["cold"] = int(statuses.get("cold", 0)) + layers
	if int(statuses["cold"]) >= 5:
		statuses.erase("cold")
		statuses["freeze"] = int(statuses.get("freeze", 0)) + 1
		_log(_format_text("BATTLE_LOG_COLD_TO_FREEZE", {"name": unit["name"]}))


func _status_layers_from_skill(actor: Dictionary, status: Dictionary) -> int:
	if status.has("scale_pct"):
		var stat_name := str(status.get("scale_stat", "strength"))
		return int(round(float(actor.get(stat_name, 0)) * float(status.get("scale_pct", 0.0)) / 100.0)) + int(status.get("flat", 0))
	return int(status.get("layers", 0))


func _apply_vulnerable_damage_bonus(target: Dictionary, damage: int) -> int:
	var multiplier := _vulnerable_damage_multiplier(target)
	if multiplier <= 1.0:
		return damage
	return int(round(float(damage) * multiplier))


func _vulnerable_damage_multiplier(target: Dictionary) -> float:
	var layers := _get_status_layers(target, "vulnerable")
	if layers <= 0:
		return 1.0
	var bonus := 0.25 + float(max(layers - 1, 0)) * 0.05
	return 1.0 + bonus


func _weak_damage_reduction(source: Dictionary) -> int:
	if source.is_empty():
		return 0
	var layers: int = mini(_get_status_layers(source, "weak"), 10)
	if layers <= 0:
		return 0
	return mini(20 + max(layers - 1, 0) * 5, 65)


func _try_consume_freeze(unit: Dictionary) -> bool:
	if _get_status_layers(unit, "freeze") <= 0:
		return false
	_reduce_layered_status(unit, "freeze", 1)
	_log(_format_text("BATTLE_LOG_FREEZE_SKIP", {"name": unit["name"]}))
	return true


func _process_layered_statuses_at_turn_end() -> void:
	for unit in allies + enemies:
		if not _is_active(unit):
			continue
		var burn_layers := _get_status_layers(unit, "burn")
		if burn_layers > 0:
			_deal_burn_damage(unit, burn_layers)
			_reduce_layered_status(unit, "burn", 1)
		_reduce_layered_status(unit, "vulnerable", 1)
		_reduce_layered_status(unit, "weak", 1)
		_reduce_layered_status(unit, "cold", 1)


func _deal_burn_damage(unit: Dictionary, damage: int) -> void:
	var defense_multiplier: float = _consume_next_damage_multiplier(unit)
	var final_damage: int = int(round(float(damage) * defense_multiplier))
	var shield_damage: int = mini(int(unit.get("shield", 0)), final_damage)
	unit["shield"] = maxi(int(unit.get("shield", 0)) - shield_damage, 0)
	var hp_damage: int = maxi(final_damage - shield_damage, 0)
	unit["hp"] = maxi(int(unit["hp"]) - hp_damage, 0)
	_log(_format_text("BATTLE_LOG_BURN_DAMAGE", {"name": unit["name"], "damage": final_damage, "shield": shield_damage}))
	if int(unit["hp"]) <= 0:
		_handle_unit_down(unit, {})


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


func _add_status(unit: Dictionary, status_id: String, name_key: String, stat: String, value: int, turns: int) -> void:
	# 添加持续状态。当前 Demo 用于加速和减伤。
	for status in unit.get("status_effects", []):
		if _status_effect_id(status) == status_id and str(status.get("stat", "")) == stat and int(status.get("value", 0)) == value:
			if turns < 0 or int(status.get("turns", 0)) < 0:
				status["turns"] = -1
				return
			status["turns"] = int(status.get("turns", 0)) + turns
			return
	unit["status_effects"].append({
		"id": status_id,
		"name_key": name_key,
		"stat": stat,
		"value": value,
		"turns": turns
	})


func _tick_statuses() -> void:
	# 回合结束时减少状态持续时间，到 0 的状态会被移除。
	for unit in allies + enemies:
		var remaining := []
		for status in unit.get("status_effects", []):
			if int(status.get("turns", 0)) < 0:
				remaining.append(status)
				continue
			status["turns"] = int(status["turns"]) - 1
			if int(status["turns"]) > 0:
				remaining.append(status)
		unit["status_effects"] = remaining


func _reduce_cooldowns() -> void:
	# 回合结束时所有技能 CD -1。
	for ally in allies:
		var cooldowns: Dictionary = ally.get("skill_cooldowns", {})
		for key in cooldowns.keys():
			cooldowns[key] = max(int(cooldowns[key]) - 1, 0)


func _heal_retreated_allies() -> void:
	# 待部署区角色每回合结束恢复 5% 最大生命。
	for ally in allies:
		if bool(ally["retreated"]) and not bool(ally["dead"]):
			_heal(ally, max(1, int(round(float(ally["max_hp"]) * 0.05))))


func _heal_surviving_allies_after_battle() -> void:
	var healed_names: Array[String] = []
	for ally in allies:
		if bool(ally.get("dead", false)) or int(ally.get("hp", 0)) <= 0:
			continue
		var heal_amount: int = max(1, int(round(float(ally["max_hp"]) * 0.15)))
		var before_hp: int = int(ally["hp"])
		_heal(ally, heal_amount)
		var actual_heal: int = int(ally["hp"]) - before_hp
		if actual_heal > 0:
			healed_names.append("%s +%d" % [ally["name"], actual_heal])
	if not healed_names.is_empty():
		_log(_format_text("BATTLE_LOG_POST_BATTLE_HEAL", {"healed": "，".join(healed_names)}))


func _skill_cd(actor: Dictionary, skill: Dictionary) -> int:
	# 查询某角色某技能当前 CD。
	return int(actor.get("skill_cooldowns", {}).get(skill["card_id"], 0))


func _skill_cost(skill: Dictionary) -> int:
	# 技能能量消耗。低士气惩罚会让所有技能 +1 能量。
	return int(skill["energy_cost"]) + (1 if morale < 40 else 0)


func _effective_speed(unit: Dictionary) -> int:
	# 当前速度 = 基础速度 + 士气修正 + 状态修正。
	var speed := int(unit["speed"])
	if unit["team"] == "ally":
		if morale >= 80:
			speed += 2
		elif morale < 40:
			speed -= 2
	for status in unit.get("status_effects", []):
		if status["stat"] == "speed":
			speed += int(status["value"])
	speed -= _get_status_layers(unit, "cold")
	return speed


func _damage_reduction(unit: Dictionary) -> int:
	# 统计减伤状态，给一个上限避免数值变成负伤害。
	var reduction := 0
	for status in unit.get("status_effects", []):
		if status["stat"] == "damage_reduction":
			reduction += int(status["value"])
	return min(reduction, 80)


func _consume_next_damage_multiplier(unit: Dictionary) -> float:
	var multiplier := 1.0
	var remaining := []
	for status in unit.get("status_effects", []):
		if str(status.get("stat", "")) == "next_damage_reduction":
			multiplier *= 1.0 - float(status.get("value", 0)) / 100.0
		else:
			remaining.append(status)
	unit["status_effects"] = remaining
	return multiplier


func _change_morale(delta: int, reason: String) -> void:
	# 修改士气并写入战斗日志。
	var before := morale
	morale = clamp(morale + delta, 0, 100)
	if delta != 0:
		_log(_format_text("BATTLE_LOG_MORALE_CHANGE", {
			"reason": reason,
			"delta": _signed_int(delta),
			"before": before,
			"after": morale
		}))


func _morale_text() -> String:
	# 士气区间说明，显示在右侧状态区。
	if morale >= 80:
		return _text("BATTLE_UI_MORALE_HIGH")
	if morale < 40:
		return _text("BATTLE_UI_MORALE_LOW")
	return _text("BATTLE_UI_MORALE_NORMAL")


func _log(text: String) -> void:
	# 战斗日志保留较多历史记录，并交给 RichTextLabel 的滚动条查看。
	battle_log.append(text)
	while battle_log.size() > 80:
		battle_log.remove_at(0)


func _show_unit_info(unit: Dictionary) -> void:
	# 鼠标悬停单位时显示当前属性、状态和敌方行动说明。
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]%s[/b]" % unit["name"])
	if str(unit.get("team", "")) == "enemy":
		lines.append(_format_text("BATTLE_UI_FIELD_TYPE", {"value": _enemy_role_name(str(unit.get("role", "")))}))
	else:
		lines.append(_format_text("BATTLE_UI_FIELD_PROFESSION", {"value": unit.get("profession_name", _text("BATTLE_UI_DEFAULT_PROFESSION"))}))
	lines.append(_format_text("BATTLE_UI_FIELD_HP", {"hp": unit["hp"], "max_hp": unit["max_hp"]}))
	lines.append(_format_text("BATTLE_UI_FIELD_SHIELD", {"value": unit["shield"]}))
	lines.append(_format_text("BATTLE_UI_FIELD_STRENGTH", {"value": unit["strength"]}))
	lines.append(_format_text("BATTLE_UI_FIELD_WILL", {"value": unit.get("will", 0)}))
	lines.append(_format_text("BATTLE_UI_FIELD_SPEED", {"base": unit["speed"], "current": _effective_speed(unit)}))
	if str(unit.get("team", "")) == "enemy":
		lines.append("")
		lines.append(_text("BATTLE_UI_ATTACK_SECTION"))
		lines.append(str(unit.get("attack_desc", _text("BATTLE_ATTACK_DEFAULT"))))
		lines.append(_text("BATTLE_UI_TRAIT_SECTION"))
		lines.append(str(unit.get("trait_desc", _text("BATTLE_TRAIT_DEFAULT"))))
	lines.append("")
	lines.append(_text("BATTLE_UI_STATUS_SECTION"))
	lines.append(_status_text(unit))
	_show_info_popup("\n".join(lines))


func _enemy_role_name(role: String) -> String:
	match role:
		"bruiser":
			return _text("BATTLE_ROLE_BRUISER")
		"guard":
			return _text("BATTLE_ROLE_GUARD")
		"archer":
			return _text("BATTLE_ROLE_ARCHER")
		"healer":
			return _text("BATTLE_ROLE_HEALER")
		"bomber":
			return _text("BATTLE_ROLE_BOMBER")
		"demoralizer":
			return _text("BATTLE_ROLE_DEMORALIZER")
		"assassin":
			return _text("BATTLE_ROLE_ASSASSIN")
		"captain":
			return _text("BATTLE_ROLE_CAPTAIN")
		"shaman":
			return _text("BATTLE_ROLE_SHAMAN")
		"leader":
			return _text("BATTLE_ROLE_LEADER")
	return role


func _show_skill_info(actor: Dictionary, skill: Dictionary) -> void:
	# 鼠标悬停技能按钮时显示技能消耗、目标和构筑生成效果。
	var lines := PackedStringArray()
	lines.append("[b]%s[/b]" % skill["name"])
	lines.append(_format_text("BATTLE_UI_SKILL_CARRIER", {"name": actor["name"]}))
	lines.append(_format_text("BATTLE_UI_SKILL_ENERGY", {"value": _skill_cost(skill)}))
	lines.append(_format_text("BATTLE_UI_SKILL_CD", {"value": _skill_cd(actor, skill)}))
	lines.append(_format_text("BATTLE_UI_SKILL_TARGET", {"target": skill["target"]}))
	lines.append(_format_text("BATTLE_UI_SKILL_EFFECT", {"effect": BattleRuntime.skill_effect_summary(skill)}))
	if not skill["triggered_specials"].is_empty():
		lines.append(_format_text("BATTLE_UI_SKILL_SPECIALS", {"specials": "；".join(skill["triggered_specials"])}))
	_show_info_popup("\n".join(lines))


func _show_info_popup(text: String) -> void:
	# 在鼠标旁显示悬浮信息面板。
	info_label.text = text
	info_popup.visible = true
	info_popup.position = get_local_mouse_position() + Vector2(18, 18)


func _hide_info_popup() -> void:
	# 鼠标移出时隐藏悬浮信息面板。
	info_popup.visible = false


func _status_summary_text(unit: Dictionary) -> String:
	# 棋盘格只显示状态名和层数/回合数，完整效果说明留给悬浮面板。
	var parts := PackedStringArray()
	for status_id in _layered_statuses(unit).keys():
		var id_text := str(status_id)
		var layers: int = int(_layered_statuses(unit)[status_id])
		parts.append(_format_text("BATTLE_UI_STATUS_SUMMARY_LAYER", {"name": _status_display_name(id_text), "layers": layers}))
	for status in unit.get("status_effects", []):
		var status_name: String = _status_effect_display_name(status)
		if str(status.get("stat", "")) == "next_damage_reduction":
			parts.append(_format_text("BATTLE_UI_STATUS_SUMMARY_LAYER", {"name": status_name, "layers": 1}))
		else:
			parts.append(_format_text("BATTLE_UI_STATUS_SUMMARY_LAYER", {"name": status_name, "layers": int(status.get("turns", 0))}))
	return "，".join(parts) if not parts.is_empty() else _text("BATTLE_UI_NONE")


func _status_text(unit: Dictionary) -> String:
	# 把状态数组转换成带效果说明的多行文字，用于悬浮面板。
	var parts := PackedStringArray()
	for status_id in _layered_statuses(unit).keys():
		var id_text := str(status_id)
		var layers: int = int(_layered_statuses(unit)[status_id])
		parts.append(_format_text("BATTLE_UI_STATUS_DETAIL_LAYER", {
			"name": _status_display_name(id_text),
			"layers": layers,
			"effect": _layered_status_effect_text(id_text, layers)
		}))
	for status in unit.get("status_effects", []):
		var status_name: String = _status_effect_display_name(status)
		if str(status.get("stat", "")) == "next_damage_reduction":
			parts.append(_format_text("BATTLE_UI_STATUS_NEXT_DAMAGE", {"name": status_name, "value": int(status.get("value", 0))}))
		else:
			parts.append(_format_text("BATTLE_UI_STATUS_TIMED", {
				"name": status_name,
				"turns": int(status.get("turns", 0)),
				"effect": _timed_status_effect_text(status)
			}))
	if unit.get("team", "") == "ally" and int(unit.get("injury_marks", 0)) > 0:
		parts.append(_format_text("BATTLE_UI_STATUS_INJURY_DETAIL", {"marks": int(unit["injury_marks"])}))
	return "\n".join(parts) if not parts.is_empty() else _text("BATTLE_UI_NONE")


func _layered_status_effect_text(status_id: String, layers: int) -> String:
	match status_id:
		"freeze":
			return _text("BATTLE_UI_LAYERED_FREEZE")
		"vulnerable":
			var bonus: int = int(round((0.25 + float(max(layers - 1, 0)) * 0.05) * 100.0))
			return _format_text("BATTLE_UI_LAYERED_VULNERABLE", {"value": bonus})
		"weak":
			var reduction: int = mini(20 + max(layers - 1, 0) * 5, 65)
			return _format_text("BATTLE_UI_LAYERED_WEAK", {"value": reduction})
		"burn":
			return _format_text("BATTLE_UI_LAYERED_BURN", {"layers": layers})
		"cold":
			return _format_text("BATTLE_UI_LAYERED_COLD", {"layers": layers})
	return _text("BATTLE_UI_LAYERED_DEFAULT")


func _timed_status_effect_text(status: Dictionary) -> String:
	var stat: String = str(status.get("stat", ""))
	var value: int = int(status.get("value", 0))
	match stat:
		"speed":
			return _format_text("BATTLE_UI_TIMED_SPEED", {"value": _signed_int(value), "turns": int(status.get("turns", 0))})
		"damage_reduction":
			return _format_text("BATTLE_UI_TIMED_REDUCTION", {"value": value, "turns": int(status.get("turns", 0))})
	return _format_text("BATTLE_UI_TIMED_DEFAULT", {"turns": int(status.get("turns", 0))})


func _status_effect_display_name(status: Dictionary) -> String:
	if status.has("name_key"):
		return _text(str(status["name_key"]))
	match _status_effect_id(status):
		"defend":
			return _text("BATTLE_STATUS_DEFEND")
		"haste":
			return _text("BATTLE_STATUS_HASTE")
		"sturdy":
			return _text("BATTLE_STATUS_STURDY")
		"war_drum":
			return _text("BATTLE_STATUS_DRUM")
	return str(status.get("name", _text("BATTLE_UI_STATUS_DEFAULT")))


func _status_effect_id(status: Dictionary) -> String:
	if status.has("id"):
		return str(status["id"])
	var legacy_name := str(status.get("name", ""))
	if legacy_name == _text("BATTLE_STATUS_DEFEND"):
		return "defend"
	if legacy_name == _text("BATTLE_STATUS_HASTE"):
		return "haste"
	if legacy_name == _text("BATTLE_STATUS_STURDY"):
		return "sturdy"
	if legacy_name == _text("BATTLE_STATUS_DRUM"):
		return "war_drum"
	return str(status.get("name", ""))


func _style_scene() -> void:
	# 初始化静态 UI 文案、颜色、面板样式。
	# 战斗内隐藏返回准备按钮，避免进入战斗后破坏流程。
	%TitleLabel.add_theme_font_size_override("font_size", 36)
	%SubtitleLabel.add_theme_font_size_override("font_size", 18)
	%TitleLabel.add_theme_color_override("font_color", Color("f6f7fb"))
	%SubtitleLabel.add_theme_color_override("font_color", Color("97a3b6"))
	for panel in [%AllyPanel, %EnemyPanel, %OrderPanel, %LogPanel]:
		panel.add_theme_stylebox_override("panel", _panel_style())
	for label in [order_label, log_label]:
		label.bbcode_enabled = true
		label.fit_content = label != log_label
		label.scroll_active = label == log_label
		label.scroll_following = label == log_label
		label.add_theme_font_size_override("normal_font_size", 16)
		label.add_theme_color_override("default_color", Color("dce5f4"))
	back_button.visible = false
	for button in [next_action_button]:
		_style_button(button)
	_create_info_popup()


func _apply_static_texts() -> void:
	%TitleLabel.text = _text("UI_BATTLE_TITLE")
	%SubtitleLabel.text = _text("UI_BATTLE_SUBTITLE")
	next_action_button.text = _text("UI_NEXT_ACTION")
	back_button.text = _text("UI_RETURN_TO_SKILL_SANDBOX")


func _create_info_popup() -> void:
	# 动态创建悬浮信息面板，避免手动维护 tscn 节点。
	info_popup = PanelContainer.new()
	info_popup.visible = false
	info_popup.z_index = 40
	info_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_popup.custom_minimum_size = Vector2(280, 0)
	info_popup.add_theme_stylebox_override("panel", _info_panel_style())
	add_child(info_popup)
	info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.fit_content = true
	info_label.scroll_active = false
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_label.custom_minimum_size = Vector2(260, 0)
	info_label.add_theme_font_size_override("normal_font_size", 16)
	info_label.add_theme_color_override("default_color", Color("e7edf7"))
	info_popup.add_child(info_label)


func _panel_style() -> StyleBoxFlat:
	# 通用面板样式。
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1b2029")
	style.border_color = Color("2a3342")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18
	style.content_margin_top = 18
	style.content_margin_right = 18
	style.content_margin_bottom = 18
	return style


func _info_panel_style() -> StyleBoxFlat:
	# 悬浮信息面板样式。
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111722")
	style.border_color = Color("5f7594")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_top = 10
	style.content_margin_right = 10
	style.content_margin_bottom = 10
	return style


func _cell_style(has_unit: bool, is_ally: bool, highlighted: bool = false) -> StyleBoxFlat:
	# 棋盘格样式。
	# 注意：目标选择时只改边框，不改已有单位底色，避免盖住名字和血量。
	var style := StyleBoxFlat.new()
	style.bg_color = Color("203044") if has_unit and is_ally else Color("242d39") if has_unit else Color("171c24")
	if highlighted and not has_unit:
		style.bg_color = Color("254d35") if is_ally else Color("171c24")
	style.border_color = Color("72d695") if highlighted and is_ally else Color("ff8fa3") if highlighted else Color("4d6a8d") if is_ally else Color("8a4652")
	style.set_border_width_all(2 if highlighted else 1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_top = 10
	style.content_margin_right = 10
	style.content_margin_bottom = 10
	return style


func _apply_button_cell_style(button: Button, style: StyleBoxFlat) -> void:
	# 可点击棋盘格本质是 Button，这里把它伪装成普通格子的视觉。
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_color_override("font_color", Color("dce5f4"))


func _style_button(button: Button) -> void:
	# 底部动作按钮统一样式。
	button.add_theme_font_size_override("font_size", 16)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("2e6ee6")
	style.border_color = Color("568df0")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_top = 11
	style.content_margin_right = 14
	style.content_margin_bottom = 11
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("disabled", style)
	button.add_theme_color_override("font_color", Color("eff3fb"))
	button.add_theme_color_override("font_disabled_color", Color("8a93a3"))


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


func _row_name(row: int) -> String:
	if row < 0 or row >= ROW_NAME_KEYS.size():
		return str(row)
	return _text(ROW_NAME_KEYS[row])


func _signed_int(value: int) -> String:
	if value > 0:
		return "+%d" % value
	return str(value)
