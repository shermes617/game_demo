extends Control
class_name BattleUnitView

@onready var portrait_rect: TextureRect = %PortraitRect
@onready var portrait_background: PanelContainer = %PortraitBackground
@onready var hp_label: Label = %HpLabel
@onready var hp_badge: PanelContainer = %HpBadge

var pending_unit: Dictionary = {}
var pending_is_ally := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not pending_unit.is_empty():
		_apply_unit(pending_unit, pending_is_ally)


func bind_unit(unit: Dictionary, is_ally: bool) -> void:
	pending_unit = unit
	pending_is_ally = is_ally
	if not is_node_ready():
		return
	_apply_unit(unit, is_ally)


func _apply_unit(unit: Dictionary, is_ally: bool) -> void:
	var portrait = unit.get("portrait", null)
	if portrait is Texture2D:
		portrait_rect.texture = portrait
	elif not str(unit.get("portrait_path", "")).is_empty():
		portrait_rect.texture = load(str(unit.get("portrait_path", "")))
	else:
		portrait_rect.texture = null
	hp_label.text = "%d/%d" % [int(unit.get("hp", 0)), int(unit.get("max_hp", 0))]
	_apply_team_style(is_ally)


func _apply_team_style(is_ally: bool) -> void:
	var portrait_style := StyleBoxFlat.new()
	portrait_style.bg_color = Color("162638") if is_ally else Color("2a1820")
	portrait_style.border_color = Color("315276") if is_ally else Color("743246")
	portrait_style.border_width_left = 1
	portrait_style.border_width_top = 1
	portrait_style.border_width_right = 1
	portrait_style.border_width_bottom = 1
	portrait_style.corner_radius_top_left = 3
	portrait_style.corner_radius_top_right = 3
	portrait_style.corner_radius_bottom_left = 3
	portrait_style.corner_radius_bottom_right = 3
	portrait_background.add_theme_stylebox_override("panel", portrait_style)

	var style := StyleBoxFlat.new()
	style.bg_color = Color("1f6b42") if is_ally else Color("782b3a")
	style.border_color = Color("85d69f") if is_ally else Color("e26f83")
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	hp_badge.add_theme_stylebox_override("panel", style)
