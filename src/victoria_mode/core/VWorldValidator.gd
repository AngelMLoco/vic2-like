class_name VWorldValidator
extends RefCounted
## M6: validación de un dataset de mundo sobre sus archivos (sin construir la partida).
##
##   var r := VWorldValidator.validate("test_fantasy")      # {"errors": [...], "warnings": [...]}
##   var r := VWorldValidator.validate_scenario("aether_era1")
##
## Errores: rompen la carga o la simulación (ids repetidos, referencias inexistentes, provincia sin estado…).
## Avisos: datos válidos pero sospechosos (mares interiores sin paso, países sin provincias…).


static func validate(world_id: String, history_rel: String = "") -> Dictionary:
	var meta := VWorlds.world_meta(world_id)
	if meta.is_empty():
		return {"errors": ["mundo «%s» no registrado en worlds/worlds.json" % world_id], "warnings": []}
	return validate_dir(String(meta["root_path"]), meta, history_rel)


## Valida una carpeta de mundo cualquiera (también fuera del registro, p. ej. una copia en user://).
static func validate_dir(root: String, meta: Dictionary = {}, history_rel: String = "") -> Dictionary:
	var r := {"errors": [], "warnings": []}
	var world_id := String(meta.get("id", root))
	if meta.is_empty() and FileAccess.file_exists(root + "world.json"):
		meta = VJson.load_dict(root + "world.json")
	for f in VWorlds.WORLD_FILES:
		if not FileAccess.file_exists(root + f):
			r["errors"].append("%s: falta %s" % [world_id, f])
	if not r["errors"].is_empty():
		return r
	var E: Array = r["errors"]
	var Wn: Array = r["warnings"]
	var base := VWorlds.BASE_ROOT
	var shared := func(rel: String) -> String:
		return root + rel if FileAccess.file_exists(root + rel) else base + rel

	# ---- mapa
	var map := VJson.load_dict(root + "map/map.json")
	var mw := int(map.get("width", 0))
	var mh := int(map.get("height", 0))
	if mw <= 0 or mh <= 0:
		E.append("map/map.json: dimensiones inválidas %dx%d" % [mw, mh])
	if int(meta.get("width", 0)) > 0 and (int(meta["width"]) != mw or int(meta.get("height", 0)) != mh):
		E.append("world.json declara %dx%d y map/map.json %dx%d" % [int(meta["width"]), int(meta.get("height", 0)), mw, mh])
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(root + "map/provinces.png")) != OK:
		E.append("map/provinces.png ilegible")
	elif img.get_width() != mw or img.get_height() != mh:
		E.append("map/provinces.png mide %dx%d y map/map.json %dx%d" % [img.get_width(), img.get_height(), mw, mh])
	var first_sea := int(map.get("first_sea_id", 0))
	var first_lake := int(map.get("first_lake_id", 0))
	var geo := VJson.load_array(root + "map/geometry.json")
	var kinds := {}
	var nbs := {}
	for g in geo:
		var id := int(g.get("id", 0))
		if kinds.has(id):
			E.append("map/geometry.json: id repetido %d" % id)
		kinds[id] = String(g.get("kind", ""))
		nbs[id] = g.get("neighbors", [])
		if int(g.get("area_px", 0)) <= 0:
			E.append("map/geometry.json: la provincia %d no tiene píxeles" % id)
	var max_id := geo.size()
	for id in range(1, max_id + 1):
		if not kinds.has(id):
			E.append("map/geometry.json: falta el id %d (los ids deben ser 1..%d sin huecos)" % [id, max_id])
			continue
		var want := "land" if id < first_sea else ("sea" if id < first_lake else "lake")
		if kinds[id] != want:
			E.append("map/geometry.json: el id %d es «%s» y por su rango debería ser «%s»" % [id, kinds[id], want])
		for n in nbs[id]:
			if not kinds.has(int(n)):
				E.append("map/geometry.json: la provincia %d tiene un vecino inexistente %s" % [id, str(n)])
	if int(map.get("land_count", -1)) >= 0 and int(map["land_count"]) != first_sea - 1:
		E.append("map/map.json: land_count %d no cuadra con first_sea_id %d" % [int(map["land_count"]), first_sea])

	# ---- definiciones
	var goods := {}
	for g in VJson.load_array(shared.call("goods/goods.json"), "goods"):
		goods[g["id"]] = true
	var terrains := {}
	for t in VJson.load_array(shared.call("terrain/terrain.json"), "terrain"):
		terrains[t["id"]] = true
	var govs := {}
	for g in VJson.load_array(shared.call("governments/governments.json"), "governments"):
		govs[g["id"]] = true
	var ideos := {}
	for i in VJson.load_array(shared.call("ideologies/ideologies.json"), "ideologies"):
		ideos[i["id"]] = true
	var cult := VJson.load_dict(root + "cultures/cultures.json")
	var groups := {}
	for g in cult.get("groups", []):
		groups[g["id"]] = true
	var cultures := {}
	var religions := {}
	for rl in VJson.load_array(root + "religions/religions.json", "religions"):
		if religions.has(rl["id"]):
			E.append("religions.json: id repetido «%s»" % rl["id"])
		religions[rl["id"]] = true
	for c in cult.get("cultures", []):
		if cultures.has(c["id"]):
			E.append("cultures.json: id repetido «%s»" % c["id"])
		cultures[c["id"]] = true
		if c.has("group") and not groups.has(c["group"]):
			E.append("cultures.json: «%s» usa el grupo inexistente «%s»" % [c["id"], c["group"]])
		if c.has("religion") and not religions.has(c["religion"]):
			E.append("cultures.json: «%s» usa la religión inexistente «%s»" % [c["id"], c["religion"]])
	var countries := {}
	for c in VJson.load_array(root + "countries/countries.json", "countries"):
		var tag := String(c.get("tag", ""))
		if countries.has(tag):
			E.append("countries.json: tag repetido «%s»" % tag)
		countries[tag] = c
		if not cultures.has(c.get("primary_culture", "")):
			E.append("countries.json: %s tiene la cultura inexistente «%s»" % [tag, c.get("primary_culture", "")])
		for ac in c.get("accepted_cultures", []):
			if not cultures.has(ac):
				E.append("countries.json: %s acepta la cultura inexistente «%s»" % [tag, ac])
		if not religions.has(c.get("religion", "")):
			E.append("countries.json: %s tiene la religión inexistente «%s»" % [tag, c.get("religion", "")])
		if not govs.has(c.get("government", "")):
			E.append("countries.json: %s tiene el gobierno inexistente «%s»" % [tag, c.get("government", "")])
		var rp: Dictionary = c.get("ruling_party", {})
		if not ideos.has(rp.get("ideology", "")):
			E.append("countries.json: %s tiene el partido con ideología inexistente «%s»" % [tag, rp.get("ideology", "")])

	# ---- provincias, estados, mares
	var states := {}
	var state_of := {}
	for s in VJson.load_array(root + "states/states.json"):
		var sid := int(s.get("id", 0))
		if states.has(sid):
			E.append("states.json: id de estado repetido %d" % sid)
		states[sid] = s
		for p in s.get("provinces", []):
			var pid := int(p)
			if pid < 1 or pid >= first_sea:
				E.append("states.json: el estado %d («%s») incluye %d, que no es una provincia terrestre" % [sid, s.get("name", ""), pid])
			elif state_of.has(pid):
				E.append("states.json: la provincia %d está en los estados %d y %d" % [pid, state_of[pid], sid])
			state_of[pid] = sid
	var owned := {}
	var prov_owner := {}
	var seen := {}
	for p in VJson.load_array(root + "provinces/provinces.json"):
		var id := int(p.get("id", 0))
		var where := "provinces.json (%d «%s»)" % [id, p.get("name", "")]
		if seen.has(id):
			E.append("%s: id repetido" % where)
		seen[id] = true
		if id < 1 or id >= first_sea:
			E.append("%s: no es un id terrestre (1..%d)" % [where, first_sea - 1])
			continue
		if not states.has(int(p.get("state", 0))):
			E.append("%s: estado inexistente %s" % [where, str(p.get("state"))])
		elif int(state_of.get(id, -1)) != int(p["state"]):
			E.append("%s: declara el estado %d pero states.json la pone en %s" % [where, int(p["state"]), str(state_of.get(id, "ninguno"))])
		var ow := String(p.get("owner", ""))
		if ow != "" and not countries.has(ow):
			E.append("%s: propietario inexistente «%s»" % [where, ow])
		owned[ow] = int(owned.get(ow, 0)) + 1
		prov_owner[id] = ow
		if not cultures.has(p.get("culture", "")):
			E.append("%s: cultura inexistente «%s»" % [where, p.get("culture", "")])
		if not religions.has(p.get("religion", "")):
			E.append("%s: religión inexistente «%s»" % [where, p.get("religion", "")])
		if not goods.has(p.get("rgo", "")):
			E.append("%s: RGO inexistente «%s»" % [where, p.get("rgo", "")])
		if not terrains.has(p.get("terrain", "")):
			E.append("%s: terreno inexistente «%s»" % [where, p.get("terrain", "")])
	for id in range(1, first_sea):
		if not seen.has(id):
			E.append("provinces.json: falta la provincia terrestre %d" % id)
		if not state_of.has(id):
			E.append("states.json: la provincia terrestre %d no tiene estado" % id)
	var named := {}
	for s in VJson.load_array(root + "provinces/sea_zones.json"):
		var id := int(s.get("id", 0))
		if id < first_sea or id > max_id:
			E.append("sea_zones.json: %d no es un id de mar o lago" % id)
		if named.has(id):
			E.append("sea_zones.json: id repetido %d" % id)
		named[id] = true
	for id in range(first_sea, max_id + 1):
		if not named.has(id):
			E.append("sea_zones.json: falta la zona marítima o lago %d" % id)
	var straits := {}
	for a in VJson.load_array(root + "map/adjacencies.json"):
		var ia := int(a.get("a", 0))
		var ib := int(a.get("b", 0))
		if not kinds.has(ia) or not kinds.has(ib):
			E.append("adjacencies.json: «%s» une ids inexistentes %d-%d" % [a.get("name", ""), ia, ib])
			continue
		if String(a.get("type", "")) == "sea_strait":
			straits[ia] = straits.get(ia, []) + [ib]
			straits[ib] = straits.get(ib, []) + [ia]

	# ---- conectividad marítima
	if first_lake > first_sea:
		var comp := 0
		var visited := {}
		var sizes: Array = []
		for start in range(first_sea, first_lake):
			if visited.has(start):
				continue
			comp += 1
			var n := 0
			var stack: Array = [start]
			visited[start] = true
			while not stack.is_empty():
				var cur: int = stack.pop_back()
				n += 1
				var around: Array = Array(nbs.get(cur, [])) + Array(straits.get(cur, []))
				for nb in around:
					var v := int(nb)
					if v >= first_sea and v < first_lake and not visited.has(v):
						visited[v] = true
						stack.append(v)
			sizes.append(n)
			var touches_land := false
			for nb in nbs.get(start, []):
				if int(nb) < first_sea:
					touches_land = true
			if n == 1 and not touches_land:
				Wn.append("sea_zones: la zona marítima %d está aislada (sin mar ni costa vecinos)" % start)
		if comp > 1:
			sizes.sort()
			sizes.reverse()
			Wn.append("conectividad marítima: %d masas de agua separadas (zonas: %s); las flotas no pasan entre ellas sin estrecho" % [comp, str(sizes.slice(0, 8))])

	# ---- historia y capitales
	if history_rel != "":
		if not FileAccess.file_exists(root + history_rel):
			E.append("falta la historia %s" % history_rel)
		else:
			var hist := VJson.load_dict(root + history_rel)
			for tag in hist.get("countries", {}):
				if not countries.has(tag):
					E.append("%s: país inexistente «%s»" % [history_rel, tag])
					continue
				var cap = hist["countries"][tag].get("capital", null)
				if cap != null and String(prov_owner.get(int(cap), "")) != tag:
					E.append("%s: la capital %s de %s no es suya" % [history_rel, str(cap), tag])
			for k in hist.get("provinces", {}):
				if not seen.has(int(k)):
					E.append("%s: provincia inexistente %s" % [history_rel, k])
				var h: Dictionary = hist["provinces"][k]
				if h.has("owner"):
					owned[String(h["owner"])] = int(owned.get(String(h["owner"]), 0)) + 1
	for tag in countries:
		var cap = countries[tag].get("capital", null)
		if cap != null and String(prov_owner.get(int(cap), "")) != tag:
			E.append("countries.json: la capital %s de %s no es suya" % [str(cap), tag])
		if int(owned.get(tag, 0)) == 0 and not bool(countries[tag].get("landless", false)):
			Wn.append("countries.json: %s no tiene provincias al inicio (márcalo \"landless\": true si es intencionado)" % tag)
	return r


## Valida el mundo de un escenario y su relación con él (paquetes prohibidos, historia).
static func validate_scenario(scenario_id: String) -> Dictionary:
	var sc := VWorlds.scenario(scenario_id)
	if sc.is_empty():
		return {"errors": ["escenario desconocido «%s»" % scenario_id], "warnings": []}
	var wid := VWorlds.world_of(sc)
	var r := validate(wid, String(sc.get("history", "")))
	var meta := VWorlds.world_meta(wid)
	for p in sc.get("content_packs", []):
		if String(p) in meta.get("forbidden_packs", []):
			r["errors"].append("escenario «%s»: el mundo «%s» no admite el paquete «%s»" % [scenario_id, wid, p])
		if not DirAccess.dir_exists_absolute(VWorlds.CONTENT_ROOT + "content/" + String(p)):
			r["errors"].append("escenario «%s»: paquete de contenido inexistente «%s»" % [scenario_id, p])
	return r


static func describe(r: Dictionary, limit: int = 20) -> String:
	var lines: Array = []
	for e in r["errors"].slice(0, limit):
		lines.append("ERROR  " + str(e))
	if r["errors"].size() > limit:
		lines.append("… y %d errores más" % (r["errors"].size() - limit))
	for w in r["warnings"].slice(0, limit):
		lines.append("AVISO  " + str(w))
	return "\n".join(lines)
