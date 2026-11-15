class_name VRebelSystem
extends RefCounted
## Facciones rebeldes. No hay un segundo sistema de descontento: nacen de los movimientos de
## VPoliticsSystem cuando su radicalismo, organización, apoyo y la militancia de sus partidarios
## superan los umbrales de rebels/rebel_types.json.
##
## RebelFaction: id, type, country, movement (reforma), demand {reform, level}, supporting_pops[],
## strength, organisation, risen, controlled_provinces[], armies[], months_holding.
## Al alzarse, sus brigadas salen de los POPs militantes reales (una fracción de su tamaño deja el POP
## y forma la brigada: no se crean soldados de la nada). Si la rebelión se disuelve, los supervivientes
## vuelven a sus POPs. Si mantienen la capital o el % de provincias requerido durante varios meses,
## imponen su demanda (subir la reforma, cambiar el partido gobernante).


static func monthly(gs: VGameState) -> void:
	var r: Dictionary = gs.rebel_rules
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		if c["provinces"].is_empty():
			continue
		for rid in c.get("movements", {}):
			var mv: Dictionary = c["movements"][rid]
			if not mv.get("rebel_risk", false) or float(mv["organisation"]) < float(r.get("min_organisation", 0.5)) or float(mv["radicalism"]) < float(r.get("min_radicalism", 0.8)):
				continue
			if not faction_for(gs, tag, rid).is_empty():
				continue
			_try_form(gs, tag, rid)
	for fid in gs.rebel_factions.keys():
		var f: Dictionary = gs.rebel_factions.get(fid, {})
		if not f.is_empty():
			_update_faction(gs, f)


static func faction_for(gs: VGameState, tag: String, movement: String) -> Dictionary:
	for fid in gs.rebel_factions:
		var f: Dictionary = gs.rebel_factions[fid]
		if f["country"] == tag and f["movement"] == movement:
			return f
	return {}


static func type_for_reform(gs: VGameState, reform: String) -> String:
	for t in gs.rebel_types:
		if reform in gs.rebel_types[t].get("from_reforms", []):
			return t
	return "liberal_rebels"


static func _try_form(gs: VGameState, tag: String, reform: String) -> Dictionary:
	var r: Dictionary = gs.rebel_rules
	var min_mil := float(r.get("min_supporter_militancy", 4.0))
	var cur := gs.reform_level(tag, reform)
	var supporters := []
	var total := 0
	for id in gs.countries[tag]["provinces"]:
		for pop in gs.provinces[id]["pops"]:
			if float(pop["militancy"]) >= min_mil and VPoliticsSystem.desired_level(gs, pop, reform, cur) > cur:
				supporters.append(int(pop["id"]))
				total += int(pop["size"])
	if total < 30000:
		return {}
	return form_faction(gs, tag, reform, supporters)


static func form_faction(gs: VGameState, tag: String, reform: String, supporters: Array) -> Dictionary:
	var id := gs.new_id("rebel")
	var t := type_for_reform(gs, reform)
	var f := {"id": id, "type": t, "country": tag, "movement": reform,
		"demand": {"reform": reform, "level": gs.reform_level(tag, reform) + 1}, "supporting_pops": supporters,
		"strength": 0, "organisation": 0.2, "risen": false, "controlled_provinces": [], "armies": [], "months_holding": 0}
	gs.rebel_factions[id] = f
	gs.log_event(tag, "Se forma una facción rebelde: %s (exigen %s)" % [gs.rebel_types.get(t, {}).get("name", t), gs.reforms.get(reform, {}).get("name", reform)])
	return f


static func _find_pop(gs: VGameState, tag: String, pop_id: int) -> Dictionary:
	for id in gs.countries[tag]["provinces"]:
		for pop in gs.provinces[id]["pops"]:
			if int(pop["id"]) == pop_id:
				return pop
	return {}


## Alzamiento: brigadas formadas con personas reales de los POPs militantes.
static func rise(gs: VGameState, f: Dictionary) -> void:
	var r: Dictionary = gs.rebel_rules
	var share := float(r.get("spawn_share", 0.03))
	var max_b := int(r.get("max_brigades", 12))
	var tag: String = f["country"]
	var by_prov := {}
	var pool := []
	for pid in f["supporting_pops"]:
		var pop := _find_pop(gs, tag, int(pid))
		if not pop.is_empty():
			pool.append(pop)
	pool.sort_custom(func(a, b): return float(a["militancy"]) > float(b["militancy"]))
	var made := 0
	for pop in pool:
		if made >= max_b:
			break
		var men := int(float(pop["size"]) * share)
		while men >= 1000 and made < max_b:
			var take := mini(men, gs.unit_manpower)
			men -= take
			pop["size"] = maxi(1, int(pop["size"]) - take)
			var prov := int(pop["province"])
			if not by_prov.has(prov):
				var army := VArmySystem.new_army(gs, tag, prov, "Rebeldes de %s" % gs.provinces[prov]["name"])
				VUnitIndex.army_set_rebel(gs, army, int(f["id"]))
				by_prov[prov] = army
				f["armies"].append(int(army["id"]))
			var bid := gs.new_id("brigade")
			var b := {"id": bid, "type": "infantry", "strength": take, "organisation": 0.6, "experience": 0.0,
				"source_pop_id": int(pop["id"]), "source_province_id": prov, "army": 0, "rebel": true}
			gs.brigades[bid] = b
			VArmySystem.attach_brigade(gs, by_prov[prov], b)
			made += 1
	f["risen"] = true
	f["strength"] = made * gs.unit_manpower
	gs.log_event(tag, "¡Levantamiento! %s: %d brigadas en armas" % [gs.rebel_types.get(f["type"], {}).get("name", "Rebeldes"), made])
	for army in by_prov.values():
		VCombatSystem.on_army_arrived(gs, army)


static func _update_faction(gs: VGameState, f: Dictionary) -> void:
	var tag: String = f["country"]
	if not gs.countries.has(tag) or gs.countries[tag]["provinces"].is_empty():
		dissolve(gs, f, false)
		return
	var r: Dictionary = gs.rebel_rules
	if not f["risen"]:
		f["organisation"] = minf(1.0, float(f["organisation"]) + 0.15)
		var mv: Dictionary = gs.countries[tag].get("movements", {}).get(f["movement"], {})
		if gs.reform_level(tag, f["movement"]) >= int(f["demand"]["level"]):
			dissolve(gs, f, true)
			return
		if float(f["organisation"]) >= 1.0 and float(mv.get("radicalism", 0.0)) >= float(r.get("min_radicalism", 0.8)):
			rise(gs, f)
		return
	# alzada: ejércitos vivos, provincias controladas, condiciones de victoria
	var alive := []
	for aid in f["armies"]:
		if gs.armies.has(int(aid)):
			alive.append(int(aid))
	f["armies"] = alive
	var controlled := []
	for id in gs.countries[tag]["provinces"]:
		if gs.provinces[id]["controller"] == VGameState.REBEL_TAG and int(gs.provinces[id].get("rebel_faction", 0)) == int(f["id"]):
			controlled.append(id)
	f["controlled_provinces"] = controlled
	if alive.is_empty() and controlled.is_empty():
		dissolve(gs, f, false)
		return
	var cap := int(gs.countries[tag].get("capital", -1))
	var share := float(controlled.size()) / maxf(1.0, float(gs.countries[tag]["provinces"].size()))
	if (cap in controlled) or share >= float(r.get("victory_province_share", 0.3)):
		f["months_holding"] = int(f["months_holding"]) + 1
		if int(f["months_holding"]) >= int(r.get("victory_months", 3)):
			enforce(gs, f)
	else:
		f["months_holding"] = 0


## Victoria rebelde: se impone la demanda y la facción se disuelve.
static func enforce(gs: VGameState, f: Dictionary) -> void:
	var tag: String = f["country"]
	var c: Dictionary = gs.countries[tag]
	var t: Dictionary = gs.rebel_types.get(f["type"], {})
	match t.get("demand", "raise_reform"):
		"raise_reform":
			var rid: String = f["demand"]["reform"]
			var lvl := mini(int(f["demand"]["level"]), gs.reforms[rid]["levels"].size() - 1)
			c["reforms"][rid] = lvl
			VModifiers.recompute(gs, tag)
			gs.log_event(tag, "Los rebeldes imponen la reforma: %s → %s" % [gs.reforms[rid]["name"], gs.reforms[rid]["levels"][lvl]["name"]])
		"change_ruling_ideology", "lower_reform":
			var ideo: String = t.get("ideology", "tradicionalista")
			for i in c["parties"].size():
				if c["parties"][i]["ideology"] == ideo:
					c["ruling_party_index"] = i
					c["ruling_party"] = {"name": c["parties"][i]["name"], "ideology": ideo}
			gs.log_event(tag, "Los rebeldes imponen un gobierno %s" % gs.ideologies.get(ideo, {}).get("name", ideo))
	dissolve(gs, f, true)


static func dissolve(gs: VGameState, f: Dictionary, success: bool) -> void:
	var tag: String = f["country"]
	for aid in f["armies"]:
		if gs.armies.has(int(aid)):
			VArmySystem.destroy_army(gs, gs.armies[int(aid)], true)
	if gs.countries.has(tag):
		for id in gs.countries[tag]["provinces"]:
			var p: Dictionary = gs.provinces[id]
			if p["controller"] == VGameState.REBEL_TAG and int(p.get("rebel_faction", 0)) == int(f["id"]):
				VWarSystem.set_controller(gs, int(id), tag)
				p["rebel_faction"] = 0
				p["occupation"] = 0.0
		for pid in f["supporting_pops"]:
			var pop := _find_pop(gs, tag, int(pid))
			if not pop.is_empty():
				pop["militancy"] = maxf(0.0, float(pop["militancy"]) - (3.0 if success else 2.0))
		var mv: Dictionary = gs.countries[tag].get("movements", {}).get(f["movement"], {})
		if not mv.is_empty():
			mv["radicalism"] = float(mv["radicalism"]) * 0.3
			mv["rebel_risk"] = false
		gs.log_event(tag, "Facción rebelde disuelta (%s)" % ("tras lograr su objetivo" if success else "derrotada"))
	gs.rebel_factions.erase(int(f["id"]))
	gs.flags["_overlay_dirty"] = true


static func country_factions(gs: VGameState, tag: String) -> Array:
	var out := []
	for fid in gs.rebel_factions:
		if gs.rebel_factions[fid]["country"] == tag:
			out.append(gs.rebel_factions[fid])
	return out
