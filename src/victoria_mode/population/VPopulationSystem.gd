class_name VPopulationSystem
extends RefCounted
## POPs: modelo, generación inicial, compra de necesidades y consecuencias sociales.
##
## Ciclo de un POP (una vez al mes, repartido por cubos de provincias, ver VWorldSimulation):
##   trabajo (VProductionSystem) → renta (salario/beneficio/sueldo estatal, menos impuestos)
##   → compra necesidades: vida → diario → lujo (con el efectivo disponible y el llenado del mercado)
##   → ahorra/deposita el resto → crecimiento, alfabetización, conciencia, militancia, ideología, issues
##   → promoción/democión y migración (VMobilitySystem).
##
## Las cestas de necesidades están en pop_types.json (cantidades por 10.000 personas y mes).

const TIERS := ["life", "everyday", "luxury"]
const POP_UNIT := 10000.0


# ------------------------------------------------------------ generación
static func generate_initial(gs: VGameState) -> void:
	var dist: Dictionary = gs.pop_distribution
	var headroom := float(dist.get("factory_staff_headroom", 1.05))
	# plazas de fábrica por provincia (obreros y oficinistas se reparten según población)
	var staff := {}
	for key in gs.state_instances:
		var si: Dictionary = gs.state_instances[key]
		var cr := 0.0
		var cl := 0.0
		for f in si["factories"]:
			var wf: Dictionary = gs.factory_types.get(f["type"], {}).get("workforce", {})
			cr += float(wf.get("craftsmen", 9000)) * int(f["level"])
			cl += float(wf.get("clerks", 1000)) * int(f["level"])
		if cr <= 0.0:
			continue
		var tot := 0.0
		for id in si["provinces"]:
			tot += float(gs.provinces[id]["population"])
		for id in si["provinces"]:
			var w := float(gs.provinces[id]["population"]) / maxf(1.0, tot)
			staff[id] = {"craftsmen": cr * w * headroom, "clerks": cl * w * headroom}
	for id in range(1, gs.first_sea_id):
		var p: Dictionary = gs.provinces[id]
		var total := int(p.get("base_population", p["population"]))
		var owner: String = p["owner"]
		var shares := {}
		var civilized := false
		if owner == "":
			shares = dist.get("unowned", {}).duplicate()
		else:
			civilized = gs.countries[owner].get("civilized", true)
			shares = dist.get("civilized" if civilized else "uncivilized", {}).duplicate()
			if int(gs.countries[owner].get("reforms", {}).get("slavery", 1)) == 0:
				shares["slaves"] = float(dist.get("slaves_if_allowed", 0.05))
		var counts := {}
		var used := 0
		for k in shares:
			counts[k] = int(total * float(shares[k]))
			used += counts[k]
		if staff.has(id):
			for k in ["craftsmen", "clerks"]:
				counts[k] = int(min(staff[id][k], float(total - used) * 0.5))
				used += counts[k]
		var good: Dictionary = gs.goods.get(p["rgo"], {})
		var worker := "farmers" if good.get("rgo", "farm") == "farm" else "labourers"
		counts[worker] = int(counts.get(worker, 0)) + max(0, total - used)
		var lit_base := 0.02 if owner == "" else float(gs.countries[owner]["literacy"])
		var pops: Array = []
		for t in counts:
			if int(counts[t]) < 10:
				continue
			pops.append(make_pop(gs, t, int(counts[t]), p["culture"], p["religion"], id, lit_base))
		p["pops"] = pops
		recalc_province(gs, id)


static func make_pop(gs: VGameState, type_id: String, size: int, culture: String, religion: String, province_id: int, lit_base: float) -> Dictionary:
	var pt: Dictionary = gs.pop_types.get(type_id, {})
	var strata: String = pt.get("strata", "poor")
	var ideo := {}
	for i in gs.ideologies:
		var w := float(gs.ideologies[i].get("strata_affinity", {}).get(strata, 0.0))
		if w > 0.0:
			ideo[i] = w
	_normalize(ideo)
	var cash_pc := 0.002 if strata == "poor" else (0.012 if strata == "middle" else 0.06)
	var pop := {
		"id": gs.next_pop_id,
		"province": province_id,
		"type": type_id,
		"size": size,
		"culture": culture,
		"religion": religion,
		"literacy": clampf(lit_base * float(pt.get("literacy_mult", 1.0)), 0.0, 1.0),
		"consciousness": 0.5 if strata == "poor" else 1.5,
		"militancy": 1.0,
		"ideology": ideo,
		"issues": {},
		"cash": float(size) * cash_pc,
		"bank": 0.0,
		"income": 0.0,
		"income_acc": 0.0,
		"employment": 1.0,
		"employer": "",
		"needs_satisfaction": {"life": 1.0, "everyday": 0.5, "luxury": 0.1},
		"migration_target": 0,
		"promotion_target": "",
		"unemployed_months": 0,
		"product": "",
	}
	gs.next_pop_id += 1
	return pop


static func _normalize(d: Dictionary) -> void:
	var t := 0.0
	for k in d:
		t += float(d[k])
	if t <= 0.0:
		return
	for k in d:
		d[k] = float(d[k]) / t


static func recalc_province(gs: VGameState, id: int) -> void:
	var p: Dictionary = gs.provinces[id]
	var total := 0
	for pop in p["pops"]:
		total += int(pop["size"])
	p["population"] = total


static func needs_basket(gs: VGameState, type_id: String, tier: String) -> Dictionary:
	return gs.pop_types.get(type_id, {}).get("needs", {}).get(tier, {})


# ---------------------------------------------------- caché de precios
## Al inicio de cada mes: coste por 10.000 de cada nivel de necesidades (a precio de compra
## con aranceles) y fracción esperada de llenado, por nación y tipo de POP.
static var ZERO_NEEDS := PackedFloat64Array([0.0, 0.0, 0.0, 1.0, 1.0, 1.0])
const EMPTY_TD := []
const AGG_SPECIAL := {"clergy": true, "clerks": true, "capitalists": true, "aristocrats": true}


static func prepare_month(gs: VGameState) -> void:
	var prices: Dictionary = gs.market["price"]
	var all_shares: Dictionary = gs.market.get("import_share", {})
	var all_fills: Dictionary = gs.market.get("fill_buy", {})
	# cestas disponibles (sin bienes bloqueados), una vez para todas las naciones
	var baskets := {}
	for t in gs.pop_types:
		var arr := []
		for i in 3:
			var basket := needs_basket(gs, t, TIERS[i])
			var clean := {}
			for g in basket:
				if VMarketSystem.is_available(gs, g):
					clean[g] = float(basket[g])
			arr.append(clean)
		baskets[t] = arr
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		if c["provinces"].is_empty():
			continue
		var tariff := float(c["budget"].get("tariffs", 0.0))
		var shares: Dictionary = all_shares.get(tag, {})
		var fills: Dictionary = all_fills.get(tag, {})
		var cache := {}
		for t in baskets:
			var costs := [0.0, 0.0, 0.0]
			var fl := [1.0, 1.0, 1.0]
			for i in 3:
				var basket: Dictionary = baskets[t][i]
				var cost := 0.0
				var got := 0.0
				for g in basket:
					var v := float(basket[g]) * float(prices[g]) * (1.0 + tariff * float(shares.get(g, 0.0)))
					cost += v
					got += v * float(fills.get(g, 1.0))
				costs[i] = cost
				fl[i] = got / cost if cost > 0.0 else 1.0
			cache[t] = {"cost": costs, "fill": fl,
				"flat": PackedFloat64Array([costs[0], costs[1], costs[2], fl[0], fl[1], fl[2]])}
		c["_needs"] = cache
		c.erase("_needs_flat")
		if not c.has("_tier_demand"):
			c["_tier_demand"] = {}
		c["_agg"] = new_agg()
		c["_vote_rule"] = VPoliticsSystem.vote_rule(gs, tag) if gs.month_index % 3 == 2 else ""


## Al final del mes convierte la demanda agregada por niveles en demanda de bienes concretos.
static func flush_demand(gs: VGameState) -> void:
	# cestas disponibles por tipo y nivel (bienes no disponibles fuera), una vez para todas las naciones
	var baskets := {}
	var acc_all: Dictionary = gs.market["acc_demand"]
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		var td: Dictionary = c.get("_tier_demand", {})
		if td.is_empty():
			continue
		if not acc_all.has(tag):
			acc_all[tag] = {}
		var acc: Dictionary = acc_all[tag]
		for t in td:
			var arr: Array = td[t]
			var bl: Array = baskets.get(t, EMPTY_TD)
			if bl.is_read_only():
				bl = []
				for i in 3:
					var clean := []
					var basket := needs_basket(gs, t, TIERS[i])
					for g in basket:
						if VMarketSystem.is_available(gs, g):
							clean.append([g, float(basket[g])])
					bl.append(clean)
				baskets[t] = bl
			for i in 3:
				var units := float(arr[i])
				if units <= 0.0:
					continue
				for e in bl[i]:
					var q := float(e[1]) * units
					if q > 0.0:
						acc[e[0]] = float(acc.get(e[0], 0.0)) + q
		c["_tier_demand"] = {}


# ------------------------------------------------- proceso mensual (provincia)
## Compra de necesidades y consecuencias para todos los POPs de una provincia.
static func process_province(gs: VGameState, id: int) -> void:
	var p: Dictionary = gs.provinces[id]
	var owner: String = p["owner"]
	if owner == "":
		_process_unowned(gs, p)
		return
	var c: Dictionary = gs.countries[owner]
	var cache: Dictionary = c.get("_needs", {})
	var flat: Dictionary = c.get("_needs_flat", {})
	if flat.is_empty() and not cache.is_empty():
		for t0 in cache:
			flat[t0] = cache[t0].get("flat", ZERO_NEEDS)
		c["_needs_flat"] = flat
	var tier_dem: Dictionary = c["_tier_demand"]
	var mods: Dictionary = c.get("mods", {})
	var budget: Dictionary = c["budget"]
	var deposit_share := float(gs.economy_rules.get("bank_deposit_share", 0.05))
	# efecto del clero en la provincia (educación)
	var clergy := 0
	var total := 0
	for pop in p["pops"]:
		total += int(pop["size"])
		if pop["type"] == "clergy":
			clergy += int(pop["size"])
	var clergy_eff: float = clampf(float(clergy) / maxf(1.0, float(total)) / 0.016, 0.0, 1.5)
	var edu_factor := (0.2 + float(budget.get("education", 0.0))) * float(c.get("pay_ratio", 1.0))
	var lit_rate := 0.0011 * clergy_eff * edu_factor * (1.0 + float(mods.get("literacy_growth", 0.0)))
	var con_mod := 1.0 + float(mods.get("consciousness_growth", 0.0))
	var mil_mod := float(mods.get("militancy_growth", 0.0))
	var worker_mil := float(mods.get("worker_militancy", 0.0))
	var drift := 0.03 * float(mods.get("ideology_drift", 1.0))
	var socialist := 1.0 + float(mods.get("socialist_drift", 0.0))
	var growth_mod := float(mods.get("pop_growth", 0.0))
	# cansancio bélico → militancia (hook del milestone 3)
	var war_mil := float(c.get("war_exhaustion", 0.0)) / 100.0 * 0.05
	var lr := float(p["life_rating"])
	var do_issues := (gs.month_index + id) % 3 == 0
	# consecuencias lentas (crecimiento, alfabetización, conciencia, militancia) cada 2 meses con paso doble
	var do_slow := (gs.month_index + id) % 2 == 0
	# deriva ideológica trimestral, escalonada por provincia (misma velocidad media)
	var do_drift := (gs.month_index + id + 1) % 3 == 0
	var agg: Dictionary = c.get("_agg", {})
	if agg.is_empty():
		agg = new_agg()
		c["_agg"] = agg
	agg["n"] = int(agg["n"]) + 1
	var vote_rule: String = c.get("_vote_rule", "")
	var spent_total := 0.0
	var ptc := _type_cache(gs)
	var life_sum := 0.0
	var unemp_sum := 0.0
	var poor_size := 0.0
	var agg_st: Dictionary = agg["strata"]
	var agg_ty: Dictionary = agg["types"]
	var a_tot := 0
	var a_lit := 0.0
	var a_mil := 0.0
	var a_con := 0.0
	var a_unemp := 0.0
	var a_life := 0.0
	for pop in p["pops"]:
		var t: String = pop["type"]
		var tc: Array = ptc.get(t, ptc["_default"])
		var units := float(pop["size"]) / POP_UNIT
		pop["income"] = float(pop.get("income_acc", 0.0))
		pop["income_acc"] = 0.0
		# --- compra de necesidades (costes/llenados planos por tipo; sin arrays temporales por POP)
		var nf: PackedFloat64Array = flat.get(t, ZERO_NEEDS)
		var c0 := nf[0] * units
		var c1 := nf[1] * units
		var c2 := nf[2] * units
		var cash := float(pop["cash"])
		var want_cash := (c0 + c1 + c2) * 1.5
		if cash < want_cash:
			var bank := float(pop.get("bank", 0.0))
			if bank > 0.0:
				var w: float = minf(bank, want_cash - cash)
				pop["bank"] = bank - w
				cash += w
				c["bank"]["deposits"] = maxf(0.0, float(c["bank"]["deposits"]) - w)
		var spend := cash * float(tc[0])
		var td: Array = tier_dem.get(t, EMPTY_TD)
		if td.is_read_only():
			td = [0.0, 0.0, 0.0]
			tier_dem[t] = td
		var s0 := 0.0
		var s1 := 0.0
		var s2 := 0.0
		# nivel 0 (vida) → 1 (diario) → 2 (lujo); si un nivel no se completa, los siguientes no se compran
		var full_total := c0 + c1 + c2
		var a := 1.0 if c0 <= 0.0 else clampf(spend / c0, 0.0, 1.0)
		td[0] = float(td[0]) + units * a
		var paid := c0 * a * nf[3]
		spend -= paid
		cash -= paid
		spent_total += paid
		s0 = a * nf[3]
		if a >= 1.0:
			a = 1.0 if c1 <= 0.0 else clampf(spend / c1, 0.0, 1.0)
			td[1] = float(td[1]) + units * a
			paid = c1 * a * nf[4]
			spend -= paid
			cash -= paid
			spent_total += paid
			s1 = a * nf[4]
			if a >= 1.0:
				a = 1.0 if c2 <= 0.0 else clampf(spend / c2, 0.0, 1.0)
				td[2] = float(td[2]) + units * a
				paid = c2 * a * nf[5]
				spend -= paid
				cash -= paid
				spent_total += paid
				s2 = a * nf[5]
		var strata: String = tc[1]
		# riqueza sobrante: más consumo de lujo (cestas adicionales) y después ahorro bancario
		var reserve := full_total * 2.0
		if s2 >= 0.99 and c2 > 0.0 and cash > reserve:
			var extra := (cash - reserve) * 0.35
			var k := extra / c2
			td[2] = float(td[2]) + units * k
			var paid_x := extra * nf[5]
			cash -= paid_x
			spent_total += paid_x
			s2 = 1.0 + minf(1.0, k)
		if strata != "poor":
			var excess := cash - reserve * 3.0
			if excess > 0.0:
				var dep := excess * deposit_share
				pop["bank"] = float(pop.get("bank", 0.0)) + dep
				cash -= dep
				c["bank"]["deposits"] = float(c["bank"]["deposits"]) + dep
		pop["cash"] = cash
		var ns: Dictionary = pop["needs_satisfaction"]
		var lux: float = minf(1.0, s2)
		ns["life"] = s0
		ns["everyday"] = s1
		ns["luxury"] = lux
		# --- consecuencias
		var life: float = s0
		var every: float = s1
		var unemp := 1.0 - float(pop["employment"])
		if unemp > 0.1:
			pop["unemployed_months"] = int(pop["unemployed_months"]) + 1
		else:
			pop["unemployed_months"] = 0
		if not do_slow:
			if do_drift:
				_drift_ideology(gs, pop, strata, float(pop["literacy"]), float(pop["consciousness"]), every, drift * 3.0, socialist)
			if do_issues:
				update_issues(gs, pop, owner)
			var sz0 := int(pop["size"])
			if vote_rule != "" or AGG_SPECIAL.has(t):
				_agg_pop(gs, agg, pop, t, strata, vote_rule, sz0)
			else:
				agg_st[strata] = int(agg_st.get(strata, 0)) + sz0
				agg_ty[t] = int(agg_ty.get(t, 0)) + sz0
			var fs0 := float(sz0)
			a_tot += sz0
			a_lit += float(pop["literacy"]) * fs0
			a_mil += float(pop["militancy"]) * fs0
			a_con += float(pop["consciousness"]) * fs0
			a_unemp += unemp * fs0
			a_life += life * fs0
			if strata == "poor":
				life_sum += life * fs0
				unemp_sum += unemp * fs0
				poor_size += fs0
			continue
		var annual: float = 0.012 * clampf((life - 0.45) / 0.55, -1.5, 1.0) + (lr - 25.0) * 0.0004 + growth_mod
		if life < 0.25:
			annual -= 0.02
		pop["size"] = max(1, int(round(float(pop["size"]) * (1.0 + annual / 6.0))))
		var lit := float(pop["literacy"])
		pop["literacy"] = clampf(lit + 2.0 * lit_rate * (1.0 - lit) * float(tc[2]), 0.0, 1.0)
		var con := float(pop["consciousness"])
		con += 2.0 * (0.03 * lit * con_mod + 0.04 * maxf(0.0, 0.8 - life) + 0.02 * maxf(0.0, 0.5 - every) + 0.01 * unemp - 0.02)
		pop["consciousness"] = clampf(con, 0.0, 10.0)
		var mil := float(pop["militancy"])
		var dmil := 0.06 * maxf(0.0, 0.5 - life) + (0.02 * maxf(0.0, 0.3 - every) + 0.03 * unemp) * (con / 5.0)
		dmil += -0.02 * lux - 0.015 + mil_mod * 0.1 + float(pop.get("movement_push", 0.0)) + war_mil
		if tc[3]:
			dmil += worker_mil
		pop["militancy"] = clampf(mil + 2.0 * dmil, 0.0, 10.0)
		if do_drift:
			_drift_ideology(gs, pop, strata, lit, con, every, drift * 3.0, socialist)
		if do_issues:
			update_issues(gs, pop, owner)
		var sz := int(pop["size"])
		if vote_rule != "" or AGG_SPECIAL.has(t):
			_agg_pop(gs, agg, pop, t, strata, vote_rule, sz)
		else:
			agg_st[strata] = int(agg_st.get(strata, 0)) + sz
			agg_ty[t] = int(agg_ty.get(t, 0)) + sz
		var fs := float(sz)
		a_tot += sz
		a_lit += float(pop["literacy"]) * fs
		a_mil += float(pop["militancy"]) * fs
		a_con += float(pop["consciousness"]) * fs
		a_unemp += unemp * fs
		a_life += life * fs
		if strata == "poor":
			life_sum += life * fs
			unemp_sum += unemp * fs
			poor_size += fs
	agg["total"] = int(agg["total"]) + a_tot
	agg["lit"] = float(agg["lit"]) + a_lit
	agg["mil"] = float(agg["mil"]) + a_mil
	agg["con"] = float(agg["con"]) + a_con
	agg["unemp"] = float(agg["unemp"]) + a_unemp
	agg["life"] = float(agg["life"]) + a_life
	VMoney.destroyed(gs, spent_total, "pop_purchases")
	recalc_province(gs, id)
	p["avg_life"] = life_sum / poor_size if poor_size > 0.0 else 1.0
	p["unemployment"] = unemp_sum / poor_size if poor_size > 0.0 else 0.0


static func _process_unowned(gs: VGameState, p: Dictionary) -> void:
	var lr := float(p["life_rating"])
	for pop in p["pops"]:
		var ns: Dictionary = pop["needs_satisfaction"]
		ns["life"] = 0.8
		ns["everyday"] = 0.1
		ns["luxury"] = 0.0
		var annual := 0.003 + (lr - 25.0) * 0.0003
		pop["size"] = max(1, int(round(float(pop["size"]) * (1.0 + annual / 12.0))))
	recalc_province(gs, int(p["id"]))


## Deriva ideológica hacia un objetivo que depende de estrato, alfabetización, necesidades y conciencia.
## (sin copiar diccionarios: el objetivo se calcula clave a clave y se normaliza con el total conocido)
static func _drift_ideology(gs: VGameState, pop: Dictionary, strata: String, lit: float, con: float, every: float, rate: float, socialist: float) -> void:
	var bases: Dictionary = gs.market.get("_ideo_base", {})
	var entry: Array = bases.get(strata, [])
	if entry.is_empty():
		# [claves, bases, ranura (0 ninguna, 1 liberal, 2 radical, 3 socialista, 4 tradicionalista), total]
		var keys := []
		var vals := PackedFloat64Array()
		var slots := PackedInt32Array()
		var tot := 0.0
		for i in gs.ideologies:
			var v := float(gs.ideologies[i].get("strata_affinity", {}).get(strata, 0.0))
			keys.append(i)
			vals.append(v)
			slots.append({"liberal": 1, "radical": 2, "socialista": 3, "tradicionalista": 4}.get(i, 0))
			tot += v
		entry = [keys, vals, slots, tot]
		bases[strata] = entry
		gs.market["_ideo_base"] = bases
	var add := PackedFloat64Array([0.0, 0.3 * lit, 0.1 * con / 10.0 + 0.05 * lit,
		0.4 * maxf(0.0, 0.6 - every) * socialist if (lit > 0.15 and strata != "rich") else 0.0, 0.25 * (1.0 - lit)])
	var total := float(entry[3]) + add[1] + add[2] + add[3] + add[4]
	if total <= 0.0:
		return
	var ideo: Dictionary = pop["ideology"]
	var keep := 1.0 - rate
	var k_rate := rate / total
	var keys: Array = entry[0]
	var vals: PackedFloat64Array = entry[1]
	var slots: PackedInt32Array = entry[2]
	for i in keys.size():
		var k: String = keys[i]
		ideo[k] = float(ideo.get(k, 0.0)) * keep + (vals[i] + add[slots[i]]) * k_rate


static func dominant_ideology(pop: Dictionary) -> String:
	var best := ""
	var bv := -1.0
	for k in pop["ideology"]:
		if float(pop["ideology"][k]) > bv:
			bv = float(pop["ideology"][k])
			best = k
	return best


## Posición preferida en cada cuestión: ideología dominante → sesgo del tipo → reglas condicionales.
## La combinación (ideología, tipo) se cachea; si ninguna regla condicional aplica, el POP comparte
## el diccionario cacheado (solo se lee).
static func update_issues(gs: VGameState, pop: Dictionary, tag: String) -> void:
	# ideología dominante (en línea)
	var dom := ""
	var bv := -1.0
	var ideo: Dictionary = pop["ideology"]
	for k in ideo:
		var v := float(ideo[k])
		if v > bv:
			bv = v
			dom = k
	var t: String = pop["type"]
	# máscara de reglas condicionales que se cumplen (en orden)
	var rules := _issue_rules(gs)
	var ns: Dictionary = pop["needs_satisfaction"]
	var mask := 0
	for ri in rules.size():
		var rule: Array = rules[ri]
		var kinds: PackedInt32Array = rule[2]
		var vals: PackedFloat64Array = rule[3]
		var ok := true
		for i in kinds.size():
			var v := vals[i]
			match kinds[i]:
				0:
					ok = float(ns["life"]) <= v
				1:
					ok = float(ns["life"]) >= v
				2:
					ok = float(ns["everyday"]) <= v
				3:
					ok = float(pop["literacy"]) >= v
				4:
					ok = float(pop["consciousness"]) >= v
				5:
					ok = float(pop["militancy"]) >= v
				_:
					ok = VConditions.pop_ok(gs, pop, rule[4], tag, {})
			if not ok:
				break
		if ok:
			mask |= 1 << ri
	# el resultado solo depende de (ideología dominante, tipo, máscara): se comparte entre POPs (solo lectura)
	var cache: Dictionary = gs.market.get("_issue_base", {})
	if cache.is_empty():
		gs.market["_issue_base"] = cache
	var by_type: Dictionary = cache.get(dom, {})
	if by_type.is_empty():
		cache[dom] = by_type
	var by_mask: Dictionary = by_type.get(t, {})
	if by_mask.is_empty():
		by_type[t] = by_mask
	var result = by_mask.get(mask)
	if result == null:
		var res: Dictionary = gs.ideologies.get(dom, {}).get("issues", {}).duplicate()
		var bias: Dictionary = gs.pop_types.get(t, {}).get("issue_bias", {})
		for k in bias:
			res[k] = bias[k]
		for ri in rules.size():
			if mask & (1 << ri):
				res[rules[ri][0]] = rules[ri][1]
		res.make_read_only()
		by_mask[mask] = res
		result = res
	pop["issues"] = result


const _COND_KIND := {"max_life": 0, "min_life": 1, "max_everyday": 2, "min_literacy": 3, "min_consciousness": 4, "min_militancy": 5}


## Reglas condicionales de issues precompiladas: [issue, posición, tipos, valores, condiciones no rápidas].
static func _issue_rules(gs: VGameState) -> Array:
	var rules: Array = gs.market.get("_issue_rules", [])
	if rules.is_empty() and not gs.issue_conditionals.is_empty():
		for rule in gs.issue_conditionals:
			var cond: Dictionary = rule.get("if", {})
			var kinds := PackedInt32Array()
			var vals := PackedFloat64Array()
			var slow := {}
			for ck in cond:
				if _COND_KIND.has(ck):
					kinds.append(int(_COND_KIND[ck]))
					vals.append(float(cond[ck]))
				else:
					slow[ck] = cond[ck]
			if not slow.is_empty():
				kinds.append(9)
				vals.append(0.0)
			rules.append([rule["issue"], rule["position"], kinds, vals, slow])
		gs.market["_issue_rules"] = rules
	return rules


## Datos por tipo de POP que el bucle mensual necesita (evita búsquedas en diccionarios por POP):
## [spend_fraction, strata, factor de alfabetización, es trabajador manual, empleo, sueldo estatal]
static func _type_cache(gs: VGameState) -> Dictionary:
	var cache: Dictionary = gs.market.get("_pop_type_cache", {})
	if cache.is_empty():
		for t in gs.pop_types:
			var pt: Dictionary = gs.pop_types[t]
			cache[t] = [float(pt.get("spend_fraction", 1.0)), String(pt.get("strata", "poor")),
				0.7 + 0.3 * float(pt.get("literacy_mult", 1.0)), pt.get("job", "") in ["rgo_farm", "rgo_mine", "factory_worker"],
				String(pt.get("job", "none")), float(pt.get("gov_wage", 0.0))]
		cache["_default"] = [1.0, "poor", 1.0, false, "none", 0.0]
		gs.market["_pop_type_cache"] = cache
	return cache


## Estrato de un tipo de POP (desde la caché de tipos).
static func strata_of(gs: VGameState, type_id: String) -> String:
	var ptc := _type_cache(gs)
	return ptc.get(type_id, ptc["_default"])[1]


static func new_agg() -> Dictionary:
	return {"n": 0, "strata": {"poor": 0, "middle": 0, "rich": 0}, "types": {}, "total": 0, "lit": 0.0, "mil": 0.0,
		"con": 0.0, "unemp": 0.0, "life": 0.0, "clergy_lit": 0.0, "clerks_lit": 0.0, "capitalists": [], "aristocrats": [],
		"voters": {}, "vote_total": 0.0}


## Parte del agregado que no son sumas simples (tipos, estratos, listas, votos). Las sumas
## (población, alfabetización, militancia, conciencia, paro, vida) las acumula el llamador.
static func _agg_pop(gs: VGameState, agg: Dictionary, pop: Dictionary, t: String, strata: String, vote_rule: String, s: int) -> void:
	match t:
		"clergy":
			agg["clergy_lit"] = float(agg["clergy_lit"]) + float(s) * float(pop["literacy"])
		"clerks":
			agg["clerks_lit"] = float(agg["clerks_lit"]) + float(s) * float(pop["literacy"])
		"capitalists":
			agg["capitalists"].append(pop)
		"aristocrats":
			agg["aristocrats"].append(pop)
	if vote_rule != "":
		var vw := VPoliticsSystem.vote_weight(gs, pop, vote_rule)
		if vw > 0.0:
			agg["vote_total"] = float(agg["vote_total"]) + vw
			var voters: Dictionary = agg["voters"]
			for k in pop["ideology"]:
				voters[k] = float(voters.get(k, 0.0)) + float(pop["ideology"][k]) * vw
	var st: Dictionary = agg["strata"]
	st[strata] = int(st.get(strata, 0)) + s
	var ty: Dictionary = agg["types"]
	ty[t] = int(ty.get(t, 0)) + s


static func _agg_add(gs: VGameState, agg: Dictionary, pop: Dictionary, strata: String, vote_rule: String) -> void:
	var s := int(pop["size"])
	var t: String = pop["type"]
	match t:
		"clergy":
			agg["clergy_lit"] = float(agg["clergy_lit"]) + float(s) * float(pop["literacy"])
		"clerks":
			agg["clerks_lit"] = float(agg["clerks_lit"]) + float(s) * float(pop["literacy"])
		"capitalists":
			agg["capitalists"].append(pop)
		"aristocrats":
			agg["aristocrats"].append(pop)
	if vote_rule != "":
		var vw := VPoliticsSystem.vote_weight(gs, pop, vote_rule)
		if vw > 0.0:
			agg["vote_total"] = float(agg["vote_total"]) + vw
			var voters: Dictionary = agg["voters"]
			for k in pop["ideology"]:
				voters[k] = float(voters.get(k, 0.0)) + float(pop["ideology"][k]) * vw
	agg["total"] = int(agg["total"]) + s
	agg["strata"][strata] = int(agg["strata"].get(strata, 0)) + s
	agg["types"][t] = int(agg["types"].get(t, 0)) + s
	agg["lit"] = float(agg["lit"]) + float(pop["literacy"]) * s
	agg["mil"] = float(agg["mil"]) + float(pop["militancy"]) * s
	agg["con"] = float(agg["con"]) + float(pop["consciousness"]) * s
	agg["unemp"] = float(agg["unemp"]) + (1.0 - float(pop["employment"])) * s
	agg["life"] = float(agg["life"]) + float(pop["needs_satisfaction"]["life"]) * s


## Agregados nacionales al cierre del mes. Si el recorrido mensual por cubos cubrió todas las provincias
## de la nación se usan sus acumuladores (sin segunda pasada); si no (inicio, carga, cambios de territorio),
## se recorre la nación entera.
static func refresh_country_caches(gs: VGameState, force_full: bool = false) -> void:
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		var agg: Dictionary = c.get("_agg", {})
		if not force_full and not agg.is_empty() and int(agg["n"]) >= c["provinces"].size() and c["provinces"].size() > 0:
			_apply_agg(c, agg, c.get("_vote_rule", "") != "")
			continue
		var full := new_agg()
		var rule := VPoliticsSystem.vote_rule(gs, tag) if (not c["provinces"].is_empty() and (gs.month_index % 3 == 0 or not c.has("voter_ideology"))) else ""
		for id in c["provinces"]:
			for pop in gs.provinces[id]["pops"]:
				_agg_add(gs, full, pop, gs.pop_types.get(pop["type"], {}).get("strata", "poor"), rule)
		_apply_agg(c, full, rule != "")


static func _apply_agg(c: Dictionary, agg: Dictionary, has_votes: bool) -> void:
	var total := int(agg["total"])
	if has_votes and float(agg["vote_total"]) > 0.0:
		var voters: Dictionary = agg["voters"]
		for k in voters:
			voters[k] = float(voters[k]) / float(agg["vote_total"])
		c["voter_ideology"] = voters
	c["_clergy_literacy"] = agg["clergy_lit"]
	c["_clerks_literacy"] = agg["clerks_lit"]
	c["_capitalists"] = agg["capitalists"]
	c["_aristocrats"] = agg["aristocrats"]
	c["strata_pop"] = agg["strata"]
	c["type_sizes"] = agg["types"]
	c["population"] = total
	if total > 0:
		c["literacy"] = float(agg["lit"]) / total
		c["avg_militancy"] = float(agg["mil"]) / total
		c["avg_consciousness"] = float(agg["con"]) / total
		c["unemployment"] = float(agg["unemp"]) / total
		c["avg_life"] = float(agg["life"]) / total


# ------------------------------------------------------- consultas para UI
static func sizes_by(gs: VGameState, province_ids: Array, field: String = "type") -> Dictionary:
	var out := {}
	for id in province_ids:
		for pop in gs.provinces[id]["pops"]:
			var k = pop[field]
			out[k] = out.get(k, 0) + int(pop["size"])
	return out


static func ideology_mix(gs: VGameState, province_ids: Array) -> Dictionary:
	var out := {}
	var total := 0.0
	for id in province_ids:
		for pop in gs.provinces[id]["pops"]:
			var s := float(pop["size"])
			total += s
			for k in pop["ideology"]:
				out[k] = out.get(k, 0.0) + float(pop["ideology"][k]) * s
	if total > 0.0:
		for k in out:
			out[k] /= total
	return out


static func weighted_average(gs: VGameState, province_ids: Array, field: String) -> float:
	var total := 0.0
	var acc := 0.0
	for id in province_ids:
		for pop in gs.provinces[id]["pops"]:
			var s := float(pop["size"])
			total += s
			var v = pop[field] if field in pop else 0.0
			acc += float(v) * s
	return acc / total if total > 0.0 else 0.0


static func needs_average(gs: VGameState, province_ids: Array, tier: String, type_filter: String = "") -> float:
	var total := 0.0
	var acc := 0.0
	for id in province_ids:
		for pop in gs.provinces[id]["pops"]:
			if type_filter != "" and pop["type"] != type_filter:
				continue
			var s := float(pop["size"])
			total += s
			acc += float(pop["needs_satisfaction"][tier]) * s
	return acc / total if total > 0.0 else 0.0


static func country_pops(gs: VGameState, tag: String) -> Array:
	var out := []
	for id in gs.owned_provinces(tag):
		out.append_array(gs.provinces[id]["pops"])
	return out
