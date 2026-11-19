class_name VDataLoader
extends RefCounted
## Carga los datos y construye un VGameState listo para jugar. Nada del contenido (países, provincias,
## bienes...) está escrito en código: todo sale de JSON.
## M6: escenario → mundo. Las reglas compartidas salen de base_root, el mapa, los países, las culturas, las
## religiones y la historia salen del mundo del escenario (world_root). Ver VWorlds.

## Raíz de las reglas compartidas y de los paquetes de contenido (no del mapa: ver VWorlds).
const ROOT := VWorlds.BASE_ROOT

static var _history_wars: Array = []


## scenario_id: escenario/bookmark de scenarios/scenarios.json ("" = el de por defecto).
static func new_game(scenario_id: String = "") -> VGameState:
	var gs := VGameState.new()
	var t0 := Time.get_ticks_msec()
	_load_scenario(gs, scenario_id)
	_load_definitions(gs)
	_load_map(gs)
	_load_countries(gs)
	var hist := VJson.load_dict(VWorlds.world_file(gs, String(gs.scenario.get("history", "history/start_136.json"))))
	_apply_province_history(gs, hist)
	gs.rebuild_territory()
	_apply_history(gs, hist)
	load_content(gs)
	gs.pops.setup(gs)
	VPopulationSystem.generate_initial(gs)
	VPoliticsSystem.setup_new_game(gs)
	VTechnologySystem.setup_new_game(gs)
	_apply_late_history(gs, hist)
	for tag in gs.countries:
		VModifiers.recompute(gs, tag)
	VMarketSystem.setup_new_game(gs)
	VProductionSystem.setup_new_game(gs)
	VBudgetSystem.setup_new_game(gs)
	VRankingSystem.recalculate(gs)
	VDiplomacySystem.setup_new_game(gs)
	VInfluenceSystem.setup_new_game(gs)
	VArmySystem.setup_new_game(gs)
	VNavySystem.setup_new_game(gs)
	VWarSystem.setup_new_game(gs, _history_wars)
	VRankingSystem.recalculate(gs)
	print("[VictoriaMode] mundo «%s» (mapa v%d) cargado en %d ms: %d provincias terrestres, %d estados, %d países" % [
		gs.world_id, gs.map_version, Time.get_ticks_msec() - t0, gs.first_sea_id - 1, gs.states.size(), gs.countries.size()])
	return gs


## Escenario: mundo, fecha, historia y paquetes de contenido (no se asume el año 136 ni la Tierra).
static func _load_scenario(gs: VGameState, scenario_id: String) -> void:
	var want: String = scenario_id if scenario_id != "" else VWorlds.default_scenario_id()
	gs.scenario = VWorlds.scenario(want).duplicate(true)
	if gs.scenario.is_empty():
		gs.data_errors.append("scenarios.json: escenario desconocido «%s»" % want)
		gs.scenario = {"id": want, "history": "history/start_136.json"}
	gs.scenario_id = String(gs.scenario.get("id", want))
	gs.content_packs = []
	for p in gs.scenario.get("content_packs", []):
		gs.content_packs.append(String(p))
	gs.base_root = VWorlds.BASE_ROOT
	gs.world_id = VWorlds.world_of(gs.scenario)
	gs.world = VWorlds.world_meta(gs.world_id)
	if gs.world.is_empty():
		gs.data_errors.append("escenario «%s»: mundo no registrado «%s»" % [gs.scenario_id, gs.world_id])
	gs.world_root = String(gs.world.get("root_path", VWorlds.BASE_ROOT + "worlds/%s/" % gs.world_id))
	gs.wrap_x = bool(gs.world.get("wrap_x", false))
	for p in gs.content_packs:
		if String(p) in gs.world.get("forbidden_packs", []):
			gs.data_errors.append("escenario «%s»: el mundo «%s» no admite el paquete «%s»" % [gs.scenario_id, gs.world_id, p])


## Contenido de los paquetes activos (también al cargar una partida): reglas y ramas mágicas, actitudes de
## religiones y culturas, eventos, decisiones, crónica, manifiesto de arte y biblia de lore.
static func load_content(gs: VGameState) -> void:
	var root := VWorlds.CONTENT_ROOT
	VContentPacks.validate(gs, root)
	VMagicSystem.apply_prototype_branches(gs, root)
	VEventSystem.load_definitions(gs, root)
	VDecisionSystem.load_definitions(gs, root)
	VChronicle.load_templates(gs, root)
	VLoreLoader.load_all(gs, root)
	for e in gs.data_errors:
		push_error("[datos] " + str(e))


static func _index(arr: Array, key: String = "id") -> Dictionary:
	var out := {}
	for item in arr:
		out[item[key]] = item
	return out


static func _load_definitions(gs: VGameState) -> void:
	var cult := VJson.load_dict(VWorlds.world_file(gs, "cultures/cultures.json"))
	gs.cultures = _index(cult.get("cultures", []))
	gs.culture_groups = _index(cult.get("groups", []))
	for id in gs.cultures:
		var c: Dictionary = gs.cultures[id]
		c["color_obj"] = Color(c["color"]) if c.has("color") else _hash_color(id)
	gs.religions = _index(VJson.load_array(VWorlds.world_file(gs, "religions/religions.json"), "religions"))
	for id in gs.religions:
		gs.religions[id]["color_obj"] = Color(gs.religions[id].get("color", "888888"))
	gs.goods = _index(VJson.load_array(VWorlds.data_path(gs, "goods/goods.json"), "goods"))
	for id in gs.goods:
		gs.goods[id]["color_obj"] = Color(gs.goods[id].get("color", "888888"))
	gs.factory_types = _index(VJson.load_array(VWorlds.data_path(gs, "factories/factories.json"), "factories"))
	gs.terrain_types = _index(VJson.load_array(VWorlds.data_path(gs, "terrain/terrain.json"), "terrain"))
	for id in gs.terrain_types:
		gs.terrain_types[id]["color_obj"] = Color(gs.terrain_types[id].get("color", "888888"))
	var pt := VJson.load_dict(VWorlds.data_path(gs, "pops/pop_types.json"))
	gs.pop_types = _index(pt.get("pop_types", []))
	for id in gs.pop_types:
		gs.pop_types[id]["color_obj"] = Color(gs.pop_types[id].get("color", "888888"))
	gs.pop_distribution = pt.get("initial_distribution", {})
	gs.governments = _index(VJson.load_array(VWorlds.data_path(gs, "governments/governments.json"), "governments"))
	gs.ideologies = _index(VJson.load_array(VWorlds.data_path(gs, "ideologies/ideologies.json"), "ideologies"))
	for id in gs.ideologies:
		gs.ideologies[id]["color_obj"] = Color(gs.ideologies[id].get("color", "888888"))
	gs.economy_rules = VJson.load_dict(VWorlds.data_path(gs, "economy/economy_rules.json"))
	gs.promotion_rules = VJson.load_array(VWorlds.data_path(gs, "pops/promotion.json"), "rules")
	var iss := VJson.load_dict(VWorlds.data_path(gs, "politics/issues.json"))
	gs.issues = _index(iss.get("issues", []))
	gs.issue_conditionals = iss.get("conditional", [])
	var ref := VJson.load_dict(VWorlds.data_path(gs, "politics/reforms.json"))
	for r in ref.get("reforms", []):
		gs.reforms[r["id"]] = r
		gs.reform_order.append(r["id"])
	gs.reform_meta = {"movement_names": ref.get("movement_names", {}), "cooldown_months": int(ref.get("cooldown_months", 6))}
	gs.party_templates = VJson.load_array(VWorlds.data_path(gs, "politics/party_templates.json"), "templates")
	var tech := VJson.load_dict(VWorlds.data_path(gs, "technologies/technologies.json"))
	gs.technologies = _index(tech.get("technologies", []))
	gs.tech_categories = tech.get("categories", [])
	gs.tech_categories.append_array(VJson.load_dict(VWorlds.data_path(gs, "magic/technologies.json")).get("categories", []))
	gs.inventions = _index(VJson.load_array(VWorlds.data_path(gs, "technologies/inventions.json"), "inventions"))
	# M4: tecnologías e inventos mágicos (data/victoria_mode/magic/technologies.json) en las mismas tablas
	var mtech := VJson.load_dict(VWorlds.data_path(gs, "magic/technologies.json"))
	for t in mtech.get("technologies", []):
		gs.technologies[t["id"]] = t
	for i in mtech.get("inventions", []):
		gs.inventions[i["id"]] = i
	var units := VJson.load_dict(VWorlds.data_path(gs, "military/unit_types.json"))
	gs.unit_types = _index(units.get("units", []))
	gs.unit_manpower = int(units.get("manpower", 3000))
	gs.combat_width = int(units.get("base_combat_width", 12))
	gs.ship_types = _index(VJson.load_array(VWorlds.data_path(gs, "military/ship_types.json"), "ships"))
	gs.leader_traits = VJson.load_dict(VWorlds.data_path(gs, "military/leader_traits.json"))
	var cb := VJson.load_dict(VWorlds.data_path(gs, "war/casus_belli.json"))
	gs.cb_types = _index(cb.get("casus_belli", []))
	gs.war_rules = cb
	gs.diplo_rules = VJson.load_dict(VWorlds.data_path(gs, "diplomacy/diplomacy_rules.json"))
	var reb := VJson.load_dict(VWorlds.data_path(gs, "rebels/rebel_types.json"))
	gs.rebel_types = _index(reb.get("types", []))
	gs.rebel_rules = reb


static func _hash_color(key: String) -> Color:
	var h := key.hash()
	return Color.from_hsv(float(h & 1023) / 1023.0, 0.45 + float((h >> 10) & 255) / 255.0 * 0.35, 0.55 + float((h >> 18) & 255) / 255.0 * 0.35)


static func _load_map(gs: VGameState) -> void:
	var meta := VJson.load_dict(VWorlds.world_file(gs, "map/map.json"))
	gs.map_width = int(meta["width"])
	gs.map_height = int(meta["height"])
	gs.first_sea_id = int(meta["first_sea_id"])
	gs.first_lake_id = int(meta["first_lake_id"])
	# versión de la geometría: la escribe el importador en map.json; si falta, la declara world.json
	gs.map_version = int(meta.get("map_version", gs.world.get("map_version", 1)))
	var geometry := VJson.load_array(VWorlds.world_file(gs, "map/geometry.json"))
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
	for p in VJson.load_array(VWorlds.world_file(gs, "provinces/provinces.json")):
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
		prov["pop_slots"] = []
		for n in prov["neighbors"]:
			if n >= gs.first_sea_id and n < gs.first_lake_id:
				prov["coastal"] = true
	for s in VJson.load_array(VWorlds.world_file(gs, "provinces/sea_zones.json")):
		gs.provinces[int(s["id"])]["name"] = s["name"]
	for s in VJson.load_array(VWorlds.world_file(gs, "states/states.json")):
		var ids: Array = []
		for p in s["provinces"]:
			ids.append(int(p))
		gs.states[int(s["id"])] = {"id": int(s["id"]), "name": s["name"], "provinces": ids, "modern_region": s.get("modern_region", "")}
	gs.adjacencies = VJson.load_array(VWorlds.world_file(gs, "map/adjacencies.json"))
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
	for c in VJson.load_array(VWorlds.world_file(gs, "countries/countries.json"), "countries"):
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
		d["budget"] = {"tax_poor": 0.15, "tax_middle": 0.2, "tax_rich": 0.25, "tariffs": 0.1,
			"education": 0.6, "administration": 0.6, "military": 0.6, "social": 0.3, "stockpile": 0.4}
		d["mods"] = {}
		gs.countries[tag] = d
		gs.country_order.append(tag)


## Propiedad, control y núcleos por provincia declarados por la historia (antes de construir los estados).
##   "provinces": {"<id>": {"owner": TAG, "controller": TAG, "cores": [TAG…]}}
static func _apply_province_history(gs: VGameState, hist: Dictionary) -> void:
	var ph: Dictionary = hist.get("provinces", {})
	for k in ph:
		var p := gs.province(int(k))
		if p.is_empty():
			gs.data_errors.append("historia: provincia desconocida %s" % k)
			continue
		var h: Dictionary = ph[k]
		if h.has("owner"):
			p["owner"] = String(h["owner"])
			p["controller"] = String(h["owner"])
		if h.has("controller"):
			p["controller"] = String(h["controller"])
		if h.has("cores"):
			p["cores"] = h["cores"].duplicate()


## Historia que necesita los sistemas ya preparados: tecnologías, inventos, reformas, banderas, variables,
## modificadores permanentes y ramas mágicas por nación; banderas globales y rivalidades.
static func _apply_late_history(gs: VGameState, hist: Dictionary) -> void:
	for f in hist.get("flags", []):
		gs.flags[String(f)] = true
	for pair in hist.get("rivals", []):
		if gs.countries.has(pair[0]) and gs.countries.has(pair[1]):
			for i in 2:
				var a: String = pair[i]
				var b: String = pair[1 - i]
				var rv: Array = gs.countries[a].get("rivals", [])
				if not (b in rv):
					rv.append(b)
				gs.countries[a]["rivals"] = rv
			_set_relation(gs, pair[0], pair[1], mini(int(gs.countries[pair[0]]["relations"].get(pair[1], 0)), -100))
	var per: Dictionary = hist.get("countries", {})
	for tag in per:
		if not gs.countries.has(tag):
			gs.data_errors.append("historia: país desconocido «%s»" % tag)
			continue
		var h: Dictionary = per[tag]
		var c: Dictionary = gs.countries[tag]
		for t in h.get("technologies", []):
			if gs.technologies.has(t):
				VTechnologySystem.complete(gs, tag, t)
			else:
				gs.data_errors.append("historia %s: tecnología desconocida «%s»" % [tag, t])
		for inv in h.get("inventions", []):
			VTechnologySystem.activate_invention(gs, tag, inv)
		for rid in h.get("reforms", {}):
			if gs.reforms.has(rid):
				c["reforms"][rid] = int(h["reforms"][rid])
			else:
				gs.data_errors.append("historia %s: reforma desconocida «%s»" % [tag, rid])
		for f in h.get("flags", []):
			VScopedState.set_country_flag(gs, tag, String(f))
		for n in h.get("variables", {}):
			VScopedState.change_variable(gs, tag, n, float(h["variables"][n]), true)
		for m in h.get("modifiers", []):
			var md: Dictionary = m if m is Dictionary else {"id": m}
			VScopedState.add_country_modifier(gs, tag, md["id"], int(md.get("months", 0)), "history", md.get("effects", {}))
		for b in h.get("magic_branches", {}):
			c["magic_branches"][b] = h["magic_branches"][b]


static func _apply_history(gs: VGameState, hist: Dictionary) -> void:
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
		var cap_h = hist.get("countries", {}).get(tag, {}).get("capital", c.get("capital"))
		if cap_h != null and gs.province(int(cap_h)).get("owner", "") == tag:
			best = int(cap_h)
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
	# las guerras históricas se crean como entidades War tras generar ejércitos (VWarSystem.setup_new_game)
	_history_wars = hist.get("wars", [])
	# ejército, flota e industria inicial
	var ftypes: Array = []
	for ft in gs.factory_types:
		if VProductionSystem.goods_unlocked(gs, ft):
			ftypes.append(ft)
	ftypes.sort()
	var per_country: Dictionary = hist.get("countries", {})
	for tag in per_country:
		if not gs.countries.has(tag):
			continue
		var h: Dictionary = per_country[tag]
		if h.has("government"):
			gs.countries[tag]["government"] = String(h["government"])
		for fld in ["literacy", "prestige", "treasury"]:
			if h.has(fld):
				gs.countries[tag][fld] = float(h[fld])
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
