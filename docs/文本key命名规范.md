# 文本 key 命名规范

更新时间：2026-06-05

本文档用于规范 `res://localization/localization.csv` 中显示文本 key 的命名、分类、复用和废弃流程。新增显示文本前应先阅读本文档。

## 1. 总原则

- 所有显示文本必须放在 `res://localization/localization.csv`。
- `.gd`、`.tscn`、`.json` 中只保留文本 key，不直接写显示文本。
- key 使用全大写英文和下划线，格式为 `PREFIX_DOMAIN_PURPOSE`。
- 新增 key 必须有清晰归属，不为了省事放进 `UI_*`。
- 旧 key 保持兼容，非必要不批量重命名，避免引入大范围回归风险。

## 2. 前缀职责

### `UI_*`

跨场景通用 UI 文本。

适合：
- `UI_BACK`
- `UI_CONFIRM`
- `UI_CANCEL`

不建议新增长场景专用标题，例如 `UI_BATTLE_TITLE`。已有旧 key 可以暂时保留。

### `BUILD_*`

技能构筑页专用文本。

适合：
- `BUILD_PREVIEW_DAMAGE`
- `BUILD_STATUS_READY`
- `BUILD_MODULE_PREVIEW`

### `PREP_*`

战斗准备页专用文本。

适合：
- `PREP_WARNING_EMPTY_SKILL`
- `PREP_READY_STATUS`

### `MAP_*`

探索地图、商店、宝箱、火堆相关文本。

适合：
- `MAP_SHOP_BUY_SUCCESS`
- `MAP_NODE_BOSS`

### `BATTLE_*`

战斗系统相关文本。新增战斗文本必须优先使用更细的子域：

- `BATTLE_UI_*`：战斗界面面板、资源、队列、悬浮信息。
- `BATTLE_ACTION_*`：战斗操作按钮。
- `BATTLE_LOG_*`：战斗日志句子。
- `BATTLE_REASON_*`：日志中的原因短语。
- `BATTLE_ATTACK_*`：敌人攻击方式说明。
- `BATTLE_TRAIT_*`：敌人特殊特性说明。
- `BATTLE_ROLE_*`：角色或敌人在战斗内的职责标签。
- `BATTLE_STATUS_*`：战斗状态显示文本。

### `RUNTIME_*`

跨构筑、准备、战斗复用的运行时摘要文本。

适合：
- `RUNTIME_SUMMARY_DAMAGE`
- `RUNTIME_NO_EFFECT`

### 数据对象前缀

以下前缀用于静态数据对象：

- `SKILL_*`：技能卡名称、目标、摘要。
- `MODULE_*`：模组名称、短标签、描述。
- `CHARACTER_*`：角色名称、职业、定位。
- `ENEMY_*`：敌人名称。
- `ENCOUNTER_*`：遭遇名称。
- `RELIC_*`：遗物名称和描述。
- `STATUS_*`：通用状态名称。
- `SPECIAL_*`：技能卡特殊格显示文本。
- `ERROR_*`：错误提示或加载失败信息。

## 3. 后缀规则

- `_NAME`：对象名称，例如技能、模组、敌人、遗物。
- `_DESC`：对象描述。
- `_SHORT`：短标签或格子内短名。
- `_TITLE`：页面或区域标题。
- `_SUBTITLE`：页面副标题。
- `_LABEL`：字段标签、短说明。
- `_HINT`：操作提示。
- `_BUTTON`：按钮文本。已有 `BATTLE_ACTION_*` 可继续保留。
- `_SUMMARY`：简短摘要。
- `_LINE`：列表行模板。
- `_WARNING_*`：警告提示。
- `_EMPTY_*`：空状态文本。
- `_SUCCESS` / `_FAILED`：结果状态。

`BATTLE_LOG_*` 应表示完整日志句子；`BATTLE_REASON_*` 应表示原因短语，不单独作为完整句子使用。

## 4. 通用文本与场景专用文本

新增 key 时按以下规则判断：

- 多个场景都会用：放 `UI_*`。
- 只属于构筑页：放 `BUILD_*`。
- 只属于地图页：放 `MAP_*`。
- 只属于战斗页：放 `BATTLE_UI_*`、`BATTLE_ACTION_*` 或 `BATTLE_LOG_*`。
- 只属于准备页：放 `PREP_*`。
- 来自数据对象：放 `SKILL_*`、`MODULE_*`、`CHARACTER_*`、`ENEMY_*`、`RELIC_*` 等。

已有 `UI_SKILL_BUILD_TITLE`、`UI_BATTLE_TITLE`、`UI_MAP_TITLE` 可暂时保留。后续如果重命名，必须单独计划、批量替换、跑完整扫描。

## 5. 英文列策略

- 新增 key 必须同时填写 `zh` 和 `en`。
- 旧 key 的 `en` 可暂时为空，不作为当前阻塞项。
- 如果某次任务修改了旧 key，顺手补齐该 key 的英文列。
- 不为补英文而进行大规模无功能变更，避免污染 diff。
- `en` 暂缺时，`TextDatabase` 继续以中文为主语言，不影响当前 Demo。

## 6. 未引用 key 处理流程

发现未引用 key 时不要直接删除，先分类：

- 明确废弃：列入候选删除清单，等确认后删除。
- 未来预留：保留，并在清单中说明用途。
- 可能漏用：优先检查代码或场景是否应该使用该 key。

当前候选：

- `UI_BACK`：通用返回文本，建议保留。
- `MODULE_TAG_LIMITED`：可能用于“限1”标签，建议暂时保留，等模组列表组件化时再判断是否接入或删除。

## 7. 缺失 key 处理流程

如果扫描发现“引用了但未定义”的 key：

- 优先补 `localization.csv`。
- 不要在代码里 fallback 成中文硬编码。
- 补 key 后扫描确认缺失数量为 0。
- 如果是拼写错误，修改引用处，不新增错误 key。

## 8. 重命名原则

不为了命名整齐批量重命名已稳定 key。

只有在以下情况才重命名：

- key 语义明显错误。
- key 所属场景或模块已经迁移。
- 重命名能减少长期维护混乱。

重命名必须：

- 先输出计划。
- 同时修改 `localization.csv` 和全部引用。
- 扫描确认旧 key 无残留、新 key 无缺失。
- 跑 Godot MCP `detect_broken_scripts`。
