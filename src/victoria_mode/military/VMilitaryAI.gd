class_name VMilitaryAI
extends RefCounted
## IA militar y naval (no omnisciente: solo mira provincias cercanas al decidir si evita un ejército).
## Se ejecuta cada 5 días por nación, escalonada.
##  · ejércitos dañados (organización o fuerza bajas) vuelven a casa a recuperarse y se fusionan;
##  · con rebeldes en el país, los cazan;
##  · en guerra: van a por los estados objetivo, después a la provincia enemiga más cercana;
##    evitan destinos con un ejército enemigo claramente superior; asedian al llegar;
##  · si el objetivo no es alcanzable por tierra, usan transportes (embarcar → navegar → desembarcar);
##  · flotas: bloquean costas enemigas salvo que haya una flota superior cerca; vuelven a puerto a reparar.
##
## Rendimiento: solo se prepara información para las naciones a las que les toca hoy (≈1/5); los
## destinos estratégicos (candidatos) se recalculan cada STRATEGIC_DAYS días o si cambia el acceso;
## la elección táctica (cada 5 días) ordena por distancia y solo evalúa el peligro de los más cercanos;
## las búsquedas A* nuevas están limitadas a PATH_BUDGET por día y el resto espera en cola.

const STRATEGIC_DAYS := 10
const PATH_BUDGET := 10


static func daily(gs: VGameState) -> void:
	if gs.flags.get("ai_disabled", false):
		return
	var d := gs.date.ordinal()
	VArmySystem.reset_path_budget(gs, PATH_BUDGET)
	_process_queue(gs)
	var land_us := 0
	var navy_us := 0
	for tag in gs.country_order:
		if tag == gs.player_tag or (d + absi(tag.hash())) % 5 != 0:
			continue
		var c: Dictionary = gs.countries[tag]
		if c["provinces"].is_empty():
			continue
		VProfiler.count(gs, "ai_countries_evaluated")
		var t1 := Time.get_ticks_usec()
		_land(gs, tag)
		var t2 := Time.get_ticks_usec()
		_naval(gs, tag)
		land_us += t2 - t1
		navy_us += Time.get_ticks_usec() - t2
	VProfiler.add(gs, "military_ai_land", land_us / 1000.0)
	VProfiler.add(gs, "military_ai_navy", navy_us / 1000.0)
	# los rebeldes también actúan
	if d % 5 == 2:
		for fid in gs.rebel_factions:
			var f: Dictionary = gs.rebel_factions[fid]
			for aid in f.get("armies", []):
				var a: Dictionary = gs.armies.get(int(aid), {})
				if not a.is_empty():
					_rebel_army(gs, a, f)


static func _idle(a: Dictionary) -> bool:
	return a["path"].is_empty() and int(a["battle"]) == 0 and int(a["embarked"]) == 0 and not a.get("retreating", false)


## Orden de movimiento de la IA con presupuesto de búsquedas: si la ruta no está en caché y ya se
## gastó el presupuesto del día, la orden espera en cola (se atiende en los próximos días).
static func _order(gs: VGameState, a: Dictionary, target: int, naval_fallback: bool = false) -> void:
	if not VArmySystem.path_ready(gs, a, target):
		var q: Array = _queue(gs)
		q.append([int(a["id"]), target, naval_fallback])
		VProfiler.count(gs, "path_queued")
		a["_ai_pending"] = true
		return
	if VArmySystem.order_move(gs, a, target) != "" and naval_fallback:
		_try_naval_invasion(gs, a, target)


static func _queue(gs: VGameState) -> Array:
	var ix := gs.unit_index
	if not ix.has("pq"):
		ix["pq"] = []
	return ix["pq"]


static func _process_queue(gs: VGameState) -> void:
	if gs.unit_index.is_empty() or not gs.unit_index.has("pq"):
		return
	var q: Array = gs.unit_index["pq"]
	while not q.is_empty() and VArmySystem.path_budget_left(gs) > 0:
		var e: Array = q.pop_front()
		var a: Dictionary = gs.armies.get(int(e[0]), {})
		if a.is_empty():
			continue
		a.erase("_ai_pending")
		if _idle(a):
			_order(gs, a, int(e[1]), bool(e[2]))


## Reclutamiento de la IA: una brigada cada ~2 meses si hay soldados libres y el tesoro lo permite
## (más a menudo en guerra), hasta el 80 % de lo que sus Soldier POPs pueden sostener.
static func _recruit(gs: VGameState, tag: String) -> void:
	var c: Dictionary = gs.countries[tag]
	var at_war := VWarSystem.is_at_war(gs, tag)
	if (gs.date.ordinal() / 5 + absi(tag.hash())) % (4 if at_war else 12) != 0:
		return
	if float(c["treasury"]) < maxf(200.0, float(c.get("monthly_expense", 0.0)) * (2.0 if at_war else 6.0)):
		return
	var soldiers := float(c.get("type_sizes", {}).get("soldiers", 0))
	var cap := soldiers / float(gs.unit_manpower) * 0.8
	if not at_war:
		cap = minf(cap, maxf(2.0, float(c.get("base_brigades", 4)) * 1.25))
	if float(c["military"]["brigades"]) >= cap:
		return
	# reclutar preferentemente en la capital (allí se fusiona con el ejército existente)
	var capital := int(c.get("capital", -1))
	if capital > 0 and VArmySystem.can_recruit(gs, tag, capital, "infantry")["ok"]:
		VArmySystem.recruit(gs, tag, capital, "infantry")
		return
	for id in c["provinces"]:
		var chk := VArmySystem.can_recruit(gs, tag, id, "infantry")
		if chk["ok"]:
			VArmySystem.recruit(gs, tag, id, "infantry")
			return


static func _land(gs: VGameState, tag: String) -> void:
	_recruit(gs, tag)
	var armies: Array = VArmySystem.country_armies(gs, tag)
	if armies.is_empty():
		return
	var at_war := VWarSystem.is_at_war(gs, tag)
	var rebels := []
	for f in VRebelSystem.country_factions(gs, tag):
		for aid in f.get("armies", []):
			if gs.armies.has(int(aid)):
				rebels.append(gs.armies[int(aid)])
	var cap := int(gs.countries[tag].get("capital", -1))
	# fusionar ejércitos detenidos en la misma provincia
	var by_prov := {}
	for a in armies:
		if _idle(a):
			var k := int(a["province"])
			if by_prov.has(k):
				VArmySystem.merge(gs, by_prov[k], [a])
			else:
				by_prov[k] = a
	var cands := _strategic_targets(gs, tag) if at_war else []
	for a in armies:
		if not gs.armies.has(int(a["id"])) or not _idle(a) or a.get("_ai_pending", false):
			continue
		VProfiler.count(gs, "ai_armies_evaluated")
		var org := VArmySystem.army_organisation(gs, a)
		var str_ratio := float(VArmySystem.army_strength(gs, a)) / maxf(1.0, float(a["brigades"].size() * gs.unit_manpower))
		var here := gs.province(int(a["province"]))
		if (org < 0.35 or str_ratio < 0.5) and here.get("controller", "") != tag and cap > 0:
			_order(gs, a, cap)
			continue
		if org < 0.5:
			continue
		if not rebels.is_empty():
			var target := _nearest_army(gs, a, rebels)
			if target > 0:
				_order(gs, a, target)
				continue
		if not at_war:
			continue
		var tgt := _war_target(gs, a, tag, cands)
		if tgt > 0:
			_order(gs, a, tgt, true)


static func _nearest_army(gs: VGameState, a: Dictionary, targets: Array) -> int:
	var best := -1
	var bd := INF
	var c: Vector2 = gs.provinces[int(a["province"])]["center"]
	for t in targets:
		var dd := c.distance_squared_to(gs.provinces[int(t["province"])]["center"])
		if dd < bd:
			bd = dd
			best = int(t["province"])
	return best


## Capa estratégica: destinos de guerra de la nación, cacheados STRATEGIC_DAYS días (o hasta que cambie
## el acceso). La capa táctica filtra en cada uso los que ya no controla el enemigo.
static func _strategic_targets(gs: VGameState, tag: String) -> Array:
	var c: Dictionary = gs.countries[tag]
	var sc: Dictionary = c.get("_ai_targets", {})
	var d := gs.date.ordinal()
	if sc.is_empty() or int(sc["ver"]) != gs.access_version or d - int(sc["day"]) >= STRATEGIC_DAYS:
		sc = {"ver": gs.access_version, "day": d, "list": _war_candidates(gs, tag)}
		c["_ai_targets"] = sc
		VProfiler.count(gs, "ai_strategic_recalcs")
	var en := VWarSystem.enemies_of(gs, tag)
	var out := []
	for id in sc["list"]:
		if en.has(gs.provinces[id]["controller"]):
			out.append(id)
	return out


## Elige destino: provincias de estados objetivo sin controlar, si no la provincia enemiga más cercana.
## Evita las que tienen (o lindan con) un ejército enemigo más del 50 % más fuerte.
static func _war_candidates(gs: VGameState, tag: String) -> Array:
	var cands := {}
	for wid in gs.countries[tag]["wars"]:
		var w: Dictionary = gs.wars.get(int(wid), {})
		if w.is_empty():
			continue
		var enemies := VWarSystem.enemies_in_war(gs, w, tag)
		for g in w["war_goals"]:
			if int(g.get("state_id", 0)) > 0 and g["actor"] == tag:
				for id in gs.state_part(int(g["state_id"]), g["target"]):
					if gs.provinces[id]["controller"] in enemies:
						cands[id] = true
		# provincias propias ocupadas por el enemigo
		for id in gs.countries[tag]["provinces"]:
			if gs.provinces[id]["controller"] in enemies:
				cands[id] = true
		if cands.is_empty():
			for e in enemies:
				if gs.countries.has(e):
					var cap := int(gs.countries[e].get("capital", -1))
					if cap > 0 and gs.provinces[cap]["controller"] in enemies:
						cands[cap] = true
			# provincias enemigas fronterizas
			for id in gs.countries[tag]["provinces"]:
				for n in gs.provinces[id]["neighbors"]:
					if gs.is_land(n) and gs.provinces[n]["controller"] in enemies:
						cands[n] = true
	return cands.keys()


## Selección táctica barata: ordena por distancia² y evalúa el peligro solo hasta encontrar el primer
## destino aceptable (mismo resultado que evaluar todos y quedarse con el más cercano seguro).
## No dispara A*: la ruta se calcula una vez, solo para el destino elegido.
static func _war_target(gs: VGameState, a: Dictionary, tag: String, cands: Array) -> int:
	if cands.is_empty():
		return -1
	var power := VArmySystem.army_power(gs, a)
	var here: Vector2 = gs.provinces[int(a["province"])]["center"]
	var excluded := {}
	# el candidato más cercano (desempate por id); si es peligroso se descarta y se busca el siguiente.
	# Sin ordenar ni crear arrays por ejército.
	while excluded.size() < cands.size():
		var best := -1
		var bd := INF
		for c in cands:
			var id: int = c
			if excluded.has(id):
				continue
			var dd := here.distance_squared_to(gs.provinces[id]["center"])
			if dd < bd or (dd == bd and id < best):
				bd = dd
				best = id
		if best < 0:
			return -1
		if _danger(gs, a, best) <= power * 1.5:
			return best
		excluded[best] = true
	return -1


## Poder enemigo en la provincia y sus vecinas (índice por provincia: sin recorrer listas globales).
static func _danger(gs: VGameState, a: Dictionary, prov: int) -> float:
	var t := _danger_at(gs, a, prov)
	for id in gs.provinces[prov]["neighbors"]:
		if gs.is_land(id):
			t += _danger_at(gs, a, id)
	return t


static func _danger_at(gs: VGameState, a: Dictionary, id: int) -> float:
	var t := 0.0
	for o in VArmySystem.armies_in(gs, id):
		if VCombatSystem.hostile(gs, a, o):
			t += VArmySystem.army_power(gs, o)
	return t


## Invasión anfibia sencilla: si el ejército está en un puerto con una flota propia con capacidad,
## embarca y la flota navega frente a la costa enemiga más cercana al objetivo; al llegar desembarca.
static func _try_naval_invasion(gs: VGameState, a: Dictionary, target: int) -> void:
	var prov := int(a["province"])
	if not gs.provinces[prov].get("coastal", false):
		return
	for f in VNavySystem.country_fleets(gs, a["country"]):
		if VNavySystem.can_load(gs, a, f) != "":
			continue
		# zona marítima frente a una costa enemiga accesible cerca del objetivo
		var best_zone := -1
		var best_coast := -1
		var bd := INF
		var tc: Vector2 = gs.provinces[target]["center"]
		var near: Array = Array(gs.provinces[target]["neighbors"])
		near.append(target)
		for n in near:
			if not gs.is_land(n) or not gs.provinces[n].get("coastal", false) or not VArmySystem.can_enter(gs, a["country"], n):
				continue
			for z in gs.provinces[n]["neighbors"]:
				if VNavySystem.is_sea(gs, z):
					var dd: float = tc.distance_squared_to(gs.provinces[n]["center"])
					if dd < bd:
						bd = dd
						best_zone = z
						best_coast = n
		if best_zone < 0:
			return
		if VNavySystem.load_army(gs, a, f) == "" and VNavySystem.order_move(gs, f, best_zone) == "":
			f["mission"] = "transport"
			f["unload_at"] = best_coast
			gs.log_event(a["country"], "%s embarca hacia %s" % [a["name"], gs.provinces[best_coast]["name"]])
		return


static func _naval(gs: VGameState, tag: String) -> void:
	var at_war := VWarSystem.is_at_war(gs, tag)
	for f in VNavySystem.country_fleets(gs, tag):
		if int(f.get("battle", 0)) > 0 or not f["path"].is_empty():
			continue
		# desembarco al llegar
		if f.get("mission", "") == "transport":
			for aid in f["transported_armies"].duplicate():
				var a: Dictionary = gs.armies.get(aid, {})
				if not a.is_empty() and VNavySystem.unload_army(gs, a, int(f.get("unload_at", -1))) == "":
					gs.log_event(tag, "%s desembarca en %s" % [a["name"], gs.provinces[int(a["province"])]["name"]])
			if f["transported_armies"].is_empty():
				f["mission"] = "idle"
			continue
		var hull := 0.0
		for s in f["ships"]:
			hull += float(s["hull"])
		hull /= maxf(1.0, float(f["ships"].size()))
		if hull < 0.5 and not VNavySystem.docked(gs, f):
			var port := VNavySystem.nearest_port(gs, f)
			if port > 0:
				VNavySystem.order_move(gs, f, port)
			continue
		if not at_war or hull < 0.8:
			continue
		# bloquear: zona marítima junto a una costa enemiga, si no hay flota enemiga más fuerte
		var target := -1
		for wid in gs.countries[tag]["wars"]:
			var w: Dictionary = gs.wars.get(int(wid), {})
			for e in VWarSystem.enemies_in_war(gs, w, tag):
				var ep := VNavySystem.home_port(gs, e)
				if ep > 0:
					for z in gs.provinces[ep]["neighbors"]:
						if VNavySystem.is_sea(gs, z):
							target = z
							break
				if target > 0:
					break
			if target > 0:
				break
		if target > 0 and int(f["location"]) != target and _enemy_fleet_power(gs, tag, target) < VNavalBattleResolver._power(gs, f) * 1.3:
			VNavySystem.order_move(gs, f, target)
			f["mission"] = "blockade"


static func _enemy_fleet_power(gs: VGameState, tag: String, zone: int) -> float:
	var t := 0.0
	for f in VUnitIndex.fleets_at(gs, zone):
		if VWarSystem.at_war_with(gs, tag, f["country"]):
			t += VNavalBattleResolver._power(gs, f)
	return t


static func _rebel_army(gs: VGameState, a: Dictionary, f: Dictionary) -> void:
	if not _idle(a):
		return
	var tag: String = f["country"]
	var cap := int(gs.countries.get(tag, {}).get("capital", -1))
	# marchar hacia la capital ocupando por el camino; si la capital ya es suya, ocupar vecinas
	var target := cap
	if cap > 0 and gs.provinces[cap]["controller"] == VGameState.REBEL_TAG:
		target = -1
		for n in gs.provinces[int(a["province"])]["neighbors"]:
			if gs.is_land(n) and gs.provinces[n]["owner"] == tag and gs.provinces[n]["controller"] != VGameState.REBEL_TAG:
				target = n
				break
	var here := gs.province(int(a["province"]))
	if not here.is_empty() and here["controller"] != VGameState.REBEL_TAG and here["owner"] == tag:
		return  # primero ocupar donde está
	if target > 0:
		_order(gs, a, target)
