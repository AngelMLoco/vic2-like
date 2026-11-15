class_name VNavySystem
extends RefCounted
## Flotas sobre las zonas marítimas del mapa (mismos ids que las provincias, kind = "sea").
##
## Fleet: id, country, location (zona marítima, o provincia costera = atracada en puerto), ships[],
## admiral, path[], move_progress, mission, transported_armies[], battle.
## Movimiento: zona → zona vecina; solo se entra en tierra para atracar en un puerto propio/aliado/con
## acceso. Nunca se cruza tierra ni se salta entre costas.
## Transporte: un ejército en una provincia costera embarca en una flota atracada allí o en una zona
## marítima vecina; la capacidad (suma de 'transport' de los barcos) limita las brigadas; desembarca
## en una costa accesible vecina de la zona donde está la flota.
## Bloqueo: una flota en guerra, en el mar, bloquea las provincias costeras enemigas vecinas; eso
## suma warscore, cansancio y reduce el acceso del país bloqueado al mercado mundial (VMarketSystem).


static func setup_new_game(gs: VGameState) -> void:
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		c["ship_queue"] = []
		c["blockade_ratio"] = 0.0
		var n := int(c.get("military", {}).get("ships", 0))
		if n <= 0 or c["provinces"].is_empty():
			continue
		var port := home_port(gs, tag)
		if port <= 0:
			continue
		var f := new_fleet(gs, tag, port, "Flota de %s" % VMapLabels.short_name(c["name"]))
		var techs: Array = c.get("technologies", [])
		for i in n:
			var t := "frigate"
			if i % 10 in [2, 5, 8]:
				t = "transport"
			elif i % 10 == 9 and "ship_of_the_line" in techs:
				t = "man_o_war"
			f["ships"].append(new_ship(gs, t))
	update_counts(gs)


static func home_port(gs: VGameState, tag: String) -> int:
	var c: Dictionary = gs.countries[tag]
	var cap := int(c.get("capital", -1))
	if cap > 0 and gs.provinces[cap].get("coastal", false):
		return cap
	var best := -1
	for id in c["provinces"]:
		var p: Dictionary = gs.provinces[id]
		if p.get("coastal", false):
			if int(p.get("naval_base", 0)) > 0:
				return id
			if best < 0:
				best = id
	return best


static func new_fleet(gs: VGameState, tag: String, location: int, fleet_name: String = "") -> Dictionary:
	var id := gs.new_id("fleet")
	var f := {"id": id, "country": tag, "name": fleet_name if fleet_name != "" else "Flota %d" % id, "location": location,
		"ships": [], "admiral": 0, "path": [], "move_progress": 0.0, "mission": "idle", "transported_armies": [], "battle": 0, "organisation": 1.0}
	gs.fleets[id] = f
	return f


static func new_ship(gs: VGameState, type_id: String) -> Dictionary:
	return {"id": gs.new_id("ship"), "type": type_id, "hull": 1.0, "organisation": 1.0}


static func update_counts(gs: VGameState) -> void:
	var counts := {}
	for fid in gs.fleets:
		var f: Dictionary = gs.fleets[fid]
		counts[f["country"]] = int(counts.get(f["country"], 0)) + f["ships"].size()
	for tag in gs.countries:
		gs.countries[tag]["military"]["ships"] = int(counts.get(tag, 0))


static func country_fleets(gs: VGameState, tag: String) -> Array:
	var out := []
	for fid in gs.fleets:
		if gs.fleets[fid]["country"] == tag:
			out.append(gs.fleets[fid])
	return out


static func docked(gs: VGameState, f: Dictionary) -> bool:
	return gs.is_land(int(f["location"]))


static func is_sea(gs: VGameState, id: int) -> bool:
	return gs.province(id).get("kind", "") == "sea"


static func capacity(gs: VGameState, f: Dictionary) -> int:
	var cap := 0
	for s in f["ships"]:
		if float(s["hull"]) > 0.2:
			cap += int(gs.ship_types.get(s["type"], {}).get("transport", 0))
	return cap


static func carried_brigades(gs: VGameState, f: Dictionary) -> int:
	var n := 0
	for aid in f["transported_armies"]:
		n += gs.armies.get(aid, {}).get("brigades", []).size()
	return n


static func fleet_speed(gs: VGameState, f: Dictionary) -> float:
	var s := 9.0
	for sh in f["ships"]:
		s = minf(s, float(gs.ship_types.get(sh["type"], {}).get("speed", 1.0)))
	return 1.0 if s >= 9.0 else s


static func can_dock(gs: VGameState, tag: String, province_id: int) -> bool:
	if not gs.is_land(province_id):
		return false
	var p: Dictionary = gs.provinces[province_id]
	if not p.get("coastal", false):
		return false
	var owner: String = p["owner"]
	return owner == tag or VDiplomacySystem.are_allied(gs, tag, owner) or VDiplomacySystem.has_access(gs, tag, owner)


## Ruta naval (Dijkstra simple sobre zonas marítimas). El destino puede ser una zona o un puerto.
static func find_path(gs: VGameState, tag: String, from_id: int, to_id: int) -> Array:
	if from_id == to_id:
		return []
	if gs.is_land(to_id) and not can_dock(gs, tag, to_id):
		return []
	if not gs.is_land(to_id) and not is_sea(gs, to_id):
		return []
	var dist := {from_id: 0}
	var came := {}
	var frontier := [from_id]
	while not frontier.is_empty():
		var nxt := []
		for cur in frontier:
			for n in gs.provinces[cur]["neighbors"]:
				if dist.has(n):
					continue
				var ok: bool = is_sea(gs, n) or (n == to_id and gs.is_land(n))
				if not ok:
					continue
				dist[n] = int(dist[cur]) + 1
				came[n] = cur
				if n == to_id:
					var path := [n]
					var c2: int = n
					while came.has(c2) and came[c2] != from_id:
						c2 = came[c2]
						path.push_front(c2)
					return path
				if is_sea(gs, n):
					nxt.append(n)
		frontier = nxt
		if dist.size() > 3000:
			break
	return []


static func order_move(gs: VGameState, f: Dictionary, to_id: int) -> String:
	if int(f.get("battle", 0)) > 0:
		return "La flota está en combate."
	var path := find_path(gs, f["country"], int(f["location"]), to_id)
	if path.is_empty():
		return "No hay ruta marítima (solo se navega por zonas marítimas y se atraca en puertos propios, aliados o con acceso)."
	f["path"] = path
	f["move_progress"] = 0.0
	return ""


# ------------------------------------------------------------ transporte
static func can_load(gs: VGameState, army: Dictionary, f: Dictionary) -> String:
	if army["country"] != f["country"]:
		return "La flota es de otra nación."
	if int(army["battle"]) > 0 or army.get("retreating", false) or not army["path"].is_empty():
		return "El ejército debe estar detenido y fuera de combate."
	if int(army["embarked"]) > 0:
		return "Ya está embarcado."
	var prov := int(army["province"])
	if not gs.provinces[prov].get("coastal", false):
		return "El ejército debe estar en una provincia costera."
	var loc := int(f["location"])
	if loc != prov and not (loc in gs.provinces[prov]["neighbors"]):
		return "La flota debe estar atracada allí o en una zona marítima vecina."
	var free := capacity(gs, f) - carried_brigades(gs, f)
	if army["brigades"].size() > free:
		return "Capacidad de transporte insuficiente (%d brigadas libres, el ejército tiene %d)." % [free, army["brigades"].size()]
	return ""


static func load_army(gs: VGameState, army: Dictionary, f: Dictionary) -> String:
	var err := can_load(gs, army, f)
	if err != "":
		return err
	army["embarked"] = int(f["id"])
	army["path"] = []
	f["transported_armies"].append(int(army["id"]))
	return ""


static func can_unload(gs: VGameState, army: Dictionary, province_id: int) -> String:
	var fid := int(army.get("embarked", 0))
	if fid <= 0 or not gs.fleets.has(fid):
		return "El ejército no está embarcado."
	var f: Dictionary = gs.fleets[fid]
	if not f["path"].is_empty():
		return "La flota está navegando."
	if not gs.is_land(province_id) or not gs.provinces[province_id].get("coastal", false):
		return "Hay que desembarcar en una provincia costera."
	var loc := int(f["location"])
	if loc != province_id and not (loc in gs.provinces[province_id]["neighbors"]):
		return "La flota debe estar frente a esa costa."
	if not VArmySystem.can_enter(gs, army["country"], province_id):
		return "No tienes acceso a esa provincia."
	return ""


static func unload_army(gs: VGameState, army: Dictionary, province_id: int) -> String:
	var err := can_unload(gs, army, province_id)
	if err != "":
		return err
	var f: Dictionary = gs.fleets[int(army["embarked"])]
	f["transported_armies"].erase(int(army["id"]))
	army["embarked"] = 0
	army["province"] = province_id
	army["dig_in"] = 0
	VCombatSystem.on_army_arrived(gs, army)
	return ""


# ------------------------------------------------------------ diario
static func daily(gs: VGameState) -> void:
	# movimiento
	for fid in gs.fleets.keys():
		var f: Dictionary = gs.fleets.get(fid, {})
		if f.is_empty():
			continue
		if not f["path"].is_empty() and int(f.get("battle", 0)) == 0:
			f["move_progress"] = float(f["move_progress"]) + 1.0
			if float(f["move_progress"]) >= 3.0 / fleet_speed(gs, f):
				f["location"] = int(f["path"][0])
				f["path"].remove_at(0)
				f["move_progress"] = 0.0
				for aid in f["transported_armies"]:
					if gs.armies.has(aid):
						gs.armies[aid]["province"] = int(f["location"]) if gs.is_land(int(f["location"])) else int(gs.armies[aid]["province"])
		# reparación en puerto propio con base naval
		if docked(gs, f):
			var p: Dictionary = gs.provinces[int(f["location"])]
			var base := int(p.get("naval_base", 0))
			for s in f["ships"]:
				s["hull"] = minf(1.0, float(s["hull"]) + (0.02 if base > 0 else 0.005))
				s["organisation"] = minf(1.0, float(s["organisation"]) + 0.05)
		else:
			for s in f["ships"]:
				s["organisation"] = minf(1.0, float(s["organisation"]) + 0.01)
	_naval_battles(gs)
	_blockades(gs)
	_build_queue(gs)


static func _naval_battles(gs: VGameState) -> void:
	var by_zone := {}
	for fid in gs.fleets:
		var f: Dictionary = gs.fleets[fid]
		if docked(gs, f) or f["ships"].is_empty():
			continue
		var z := int(f["location"])
		if not by_zone.has(z):
			by_zone[z] = []
		by_zone[z].append(f)
	for z in by_zone:
		var fl: Array = by_zone[z]
		if fl.size() < 2:
			continue
		for i in fl.size():
			for j in range(i + 1, fl.size()):
				var a: Dictionary = fl[i]
				var b: Dictionary = fl[j]
				if VWarSystem.at_war_with(gs, a["country"], b["country"]) and int(a.get("battle", 0)) == 0 and int(b.get("battle", 0)) == 0:
					var res := VNavalBattleResolver.fight(gs, a, b)
					_finish_naval(gs, a, b, res)


static func _finish_naval(gs: VGameState, a: Dictionary, b: Dictionary, res: Dictionary) -> void:
	var winner: Dictionary = a if res["winner"] == "a" else b
	var loser: Dictionary = b if res["winner"] == "a" else a
	var wid := VWarSystem.war_between(gs, a["country"], b["country"])
	if wid > 0:
		var w: Dictionary = gs.wars[wid]
		var sign := 1.0 if VWarSystem.side_of(w, winner["country"]) == "attackers" else -1.0
		w["battle_ws"] = clampf(float(w["battle_ws"]) + sign * clampf(1.0 + float(res["sunk"]) * 1.5, 1.0, 8.0), -40.0, 40.0)
	var txt := "Batalla naval en %s: vence %s (%d barcos hundidos)" % [gs.provinces[int(a["location"])]["name"], gs.country_name(winner["country"]), int(res["sunk"])]
	gs.log_event(a["country"], txt)
	gs.log_event(b["country"], txt)
	for f in [a, b]:
		if f["ships"].is_empty():
			for aid in f["transported_armies"].duplicate():
				if gs.armies.has(aid):
					VArmySystem.stack_wipe(gs, gs.armies[aid])
			gs.fleets.erase(int(f["id"]))
	if gs.fleets.has(int(loser["id"])):
		var port := nearest_port(gs, loser)
		if port > 0:
			order_move(gs, loser, port)
	update_counts(gs)


static func nearest_port(gs: VGameState, f: Dictionary) -> int:
	var tag: String = f["country"]
	var start := int(f["location"])
	var seen := {start: true}
	var frontier := [start]
	var depth := 0
	while not frontier.is_empty() and depth < 40:
		var nxt := []
		for cur in frontier:
			for n in gs.provinces[cur]["neighbors"]:
				if seen.has(n):
					continue
				seen[n] = true
				if gs.is_land(n) and can_dock(gs, tag, n) and gs.provinces[n]["controller"] == gs.provinces[n]["owner"]:
					return n
				if is_sea(gs, n):
					nxt.append(n)
		frontier = nxt
		depth += 1
	return -1


static func _blockades(gs: VGameState) -> void:
	var prev: Dictionary = gs.market.get("_blockaded", {})
	for id in prev:
		gs.provinces[id]["blockaded_by"] = ""
	var now := {}
	for fid in gs.fleets:
		var f: Dictionary = gs.fleets[fid]
		if docked(gs, f) or f["ships"].is_empty():
			continue
		var war_ships := 0
		for s in f["ships"]:
			if float(gs.ship_types.get(s["type"], {}).get("attack", 0.0)) > 0.0:
				war_ships += 1
		if war_ships == 0:
			continue
		for n in gs.provinces[int(f["location"])]["neighbors"]:
			if not gs.is_land(n):
				continue
			var p: Dictionary = gs.provinces[n]
			if VWarSystem.at_war_with(gs, f["country"], p["owner"]):
				p["blockaded_by"] = f["country"]
				now[n] = true
	gs.market["_blockaded"] = now
	if gs.date.day == 1 or not now.is_empty() or not prev.is_empty():
		for tag in gs.country_order:
			var c: Dictionary = gs.countries[tag]
			var coastal := 0
			var bl := 0
			for id in c["provinces"]:
				if gs.provinces[id].get("coastal", false):
					coastal += 1
					if now.has(id):
						bl += 1
			c["blockade_ratio"] = float(bl) / float(coastal) if coastal > 0 else 0.0
			if bl > 0:
				c["war_exhaustion"] = minf(100.0, float(c.get("war_exhaustion", 0.0)) + 0.02 * float(c["blockade_ratio"]))


# ------------------------------------------------------- construcción
static func can_build(gs: VGameState, tag: String, port: int, type_id: String) -> String:
	var p := gs.province(port)
	if p.is_empty() or p.get("owner", "") != tag or p["controller"] != tag:
		return "Hay que construir en un puerto propio no ocupado."
	if int(p.get("naval_base", 0)) <= 0:
		return "La provincia no tiene base naval."
	var st: Dictionary = gs.ship_types.get(type_id, {})
	if st.is_empty():
		return "Tipo de barco desconocido."
	var req: String = st.get("requires_tech", "")
	if req != "" and not (req in gs.countries[tag].get("technologies", [])):
		return "Requiere la tecnología «%s»." % gs.technologies.get(req, {}).get("name", req)
	return ""


static func build(gs: VGameState, tag: String, port: int, type_id: String) -> String:
	var err := can_build(gs, tag, port, type_id)
	if err != "":
		return err
	var st: Dictionary = gs.ship_types[type_id]
	var cost := 0.0
	for g in st.get("build_cost", {}):
		var q := float(st["build_cost"][g])
		var stock := float(gs.countries[tag]["stockpile"].get(g, 0.0))
		var take := minf(stock, q)
		gs.countries[tag]["stockpile"][g] = stock - take
		if q > take:
			VMarketSystem.add_demand(gs, tag, g, q - take)
			cost += (q - take) * VMarketSystem.buy_price(gs, tag, g)
	VBudgetSystem.add_expense(gs, tag, "construction", cost)
	gs.countries[tag]["ship_queue"].append({"type": type_id, "port": port, "days": int(st.get("days", 90))})
	return ""


static func _build_queue(gs: VGameState) -> void:
	for tag in gs.country_order:
		var q: Array = gs.countries[tag].get("ship_queue", [])
		if q.is_empty():
			continue
		for item in q.duplicate():
			item["days"] = int(item["days"]) - 1
			if int(item["days"]) <= 0:
				q.erase(item)
				var port := int(item["port"])
				var target: Dictionary = {}
				for f in country_fleets(gs, tag):
					if int(f["location"]) == port and f["path"].is_empty():
						target = f
						break
				if target.is_empty():
					target = new_fleet(gs, tag, port)
				target["ships"].append(new_ship(gs, item["type"]))
				update_counts(gs)
				gs.log_event(tag, "Botado un %s en %s" % [gs.ship_types[item["type"]]["name"], gs.provinces[port]["name"]])
