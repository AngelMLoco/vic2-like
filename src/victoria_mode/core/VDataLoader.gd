class_name VDataLoader
extends RefCounted
## Carga todos los datos de data/victoria_mode/ y construye un VGameState listo para jugar.
## Nada del contenido (países, provincias, bienes...) está escrito en código: todo sale de JSON.

const ROOT := "res://data/victoria_mode/"


static func new_game() -> VGameState:
	var gs := VGameState.new()
	var t0 := Time.get_ticks_msec()
	_load_definitions(gs)
	_load_map(gs)
	_load_countries(gs)
	gs.rebuild_territory()
	_apply_history(gs)
	VPopulationSystem.generate_initial(gs)
	VRankingSystem.recalculate(gs)
	print("[VictoriaMode] mundo cargado en %d ms: %d provincias terrestres, %d estados, %d países" % [
		Time.get_ticks_msec() - t0, gs.first_sea_id - 1, gs.states.size(), gs.countries.size()])
	return gs


static func _index(arr: Array, key: String = "id") -> Dictionary:
	var out := {}
	for item in arr:
		out[item[key]] = item
	return out


static func _load_definitions(gs: VGameState) -> void:
	var cult := VJson.load_dict(ROOT + "cultures/cultures.json")
	gs.cultures = _index(cult.get("cultures", []))
	gs.culture_groups = _index(cult.get("groups", []))
	for id in gs.cultures:
		var c: Dictionary = gs.cultures[id]
		c["color_obj"] = Color(c["color"]) if c.has("color") else _hash_color(id)
	gs.religions = _index(VJson.load_array(ROOT + "religions/religions.json", "religions"))
	for id in gs.religions:
		gs.religions[id]["color_obj"] = Color(gs.religions[id].get("color", "888888"))
	gs.goods = _index(VJson.load_array(ROOT + "goods/goods.json", "goods"))
	for id in gs.goods:
		gs.goods[id]["color_obj"] = Color(gs.goods[id].get("color", "888888"))
	gs.factory_types = _index(VJson.load_array(ROOT + "factories/factories.json", "factories"))
	gs.terrain_types = _index(VJson.load_array(ROOT + "terrain/terrain.json", "terrain"))
	for id in gs.terrain_types:
		gs.terrain_types[id]["color_obj"] = Color(gs.terrain_types[id].get("color", "888888"))
	var pt := VJson.load_dict(ROOT + "pops/pop_types.json")
	gs.pop_types = _index(pt.get("pop_types", []))
	for id in gs.pop_types:
		gs.pop_types[id]["color_obj"] = Color(gs.pop_types[id].get("color", "888888"))
	gs.pop_distribution = pt.get("initial_distribution", {})
	gs.governments = _index(VJson.load_array(ROOT + "governments/governments.json", "governments"))
	gs.ideologies = _index(VJson.load_array(ROOT + "ideologies/ideologies.json", "ideologies"))
	for id in gs.ideologies:
		gs.ideologies[id]["color_obj"] = Color(gs.ideologies[id].get("color", "888888"))


static func _hash_color(key: String) -> Color:
	var h := key.hash()
	return Color.from_hsv(float(h & 1023) / 1023.0, 0.45 + float((h >> 10) & 255) / 255.0 * 0.35, 0.55 + float((h >> 18) & 255) / 255.0 * 0.35)


static func _load_map(gs: VGameState) -> void:
	var meta := VJson.load_dict(ROOT + "map/map.json")
	gs.map_width = int(meta["width"])
	gs.map_height = int(meta["height"])
	gs.first_sea_id = int(meta["first_sea_id"])
	gs.first_lake_id = int(meta["first_lake_id"])
	var geometry := VJson.load_array(ROOT + "map/geometry.json")
	gs.max_id = geometry.size()
	gs.provinces.resize(gs.max_id + 1)
	gs.provinces[0] = null
	for g in geometry:
		var id := int(g["id"])
		var c: Array = g["center"]
		var bb: Array = g["bbox"]
		var nb := PackedInt32Array()
		for n in g["neighbors"]:
			nb.append(int(n))
		gs.provinces[id] = {
			"id": id,
			"kind": g["kind"],
			"name": "",
			"center": Vector2(float(c[0]) + 0.5, float(c[1]) + 0.5),
			"bbox": Rect2(bb[0], bb[1], int(bb[2]) - int(bb[0]) + 1, int(bb[3]) - int(bb[1]) + 1),
			"area_px": int(g["area_px"]),
			"area_km2": int(g["area_km2"]),
			"neighbors": nb,
			"owner": "", "controller": "", "state": 0,
			"population": 0,
		}
	for p in VJson.load_array(ROOT + "provinces/provinces.json"):
		var id := int(p["id"])
		var prov: Dictionary = gs.provinces[id]
		prov["name"] = p["name"]
		prov["state"] = int(p["state"])
		prov["owner"] = p["owner"]
		prov["controller"] = p["owner"]
		prov["cores"] = [p["owner"]] if p["owner"] != "" else []
		prov["culture"] = p["culture"]
		prov["religion"] = p["religion"]
		prov["terrain"] = p["terrain"]
		prov["rgo"] = p["rgo"]
		prov["life_rating"] = int(p["life_rating"])
		prov["base_population"] = int(p["population"])
		prov["population"] = int(p["population"])
		prov["infrastructure"] = int(p.get("infrastructure", 0))
		prov["fort"] = 0
		prov["naval_base"] = 0
		prov["occupation"] = 0.0
		prov["coastal"] = false
		prov["pops"] = []
		for n in prov["neighbors"]:
			if n >= gs.first_sea_id and n < gs.first_lake_id:
				prov["coastal"] = true
	for s in VJson.load_array(ROOT + "provinces/sea_zones.json"):
		gs.provinces[int(s["id"])]["name"] = s["name"]
	for s in VJson.load_array(ROOT + "states/states.json"):
		var ids: Array = []
		for p in s["provinces"]:
			ids.append(int(p))
		gs.states[int(s["id"])] = {"id": int(s["id"]), "name": s["name"], "provinces": ids, "modern_region": s.get("modern_region", "")}
	gs.adjacencies = VJson.load_array(ROOT + "map/adjacencies.json")
	for adj in gs.adjacencies:
		var a := int(adj["a"])
		var b := int(adj["b"])
		var na: PackedInt32Array = gs.provinces[a]["neighbors"]
		na.append(b)
		gs.provinces[a]["neighbors"] = na
		var nb2: PackedInt32Array = gs.provinces[b]["neighbors"]
		nb2.append(a)
		gs.provinces[b]["neighbors"] = nb2


static func _load_countries(gs: VGameState) -> void:
	for c in VJson.load_array(ROOT + "countries/countries.json", "countries"):
		var tag: String = c["tag"]
		var d: Dictionary = c.duplicate(true)
		d["color_obj"] = Color(c["color"])
		d["provinces"] = []
		d["prestige"] = float(c.get("prestige", 0))
		d["treasury"] = float(c.get("treasury", 0))
		d["literacy"] = float(c.get("literacy", 0.1))
		d["infamy"] = 0.0
		d["war_exhaustion"] = 0.0
		d["relations"] = {}
		d["allies"] = []
		d["wars"] = []
		d["sphere_leader"] = ""
		d["influence"] = {}
		d["military"] = {"brigades": 0, "ships": 0}
		d["industry_score"] = 0.0
		d["military_score"] = 0.0
		d["total_score"] = 0.0
		d["rank"] = 0
		d["status"] = "civilized" if c.get("civilized", true) else "uncivilized"
		d["income_daily"] = 0.0
		d["expense_daily"] = 0.0
		d["research_points"] = 0.0
		d["budget"] = {"tax_poor": 0.35, "tax_middle": 0.35, "tax_rich": 0.35, "tariffs": 0.0,
			"education": 0.5, "administration": 0.5, "military": 0.6, "social": 0.0, "stockpile": 0.5}
		gs.countries[tag] = d
		gs.country_order.append(tag)


static func _apply_history(gs: VGameState) -> void:
	var hist := VJson.load_dict(ROOT + "history/start_136.json")
	if hist.has("start_date"):
		gs.date = VDate.from_dict(hist["start_date"])
	# capitales: la indicada o la provincia propia más poblada
	for tag in gs.countries:
		var c: Dictionary = gs.countries[tag]
		var best := -1
		var best_pop := -1
		for id in c["provinces"]:
			var pop := int(gs.provinces[id]["population"])
			if pop > best_pop:
				best_pop = pop
				best = id
		if c.get("capital") != null and gs.province(int(c["capital"])).get("owner", "") == tag:
			best = int(c["capital"])
		c["capital"] = best
		if best > 0 and gs.provinces[best]["coastal"]:
			gs.provinces[best]["naval_base"] = 1
		if best > 0:
			gs.provinces[best]["fort"] = 1
	# relaciones y alianzas
	for r in hist.get("relations", []):
		_set_relation(gs, r[0], r[1], int(r[2]))
	for pair in hist.get("alliances", []):
		var a: String = pair[0]
		var b: String = pair[1]
		if gs.countries.has(a) and gs.countries.has(b):
			gs.countries[a]["allies"].append(b)
			gs.countries[b]["allies"].append(a)
			_set_relation(gs, a, b, max(int(gs.countries[a]["relations"].get(b, 0)), 100))
	for w in hist.get("wars", []):
		for att in w.get("attackers", []):
			for dfd in w.get("defenders", []):
				if gs.countries.has(att) and gs.countries.has(dfd):
					gs.countries[att]["wars"].append({"name": w.get("name", "Guerra"), "enemy": dfd})
					gs.countries[dfd]["wars"].append({"name": w.get("name", "Guerra"), "enemy": att})
	# ejército, flota e industria inicial
	var ftypes: Array = gs.factory_types.keys()
	ftypes.sort()
	var per_country: Dictionary = hist.get("countries", {})
	for tag in per_country:
		if not gs.countries.has(tag):
			continue
		var h: Dictionary = per_country[tag]
		gs.countries[tag]["military"] = {"brigades": int(h.get("brigades", 0)), "ships": int(h.get("ships", 0))}
		var levels := int(h.get("factory_levels", 0))
		var instances := gs.country_state_instances(tag)
		var i := 0
		while levels > 0 and not instances.is_empty():
			var si: Dictionary = instances[i % min(instances.size(), 6)]
			var ftype: String = ftypes[(tag.hash() + i * 7) % ftypes.size()]
			var existing: Dictionary = {}
			for f in si["factories"]:
				if f["type"] == ftype:
					existing = f
			if existing.is_empty():
				si["factories"].append({"type": ftype, "level": 1, "employment": 0.85, "profit": 0.0})
			else:
				existing["level"] += 1
			levels -= 1
			i += 1


static func _set_relation(gs: VGameState, a: String, b: String, value: int) -> void:
	if not gs.countries.has(a) or not gs.countries.has(b):
		return
	value = clampi(value, -200, 200)
	gs.countries[a]["relations"][b] = value
	gs.countries[b]["relations"][a] = value
