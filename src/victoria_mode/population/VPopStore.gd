class_name VPopStore
extends RefCounted
## Almacenamiento global de POPs en «estructura de arrays» (un array por campo, índice = slot).
##
## Por qué Array tipado y no Packed*Array: en GDScript un Packed*Array es un valor con copia-en-escritura;
## un alias local (var a := store.cash) se separa del almacén en la primera escritura. Los Array tipados son
## referencias: los bucles calientes toman alias locales (var cash := store.cash) y leen/escriben por índice
## sin búsquedas en diccionarios (medido: ≈5× más rápido que un Dictionary por POP; ver Architecture → M3.2).
##
## Slots: 0 … capacidad-1. Un slot libre tiene id = -1 y está en free_list (se reutiliza; nunca se compacta).
## Cada POP tiene además un id estable (enlaces externos: brigadas, facciones rebeldes, guardado).
## id_to_slot resuelve ids, incluidos los alias de POPs fusionados (apuntan al POP que los absorbió).
##
## Las provincias guardan la lista ordenada de slots en p["pop_slots"].
## La UI no necesita conocer este formato: get_pop_details(slot) devuelve un Dictionary temporal.

const NO_SLOT := -1
const STRATA := ["poor", "middle", "rich"]
const EMPLOYERS := ["", "rgo", "estado", "inversión", "fábrica", "rgo_owner"]
const EMP_NONE := 0
const EMP_RGO := 1
const EMP_STATE := 2
const EMP_INVEST := 3
const EMP_FACTORY := 4
const EMP_OWNER := 5

# ------------------------------------------------------------- campos calientes
var id: Array[int] = []
var province: Array[int] = []
var type_id: Array[int] = []
var culture_id: Array[int] = []
var religion_id: Array[int] = []
var size: Array[int] = []
var cash: Array[float] = []
var bank: Array[float] = []
var income: Array[float] = []
var income_acc: Array[float] = []
var employment: Array[float] = []
var employer: Array[int] = []
var literacy: Array[float] = []
var consciousness: Array[float] = []
var militancy: Array[float] = []
var life: Array[float] = []
var everyday: Array[float] = []
var luxury: Array[float] = []
var unemployed_months: Array[int] = []
var movement_push: Array[float] = []
## ideología: matriz plana slot * n_ideo + k (orden de ideo_names)
var ideology: Array[float] = []
# ------------------------------------------------------------- campos fríos
var issues: Array = []  # Dictionary compartido de solo lectura (ver VPopulationSystem.update_issues)
var product: Array[String] = []  # producto de los artesanos
var migration_target: Array[int] = []
var promotion_target: Array[String] = []
var brigades: Array = []  # null o Array de ids de brigada (Soldier POPs)

var free_list: Array[int] = []
var id_to_slot := {}
var next_id: int = 1

# ------------------------------------------------------------- tablas de ids
var type_names: Array[String] = []
var type_index := {}
var culture_names: Array[String] = []
var culture_index := {}
var religion_names: Array[String] = []
var religion_index := {}
var ideo_names: Array[String] = []
var ideo_index := {}
var n_ideo: int = 0
var employer_names: Array[String] = []
var employer_index := {}

## datos por tipo (índice = type_id)
var t_strata: Array[int] = []  # 0 pobre, 1 medio, 2 rico
var t_spend: Array[float] = []
var t_litf: Array[float] = []
var t_manual: Array[bool] = []
var t_job: Array[String] = []
var t_gov_wage: Array[float] = []
var t_vote_weight: Array[float] = []
var t_migrant: Array[bool] = []

## tipos con reglas propias (−1 si el tipo no existe)
var T_FARMERS := -1
var T_LABOURERS := -1
var T_SLAVES := -1
var T_ARISTOCRATS := -1
var T_ARTISANS := -1
var T_CRAFTSMEN := -1
var T_CLERKS := -1
var T_CAPITALISTS := -1
var T_CLERGY := -1
var T_SOLDIERS := -1
var T_OFFICERS := -1

## estadísticas (desde el inicio de la partida o la carga)
var stats := {"created": 0, "removed": 0, "merged": 0, "split": 0}


func setup(gs: VGameState) -> void:
	type_names.clear()
	type_index.clear()
	for t in gs.pop_types:
		_type(gs, t)
	for cu in gs.cultures:
		culture_of(cu)
	for r in gs.religions:
		religion_of(r)
	ideo_names.clear()
	ideo_index.clear()
	for i in gs.ideologies:
		ideo_index[i] = ideo_names.size()
		ideo_names.append(i)
	n_ideo = ideo_names.size()
	employer_names.clear()
	employer_index.clear()
	for e in EMPLOYERS:
		employer_of(e)
	T_FARMERS = int(type_index.get("farmers", -1))
	T_LABOURERS = int(type_index.get("labourers", -1))
	T_SLAVES = int(type_index.get("slaves", -1))
	T_ARISTOCRATS = int(type_index.get("aristocrats", -1))
	T_ARTISANS = int(type_index.get("artisans", -1))
	T_CRAFTSMEN = int(type_index.get("craftsmen", -1))
	T_CLERKS = int(type_index.get("clerks", -1))
	T_CAPITALISTS = int(type_index.get("capitalists", -1))
	T_CLERGY = int(type_index.get("clergy", -1))
	T_SOLDIERS = int(type_index.get("soldiers", -1))
	T_OFFICERS = int(type_index.get("officers", -1))


func _type(gs: VGameState, t: String) -> int:
	if type_index.has(t):
		return int(type_index[t])
	var k := type_names.size()
	type_index[t] = k
	type_names.append(t)
	var pt: Dictionary = gs.pop_types.get(t, {})
	t_strata.append(maxi(0, STRATA.find(String(pt.get("strata", "poor")))))
	t_spend.append(float(pt.get("spend_fraction", 1.0)))
	t_litf.append(0.7 + 0.3 * float(pt.get("literacy_mult", 1.0)))
	var job := String(pt.get("job", "none"))
	t_manual.append(job in ["rgo_farm", "rgo_mine", "factory_worker"])
	t_job.append(job)
	t_gov_wage.append(float(pt.get("gov_wage", 0.0)))
	t_vote_weight.append(float(pt.get("vote_weight", 1)))
	t_migrant.append(job in ["rgo_farm", "rgo_mine", "factory_worker", "factory_clerk", "artisan"])
	return k


func type_of(gs: VGameState, t: String) -> int:
	return _type(gs, t)


func culture_of(cu: String) -> int:
	if not culture_index.has(cu):
		culture_index[cu] = culture_names.size()
		culture_names.append(cu)
	return int(culture_index[cu])


func religion_of(r: String) -> int:
	if not religion_index.has(r):
		religion_index[r] = religion_names.size()
		religion_names.append(r)
	return int(religion_index[r])


func employer_of(e: String) -> int:
	if not employer_index.has(e):
		employer_index[e] = employer_names.size()
		employer_names.append(e)
	return int(employer_index[e])


# ------------------------------------------------------------- alta / baja
## Crea un POP en la provincia (al final de su lista) y devuelve su slot.
func allocate(gs: VGameState, type_name: String, sz: int, culture: String, religion: String, province_id: int) -> int:
	var s: int
	if not free_list.is_empty():
		s = free_list.pop_back()
	else:
		s = id.size()
		_grow()
	var t := _type(gs, type_name)
	id[s] = next_id
	id_to_slot[next_id] = s
	next_id += 1
	province[s] = province_id
	type_id[s] = t
	culture_id[s] = culture_of(culture)
	religion_id[s] = religion_of(religion)
	size[s] = sz
	cash[s] = 0.0
	bank[s] = 0.0
	income[s] = 0.0
	income_acc[s] = 0.0
	employment[s] = 1.0
	employer[s] = EMP_NONE
	literacy[s] = 0.0
	consciousness[s] = 0.0
	militancy[s] = 0.0
	life[s] = 1.0
	everyday[s] = 0.5
	luxury[s] = 0.1
	unemployed_months[s] = 0
	movement_push[s] = 0.0
	for k in n_ideo:
		ideology[s * n_ideo + k] = 0.0
	issues[s] = {}
	product[s] = ""
	migration_target[s] = 0
	promotion_target[s] = ""
	brigades[s] = null
	if province_id > 0 and province_id < gs.provinces.size() and gs.provinces[province_id] != null:
		gs.provinces[province_id]["pop_slots"].append(s)
	stats["created"] = int(stats["created"]) + 1
	return s


func _grow() -> void:
	for arr in [id, province, type_id, culture_id, religion_id, size, employer, unemployed_months, migration_target]:
		arr.append(0)
	for arr in [cash, bank, income, income_acc, employment, literacy, consciousness, militancy, life, everyday, luxury, movement_push]:
		arr.append(0.0)
	for k in n_ideo:
		ideology.append(0.0)
	issues.append({})
	product.append("")
	promotion_target.append("")
	brigades.append(null)


## Libera un slot (lo quita de su provincia). Los alias que apuntaban a él se eliminan.
func free_slot(gs: VGameState, s: int) -> void:
	if s < 0 or s >= id.size() or id[s] < 0:
		return
	var p = gs.provinces[province[s]] if province[s] > 0 and province[s] < gs.provinces.size() else null
	if p != null:
		p["pop_slots"].erase(s)
	for k in id_to_slot.keys():
		if int(id_to_slot[k]) == s:
			id_to_slot.erase(k)
	id[s] = -1
	size[s] = 0
	issues[s] = {}
	brigades[s] = null
	free_list.append(s)
	stats["removed"] = int(stats["removed"]) + 1


func is_alive(s: int) -> bool:
	return s >= 0 and s < id.size() and id[s] >= 0


## Slot de un id estable (o de un POP fusionado: el que lo absorbió). −1 si no existe.
func slot_of(pop_id: int) -> int:
	var s := int(id_to_slot.get(pop_id, NO_SLOT))
	return s if is_alive(s) else NO_SLOT


func count() -> int:
	return id.size() - free_list.size()


## Mueve un POP a otra provincia (migración de un POP entero).
func move(gs: VGameState, s: int, to_province: int) -> void:
	var from := province[s]
	if from == to_province:
		return
	gs.provinces[from]["pop_slots"].erase(s)
	gs.provinces[to_province]["pop_slots"].append(s)
	province[s] = to_province


## Fusiona el POP 'src' dentro de 'dst' (misma provincia, tipo, cultura y religión): medias ponderadas,
## suma de tamaño y dinero, enlaces de brigada trasladados; el id de 'src' pasa a ser alias de 'dst'.
func merge(gs: VGameState, src: int, dst: int) -> void:
	var w_old := float(size[dst])
	var w_new := float(size[src])
	var tot := maxf(1.0, w_old + w_new)
	literacy[dst] = (literacy[dst] * w_old + literacy[src] * w_new) / tot
	consciousness[dst] = (consciousness[dst] * w_old + consciousness[src] * w_new) / tot
	militancy[dst] = (militancy[dst] * w_old + militancy[src] * w_new) / tot
	for k in n_ideo:
		ideology[dst * n_ideo + k] = (ideology[dst * n_ideo + k] * w_old + ideology[src * n_ideo + k] * w_new) / tot
	size[dst] += size[src]
	cash[dst] += cash[src]
	bank[dst] += bank[src]
	income_acc[dst] += income_acc[src]
	if brigades[src] != null:
		var lst: Array = brigades[dst] if brigades[dst] != null else []
		for bid in brigades[src]:
			lst.append(bid)
			var b: Dictionary = gs.brigades.get(int(bid), {})
			if not b.is_empty():
				b["source_pop_id"] = id[dst]
				b["source_province_id"] = province[dst]
				b.erase("_pop")
		brigades[dst] = lst
		brigades[src] = null
	var old_id := id[src]
	free_slot(gs, src)
	stats["removed"] = int(stats["removed"]) - 1
	stats["merged"] = int(stats["merged"]) + 1
	id_to_slot[old_id] = dst


# ------------------------------------------------------------- ideología
func ideology_dict(s: int) -> Dictionary:
	var d := {}
	for k in n_ideo:
		var v := ideology[s * n_ideo + k]
		if v > 0.0:
			d[ideo_names[k]] = v
	return d


func set_ideology(s: int, d: Dictionary) -> void:
	for k in n_ideo:
		ideology[s * n_ideo + k] = float(d.get(ideo_names[k], 0.0))


func dominant_ideology(s: int) -> int:
	var best := -1
	var bv := -1.0
	var base := s * n_ideo
	for k in n_ideo:
		var v := ideology[base + k]
		if v > bv:
			bv = v
			best = k
	return best


# ------------------------------------------------------------- capa de compatibilidad (UI, depuración)
func type_name(s: int) -> String:
	return type_names[type_id[s]]


func strata_name(s: int) -> String:
	return STRATA[t_strata[type_id[s]]]


## Diccionario temporal con los mismos campos que el antiguo POP (para la UI: un POP a la vez).
func get_pop_details(s: int) -> Dictionary:
	if not is_alive(s):
		return {}
	return {"id": id[s], "slot": s, "province": province[s], "type": type_names[type_id[s]], "size": size[s],
		"culture": culture_names[culture_id[s]], "religion": religion_names[religion_id[s]],
		"literacy": literacy[s], "consciousness": consciousness[s], "militancy": militancy[s],
		"ideology": ideology_dict(s), "issues": issues[s], "cash": cash[s], "bank": bank[s], "income": income[s],
		"income_acc": income_acc[s], "employment": employment[s], "employer": employer_names[employer[s]],
		"needs_satisfaction": {"life": life[s], "everyday": everyday[s], "luxury": luxury[s]},
		"migration_target": migration_target[s], "promotion_target": promotion_target[s],
		"unemployed_months": unemployed_months[s], "product": product[s], "movement_push": movement_push[s],
		"brigades": (brigades[s] as Array).duplicate() if brigades[s] != null else []}


func get_pop_summary(s: int) -> String:
	if not is_alive(s):
		return "(POP inexistente)"
	return "%s %d (%s/%s) lit %.0f%% mil %.1f" % [type_names[type_id[s]], size[s], culture_names[culture_id[s]],
		religion_names[religion_id[s]], literacy[s] * 100.0, militancy[s]]


func get_pop_field(s: int, field: String) -> Variant:
	return get_pop_details(s).get(field)


func get_pop_type_name(s: int) -> String:
	return type_name(s)


## Lista de enlaces de brigada de un POP (crea la lista si no existe).
func brigade_links(s: int) -> Array:
	if brigades[s] == null:
		brigades[s] = []
	return brigades[s]


func brigade_count(s: int) -> int:
	return 0 if brigades[s] == null else (brigades[s] as Array).size()


# ------------------------------------------------------------- guardado (columnar)
const SAVE_INT := ["id", "province", "type_id", "culture_id", "religion_id", "size", "employer", "unemployed_months", "migration_target"]
const SAVE_FLOAT := ["cash", "bank", "income", "income_acc", "employment", "literacy", "consciousness", "militancy",
	"life", "everyday", "luxury", "movement_push"]


## Solo los POPs vivos, en orden de slot. Las tablas de nombres viajan con los datos.
func to_save() -> Dictionary:
	var alive: Array[int] = []
	for s in id.size():
		if id[s] >= 0:
			alive.append(s)
	var out := {"types": type_names.duplicate(), "cultures": culture_names.duplicate(), "religions": religion_names.duplicate(),
		"ideologies": ideo_names.duplicate(), "employers": employer_names.duplicate(), "next_id": next_id, "count": alive.size()}
	for f in SAVE_INT + SAVE_FLOAT:
		var src: Array = get(f)
		var col := []
		col.resize(alive.size())
		for i in alive.size():
			col[i] = src[alive[i]]
		out[f] = col
	var ideo := []
	ideo.resize(alive.size() * n_ideo)
	# issues: tabla de diccionarios distintos + índice por POP (los POPs comparten diccionarios)
	var issue_table := []
	var issue_map := {}
	var issue_idx := []
	var prod := []
	var promo := []
	var brig := {}
	for i in alive.size():
		var s := alive[i]
		for k in n_ideo:
			ideo[i * n_ideo + k] = ideology[s * n_ideo + k]
		var iss: Dictionary = issues[s]
		if not issue_map.has(iss):
			issue_map[iss] = issue_table.size()
			issue_table.append(iss)
		issue_idx.append(issue_map[iss])
		prod.append(product[s])
		promo.append(promotion_target[s])
		if brigades[s] != null and not (brigades[s] as Array).is_empty():
			brig[str(i)] = brigades[s]
	out["ideology"] = ideo
	out["issue_table"] = issue_table
	out["issue_idx"] = issue_idx
	out["product"] = prod
	out["promotion_target"] = promo
	out["brigades"] = brig
	var aliases := {}
	for k in id_to_slot:
		var s2 := int(id_to_slot[k])
		if is_alive(s2) and id[s2] != int(k):
			aliases[str(k)] = id[s2]
	out["aliases"] = aliases
	out["stats"] = stats.duplicate()
	return out


## Reconstruye el almacén y las listas de las provincias (en el orden guardado).
func from_save(gs: VGameState, d: Dictionary) -> void:
	setup(gs)
	# las tablas guardadas mandan (ids estables dentro de la partida)
	var tmap := []
	for t in d["types"]:
		tmap.append(_type(gs, String(t)))
	var cmap := []
	for cu in d["cultures"]:
		cmap.append(culture_of(String(cu)))
	var rmap := []
	for r in d["religions"]:
		rmap.append(religion_of(String(r)))
	var emap := []
	for e in d["employers"]:
		emap.append(employer_of(String(e)))
	var imap := []
	for i in d["ideologies"]:
		imap.append(int(ideo_index.get(String(i), -1)))
	var saved_ni: int = (d["ideologies"] as Array).size()
	var issue_table := []
	for iss in d.get("issue_table", []):
		var di: Dictionary = iss
		di.make_read_only()
		issue_table.append(di)
	for arr in [id, province, type_id, culture_id, religion_id, size, employer, unemployed_months, migration_target,
			cash, bank, income, income_acc, employment, literacy, consciousness, militancy, life, everyday, luxury,
			movement_push, ideology, issues, product, promotion_target, brigades, free_list]:
		arr.clear()
	id_to_slot.clear()
	for idx in gs.provinces.size():
		if gs.provinces[idx] != null:
			gs.provinces[idx]["pop_slots"] = []
	var n := int(d["count"])
	for i in n:
		_grow()
		id[i] = int(d["id"][i])
		province[i] = int(d["province"][i])
		type_id[i] = int(tmap[int(d["type_id"][i])])
		culture_id[i] = int(cmap[int(d["culture_id"][i])])
		religion_id[i] = int(rmap[int(d["religion_id"][i])])
		size[i] = int(d["size"][i])
		employer[i] = int(emap[int(d["employer"][i])])
		unemployed_months[i] = int(d["unemployed_months"][i])
		migration_target[i] = int(d["migration_target"][i])
		for f in SAVE_FLOAT:
			(get(f) as Array)[i] = float(d[f][i])
		for k in saved_ni:
			var kk: int = imap[k]
			if kk >= 0:
				ideology[i * n_ideo + kk] = float(d["ideology"][i * saved_ni + k])
		issues[i] = issue_table[int(d["issue_idx"][i])]
		product[i] = String(d["product"][i])
		promotion_target[i] = String(d["promotion_target"][i])
		id_to_slot[id[i]] = i
		gs.provinces[province[i]]["pop_slots"].append(i)
	var brig: Dictionary = d.get("brigades", {})
	for k in brig:
		var lst := []
		for bid in brig[k]:
			lst.append(int(bid))
		brigades[int(k)] = lst
	var aliases: Dictionary = d.get("aliases", {})
	for k in aliases:
		var s := int(id_to_slot.get(int(aliases[k]), NO_SLOT))
		if s >= 0:
			id_to_slot[int(k)] = s
	next_id = int(d["next_id"])
	stats = d.get("stats", stats)


## Coherencia del almacén (pruebas): listas de provincias, slots libres, ids y población de las provincias.
## check_population: comparar también p["population"] (caché que se recalcula en el cubo mensual de la
## provincia; a mitad de mes las bajas militares la desfasan).
func verify(gs: VGameState, check_population: bool = true) -> String:
	var seen := {}
	for pid in range(1, gs.provinces.size()):
		var p = gs.provinces[pid]
		if p == null:
			continue
		var total := 0
		for s in p.get("pop_slots", []):
			if not is_alive(int(s)):
				return "provincia %d: slot libre %d en su lista" % [pid, int(s)]
			if province[int(s)] != pid:
				return "slot %d en la lista de %d pero su provincia es %d" % [int(s), pid, province[int(s)]]
			if seen.has(int(s)):
				return "slot %d en dos provincias" % int(s)
			seen[int(s)] = true
			total += size[int(s)]
		if check_population and p.has("population") and int(p["population"]) != total:
			return "provincia %d: población %d, suma de POPs %d" % [pid, int(p["population"]), total]
	for s in id.size():
		if id[s] >= 0 and not seen.has(s):
			return "slot %d vivo pero en ninguna provincia" % s
		if id[s] >= 0 and slot_of(id[s]) != s:
			return "id %d no resuelve a su slot %d" % [id[s], s]
	for s in free_list:
		if id[s] >= 0:
			return "slot %d en la lista libre pero vivo" % s
	return ""
