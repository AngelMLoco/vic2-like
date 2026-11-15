class_name VJson
extends RefCounted
## Utilidades de lectura de datos JSON (modo Victoria).


static func load_any(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("VJson: no existe %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("VJson: error en %s línea %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


static func load_dict(path: String) -> Dictionary:
	var d = load_any(path)
	return d if d is Dictionary else {}


static func load_array(path: String, key: String = "") -> Array:
	var d = load_any(path)
	if d is Array:
		return d
	if d is Dictionary and key != "" and d.get(key) is Array:
		return d[key]
	return []
