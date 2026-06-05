extends PanelContainer
class_name SkillPreviewPanelView

@onready var header_label: Label = $RightVBox/PreviewHeader
@onready var title_label: Label = $RightVBox/RightScroll/RightContent/PreviewTitleLabel
@onready var body_label: RichTextLabel = $RightVBox/RightScroll/RightContent/PreviewBodyLabel
@onready var simulation_label: RichTextLabel = $RightVBox/RightScroll/RightContent/SimulationLabel


func setup_styles() -> void:
	title_label.add_theme_color_override("font_color", Color("edf1f8"))
	title_label.add_theme_font_size_override("font_size", 25)
	body_label.add_theme_font_size_override("normal_font_size", 17)
	simulation_label.add_theme_font_size_override("normal_font_size", 17)
	body_label.scroll_active = false
	simulation_label.scroll_active = false


func set_static_texts(header_text: String, placeholder_text: String) -> void:
	header_label.text = header_text
	title_label.text = placeholder_text
	body_label.text = placeholder_text
	simulation_label.text = ""


func set_preview(title: String, body: String, simulation_message: String) -> void:
	title_label.text = title
	body_label.text = body
	simulation_label.text = simulation_message
