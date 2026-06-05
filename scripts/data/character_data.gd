extends Resource
class_name CharacterData

@export var id: String = ""
@export var name_key: String = ""
@export var profession: String = ""
@export var profession_name_key: String = ""
@export var role_key: String = ""
@export var allowed_card_slots: int = 1
@export var strength: int = 0
@export var max_hp: int = 1
@export var will: int = 0
@export var speed: int = 0
@export var portrait: Texture2D


func apply_to_character_dict(character: Dictionary) -> void:
	if not name_key.is_empty():
		character["name_key"] = name_key
	if not profession.is_empty():
		character["profession"] = profession
	if not profession_name_key.is_empty():
		character["profession_name_key"] = profession_name_key
	if not role_key.is_empty():
		character["role_key"] = role_key
	character["allowed_card_slots"] = allowed_card_slots
	if not character.has("stats") or typeof(character["stats"]) != TYPE_DICTIONARY:
		character["stats"] = {}
	var stats: Dictionary = character["stats"]
	stats["strength"] = strength
	stats["hp"] = max_hp
	stats["will"] = will
	stats["speed"] = speed
	character["stats"] = stats
	character["portrait"] = portrait
	character["portrait_path"] = portrait.resource_path if portrait != null else ""
