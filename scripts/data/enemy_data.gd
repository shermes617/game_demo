extends Resource
class_name EnemyData

@export var id: String = ""
@export var name_key: String = ""
@export var role: String = ""
@export var strength: int = 0
@export var max_hp: int = 1
@export var will: int = 0
@export var speed: int = 0
@export var portrait: Texture2D


func to_runtime_dict(col: int, row: int, display_name: String, attack_desc: String, trait_desc: String) -> Dictionary:
	return {
		"enemy_id": id,
		"name_key": name_key,
		"name": display_name,
		"role": role,
		"team": "enemy",
		"col": col,
		"row": row,
		"strength": strength,
		"max_hp": max_hp,
		"hp": max_hp,
		"will": will,
		"speed": speed,
		"portrait": portrait,
		"portrait_path": portrait.resource_path if portrait != null else "",
		"shield": 0,
		"field": true,
		"dead": false,
		"status_effects": [],
		"attack_desc": attack_desc,
		"trait_desc": trait_desc
	}
