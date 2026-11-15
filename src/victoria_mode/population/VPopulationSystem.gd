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
			cache[t] = {"cost": costs, "fill": fl}
		c["_needs"] = cache
		if not c.has("_tier_demand"):
			c["_tier_demand"] = {}


## Al final del mes convierte la demanda agregada por niveles en demanda de bienes concretos.
static func flush_demand(gs: VGameState) -> void:
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		var td: Dictionary = c.get("_tier_demand", {})
		for t in td:
			var arr: Array = td[t]
			for i in 3:
				var units := float(arr[i])
				if units <= 0.0:
					continue
				var basket := needs_basket(gs, t, TIERS[i])
				for g in basket:
					if VMarketSystem.is_available(gs, g):
						VMarketSystem.add_demand(gs, tag, g, float(basket[g]) * units)
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
	var lr := float(p["life_rating"])
	var do_issues := (gs.month_index + id) % 3 == 0
	var life_sum := 0.0
	var unemp_sum := 0.0
	var poor_size := 0.0
	for pop in p["pops"]:
		var t: String = pop["type"]
		var pt: Dictionary = gs.pop_types.get(t, {})
		var units := float(pop["size"]) / POP_UNIT
		pop["income"] = float(pop.get("income_acc", 0.0))
		pop["income_acc"] = 0.0
		# --- compra de necesidades
		var nc: Dictionary = cache.get(t, {"cost": [0.0, 0.0, 0.0], "fill": [1.0, 1.0, 1.0]})
		var life_cost := float(nc["cost"][0]) * units
		if float(pop["cash"]) < life_cost and float(pop.get("bank", 0.0)) > 0.0:
			var w: float = minf(float(pop["bank"]), life_cost - float(pop["cash"]))
			pop["bank"] = float(pop["bank"]) - w
			pop["cash"] = float(pop["cash"]) + w
			c["bank"]["deposits"] = maxf(0.0, float(c["bank"]["deposits"]) - w)
		var spend := float(pop["cash"]) * float(pt.get("spend_fraction", 1.0))
		if not tier_dem.has(t):
			tier_dem[t] = [0.0, 0.0, 0.0]
		var td: Array = tier_dem[t]
		var sat := [0.0, 0.0, 0.0]
		var full_total := 0.0
		for i in 3:
			var full := float(nc["cost"][i]) * units
			full_total += full
			var a := 1.0 if full <= 0.0 else clampf(spend / full, 0.0, 1.0)
			td[i] = float(td[i]) + units * a
			var paid := full * a * float(nc["fill"][i])
			spend -= paid
			pop["cash"] = float(pop["cash"]) - paid
			sat[i] = a * float(nc["fill"][i])
			if a < 1.0:
				for j in range(i + 1, 3):
					full_total += float(nc["cost"][j]) * units
				break
		var strata: String = pt.get("strata", "poor")
		# riqueza sobrante: más consumo de lujo (cestas adicionales) y después ahorro bancario
		var lux_cost := float(nc["cost"][2]) * units
		var reserve := full_total * 2.0
		if sat[2] >= 0.99 and lux_cost > 0.0 and float(pop["cash"]) > reserve:
			var extra := (float(pop["cash"]) - reserve) * 0.35
			var k := extra / lux_cost
			td[2] = float(td[2]) + units * k
			var paid_x := extra * float(nc["fill"][2])
			pop["cash"] = float(pop["cash"]) - paid_x
			sat[2] = 1.0 + minf(1.0, k)
		if strata != "poor":
			var excess := float(pop["cash"]) - reserve
			if excess > 0.0:
				var dep := excess * deposit_share
				pop["bank"] = float(pop.get("bank", 0.0)) + dep
				pop["cash"] = float(pop["cash"]) - dep
				c["bank"]["deposits"] = float(c["bank"]["deposits"]) + dep
		var ns: Dictionary = pop["needs_satisfaction"]
		ns["life"] = sat[0]
		ns["everyday"] = sat[1]
		ns["luxury"] = minf(1.0, sat[2])
		# --- consecuencias
		var life: float = sat[0]
		var every: float = sat[1]
		var lux: float = minf(1.0, sat[2])
		var unemp := 1.0 - float(pop["employment"])
		if unemp > 0.1:
			pop["unemployed_months"] = int(pop["unemployed_months"]) + 1
		else:
			pop["unemployed_months"] = 0
		var annual: float = 0.012 * clampf((life - 0.45) / 0.55, -1.5, 1.0) + (lr - 25.0) * 0.0004 + growth_mod
		if life < 0.25:
			annual -= 0.02
		pop["size"] = max(1, int(round(float(pop["size"]) * (1.0 + annual / 12.0))))
		var lit := float(pop["literacy"])
		pop["literacy"] = clampf(lit + lit_rate * (1.0 - lit) * (0.7 + 0.3 * float(pt.get("literacy_mult", 1.0))), 0.0, 1.0)
		var con := float(pop["consciousness"])
		con += (0.03 * lit * con_mod + 0.04 * maxf(0.0, 0.8 - life) + 0.02 * maxf(0.0, 0.5 - every) + 0.01 * unemp - 0.02)
		pop["consciousness"] = clampf(con, 0.0, 10.0)
		var mil := float(pop["militancy"])
		mil += 0.06 * maxf(0.0, 0.5 - life) + (0.02 * maxf(0.0, 0.3 - every) + 0.03 * unemp) * (con / 5.0)
		mil += -0.02 * lux - 0.015 + mil_mod * 0.1 + float(pop.get("movement_push", 0.0))
		if pt.get("job", "") in ["rgo_farm", "rgo_mine", "factory_worker"]:
			mil += worker_mil
		pop["militancy"] = clampf(mil, 0.0, 10.0)
		_drift_ideology(gs, pop, strata, lit, con, every, drift, socialist)
		if do_issues:
			update_issues(gs, pop, owner)
		if strata == "poor":
			life_sum += life * float(pop["size"])
			unemp_sum += unemp * float(pop["size"])
			poor_size += float(pop["size"])
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
static func _drift_ideology(gs: VGameState, pop: Dictionary, strata: String, lit: float, con: float, every: float, rate: float, socialist: float) -> void:
	var target := {}
	for i in gs.ideologies:
		target[i] = float(gs.ideologies[i].get("strata_affinity", {}).get(strata, 0.0))
	target["liberal"] = float(target.get("liberal", 0.0)) + 0.3 * lit
	target["radical"] = float(target.get("radical", 0.0)) + 0.1 * con / 10.0 + 0.05 * lit
	if lit > 0.15 and strata != "rich":
		target["socialista"] = float(target.get("socialista", 0.0)) + 0.4 * maxf(0.0, 0.6 - every) * socialist
	target["tradicionalista"] = float(target.get("tradicionalista", 0.0)) + 0.25 * (1.0 - lit)
	_normalize(target)
	var ideo: Dictionary = pop["ideology"]
	for k in target:
		ideo[k] = float(ideo.get(k, 0.0)) * (1.0 - rate) + float(target[k]) * rate


static func dominant_ideology(pop: Dictionary) -> String:
	var best := ""
	var bv := -1.0
	for k in pop["ideology"]:
		if float(pop["ideology"][k]) > bv:
			bv = float(pop["ideology"][k])
			best = k
	return best


## Posición preferida en cada cuestión: ideología dominante → sesgo del tipo → reglas condicionales.
static func update_issues(gs: VGameState, pop: Dictionary, tag: String) -> void:
	var ideo: Dictionary = gs.ideologies.get(dominant_ideology(pop), {})
	var issues: Dictionary = ideo.get("issues", {}).duplicate()
	var bias: Dictionary = gs.pop_types.get(pop["type"], {}).get("issue_bias", {})
	for k in bias:
		issues[k] = bias[k]
	for rule in gs.issue_conditionals:
		if VConditions.pop_ok(gs, pop, rule.get("if", {}), tag, {}):
			issues[rule["issue"]] = rule["position"]
	pop["issues"] = issues


# ------------------------------------------------------------- agregados
## Agregados nacionales (al cierre de mes): población, estratos, tamaños por tipo, alfabetización.
static func refresh_country_caches(gs: VGameState) -> void:
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		var strata := {"poor": 0, "middle": 0, "rich": 0}
		var types := {}
		var total := 0
		var lit := 0.0
		var mil := 0.0
		var con := 0.0
		var unemp := 0.0
		var life := 0.0
		var clergy_lit := 0.0
		var clerks_lit := 0.0
		var capitalists := []
		var aristocrats := []
		var do_votes := gs.month_index % 3 == 0 or not c.has("voter_ideology")
		var vote_rule := VPoliticsSystem.vote_rule(gs, tag) if (do_votes and not c["provinces"].is_empty()) else ""
		var voters := {}
		var vote_total := 0.0
		for id in c["provinces"]:
			for pop in gs.provinces[id]["pops"]:
				var s := int(pop["size"])
				match pop["type"]:
					"clergy":
						clergy_lit += float(s) * float(pop["literacy"])
					"clerks":
						clerks_lit += float(s) * float(pop["literacy"])
					"capitalists":
						capitalists.append(pop)
					"aristocrats":
						aristocrats.append(pop)
				var vw := VPoliticsSystem.vote_weight(gs, pop, vote_rule) if vote_rule != "" else 0.0
				if vw > 0.0:
					vote_total += vw
					for k in pop["ideology"]:
						voters[k] = float(voters.get(k, 0.0)) + float(pop["ideology"][k]) * vw
				total += s
				var st: String = gs.pop_types.get(pop["type"], {}).get("strata", "poor")
				strata[st] = int(strata.get(st, 0)) + s
				types[pop["type"]] = int(types.get(pop["type"], 0)) + s
				lit += float(pop["literacy"]) * s
				mil += float(pop["militancy"]) * s
				con += float(pop["consciousness"]) * s
				unemp += (1.0 - float(pop["employment"])) * s
				life += float(pop["needs_satisfaction"]["life"]) * s
		if vote_total > 0.0:
			for k in voters:
				voters[k] = float(voters[k]) / vote_total
			c["voter_ideology"] = voters
		c["_clergy_literacy"] = clergy_lit
		c["_clerks_literacy"] = clerks_lit
		c["_capitalists"] = capitalists
		c["_aristocrats"] = aristocrats

		c["strata_pop"] = strata
		c["type_sizes"] = types
		c["population"] = total
		if total > 0:
			c["literacy"] = lit / total
			c["avg_militancy"] = mil / total
			c["avg_consciousness"] = con / total
			c["unemployment"] = unemp / total
			c["avg_life"] = life / total


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
