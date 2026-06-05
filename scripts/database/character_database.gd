extends RefCounted
class_name CharacterDatabase

static var _characters_by_id: Dictionary = {}


static func get_character(character_id: String):
	_ensure_loaded()
	return _characters_by_id.get(character_id, null)


static func has_character(character_id: String) -> bool:
	_ensure_loaded()
	return _characters_by_id.has(character_id)


static func all_character_ids() -> Array:
	_ensure_loaded()
	return _characters_by_id.keys()


static func _ensure_loaded() -> void:
	if not _characters_by_id.is_empty():
		return
	for path in _character_paths():
		var resource := load(path)
		if resource != null and not str(resource.get("id")).is_empty():
			_characters_by_id[str(resource.get("id"))] = resource


static func _character_paths() -> Array:
	var paths: Array = []
	paths.append("res://resources/characters/warrior_a.tres")
	paths.append("res://resources/characters/ranger_a.tres")
	paths.append("res://resources/characters/guardian_a.tres")
	paths.append("res://resources/characters/priest_a.tres")
	return paths
