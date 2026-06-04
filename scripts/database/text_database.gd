extends Node

const LOCALIZATION_PATH := "res://localization/localization.csv"
const DEFAULT_LANGUAGE := "zh"
const FALLBACK_LANGUAGE := "en"

var _texts: Dictionary = {}
var _languages: PackedStringArray = []
var _loaded := false


func _ready() -> void:
	ensure_loaded()


func ensure_loaded() -> void:
	if _loaded:
		return
	load_texts()


func load_texts() -> void:
	_texts.clear()
	_languages.clear()

	var file := FileAccess.open(LOCALIZATION_PATH, FileAccess.READ)
	if file == null:
		push_error("Failed to open localization file: %s" % LOCALIZATION_PATH)
		_loaded = true
		return

	if file.eof_reached():
		_loaded = true
		return

	var header := file.get_csv_line()
	if header.size() < 2 or header[0] != "key":
		push_error("Invalid localization header in %s" % LOCALIZATION_PATH)
		_loaded = true
		return

	for index in range(1, header.size()):
		var language := String(header[index]).strip_edges()
		if not language.is_empty():
			_languages.append(language)

	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.is_empty():
			continue

		var key := String(row[0]).strip_edges()
		if key.is_empty():
			continue

		var entry: Dictionary = {}
		for language_index in range(_languages.size()):
			var row_index := language_index + 1
			var value := ""
			if row_index < row.size():
				value = _decode_text_value(String(row[row_index]))
			entry[_languages[language_index]] = value
		_texts[key] = entry

	_loaded = true


func get_text(key: String, language: String = "", fallback: String = "") -> String:
	ensure_loaded()

	if not _texts.has(key):
		if not fallback.is_empty():
			return fallback
		return key

	var entry: Dictionary = _texts[key]
	var resolved_language := _resolve_language(language)
	if entry.has(resolved_language) and not String(entry[resolved_language]).is_empty():
		return String(entry[resolved_language])

	if entry.has(DEFAULT_LANGUAGE) and not String(entry[DEFAULT_LANGUAGE]).is_empty():
		return String(entry[DEFAULT_LANGUAGE])

	if entry.has(FALLBACK_LANGUAGE) and not String(entry[FALLBACK_LANGUAGE]).is_empty():
		return String(entry[FALLBACK_LANGUAGE])

	if not fallback.is_empty():
		return fallback
	return key


func format_text(key: String, params: Dictionary = {}, language: String = "", fallback: String = "") -> String:
	var text := get_text(key, language, fallback)
	for param_key in params.keys():
		text = text.replace("{%s}" % String(param_key), str(params[param_key]))
	return text


func has_text(key: String) -> bool:
	ensure_loaded()
	return _texts.has(key)


func available_languages() -> PackedStringArray:
	ensure_loaded()
	return _languages.duplicate()


func _resolve_language(language: String) -> String:
	if not language.is_empty():
		return language

	var locale := TranslationServer.get_locale()
	if locale.is_empty():
		return DEFAULT_LANGUAGE

	var normalized := locale.replace("-", "_")
	return normalized.get_slice("_", 0)


func _decode_text_value(value: String) -> String:
	return value.replace("\\n", "\n").replace("\\t", "\t")
