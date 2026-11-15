class_name VArmySystem
extends RefCounted
## Ejércitos y brigadas.
##
## Army → Brigades → Soldier POP. Cada brigada guarda source_pop_id y source_province_id: sus hombres
## SON parte de ese POP de soldados. Las bajas restan personas al POP; el refuerzo solo puede devolver
## la brigada hasta lo que el POP puede sostener (tamaño del POP / brigadas que mantiene, máx. 3000).
## No existe una reserva abstracta de "manpower".
##
## Movimiento: rutas por la vecindad de provincias del mapa (incluye pasos de gs.adjacencies),
## coste según terreno, infraestructura, distancia y velocidad; acceso según propiedad, control,
## guerra, alianza en guerra y acceso militar. Nada se teletransporta.

const DAYS_BASE := 5.0


static func setup_new_game(gs: VGameState) -> void:
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		c["leadership"] = 10.0
		c["casualties"] = 0
		c["disarmed_until"] = -1
		var want := int(c.get("military", {}).get("brigades", 0))
		c["base_brigades"] = want
		if want > 0 and not c["provinces"].is_empty():
			_create_initial_army(gs, tag, want)
	update_counts(gs)


static func _create_initial_army(gs: VGameState, tag: String, want: int) -> void:
	var c: Dictionary = gs.countries[tag]
	var ps := gs.pops
	var pops := []
	for id in c["provinces"]:
		for s in gs.provinces[id]["pop_slots"]:
			if ps.type_id[s] == ps.T_SOLDIERS:
				pops.append(s)
	pops.sort_custom(func(a, b): return ps.size[a] > ps.size[b])
	var techs: Array = c.get("technologies", [])
	var made := 0
	var by_state := {}
	for pop in pops:
		var cap: int = ps.size[pop] / gs.unit_manpower
		for k in cap:
			if made >= want:
				break
			var utype := "infantry"
			if made % 5 == 3:
				utype = "cavalry"
			elif made % 5 == 4 and "siege_engineering" in techs:
				utype = "artillery"
			var b := _new_brigade(gs, utype, pop, ps.province[pop])
			b["organisation"] = 1.0
			var sid := int(gs.provinces[ps.province[pop]]["state"])
			if not by_state.has(sid):
				by_state[sid] = []
			by_state[sid].append(b)
			made += 1
		if made >= want:
			break
	var n := 1
	for sid in by_state:
		var list: Array = by_state[sid]
		var i := 0
		while i < list.size():
			var chunk: Array = list.slice(i, i + 10)
			var prov := int(chunk[0]["source_province_id"])
			var army := new_army(gs, tag, prov, "%d.º Ejército" % n)
			for b in chunk:
				attach_brigade(gs, army, b)
			n += 1
			i += 10


## Brigada nueva sacada del Soldier POP del slot 's' (enlace por id estable del POP).
static func _new_brigade(gs: VGameState, utype: String, s: int, province_id: int) -> Dictionary:
	var id := gs.new_id("brigade")
	var b := {"id": id, "type": utype, "strength": gs.unit_manpower, "organisation": 0.3, "experience": 0.0,
		"source_pop_id": gs.pops.id[s], "source_province_id": province_id, "army": 0}
	gs.brigades[id] = b
	gs.pops.brigade_links(s).append(id)
	return b


static func new_army(gs: VGameState, tag: String, province_id: int, army_name: String = "") -> Dictionary:
	var id := gs.new_id("army")
	var a := {"id": id, "country": tag, "name": army_name if army_name != "" else "Ejército %d" % id, "province": province_id,
		"brigades": [], "leader": 0, "morale": 1.0, "path": [], "move_progress": 0.0, "retreating": false, "dig_in": 0,
		"supply": 1.0, "battle": 0, "embarked": 0, "rebel_faction": 0, "ai_target": 0, "attrition": 0.0}
	gs.armies[id] = a
	VUnitIndex.army_created(gs, a)
	return a


static func attach_brigade(gs: VGameState, army: Dictionary, b: Dictionary) -> void:
	if int(b.get("army", 0)) > 0 and gs.armies.has(int(b["army"])):
		var old: Dictionary = gs.armies[int(b["army"])]
		old["brigades"].erase(int(b["id"]))
		old.erase("_need")
	b["army"] = int(army["id"])
	if not (int(b["id"]) in army["brigades"]):
		army["brigades"].append(int(b["id"]))
	army.erase("_need")
	army.erase("_org_full")
	if int(b["strength"]) < gs.unit_manpower:
		VUnitIndex.mark_damaged(gs, int(army["id"]))


static func update_counts(gs: VGameState) -> void:
	for tag in gs.countries:
		update_country_count(gs, tag)


static func update_country_count(gs: VGameState, tag: String) -> void:
	var n := 0
	for a in VUnitIndex.country_armies(gs, tag):
		n += a["brigades"].size()
	gs.countries[tag]["military"]["brigades"] = n


# ------------------------------------------------------------ Soldier POP
## Slot del POP por id estable (O(1); los ids de POPs fusionados resuelven al que los absorbió). −1 si no existe.
## (province_id se conserva en la firma por compatibilidad: ya no hace falta recorrer la provincia)
static func find_pop(gs: VGameState, _province_id: int, pop_id: int) -> int:
	return gs.pops.slot_of(pop_id)


## Slot del Soldier POP de origen de la brigada (cacheado en «_pop», validado por id; no se guarda).
static func brigade_pop(gs: VGameState, b: Dictionary) -> int:
	var ps := gs.pops
	var pid := int(b["source_pop_id"])
	var ref := int(b.get("_pop", -1))
	if ref >= 0 and ps.is_alive(ref) and ps.id[ref] == pid:
		return ref
	var s := ps.slot_of(pid)
	if s >= 0:
		b["_pop"] = s
	return s


## Hombres que el POP de origen puede sostener por brigada (para el refuerzo).
static func supportable(gs: VGameState, b: Dictionary) -> int:
	var s := brigade_pop(gs, b)
	if s < 0:
		return 0
	var linked: int = maxi(1, gs.pops.brigade_count(s))
	return mini(gs.unit_manpower, gs.pops.size[s] / linked)


## Bajas: la brigada pierde hombres y el POP de origen pierde personas reales.
static func apply_casualties(gs: VGameState, b: Dictionary, men: int, tag: String) -> int:
	men = mini(men, int(b["strength"]))
	if men <= 0:
		return 0
	b["strength"] = int(b["strength"]) - men
	VUnitIndex.mark_damaged(gs, int(b.get("army", 0)))
	# (las brigadas rebeldes ya sacaron a sus hombres del POP al alzarse)
	var ps_s := -1 if b.get("rebel", false) else brigade_pop(gs, b)
	if ps_s >= 0:
		gs.pops.size[ps_s] = maxi(1, gs.pops.size[ps_s] - men)
	if gs.countries.has(tag):
		gs.countries[tag]["casualties"] = int(gs.countries[tag].get("casualties", 0)) + men
	return men


static func army_strength(gs: VGameState, army: Dictionary) -> int:
	var t := 0
	var brigades: Dictionary = gs.brigades
	for bid in army["brigades"]:
		var b = brigades.get(bid)
		if b != null:
			t += int(b["strength"])
	return t


static func army_organisation(gs: VGameState, army: Dictionary) -> float:
	var t := 0.0
	var n := 0
	for bid in army["brigades"]:
		if gs.brigades.has(bid):
			t += float(gs.brigades[bid]["organisation"])
			n += 1
	return t / float(n) if n > 0 else 0.0


## Puntuación de combate aproximada (para IA): hombres × organización × ataque/defensa.
static func army_power(gs: VGameState, army: Dictionary) -> float:
	var t := 0.0
	for bid in army["brigades"]:
		var b: Dictionary = gs.brigades.get(bid, {})
		if b.is_empty():
			continue
		var ut: Dictionary = gs.unit_types.get(b["type"], {})
		t += float(b["strength"]) / 1000.0 * (0.3 + float(b["organisation"])) * (float(ut.get("attack", 2.0)) + float(ut.get("defence", 2.0)))
	return t


static func destroy_army(gs: VGameState, army: Dictionary, return_men: bool = false) -> void:
	for bid in army["brigades"].duplicate():
		var b: Dictionary = gs.brigades.get(bid, {})
		if b.is_empty():
			continue
		var ps_s := brigade_pop(gs, b)
		if ps_s >= 0:
			if gs.pops.brigades[ps_s] != null:
				(gs.pops.brigades[ps_s] as Array).erase(int(bid))
			if return_men:
				gs.pops.size[ps_s] += int(b["strength"])
		gs.brigades.erase(bid)
	if int(army.get("leader", 0)) > 0 and gs.leaders.has(int(army["leader"])):
		gs.leaders[int(army["leader"])]["army"] = 0
	if int(army.get("embarked", 0)) > 0 and gs.fleets.has(int(army["embarked"])):
		gs.fleets[int(army["embarked"])]["transported_armies"].erase(int(army["id"]))
	VUnitIndex.army_destroyed(gs, army)
	gs.armies.erase(int(army["id"]))


## Stack wipe: el ejército desaparece y sus hombres mueren (los POPs de origen los pierden).
static func stack_wipe(gs: VGameState, army: Dictionary) -> void:
	var tag: String = army["country"]
	var lost := 0
	for bid in army["brigades"].duplicate():
		var b: Dictionary = gs.brigades.get(bid, {})
		if not b.is_empty():
			lost += apply_casualties(gs, b, int(b["strength"]), tag)
	gs.log_event(tag, "%s aniquilado (stack wipe): %s bajas" % [army["name"], UiTheme.fmt_int(lost)])
	destroy_army(gs, army)
	if gs.countries.has(tag):
		update_country_count(gs, tag)


# ------------------------------------------------------------- reclutar
static func can_recruit(gs: VGameState, tag: String, province_id: int, utype: String) -> Dictionary:
	var res := {"ok": false, "reason": "", "pop": -1}
	var p := gs.province(province_id)
	if p.is_empty() or p.get("owner", "") != tag:
		res["reason"] = "Hay que reclutar en una provincia propia."
		return res
	if p["controller"] != tag:
		res["reason"] = "La provincia está ocupada."
		return res
	var ut: Dictionary = gs.unit_types.get(utype, {})
	if ut.is_empty():
		res["reason"] = "Tipo de unidad desconocido."
		return res
	var req: String = ut.get("requires_tech", "")
	if req != "" and not (req in gs.countries[tag].get("technologies", [])):
		res["reason"] = "Requiere la tecnología «%s»." % gs.technologies.get(req, {}).get("name", req)
		return res
	if int(gs.countries[tag].get("disarmed_until", -1)) > gs.month_index:
		res["reason"] = "La nación está desarmada por un tratado de paz."
		return res
	var ps := gs.pops
	for s in p["pop_slots"]:
		if ps.type_id[s] != ps.T_SOLDIERS:
			continue
		if ps.size[s] >= (ps.brigade_count(s) + 1) * gs.unit_manpower:
			res["ok"] = true
			res["pop"] = s
			return res
	res["reason"] = "No hay soldados suficientes en %s (cada brigada necesita %s soldados de un POP sin vincular)." % [p["name"], UiTheme.fmt_int(gs.unit_manpower)]
	return res


static func recruit(gs: VGameState, tag: String, province_id: int, utype: String) -> Dictionary:
	var chk := can_recruit(gs, tag, province_id, utype)
	if not chk["ok"]:
		return {"error": chk["reason"]}
	var ut: Dictionary = gs.unit_types[utype]
	var cost := 0.0
	for g in ut.get("build_cost", {}):
		var q := float(ut["build_cost"][g])
		var stock := float(gs.countries[tag]["stockpile"].get(g, 0.0))
		var from_stock := minf(stock, q)
		gs.countries[tag]["stockpile"][g] = stock - from_stock
		var rest := q - from_stock
		if rest > 0.0:
			VMarketSystem.add_demand(gs, tag, g, rest)
			cost += rest * VMarketSystem.buy_price(gs, tag, g)
	VBudgetSystem.add_expense(gs, tag, "stockpile", cost)
	var b := _new_brigade(gs, utype, chk["pop"], province_id)
	var army: Dictionary = {}
	for a in VUnitIndex.armies_in(gs, province_id):
		if a["country"] == tag and int(a["battle"]) == 0 and a["path"].is_empty() and int(a.get("rebel_faction", 0)) == 0:
			army = a
			break
	if army.is_empty():
		army = new_army(gs, tag, province_id)
	attach_brigade(gs, army, b)
	update_country_count(gs, tag)
	return {"army": army, "brigade": b}


# ---------------------------------------------- reorganizar / líderes
static func merge(gs: VGameState, target: Dictionary, others: Array) -> String:
	for o in others:
		if int(o["id"]) == int(target["id"]):
			continue
		if int(o["province"]) != int(target["province"]) or o["country"] != target["country"]:
			return "Solo se pueden fusionar ejércitos de la misma nación en la misma provincia."
		if int(o["battle"]) > 0 or int(target["battle"]) > 0:
			return "No se puede fusionar en combate."
	for o in others:
		if int(o["id"]) == int(target["id"]):
			continue
		for bid in o["brigades"].duplicate():
			attach_brigade(gs, target, gs.brigades[bid])
		if int(target["leader"]) == 0 and int(o["leader"]) > 0:
			target["leader"] = o["leader"]
			gs.leaders[int(o["leader"])]["army"] = int(target["id"])
			o["leader"] = 0
		destroy_army(gs, o)
	return ""


static func split(gs: VGameState, army: Dictionary) -> Dictionary:
	if army["brigades"].size() < 2 or int(army["battle"]) > 0 or int(army["embarked"]) > 0:
		return {}
	var half: Array = army["brigades"].slice(army["brigades"].size() / 2)
	var na := new_army(gs, army["country"], int(army["province"]), army["name"] + " (b)")
	na["morale"] = army["morale"]
	for bid in half:
		attach_brigade(gs, na, gs.brigades[bid])
	return na


## Reorganizar: separa en un ejército aparte las brigadas muy dañadas (fuerza < 50 %).
static func reorganise(gs: VGameState, army: Dictionary) -> Dictionary:
	var weak := []
	for bid in army["brigades"]:
		if int(gs.brigades[bid]["strength"]) < gs.unit_manpower / 2:
			weak.append(bid)
	if weak.is_empty() or weak.size() == army["brigades"].size():
		return {}
	var na := new_army(gs, army["country"], int(army["province"]), army["name"] + " (reserva)")
	for bid in weak:
		attach_brigade(gs, na, gs.brigades[bid])
	return na


static func attach_leader(gs: VGameState, army: Dictionary, leader_id: int) -> String:
	var l: Dictionary = gs.leaders.get(leader_id, {})
	if l.is_empty() or l["country"] != army["country"] or l["kind"] != "general":
		return "Líder no válido."
	if int(l.get("army", 0)) > 0 and gs.armies.has(int(l["army"])):
		gs.armies[int(l["army"])]["leader"] = 0
	if int(army["leader"]) > 0 and gs.leaders.has(int(army["leader"])):
		gs.leaders[int(army["leader"])]["army"] = 0
	army["leader"] = leader_id
	l["army"] = int(army["id"])
	return ""


static func detach_leader(gs: VGameState, army: Dictionary) -> void:
	if int(army["leader"]) > 0 and gs.leaders.has(int(army["leader"])):
		gs.leaders[int(army["leader"])]["army"] = 0
	army["leader"] = 0


static func leader_stat(gs: VGameState, army: Dictionary, stat: String) -> float:
	var l: Dictionary = gs.leaders.get(int(army.get("leader", 0)), {})
	return float(l.get(stat, 0.0))


# ------------------------------------------------------------- movimiento
## ¿Puede un ejército de 'tag' (o rebelde de la facción) entrar en la provincia?
static func can_enter(gs: VGameState, tag: String, province_id: int, rebel_faction: int = 0) -> bool:
	if not gs.is_land(province_id):
		return false
	var p: Dictionary = gs.provinces[province_id]
	var owner: String = p["owner"]
	var ctrl: String = p["controller"]
	if rebel_faction > 0:
		var f: Dictionary = gs.rebel_factions.get(rebel_faction, {})
		return not f.is_empty() and owner == f["country"]
	if owner == "" or owner == tag or ctrl == tag:
		return true
	var en := VWarSystem.enemies_of(gs, tag)
	if en.has(owner) or en.has(ctrl):
		return true
	if VDiplomacySystem.has_access(gs, tag, owner):
		return true
	if VDiplomacySystem.are_allied(gs, tag, owner) and VWarSystem.shared_war(gs, tag, owner):
		return true
	return false


static func army_speed(gs: VGameState, army: Dictionary) -> float:
	var s := 9.0
	for bid in army["brigades"]:
		var b: Dictionary = gs.brigades.get(bid, {})
		if not b.is_empty():
			s = minf(s, float(gs.unit_types.get(b["type"], {}).get("speed", 1.0)))
	if s >= 9.0:
		s = 1.0
	return s * (1.0 + leader_stat(gs, army, "speed")) * (1.5 if army.get("retreating", false) else 1.0)


## Días para pasar de una provincia a otra vecina.
static func step_days(gs: VGameState, from_id: int, to_id: int, speed: float) -> float:
	var to: Dictionary = gs.provinces[to_id]
	var terr := float(gs.terrain_types.get(to.get("terrain", "plains"), {}).get("movement_cost", 1.0))
	var dist := (gs.provinces[from_id]["center"] as Vector2).distance_to(to["center"])
	var dist_f := clampf(dist / 35.0, 0.6, 3.0)
	return DAYS_BASE * terr * dist_f / (1.0 + 0.15 * float(to.get("infrastructure", 0))) / maxf(0.2, speed)


## Ruta (A*, montículo binario) por provincias accesibles. Devuelve [ids sin el origen] o [] si no hay.
## Las búsquedas fallidas se recuerdan 30 días por (nación, origen, destino) para no repetirlas.
static func find_path(gs: VGameState, tag: String, from_id: int, to_id: int, speed: float = 1.0, rebel_faction: int = 0, max_nodes: int = 4000) -> Array:
	if from_id == to_id or not can_enter(gs, tag, to_id, rebel_faction):
		return []
	VProfiler.count(gs, "path_requests")
	# provincias en masas de tierra distintas: nunca hay ruta terrestre (sin A*)
	if _component(gs, from_id) != _component(gs, to_id):
		VProfiler.count(gs, "path_unreachable_component")
		return []
	var key := "%s|%d|%d|%d" % [tag, rebel_faction, from_id, to_id]
	var pc := gs.path_cache
	if int(pc.get("_ver", -1)) != gs.access_version or int(pc.get("_epoch", -1)) != gs.path_epoch or pc.size() > 20000:
		pc.clear()
		pc["_ver"] = gs.access_version
		pc["_epoch"] = gs.path_epoch
	var hit = pc.get(key)
	if hit != null:
		if hit is Array:
			VProfiler.count(gs, "path_cache_hits")
			return hit.duplicate()
		if int(hit) > gs.date.ordinal():
			VProfiler.count(gs, "path_fail_cache_hits")
			return []
	# regiones de acceso: si origen y destino están en regiones distintas no hay ruta (sin A*)
	var lf := _reach_label(gs, tag, rebel_faction, from_id)
	if lf > 0 and lf != _reach_label(gs, tag, rebel_faction, to_id):
		VProfiler.count(gs, "path_unreachable_access")
		pc[key] = gs.date.ordinal() + 30
		return []
	var tp := VProfiler.begin()
	var res := _astar(gs, tag, from_id, to_id, speed, rebel_faction, max_nodes)
	VProfiler.end(gs, "pathfinding", tp)
	if res.is_empty():
		VProfiler.count(gs, "path_failed")
		pc[key] = gs.date.ordinal() + 30  # fallo recordado 30 días (o hasta que cambie el acceso)
	else:
		VProfiler.count(gs, "path_successful")
		pc[key] = res.duplicate()  # la ruta óptima no depende de la velocidad (coste ∝ 1/velocidad)
	return res


## Región de acceso de una provincia para 'tag': componente conexa de las provincias en las que puede
## entrar (misma validez que la caché de rutas: versión de acceso y época). Se rellena por inundación,
## una vez por región. Devuelve -1 si 'tag' no puede entrar en la provincia.
## Como can_enter solo depende de la provincia de destino, dos provincias accesibles están conectadas
## por una ruta válida si y solo si comparten región: A* solo se lanza cuando va a tener éxito.
static func _reach_label(gs: VGameState, tag: String, rf: int, id: int) -> int:
	var rkey := "_reach|%s|%d" % [tag, rf]
	var labels: Dictionary = gs.path_cache.get(rkey, {})
	if labels.is_empty():
		gs.path_cache[rkey] = labels
	if labels.has(id):
		return int(labels[id])
	if not can_enter(gs, tag, id, rf):
		return -1
	var lab := int(gs.path_cache.get(rkey + "#n", 0)) + 1
	gs.path_cache[rkey + "#n"] = lab
	labels[id] = lab
	var stack := [id]
	var n_flood := 0
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		n_flood += 1
		for n in gs.provinces[cur]["neighbors"]:
			if n > 0 and n < gs.first_sea_id and not labels.has(n) and can_enter(gs, tag, n, rf):
				labels[n] = lab
				stack.append(n)
	VProfiler.count(gs, "path_region_floods")
	VProfiler.count(gs, "path_region_nodes", n_flood)
	return lab


## Presupuesto diario de búsquedas A* nuevas para la IA (las rutas cacheadas no cuentan).
static func reset_path_budget(gs: VGameState, n: int) -> void:
	var ix := gs.unit_index
	if ix.is_empty():
		VUnitIndex.rebuild(gs)
		ix = gs.unit_index
	ix["pb"] = n


static func path_budget_left(gs: VGameState) -> int:
	return int(gs.unit_index.get("pb", 1 << 30))


## ¿Se puede pedir ya la ruta de este ejército? Sí si está en caché (éxito o fallo), si es trivial o si
## queda presupuesto (que se consume).
static func path_ready(gs: VGameState, army: Dictionary, to_id: int) -> bool:
	var from := int(army["province"])
	if from == to_id or _component(gs, from) != _component(gs, to_id):
		return true
	var pc := gs.path_cache
	if int(pc.get("_ver", -1)) == gs.access_version and int(pc.get("_epoch", -1)) == gs.path_epoch:
		if pc.has("%s|%d|%d|%d" % [army["country"], int(army.get("rebel_faction", 0)), from, to_id]):
			return true
		# destino en otra región de acceso: la respuesta (sin ruta) es inmediata
		var rf := int(army.get("rebel_faction", 0))
		var lf := _reach_label(gs, army["country"], rf, from)
		if lf > 0 and lf != _reach_label(gs, army["country"], rf, to_id):
			return true
	var left := path_budget_left(gs)
	if left <= 0:
		return false
	gs.unit_index["pb"] = left - 1
	return true


## Componente conexa terrestre (por vecindad + pasos de gs.adjacencies), calculada una vez.
static func _component(gs: VGameState, id: int) -> int:
	if gs.land_component.is_empty():
		var comp := PackedInt32Array()
		comp.resize(gs.first_sea_id)
		comp.fill(-1)
		var n_comp := 0
		for start in range(1, gs.first_sea_id):
			if comp[start] >= 0 or gs.provinces[start] == null:
				continue
			comp[start] = n_comp
			var stack := [start]
			while not stack.is_empty():
				var cur: int = stack.pop_back()
				for n in gs.provinces[cur]["neighbors"]:
					if n > 0 and n < gs.first_sea_id and comp[n] < 0:
						comp[n] = n_comp
						stack.append(n)
			n_comp += 1
		gs.land_component = comp
	return gs.land_component[id] if id > 0 and id < gs.first_sea_id else -1


static func _astar(gs: VGameState, tag: String, from_id: int, to_id: int, speed: float, rebel_faction: int, max_nodes: int) -> Array:
	var goal: Vector2 = gs.provinces[to_id]["center"]
	var heap := [[0.0, from_id]]
	var g := {from_id: 0.0}
	var came := {}
	var closed := {}
	var expanded := 0
	var hk := DAYS_BASE * 0.6 / maxf(0.2, speed) / 35.0
	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var cur: int = top[1]
		if closed.has(cur):
			continue
		if cur == to_id:
			var path := [cur]
			while came.has(cur):
				cur = came[cur]
				if cur != from_id:
					path.push_front(cur)
			VProfiler.count(gs, "path_nodes_expanded", expanded)
			VProfiler.count_max(gs, "path_max_nodes", expanded)
			return path
		closed[cur] = true
		expanded += 1
		if expanded > max_nodes:
			break
		for n in gs.provinces[cur]["neighbors"]:
			if closed.has(n) or not can_enter(gs, tag, n, rebel_faction):
				continue
			var cost := float(g[cur]) + step_days(gs, cur, n, speed)
			if not g.has(n) or cost < float(g[n]):
				g[n] = cost
				came[n] = cur
				_heap_push(heap, [cost + (gs.provinces[n]["center"] as Vector2).distance_to(goal) * hk, n])
	VProfiler.count(gs, "path_nodes_expanded", expanded)
	VProfiler.count_max(gs, "path_max_nodes", expanded)
	return []


static func _heap_push(h: Array, item: Array) -> void:
	h.append(item)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if float(h[p][0]) <= float(item[0]):
			break
		h[i] = h[p]
		i = p
	h[i] = item


static func _heap_pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if h.is_empty():
		return top
	var i := 0
	var n := h.size()
	while true:
		var l := i * 2 + 1
		if l >= n:
			break
		var r := l + 1
		var c := l if r >= n or float(h[l][0]) <= float(h[r][0]) else r
		if float(h[c][0]) >= float(last[0]):
			break
		h[i] = h[c]
		i = c
	h[i] = last
	return top


## Orden de movimiento. queue = true añade la ruta al final de la actual (tecla Mayús).
static func order_move(gs: VGameState, army: Dictionary, to_id: int, queue: bool = false) -> String:
	if army.get("retreating", false):
		return "El ejército está en retirada y no acepta órdenes."
	if int(army["battle"]) > 0:
		return "El ejército está en combate."
	if int(army["embarked"]) > 0:
		return "El ejército está embarcado: desembárcalo desde la flota."
	var start := int(army["province"])
	if queue and not army["path"].is_empty():
		start = int(army["path"][-1])
	var path := find_path(gs, army["country"], start, to_id, army_speed(gs, army), int(army.get("rebel_faction", 0)))
	if path.is_empty():
		return "No hay ruta terrestre accesible hasta %s (acceso militar, mar o territorio neutral)." % gs.provinces[to_id]["name"]
	if queue:
		army["path"].append_array(path)
	else:
		army["path"] = path
		army["move_progress"] = 0.0
	army["dig_in"] = 0
	return ""


static func stop(army: Dictionary) -> void:
	if not army.get("retreating", false):
		army["path"] = []
		army["move_progress"] = 0.0


## Avance diario de todos los ejércitos. Llama a VCombatSystem al entrar en provincias con enemigos.
static func daily_movement(gs: VGameState) -> void:
	for aid in gs.armies.keys():
		var a: Dictionary = gs.armies.get(aid, {})
		if a.is_empty() or a["path"].is_empty() or int(a["battle"]) > 0 or int(a["embarked"]) > 0:
			if not a.is_empty() and a["path"].is_empty():
				var dig := int(a.get("dig_in", 0))
				if dig < 60:
					a["dig_in"] = dig + 1
			continue
		var nxt := int(a["path"][0])
		if not can_enter(gs, a["country"], nxt, int(a.get("rebel_faction", 0))):
			a["path"] = []
			a["move_progress"] = 0.0
			gs.path_epoch += 1  # una ruta cacheada ya no es válida: se recalculan todas
			continue
		a["move_progress"] = float(a["move_progress"]) + 1.0
		if float(a["move_progress"]) >= step_days(gs, int(a["province"]), nxt, army_speed(gs, a)):
			VUnitIndex.move_army(gs, a, nxt)
			a["path"].remove_at(0)
			a["move_progress"] = 0.0
			a["dig_in"] = 0
			if a["path"].is_empty() and a.get("retreating", false):
				a["retreating"] = false
			if not a.get("retreating", false):
				VCombatSystem.on_army_arrived(gs, a)


## Retirada: a la provincia amiga más cercana sin enemigos; si no existe, stack wipe.
static func start_retreat(gs: VGameState, army: Dictionary) -> void:
	var tag: String = army["country"]
	var rf := int(army.get("rebel_faction", 0))
	var start := int(army["province"])
	var seen := {start: true}
	var frontier := [start]
	var parent := {}
	var target := -1
	var depth := 0
	while not frontier.is_empty() and depth < 10 and target < 0:
		var nxt := []
		for cur in frontier:
			for n in gs.provinces[cur]["neighbors"]:
				if seen.has(n) or not can_enter(gs, tag, n, rf):
					continue
				seen[n] = true
				parent[n] = cur
				var p: Dictionary = gs.provinces[n]
				var friendly: bool = (p["controller"] == tag or (rf == 0 and VDiplomacySystem.are_allied(gs, tag, p["controller"])) or (rf > 0 and p["controller"] == VGameState.REBEL_TAG))
				if friendly and not VCombatSystem.hostile_present(gs, army, n):
					target = n
					break
				nxt.append(n)
			if target >= 0:
				break
		frontier = nxt
		depth += 1
	if target < 0:
		stack_wipe(gs, army)
		return
	var path := [target]
	var cur2: int = target
	while parent.has(cur2) and parent[cur2] != start:
		cur2 = parent[cur2]
		path.push_front(cur2)
	army["path"] = path
	army["move_progress"] = 0.0
	army["retreating"] = true
	army["battle"] = 0
	army["dig_in"] = 0


## Ejércitos desembarcados en la provincia (lista del índice: no modificar; copiar si se destruyen).
static func armies_in(gs: VGameState, province_id: int) -> Array:
	return VUnitIndex.armies_in(gs, province_id)


## Ejércitos regulares de la nación (copia: se puede fusionar/destruir mientras se recorre).
static func country_armies(gs: VGameState, tag: String) -> Array:
	return VUnitIndex.country_armies(gs, tag).duplicate()


## Refuerzo diario: cada brigada recupera hombres hasta lo que su POP de origen puede sostener.
## Solo se recorren los ejércitos con bajas (índice «damaged», alimentado por apply_casualties).
static func daily_reinforce(gs: VGameState) -> void:
	var d := gs.date.ordinal()
	var dmg := VUnitIndex.damaged_armies(gs)
	for aid in dmg.keys():
		var a: Dictionary = gs.armies.get(aid, {})
		if a.is_empty():
			dmg.erase(aid)
			continue
		# cada ejército se refuerza cada 3 días (escalonado) con paso triple
		if (int(aid) + d) % 3 != 0:
			continue
		if int(a["battle"]) > 0 or int(a.get("rebel_faction", 0)) > 0 or int(a["embarked"]) > 0:
			continue
		var p: Dictionary = gs.province(int(a["province"]))
		if p.is_empty() or p["controller"] != a["country"]:
			continue
		var rate := 0.03 * float(a.get("supply", 1.0)) * (0.5 + float(gs.countries[a["country"]]["budget"].get("military", 0.5)))
		var full := true
		var step := maxi(1, int(float(gs.unit_manpower) * rate))
		var ps := gs.pops
		for bid in a["brigades"]:
			var b: Dictionary = gs.brigades[bid]
			var st := int(b["strength"])
			if st >= gs.unit_manpower:
				continue
			# (en línea: supportable = lo que el POP de origen sostiene por brigada enlazada)
			var src := brigade_pop(gs, b)
			var cap := 0
			if src >= 0:
				cap = mini(gs.unit_manpower, ps.size[src] / maxi(1, ps.brigade_count(src)))
			if st < cap:
				st = mini(cap, st + step)
				b["strength"] = st
			if st < gs.unit_manpower:
				full = false
		if full:
			dmg.erase(aid)
