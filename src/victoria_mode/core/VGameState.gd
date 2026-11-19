class_name VGameState
extends RefCounted
## Estado completo de una partida de la Segunda versión.
##
## Jerarquía:  MUNDO → PAÍS → ESTADO → PROVINCIA → POPs
##  - provinces[id]: provincia terrestre, zona marítima o lago (mismo espacio de ids que el mapa).
##  - states[id]: agrupación geográfica de provincias. Puede estar dividida entre varios países;
##    cada parte (estado, propietario) es una "instancia de estado" con sus propias fábricas.
##  - countries[tag]: nación. Su territorio se deriva de la propiedad (owner) de las provincias.
## La geometría vive en el mapa (PNG + geometry.json); aquí solo hay datos de juego.

signal ownership_changed(province_ids: Array)

const KIND_LAND := "land"
const KIND_SEA := "sea"
const KIND_LAKE := "lake"

var date: VDate = VDate.make(136, 1, 1)
var player_tag: String = ""
var flags := {}  # flags globales (p. ej. GLOBAL_MAGIC_ACTIVATED)

## Mapa
var map_width: int = 0
var map_height: int = 0
var first_sea_id: int = 0
var first_lake_id: int = 0
var max_id: int = 0

## Entidades
var provinces: Array = []  # índice = id; elemento 0 = null
var states := {}  # id -> Dictionary
var countries := {}  # tag -> Dictionary
var country_order: Array[String] = []  # tags en orden estable (índice usado por el mapa)
var adjacencies: Array = []

## Definiciones (datos)
var cultures := {}
var culture_groups := {}
var religions := {}
var goods := {}
var factory_types := {}
var terrain_types := {}
var pop_types := {}
var pop_distribution := {}
var governments := {}
var ideologies := {}
var economy_rules := {}
var promotion_rules: Array = []
var issues := {}  # id -> {id, name, positions[]}
var issue_conditionals: Array = []
var reforms := {}  # id -> {id, name, type, issue, default, levels[]}
var reform_order: Array = []
var reform_meta := {}
var party_templates: Array = []
var technologies := {}
var tech_categories: Array = []
var inventions := {}

## Milestone 3: definiciones militares, diplomáticas y bélicas (datos)
var unit_types := {}
var unit_manpower: int = 3000
var combat_width: int = 12
var ship_types := {}
var leader_traits := {}
var cb_types := {}
var war_rules := {}
var diplo_rules := {}
var rebel_types := {}
var rebel_rules := {}

## Milestone 3: entidades (todas serializables; ids enteros)
var armies := {}  # id -> {id, country, name, province, brigades[], leader, morale, path[], ...}
var brigades := {}  # id -> {id, type, strength, organisation, experience, source_pop_id, source_province_id, army}
var leaders := {}  # id -> {id, country, kind (general/admiral), name, traits[], attack, defence, ...}
var fleets := {}  # id -> {id, country, location, ships[], admiral, transported_armies[], ...}
var wars := {}  # id -> War
var battles := {}  # id -> batalla en curso (terrestre o naval)
var casus_belli: Array = []  # {id, owner, target, type, state_id, expires}
var justifications: Array = []  # {owner, target, type, state_id, progress, discovered}
var rebel_factions := {}  # id -> RebelFaction
var next_ids := {}

## Mercado mundial (ver VMarketSystem): precios, historial, acumuladores y ratios de llenado.
var market := {}
## Contador de meses transcurridos desde el inicio (para ciclos electorales, etc.).
var month_index: int = 0
## Rendimiento: últimas mediciones (ms) — ver VProfiler.
var profile := {}
var perf_counters := {}  # contadores de rendimiento (derivados, no se guardan)
## Índices y cachés derivados (NO se guardan; ver VUnitIndex y VArmySystem.find_path).
var unit_index := {}
var access_version: int = 0
var path_cache := {}
var path_epoch: int = 0
var controller_version: int = 0  # se incrementa con cada cambio de controlador (VWarSystem.set_controller)
var ws_values_month: int = -1  # mes en que se calcularon los valores de warscore por provincia (-1 = recalcular)
var land_component := PackedInt32Array()  # componente conexa terrestre de cada provincia (estático)
var war_cache := {}
## Registro de acontecimientos recientes (promociones, migraciones, elecciones, inventos...).
var log_entries: Array = []

func log_event(tag: String, text: String) -> void:
	log_entries.append({"date": date.short_text(), "tag": tag, "text": text})
	if log_entries.size() > 300:
		log_entries = log_entries.slice(log_entries.size() - 300)


func new_id(kind: String) -> int:
	var n := int(next_ids.get(kind, 1))
	next_ids[kind] = n + 1
	return n


## Relación diplomática entre dos naciones (−200 … +200), simétrica.
func relation(a: String, b: String) -> int:
	return int(countries.get(a, {}).get("relations", {}).get(b, 0))


func set_relation(a: String, b: String, value: int) -> void:
	if not countries.has(a) or not countries.has(b) or a == b:
		return
	value = clampi(value, -200, 200)
	countries[a]["relations"][b] = value
	countries[b]["relations"][a] = value


## Etiqueta de controlador para rebeldes (las provincias ocupadas por rebeldes usan este controlador).
const REBEL_TAG := "REB"


func is_rebel(tag: String) -> bool:
	return tag == REBEL_TAG


func reform_level(tag: String, reform_id: String) -> int:
	return int(countries.get(tag, {}).get("reforms", {}).get(reform_id, 0))


func mod(tag: String, key: String) -> float:
	return float(countries.get(tag, {}).get("mods", {}).get(key, 0.0))


## Instancias de estado: "sid:TAG" -> {state, owner, provinces[], factories[]}
var state_instances := {}

## M4: eventos, decisiones y magia. *_defs/_index/modifiers/magic_rules se cargan de datos (no se guardan);
## event_state se guarda (banderas con ámbito, variables, modificadores temporales, historial, cola…).
var event_defs := {}
var event_index := {}
var event_modifiers := {}
var decision_defs := {}
var magic_rules := {}
var data_errors: Array = []
var event_state := {}
## M5: escenario (bookmark) y paquetes de contenido activos; plantillas de crónica, manifiesto de arte,
## biblia de lore (validada, no simula) y actitudes mágicas de religiones/culturas. Todo de datos, no se guarda
## salvo scenario_id y content_packs (para recargar la misma combinación).
var scenario_id := ""
## M6: mundo (dataset de geografía, países, culturas y religiones) que usa el escenario. world_root es la
## carpeta del mundo; base_root, la de las reglas compartidas. Se guarda world_id y map_version.
var world_id := ""
var world := {}
var world_root := ""
var base_root := ""
var map_version := 0
var wrap_x := false
var scenario := {}
var content_packs: Array = []
var chronicle_templates := {}
var art_manifest := {}
var lore := {}
## POPs: almacén en estructura de arrays (VPopStore). Las provincias guardan p["pop_slots"].
var pops := VPopStore.new()


# ------------------------------------------------------------- consultas
func province(id: int) -> Dictionary:
	if id <= 0 or id >= provinces.size() or provinces[id] == null:
		return {}
	return provinces[id]


func is_land(id: int) -> bool:
	return id > 0 and id < first_sea_id


func country(tag: String) -> Dictionary:
	return countries.get(tag, {})


func country_index(tag: String) -> int:
	return country_order.find(tag) + 1  # 0 = sin dueño


func country_name(tag: String) -> String:
	if tag == "":
		return "Sin colonizar"
	if tag == REBEL_TAG:
		return "Rebeldes"
	return countries.get(tag, {}).get("name", tag)


func country_color(tag: String) -> Color:
	if tag == REBEL_TAG:
		return Color("2a2a2a")
	if tag == "" or not countries.has(tag):
		return Color("8a8070")
	return countries[tag]["color_obj"]


func state_instance_key(state_id: int, tag: String) -> String:
	return "%d:%s" % [state_id, tag]


func owned_provinces(tag: String) -> Array:
	return countries.get(tag, {}).get("provinces", [])


func culture_name(id: String) -> String:
	return cultures.get(id, {}).get("name", id)


func religion_name(id: String) -> String:
	return religions.get(id, {}).get("name", id)


func good_name(id: String) -> String:
	return goods.get(id, {}).get("name", id)


func terrain_name(id: String) -> String:
	return terrain_types.get(id, {}).get("name", id)


func pop_type_name(id: String) -> String:
	return pop_types.get(id, {}).get("name", id)


func government_name(id: String) -> String:
	return governments.get(id, {}).get("name", id)


## Lista de tags vivos (con al menos una provincia).
func living_countries() -> Array:
	var out := []
	for tag in country_order:
		if not countries[tag]["provinces"].is_empty():
			out.append(tag)
	return out


# --------------------------------------------------------- derivaciones
## Recalcula provincias de cada país y las instancias de estado. Llamar tras cambiar propietarios.
func rebuild_territory() -> void:
	for tag in countries:
		countries[tag]["provinces"] = []
	var old_instances := state_instances
	state_instances = {}
	for id in range(1, first_sea_id):
		var p: Dictionary = provinces[id]
		var owner: String = p["owner"]
		if owner != "" and countries.has(owner):
			countries[owner]["provinces"].append(id)
		var key := state_instance_key(p["state"], owner)
		if not state_instances.has(key):
			var prev: Dictionary = old_instances.get(key, {})
			state_instances[key] = {
				"key": key, "state": p["state"], "owner": owner, "provinces": [],
				"factories": prev.get("factories", []),
			}
		state_instances[key]["provinces"].append(id)


func change_owner(province_ids: Array, new_owner: String) -> void:
	for id in province_ids:
		var p := province(id)
		if p.is_empty():
			continue
		p["owner"] = new_owner
		p["controller"] = new_owner
		p["occupation"] = 0.0
	rebuild_territory()
	controller_version += 1
	ws_values_month = -1
	access_version += 1  # cambia quién puede entrar dónde (rutas cacheadas)
	ownership_changed.emit(province_ids)


func province_population(id: int) -> int:
	return int(province(id).get("population", 0))


func country_population(tag: String) -> int:
	var total := 0
	for id in owned_provinces(tag):
		total += int(provinces[id]["population"])
	return total


## Provincias de un estado que pertenecen a un país dado.
func state_part(state_id: int, tag: String) -> Array:
	return state_instances.get(state_instance_key(state_id, tag), {}).get("provinces", [])


## Instancias de estado de un país, ordenadas por población.
func country_state_instances(tag: String) -> Array:
	var rows := []
	for key in state_instances:
		var si: Dictionary = state_instances[key]
		if si["owner"] == tag:
			rows.append([_instance_pop(si), si])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	var out := []
	for r in rows:
		out.append(r[1])
	return out


func _instance_pop(si: Dictionary) -> int:
	var t := 0
	for id in si["provinces"]:
		t += int(provinces[id]["population"])
	return t


func instance_population(si: Dictionary) -> int:
	return _instance_pop(si)


## ¿El estado está dividido entre varios propietarios?
func state_is_split(state_id: int) -> bool:
	var owners := {}
	for id in states[state_id]["provinces"]:
		owners[provinces[id]["owner"]] = true
	return owners.size() > 1
