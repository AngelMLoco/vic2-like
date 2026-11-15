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
	var pops := []
	for id in c["provinces"]:
		for pop in gs.provinces[id]["pops"]:
			if pop["type"] == "soldiers":
				pops.append(pop)
	pops.sort_custom(func(a, b): return int(a["size"]) > int(b["size"]))
	var techs: Array = c.get("technologies", [])
	var made := 0
	var by_state := {}
	for pop in pops:
		var cap := int(pop["size"]) / gs.unit_manpower
		for k in cap:
			if made >= want:
				break
			var utype := "infantry"
			if made % 5 == 3:
				utype = "cavalry"
			elif made % 5 == 4 and "siege_engineering" in techs:
				utype = "artillery"
			var b := _new_brigade(gs, utype, pop, int(pop["province"]))
			b["organisation"] = 1.0
			var sid := int(gs.provinces[int(pop["province"])]["state"])
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


static func _new_brigade(gs: VGameState, utype: String, pop: Dictionary, province_id: int) -> Dictionary:
	var id := gs.new_id("brigade")
	var b := {"id": id, "type": utype, "strength": gs.unit_manpower, "organisation": 0.3, "experience": 0.0,
		"source_pop_id": int(pop["id"]), "source_province_id": province_id, "army": 0}
	gs.brigades[id] = b
	var linked: Array = pop.get("brigades", [])
	linked.append(id)
	pop["brigades"] = linked
	return b


static func new_army(gs: VGameState, tag: String, province_id: int, army_name: String = "") -> Dictionary:
	var id := gs.new_id("army")
	var a := {"id": id, "country": tag, "name": army_name if army_name != "" else "Ejército %d" % id, "province": province_id,
		"brigades": [], "leader": 0, "morale": 1.0, "path": [], "move_progress": 0.0, "retreating": false, "dig_in": 0,
		"supply": 1.0, "battle": 0, "embarked": 0, "rebel_faction": 0, "ai_target": 0, "attrition": 0.0}
	gs.armies[id] = a
	return a


static func attach_brigade(gs: VGameState, army: Dictionary, b: Dictionary) -> void:
	if int(b.get("army", 0)) > 0 and gs.armies.has(int(b["army"])):
		gs.armies[int(b["army"])]["brigades"].erase(int(b["id"]))
	b["army"] = int(army["id"])
	if not (int(b["id"]) in army["brigades"]):
		army["brigades"].append(int(b["id"]))


static func update_counts(gs: VGameState) -> void:
	var counts := {}
	for aid in gs.armies:
		var a: Dictionary = gs.armies[aid]
		if int(a.get("rebel_faction", 0)) > 0:
			continue
		counts[a["country"]] = int(counts.get(a["country"], 0)) + a["brigades"].size()
	for tag in gs.countries:
		gs.countries[tag]["military"]["brigades"] = int(counts.get(tag, 0))


# ------------------------------------------------------------ Soldier POP
static func find_pop(gs: VGameState, province_id: int, pop_id: int) -> Dictionary:
	var p := gs.province(province_id)
	if p.is_empty():
		return {}
	for pop in p.get("pops", []):
		if int(pop["id"]) == pop_id:
			return pop
	return {}


## Hombres que el POP de origen puede sostener por brigada (para el refuerzo).
static func supportable(gs: VGameState, b: Dictionary) -> int:
	var pop := find_pop(gs, int(b["source_province_id"]), int(b["source_pop_id"]))
	if pop.is_empty():
		return 0
	var linked: int = maxi(1, pop.get("brigades", []).size())
	return mini(gs.unit_manpower, int(pop["size"]) / linked)


## Bajas: la brigada pierde hombres y el POP de origen pierde personas reales.
static func apply_casualties(gs: VGameState, b: Dictionary, men: int, tag: String) -> int:
	men = mini(men, int(b["strength"]))
	if men <= 0:
		return 0
	b["strength"] = int(b["strength"]) - men
	# (las brigadas rebeldes ya sacaron a sus hombres del POP al alzarse)
	var pop := {} if b.get("rebel", false) else find_pop(gs, int(b["source_province_id"]), int(b["source_pop_id"]))
	if not pop.is_empty():
		pop["size"] = maxi(1, int(pop["size"]) - men)
	if gs.countries.has(tag):
		gs.countries[tag]["casualties"] = int(gs.countries[tag].get("casualties", 0)) + men
	return men


static func army_strength(gs: VGameState, army: Dictionary) -> int:
	var t := 0
	for bid in army["brigades"]:
		t += int(gs.brigades.get(bid, {}).get("strength", 0))
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
		var pop := find_pop(gs, int(b["source_province_id"]), int(b["source_pop_id"]))
		if not pop.is_empty():
			pop.get("brigades", []).erase(int(bid))
			if return_men:
				pop["size"] = int(pop["size"]) + int(b["strength"])
		gs.brigades.erase(bid)
	if int(army.get("leader", 0)) > 0 and gs.leaders.has(int(army["leader"])):
		gs.leaders[int(army["leader"])]["army"] = 0
	if int(army.get("embarked", 0)) > 0 and gs.fleets.has(int(army["embarked"])):
		gs.fleets[int(army["embarked"])]["transported_armies"].erase(int(army["id"]))
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
	update_counts(gs)


# ------------------------------------------------------------- reclutar
static func can_recruit(gs: VGameState, tag: String, province_id: int, utype: String) -> Dictionary:
	var res := {"ok": false, "reason": "", "pop": {}}
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
	for pop in p["pops"]:
		if pop["type"] != "soldiers":
			continue
		var linked: int = pop.get("brigades", []).size()
		if int(pop["size"]) >= (linked + 1) * gs.unit_manpower:
			res["ok"] = true
			res["pop"] = pop
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
	for aid in gs.armies:
		var a: Dictionary = gs.armies[aid]
		if a["country"] == tag and int(a["province"]) == province_id and int(a["embarked"]) == 0 and int(a["battle"]) == 0 and a["path"].is_empty() and int(a.get("rebel_faction", 0)) == 0:
			army = a
			break
	if army.is_empty():
		army = new_army(gs, tag, province_id)
	attach_brigade(gs, army, b)
	update_counts(gs)
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
	if VWarSystem.at_war_with(gs, tag, owner) or VWarSystem.at_war_with(gs, tag, ctrl):
		return true
	if VDiplomacySystem.has_access(gs, tag, owner):
		return true
	if VDiplomacySystem.are_allied(gs, tag, owner) and VWarSystem.shared_war(gs, tag, owner):
		return true
	# provincia propia bajo control rebelde
	if ctrl == VGameState.REBEL_TAG and owner == tag:
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
	var fail_key := "%s|%d|%d|%d" % [tag, rebel_faction, from_id, to_id]
	var fails: Dictionary = gs.market.get("_path_fail", {})
	if int(fails.get(fail_key, -1)) > gs.date.ordinal():
		return []
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
	if fails.size() > 2000:
		fails.clear()
	fails[fail_key] = gs.date.ordinal() + 30
	gs.market["_path_fail"] = fails
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
				a["dig_in"] = mini(int(a.get("dig_in", 0)) + 1, 60)
			continue
		var nxt := int(a["path"][0])
		if not can_enter(gs, a["country"], nxt, int(a.get("rebel_faction", 0))):
			a["path"] = []
			a["move_progress"] = 0.0
			continue
		a["move_progress"] = float(a["move_progress"]) + 1.0
		if float(a["move_progress"]) >= step_days(gs, int(a["province"]), nxt, army_speed(gs, a)):
			a["province"] = nxt
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


static func armies_in(gs: VGameState, province_id: int) -> Array:
	var out := []
	for aid in gs.armies:
		var a: Dictionary = gs.armies[aid]
		if int(a["province"]) == province_id and int(a["embarked"]) == 0:
			out.append(a)
	return out


static func country_armies(gs: VGameState, tag: String) -> Array:
	var out := []
	for aid in gs.armies:
		var a: Dictionary = gs.armies[aid]
		if a["country"] == tag and int(a.get("rebel_faction", 0)) == 0:
			out.append(a)
	return out


## Refuerzo diario: cada brigada recupera hombres hasta lo que su POP de origen puede sostener.
static func daily_reinforce(gs: VGameState) -> void:
	var d := gs.date.ordinal()
	for aid in gs.armies:
		var a: Dictionary = gs.armies[aid]
		# cada ejército se refuerza cada 3 días (escalonado) con paso triple
		if (int(aid) + d) % 3 != 0:
			continue
		if int(a["battle"]) > 0 or int(a.get("rebel_faction", 0)) > 0 or int(a["embarked"]) > 0:
			continue
		var p: Dictionary = gs.province(int(a["province"]))
		if p.is_empty() or p["controller"] != a["country"]:
			continue
		var rate := 0.03 * float(a.get("supply", 1.0)) * (0.5 + float(gs.countries[a["country"]]["budget"].get("military", 0.5)))
		for bid in a["brigades"]:
			var b: Dictionary = gs.brigades[bid]
			if int(b["strength"]) >= gs.unit_manpower:
				continue
			var cap := supportable(gs, b)
			if int(b["strength"]) < cap:
				b["strength"] = mini(cap, int(b["strength"]) + maxi(1, int(float(gs.unit_manpower) * rate)))
