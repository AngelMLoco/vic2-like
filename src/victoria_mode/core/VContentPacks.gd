class_name VContentPacks
extends RefCounted
## Paquetes de contenido (data/victoria_mode/content/). El motor no sabe qué mundo se juega: el escenario
## elige qué paquetes se cargan y en qué orden (scenarios/scenarios.json → "content_packs"), con
## content/packs.json como valor por defecto.
##
##   core/       contenido sistémico reutilizable (eventos core.*, magic.*, decisiones, modificadores, crónica)
##   prototype/  contenido TEMPORAL de la geografía de prueba (Tierra): cadenas country.<tag>.*, ramas mágicas
##   fantasy/    Chronicles of Aether (lore definitivo; vacío hasta que el usuario lo aporte)
##
## Estructura de un paquete (todo opcional):
##   pack.json                 {"id", "name", "description", "enabled", "requires": [paquetes]}
##   events/*.json             {"events": [...]}
##   decisions/*.json          {"decisions": [...]}
##   modifiers.json            {"modifiers": [...]}
##   chronicle.json            plantillas narrativas de la crónica por on_action
##   magic_branches.json       {"branches": {TAG: {rama: nivel | {"level", "paths"}}}}
##   lore/*.json               biblia de lore (ver docs/LoreBibleSchema.md); se valida, no simula
## Un id repetido en un paquete posterior es un error (no se sobrescribe en silencio).

const CONTENT := "content/"


## Paquetes activos en orden de carga.
static func active(gs: VGameState, root: String) -> Array:
	if not gs.content_packs.is_empty():
		return gs.content_packs
	var d := VJson.load_dict(root + CONTENT + "packs.json")
	var out: Array = []
	for p in d.get("load_order", ["core", "prototype"]):
		out.append(String(p))
	gs.content_packs = out
	return out


## Valida los paquetes declarados (existen, requisitos en orden). Devuelve los válidos.
static func validate(gs: VGameState, root: String) -> void:
	var seen := {}
	for p in active(gs, root):
		var path: String = root + CONTENT + p + "/"
		if DirAccess.open(path) == null:
			gs.data_errors.append("paquete de contenido inexistente «%s»" % p)
			continue
		var meta := VJson.load_dict(path + "pack.json") if FileAccess.file_exists(path + "pack.json") else {}
		for req in meta.get("requires", []):
			if not seen.has(req):
				gs.data_errors.append("paquete «%s»: requiere «%s» cargado antes" % [p, req])
		seen[p] = true


## Rutas de los .json de un subdirectorio (events/, decisions/, lore/) en todos los paquetes activos,
## por paquete y en orden alfabético dentro de cada uno.
static func files(gs: VGameState, root: String, subdir: String) -> Array:
	var out: Array = []
	for p in active(gs, root):
		var path: String = root + CONTENT + p + "/" + subdir
		var d := DirAccess.open(path)
		if d == null:
			continue
		var names := []
		for f in d.get_files():
			if f.ends_with(".json"):
				names.append(f)
		names.sort()
		for f in names:
			out.append(path + f)
	return out


## Un archivo concreto en cada paquete activo que lo tenga (modifiers.json, chronicle.json, magic_branches.json).
static func each(gs: VGameState, root: String, file: String) -> Array:
	var out: Array = []
	for p in active(gs, root):
		var path: String = root + CONTENT + p + "/" + file
		if FileAccess.file_exists(path):
			out.append(path)
	return out


## Paquete al que pertenece una ruta (para mensajes de error y estadísticas).
static func pack_of(path: String) -> String:
	var i := path.find(CONTENT)
	if i < 0:
		return ""
	var rest := path.substr(i + CONTENT.length())
	return rest.get_slice("/", 0)
