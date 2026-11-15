class_name VLoreLoader
extends RefCounted
## Biblia de lore (content/<paquete>/lore/*.json): datos de mundo que el contenido narrativo y las herramientas
## pueden consultar (gs.lore), validados contra un esquema mínimo. NO intervienen en la simulación: el estado
## jugable (países, culturas, religiones, historia inicial) sigue saliendo de sus JSON propios y del escenario.
## Esquema completo y ejemplos: docs/LoreBibleSchema.md; plantillas vacías en content/fantasy/lore/_templates/.
##
## Archivo: {"lore_type": <tipo>, "entries": [{...}]}. Tipos y campos obligatorios:

const SCHEMA := {
	"world": ["id", "name"],
	"era": ["id", "name", "start_year"],
	"calendar": ["id", "name", "months"],
	"continent": ["id", "name"],
	"region": ["id", "name", "continent"],
	"country": ["id", "name", "origin"],
	"magic": ["id", "name", "rules"],
	"magic_institution": ["id", "name", "kind"],
	"religion": ["id", "name", "magic_attitude"],
	"culture": ["id", "name", "group"],
	"conflict": ["id", "name", "sides"],
	"event_chain": ["id", "name", "stages"],
	"character": ["id", "name"],
	"dynasty": ["id", "name"],
}
const MAGIC_ATTITUDES := ["sacred", "accepted", "regulated", "suspicious", "heretical"]


static func load_all(gs: VGameState, root: String) -> void:
	gs.lore = {}
	for path in VContentPacks.files(gs, root, "lore/"):
		var where: String = VContentPacks.pack_of(path) + "/lore/" + path.get_file()
		var d := VJson.load_dict(path)
		var lt: String = d.get("lore_type", "")
		if not SCHEMA.has(lt):
			gs.data_errors.append("%s: lore_type desconocido «%s»" % [where, lt])
			continue
		if not gs.lore.has(lt):
			gs.lore[lt] = {}
		for e in d.get("entries", []):
			for req in SCHEMA[lt]:
				if not e.has(req):
					gs.data_errors.append("%s: entrada «%s» sin el campo obligatorio «%s»" % [where, e.get("id", "?"), req])
			var id: String = e.get("id", "")
			if gs.lore[lt].has(id):
				gs.data_errors.append("%s: id de lore duplicado «%s»" % [where, id])
			if lt == "religion" and not (String(e.get("magic_attitude", "")) in MAGIC_ATTITUDES):
				gs.data_errors.append("%s: magic_attitude no válida en «%s»" % [where, id])
			gs.lore[lt][id] = e


static func entries(gs: VGameState, lore_type: String) -> Dictionary:
	return gs.lore.get(lore_type, {})
