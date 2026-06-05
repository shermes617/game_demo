extends RefCounted
class_name EnemyDatabase

static var _enemies_by_id: Dictionary = {}


static func get_enemy(enemy_id: String) -> EnemyData:
	_ensure_loaded()
	return _enemies_by_id.get(enemy_id, null)


static func has_enemy(enemy_id: String) -> bool:
	_ensure_loaded()
	return _enemies_by_id.has(enemy_id)


static func all_enemy_ids() -> Array:
	_ensure_loaded()
	return _enemies_by_id.keys()


static func _ensure_loaded() -> void:
	if not _enemies_by_id.is_empty():
		return
	for path in _enemy_paths():
		var resource := load(path)
		if resource is EnemyData and not resource.id.is_empty():
			_enemies_by_id[resource.id] = resource


static func _enemy_paths() -> Array:
	var paths: Array = []
	paths.append("res://resources/enemies/bandit_bruiser.tres")
	paths.append("res://resources/enemies/bandit_guard.tres")
	paths.append("res://resources/enemies/bandit_archer.tres")
	paths.append("res://resources/enemies/bandit_healer.tres")
	paths.append("res://resources/enemies/oil_bomber.tres")
	paths.append("res://resources/enemies/demoralizer.tres")
	paths.append("res://resources/enemies/elite_guard.tres")
	paths.append("res://resources/enemies/elite_archer.tres")
	paths.append("res://resources/enemies/assassin.tres")
	paths.append("res://resources/enemies/captain.tres")
	paths.append("res://resources/enemies/bandit_leader.tres")
	paths.append("res://resources/enemies/shaman.tres")
	paths.append("res://resources/enemies/summoner.tres")
	return paths
