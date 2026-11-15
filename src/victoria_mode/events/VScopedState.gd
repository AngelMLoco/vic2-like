class_name VScopedState
extends RefCounted
## Estado con ámbito de eventos y decisiones: banderas (globales en gs.flags; de nación, provincia y estado
## aquí), variables numéricas de nación y modificadores temporales de nación y de provincia.
## Todo vive en gs.event_state (se guarda). Claves de provincia como texto (JSON).
##
## Modificador: {"id", "source", "start" (mes), "expires" (mes, -1 = permanente), "effects" {clave: valor}}.
## Los de nación se suman en VModifiers.recompute (solo al añadir/quitar); los de provincia se agregan en
## p["pmods"] (derivado, no se guarda) y los leen producción (rgo_efficiency, rgo_size) y población
## (pop_growth, militancy, literacy_growth, consciousness).


static func es(gs: VGameState) -> Dictionary:
	var e := gs.event_state
	if e.is_empty():
		e.merge({"cflags": {}, "pflags": {}, "sflags": {}, "vars": {}, "cmods": {}, "pmods": {}, "fired": {},
			"history": [], "queue": [], "scheduled": [], "decisions": {}, "budget": {}, "stats": {}})
	return e


# ------------------------------------------------------------------ banderas
static func set_country_flag(gs: VGameState, tag: String, flag: String, on: bool = true) -> void:
	var f: Dictionary = es(gs)["cflags"]
	if on:
		if not f.has(tag):
			f[tag] = {}
		f[tag][flag] = gs.month_index
	elif f.has(tag):
		f[tag].erase(flag)


static func has_country_flag(gs: VGameState, tag: String, flag: String) -> bool:
	return es(gs)["cflags"].get(tag, {}).has(flag)


static func set_province_flag(gs: VGameState, id: int, flag: String, on: bool = true) -> void:
	var f: Dictionary = es(gs)["pflags"]
	var k := str(id)
	if on:
		if not f.has(k):
			f[k] = {}
		f[k][flag] = gs.month_index
	elif f.has(k):
		f[k].erase(flag)


static func has_province_flag(gs: VGameState, id: int, flag: String) -> bool:
	return es(gs)["pflags"].get(str(id), {}).has(flag)


static func set_state_flag(gs: VGameState, state_key: String, flag: String, on: bool = true) -> void:
	var f: Dictionary = es(gs)["sflags"]
	if on:
		if not f.has(state_key):
			f[state_key] = {}
		f[state_key][flag] = gs.month_index
	elif f.has(state_key):
		f[state_key].erase(flag)


static func has_state_flag(gs: VGameState, state_key: String, flag: String) -> bool:
	return es(gs)["sflags"].get(state_key, {}).has(flag)


# ------------------------------------------------------------------ variables
static func get_variable(gs: VGameState, tag: String, name: String) -> float:
	return float(es(gs)["vars"].get(tag, {}).get(name, 0.0))


static func change_variable(gs: VGameState, tag: String, name: String, delta: float, set_value: bool = false) -> void:
	var v: Dictionary = es(gs)["vars"]
	if not v.has(tag):
		v[tag] = {}
	v[tag][name] = delta if set_value else float(v[tag].get(name, 0.0)) + delta


# ------------------------------------------------------------------ modificadores
## Efectos de un modificador: de la biblioteca (data/victoria_mode/events/modifiers.json) o en línea.
static func modifier_effects(gs: VGameState, m: Dictionary) -> Dictionary:
	if m.has("effects") and not m["effects"].is_empty():
		return m["effects"]
	return gs.event_modifiers.get(m.get("id", ""), {}).get("effects", {})


static func modifier_name(gs: VGameState, id: String) -> String:
	return gs.event_modifiers.get(id, {}).get("name", id)


static func add_country_modifier(gs: VGameState, tag: String, id: String, months: int, source: String, effects: Dictionary = {}) -> void:
	var lst: Array = es(gs)["cmods"].get(tag, [])
	for m in lst:
		if m["id"] == id:
			# renovar la duración en lugar de acumular el mismo modificador
			m["expires"] = -1 if months <= 0 else gs.month_index + months
			return
	lst.append({"id": id, "source": source, "start": gs.month_index, "expires": -1 if months <= 0 else gs.month_index + months, "effects": effects})
	es(gs)["cmods"][tag] = lst
	VModifiers.recompute(gs, tag)


static func remove_country_modifier(gs: VGameState, tag: String, id: String) -> void:
	var lst: Array = es(gs)["cmods"].get(tag, [])
	for i in range(lst.size() - 1, -1, -1):
		if lst[i]["id"] == id:
			lst.remove_at(i)
	VModifiers.recompute(gs, tag)


static func country_modifiers(gs: VGameState, tag: String) -> Array:
	return es(gs)["cmods"].get(tag, [])


static func has_country_modifier(gs: VGameState, tag: String, id: String) -> bool:
	for m in es(gs)["cmods"].get(tag, []):
		if m["id"] == id:
			return true
	return false


static func add_province_modifier(gs: VGameState, id: int, mod_id: String, months: int, source: String, effects: Dictionary = {}) -> void:
	var k := str(id)
	var lst: Array = es(gs)["pmods"].get(k, [])
	var found := false
	for m in lst:
		if m["id"] == mod_id:
			m["expires"] = -1 if months <= 0 else gs.month_index + months
			found = true
	if not found:
		lst.append({"id": mod_id, "source": source, "start": gs.month_index, "expires": -1 if months <= 0 else gs.month_index + months, "effects": effects})
	es(gs)["pmods"][k] = lst
	_refresh_province(gs, id)


static func _refresh_province(gs: VGameState, id: int) -> void:
	var p := gs.province(id)
	if p.is_empty():
		return
	var agg := {}
	for m in es(gs)["pmods"].get(str(id), []):
		var eff := modifier_effects(gs, m)
		for k in eff:
			agg[k] = float(agg.get(k, 0.0)) + float(eff[k])
	if agg.is_empty():
		p.erase("pmods")
	else:
		p["pmods"] = agg


## Caducidad mensual: solo recorre las listas de modificadores existentes (pocas).
static func expire(gs: VGameState) -> void:
	var e := es(gs)
	for tag in e["cmods"].keys():
		var lst: Array = e["cmods"][tag]
		var changed := false
		for i in range(lst.size() - 1, -1, -1):
			var ex := int(lst[i]["expires"])
			if ex >= 0 and ex <= gs.month_index:
				lst.remove_at(i)
				changed = true
		if changed and gs.countries.has(tag):
			VModifiers.recompute(gs, tag)
	for k in e["pmods"].keys():
		var lst2: Array = e["pmods"][k]
		var changed2 := false
		for i in range(lst2.size() - 1, -1, -1):
			var ex2 := int(lst2[i]["expires"])
			if ex2 >= 0 and ex2 <= gs.month_index:
				lst2.remove_at(i)
				changed2 = true
		if changed2:
			_refresh_province(gs, int(k))


## Tras cargar: reconstruye los agregados derivados de provincia y los modificadores nacionales.
static func rebuild_after_load(gs: VGameState) -> void:
	var e := es(gs)
	for k in e["pmods"]:
		_refresh_province(gs, int(k))
	for tag in gs.countries:
		VModifiers.recompute(gs, tag)


# ------------------------------------------------------------------ crónica
## Historial de la partida (crónica): fecha, evento/decisión, nación, opción, importancia, categoría y texto
## narrativo opcional. Ver VChronicle (filtros, plantillas e historia emergente).
const DECISION_CATEGORY := {"industrial": "economy", "political": "politics", "diplomatic": "diplomacy",
	"military": "war", "magic": "magic"}


static func chronicle(gs: VGameState, kind: String, id: String, tag: String, title: String, option: String, important: bool, cat: String = "", text: String = "") -> void:
	if cat == "":
		if kind == "decision":
			cat = DECISION_CATEGORY.get(String(gs.decision_defs.get(id, {}).get("category", "")), "politics")
		elif gs.event_defs.has(id):
			cat = VChronicle.category_of_event(gs.event_defs[id])
		elif kind == "world":
			cat = "magic" if id.begins_with("magic") else "politics"
		else:
			cat = "politics"
	var h: Array = es(gs)["history"]
	h.append({"date": gs.date.text(), "month": gs.month_index, "year": gs.date.year, "kind": kind, "id": id, "tag": tag,
		"title": title, "option": option, "important": important, "cat": cat, "text": text})
	while h.size() > VChronicle.MAX_ENTRIES:
		h.remove_at(0)
