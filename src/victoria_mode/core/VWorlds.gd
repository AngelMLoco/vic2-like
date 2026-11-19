class_name VWorlds
extends RefCounted
## M6: mundos (datasets) y escenarios.
##
##   MUNDO     geografía (mapa, provincias, estados, zonas marítimas), países, culturas, religiones, historia
##             y metadatos. Vive en data/victoria_mode/worlds/<id>/ (world_root) y se registra en
##             worlds/worlds.json.
##   ESCENARIO mundo + fecha + historia + paquetes de contenido + era (scenarios/scenarios.json).
##
## Tres raíces:
##   base_root    res://data/victoria_mode/     reglas compartidas (economía, POPs, gobiernos, ideologías,
##                                               bienes, fábricas, tecnologías, ejército, guerra, terreno…)
##   world_root   base_root + worlds/<id>/      datos del mundo; también puede SOBRESCRIBIR un archivo
##                                               compartido con la misma ruta relativa (p. ej. goods/goods.json)
##   content_root base_root                     paquetes de contenido (content/<pack>/), compartidos
##
## Los archivos de WORLD_FILES salen siempre del mundo, sin respaldo en base_root: un mundo nunca hereda el
## mapa, los países, las culturas ni las religiones de otro.

const BASE_ROOT := "res://data/victoria_mode/"
const CONTENT_ROOT := BASE_ROOT
const REGISTRY := "worlds/worlds.json"
const SCENARIOS := "scenarios/scenarios.json"
const DEFAULT_WORLD := "prototype_earth"

## Archivos obligatorios de un mundo (rutas relativas a world_root).
const WORLD_FILES := [
	"world.json",
	"map/map.json", "map/geometry.json", "map/adjacencies.json", "map/provinces.png",
	"provinces/provinces.json", "provinces/sea_zones.json", "states/states.json",
	"countries/countries.json", "cultures/cultures.json", "religions/religions.json",
]


## Registro: [{id, root, …world.json}] en el orden declarado.
static func list_worlds() -> Array:
	var out: Array = []
	for w in VJson.load_dict(BASE_ROOT + REGISTRY).get("worlds", []):
		out.append(world_meta(String(w.get("id", ""))))
	return out


## Metadatos de un mundo: entrada del registro + worlds/<id>/world.json. {} si no está registrado.
static func world_meta(world_id: String) -> Dictionary:
	for w in VJson.load_dict(BASE_ROOT + REGISTRY).get("worlds", []):
		if String(w.get("id", "")) != world_id:
			continue
		var root: String = BASE_ROOT + String(w.get("root", "worlds/%s/" % world_id))
		if not root.ends_with("/"):
			root += "/"
		var meta := {}
		if FileAccess.file_exists(root + "world.json"):
			meta = VJson.load_dict(root + "world.json").duplicate(true)
		for k in w:
			if not meta.has(k):
				meta[k] = w[k]
		meta["id"] = world_id
		meta["root_path"] = root
		return meta
	return {}


static func root_of(world_id: String) -> String:
	return String(world_meta(world_id).get("root_path", ""))


## Todos los escenarios declarados (sin filtrar).
static func list_scenarios() -> Array:
	return VJson.load_dict(BASE_ROOT + SCENARIOS).get("scenarios", [])


static func default_scenario_id() -> String:
	return String(VJson.load_dict(BASE_ROOT + SCENARIOS).get("default", ""))


static func scenario(scenario_id: String) -> Dictionary:
	for sc in list_scenarios():
		if String(sc.get("id", "")) == scenario_id:
			return sc
	return {}


## Mundo de un escenario: el declarado; los escenarios anteriores a M6 no lo declaran y son del prototipo.
static func world_of(sc: Dictionary) -> String:
	return String(sc.get("world", DEFAULT_WORLD))


## Motivo por el que un mundo no se puede jugar ("" = disponible). Barato: no carga la geometría.
static func world_problem(meta: Dictionary) -> String:
	if meta.is_empty():
		return "mundo no registrado"
	if not bool(meta.get("enabled", true)):
		return "mundo en desarrollo (%s)" % String(meta.get("status", "disabled"))
	var root: String = meta.get("root_path", "")
	for f in WORLD_FILES:
		if not FileAccess.file_exists(root + f):
			return "falta %s" % f
	return ""


## Motivo por el que un escenario no se puede jugar ("" = disponible).
static func scenario_problem(sc: Dictionary) -> String:
	if sc.is_empty():
		return "escenario desconocido"
	if not bool(sc.get("enabled", true)):
		return "escenario en desarrollo"
	var meta := world_meta(world_of(sc))
	var wp := world_problem(meta)
	if wp != "":
		return wp
	for p in sc.get("content_packs", []):
		if String(p) in meta.get("forbidden_packs", []):
			return "el mundo %s no admite el paquete «%s»" % [meta["id"], p]
	var hist := String(sc.get("history", ""))
	if hist == "" or not FileAccess.file_exists(String(meta["root_path"]) + hist):
		return "falta la historia %s" % hist
	return ""


## Escenarios que el jugador puede elegir: habilitados, con mundo válido y no marcados como de prueba.
static func playable_scenarios(include_test: bool = false) -> Array:
	var out: Array = []
	for sc in list_scenarios():
		if bool(sc.get("test_only", false)) and not include_test:
			continue
		var meta := world_meta(world_of(sc))
		if bool(meta.get("test_only", false)) and not include_test:
			continue
		if scenario_problem(sc) == "":
			out.append(sc)
	return out


## Ruta de un archivo propio del mundo (sin respaldo).
static func world_file(gs: VGameState, rel: String) -> String:
	return gs.world_root + rel


## Ruta de un archivo compartido: la del mundo si la sobrescribe, si no la común.
static func data_path(gs: VGameState, rel: String) -> String:
	if gs.world_root != "" and FileAccess.file_exists(gs.world_root + rel):
		return gs.world_root + rel
	return gs.base_root + rel


## Ruta del mapa de IDs del mundo por defecto (fondo del menú principal).
static func default_map_texture() -> String:
	var sc := scenario(default_scenario_id())
	return root_of(world_of(sc)) + "map/provinces.png"
