class_name VInvestmentSystem
extends RefCounted
## Inversión (M5.5). Sustituye el enfriamiento nacional único (un proyecto cada 3 meses para cualquier país)
## por CAPACIDAD de inversión proporcional a la economía, y separa tres inversores:
##
##   · capitalistas → fábricas (nuevas y ampliaciones). Proyectos simultáneos = capacidad privada:
##       1 + niveles de fábrica / levels_per_slot + capitalistas / capitalists_per_slot + capital / capital_per_slot
##       (con techo). Inicios por mes limitados (crecimiento gradual).
##   · Estado → fábricas (políticas de construcción estatal); su propia capacidad, independiente de la privada.
##     Con paro grave y tesoro sano lanza programas industriales (respetando insumos, demanda y tecnología).
##   · aristócratas (o el Estado) → desarrollo rural: mejoras de RGO en provincias con paro rural, RGO
##     rentable y demanda del bien. Límite por provincia: max_base + infraestructura + tecnología.
##
## Restricción de duplicados: estado + tipo (antes era tipo en todo el país).
## Puntuación de una fábrica nueva: margen esperado (precios medios) × (1 + escasez + tendencia de la demanda
## + presión de paro local + urbanización + infraestructura + bonos mágicos). Sin margen positivo no se
## construye: el paro acelera la industrialización pero no justifica fábricas absurdas.
## Todo el dinero respeta VMoney: el capital invertido sale de los inversores (destruido como «investment») y
## los bienes de construcción se compran al mercado durante el proyecto.

const MAGIC_FACTORIES := ["mana_refinery", "arcane_workshop", "alchemy_lab", "arcane_machine_works", "alchemical_fertilizer_works"]


static func rules(gs: VGameState) -> Dictionary:
	return gs.economy_rules.get("investment", {})


static func dev_rules(gs: VGameState) -> Dictionary:
	return gs.economy_rules.get("rgo_development", {})


# ------------------------------------------------------------------ capacidad
static func capitalist_pool(gs: VGameState, c: Dictionary) -> float:
	var ps := gs.pops
	var pool := 0.0
	for s in c.get("_capitalists", []):
		pool += ps.cash[s] + ps.bank[s]
	return pool


static func aristocrat_pool(gs: VGameState, c: Dictionary) -> float:
	var ps := gs.pops
	var pool := 0.0
	for s in c.get("_aristocrats", []):
		pool += ps.cash[s] + ps.bank[s]
	return pool


static func factory_levels(gs: VGameState, tag: String) -> int:
	var n := 0
	for si in gs.country_state_instances(tag):
		for f in si["factories"]:
			if f["open"]:
				n += int(f["level"])
	return n


## {"private", "government", "rgo", "starts"}: proyectos simultáneos por inversor e inicios por mes.
static func capacity(gs: VGameState, tag: String) -> Dictionary:
	var c: Dictionary = gs.countries[tag]
	var r := rules(gs)
	var levels := float(c.get("_factory_levels", 0))
	var caps := float(c.get("type_sizes", {}).get("capitalists", 0))
	var capital := float(c.get("_capital_pool", 0.0))
	var mult := maxf(0.2, 1.0 + gs.mod(tag, "investment_capacity"))
	var priv := (1.0 + levels / float(r.get("levels_per_slot", 25)) + caps / float(r.get("capitalists_per_slot", 40000))
		+ capital / float(r.get("capital_per_slot", 1500))) * mult
	var gov := 1.0 + levels / float(r.get("gov_levels_per_slot", 40)) + maxf(0.0, float(c.get("treasury", 0.0))) / float(r.get("gov_treasury_per_slot", 20000))
	var rgo := 1.0 + float(c.get("provinces", []).size()) / float(r.get("provinces_per_rgo_slot", 20))
	var p := clampi(int(priv), 1, int(r.get("max_private", 10)))
	# crecimiento gradual: inicios por año ≤ max(min_starts_year, niveles × max_growth_year)
	var year_cap := maxf(float(r.get("min_starts_year", 3)), levels * float(r.get("max_growth_year", 0.12)))
	return {"private": p, "year_cap": int(year_cap), "government": clampi(int(gov), 1, int(r.get("max_government", 4))),
		"rgo": clampi(int(rgo), 1, int(r.get("max_rgo", 5))), "starts": 1 + p / int(r.get("slots_per_extra_start", 4))}


static func active_counts(c: Dictionary) -> Dictionary:
	var out := {"private": 0, "government": 0, "rgo": 0}
	for pr in c.get("projects", []):
		if pr.get("kind", "factory") == "rgo":
			out["rgo"] += 1
		elif pr.get("investor", "") == "government":
			out["government"] += 1
		else:
			out["private"] += 1
	return out


static func pending_keys(c: Dictionary) -> Dictionary:
	var out := {}
	for pr in c.get("projects", []):
		out["%s|%s" % [pr.get("state_key", ""), pr.get("type", "")]] = true
		if pr.get("kind", "factory") == "rgo":
			out["rgo|%d" % int(pr.get("prov", 0))] = true
	return out


## Plazas de fábrica de una partición de estado: base + infraestructura + urbanización + tecnología.
static func state_slots(gs: VGameState, si: Dictionary) -> int:
	var r: Dictionary = gs.economy_rules.get("state_factory_slots", {})
	var infra := 0.0
	for id in si["provinces"]:
		infra += float(gs.provinces[id]["infrastructure"])
	infra /= maxf(1.0, float(si["provinces"].size()))
	var n := float(r.get("base", 6)) + infra * float(r.get("per_infrastructure", 1.0)) + float(si.get("_urban", 0.0)) * float(r.get("per_urbanisation", 10.0))
	n += gs.mod(String(si["owner"]), "state_factory_slots") if si["owner"] != "" else 0.0
	return clampi(int(n), 1, int(r.get("max", 14)))


# ------------------------------------------------------------------ demanda
## Señal de demanda de un bien: escasez actual (demanda/oferta mundial) y tendencia de precios de 6 frente a
## 12 meses. Una subida de un mes no basta (se usan medias).
## Producción mundial que ya viene en camino (proyectos en construcción y fábricas nuevas que aún no
## contratan a pleno): se descuenta de la escasez para que decenas de países no cubran el mismo hueco a la vez.
## Caché mensual (una pasada por proyectos y fábricas del mundo al mes).
static func pending_output(gs: VGameState) -> Dictionary:
	var cache: Dictionary = gs.market.get("_pending_output", {})
	if int(cache.get("_month", -1)) == gs.month_index:
		return cache
	cache = {"_month": gs.month_index}
	var rates: Dictionary = gs.market.get("factory_rate", {})
	for tag in gs.country_order:
		for pr in gs.countries[tag].get("projects", []):
			if pr.get("kind", "factory") == "rgo":
				continue
			var ft: Dictionary = gs.factory_types.get(pr["type"], {})
			for g in ft.get("outputs", {}):
				cache[g] = float(cache.get(g, 0.0)) + float(ft["outputs"][g]) * float(rates.get(pr["type"], 0.0))
	for key in gs.state_instances:
		for f in gs.state_instances[key]["factories"]:
			if f["open"] and int(f.get("age", 24)) < 12 and float(f["hiring"]) < 1.0:
				var ft2: Dictionary = gs.factory_types.get(f["type"], {})
				for g in ft2.get("outputs", {}):
					cache[g] = float(cache.get(g, 0.0)) + float(ft2["outputs"][g]) * float(rates.get(f["type"], 0.0)) * int(f["level"]) * (1.0 - float(f["hiring"]))
	gs.market["_pending_output"] = cache
	return cache


static func demand_signal(gs: VGameState, g: String) -> Dictionary:
	var w: Dictionary = gs.market.get("world", {})
	var sup := float(w.get("supply", {}).get(g, 0.0)) + float(pending_output(gs).get(g, 0.0))
	var dem := float(w.get("demand", {}).get(g, 0.0))
	var base := float(gs.goods[g]["base_price"])
	var p6 := VProductionSystem.avg_price(gs, g, 6)
	var p12 := VProductionSystem.avg_price(gs, g, 12)
	var shortage := clampf(dem / maxf(0.001, sup) - 1.0, 0.0, 1.0) if dem > 0.0 else 0.0
	var trend := clampf((p6 / maxf(0.001, p12) - 1.0) * 5.0, -0.5, 0.5)
	var in_demand := dem > sup * 1.05 or (p6 > base * 1.15 and dem > sup) or (trend > 0.1 and dem > sup * 0.98)
	return {"shortage": shortage, "trend": trend, "in_demand": in_demand, "ratio": dem / maxf(0.001, sup)}


static func output_signal(gs: VGameState, ftype: String) -> Dictionary:
	var best := {"shortage": 0.0, "trend": 0.0, "in_demand": false, "ratio": 0.0}
	var best_v := -INF
	for g in gs.factory_types.get(ftype, {}).get("outputs", {}):
		var sg := demand_signal(gs, g)
		var v := float(sg["shortage"]) + float(sg["trend"]) + (1.0 if sg["in_demand"] else 0.0)
		if v > best_v:
			best_v = v
			best = sg
	return best


# ------------------------------------------------------------------ mano de obra por partición
## Mano de obra disponible en una partición: obreros parados + parte de los campesinos/jornaleros sin plaza
## (paro rural) + algo de alfabetizados del campo. Y la tasa de paro local.
static func labour(gs: VGameState, si: Dictionary) -> Dictionary:
	var ps := gs.pops
	var pool := 0.0
	var pop := 0.0
	var unemployed := 0.0
	var magi := 0.0
	for id in si["provinces"]:
		var p: Dictionary = gs.provinces[id]
		# el campo solo llega a la fábrica por promoción (lenta): cuenta poco
		var rural_surplus := maxf(0.0, -float(p.get("rgo_free", 0)))
		pool += rural_surplus * float(gs.economy_rules.get("investment", {}).get("rural_labour_share", 0.08))
		for s: int in p["pop_slots"]:
			var tt: int = ps.type_id[s]
			var sz := float(ps.size[s])
			pop += sz
			unemployed += sz * (1.0 - ps.employment[s])
			if tt == ps.T_CRAFTSMEN:
				pool += sz * (1.0 - ps.employment[s])
			elif tt == ps.T_FARMERS or tt == ps.T_LABOURERS:
				pool += sz * float(gs.economy_rules.get("investment", {}).get("literate_rural_share", 0.012)) * minf(1.0, ps.literacy[s] * 5.0)
			elif tt == ps.T_MAGI:
				magi += sz * (1.0 - ps.employment[s])
	return {"pool": pool, "unemployment": unemployed / maxf(1.0, pop), "pop": pop, "idle_magi": magi}


# ------------------------------------------------------------------ planes de fábrica
## Lista de planes (ampliaciones y fábricas nuevas) ordenada por puntuación. why recibe el motivo si no hay.
static func factory_plans(gs: VGameState, tag: String, pending: Dictionary, why: Dictionary, max_plans: int = 4) -> Array:
	var c: Dictionary = gs.countries[tag]
	var r := rules(gs)
	var instances := gs.country_state_instances(tag)
	var max_level := int(gs.economy_rules.get("factory_max_level", 10))
	var plans := []
	var unemp := float(c.get("unemployment", 0.0))
	var w_unemp := float(r.get("weight_unemployment", 2.0))
	# --- ampliaciones: rentabilidad persistente y plantilla completa
	for si in instances:
		if int(si.get("vacancy_craftsmen", 0)) > 1000:
			continue
		for f in si["factories"]:
			if not f["open"] or int(f.get("age", 0)) < 12 or int(f["level"]) >= max_level or pending.has("%s|%s" % [si["key"], f["type"]]):
				continue
			var hist: Array = f.get("profit_hist", [])
			if hist.size() < 6 or float(f["hiring"]) < 0.95 or float(f.get("staffing", 0.0)) < 0.9:
				continue
			var avg := 0.0
			var worst := INF
			for v in hist:
				avg += float(v)
				worst = minf(worst, float(v))
			avg /= float(hist.size())
			var sig := output_signal(gs, f["type"])
			if avg <= 0.0 or worst < -0.25 * absf(avg) or not sig["in_demand"]:
				continue
			var score := avg / int(f["level"]) * (1.0 + float(sig["shortage"]) + w_unemp * unemp)
			plans.append({"state_key": si["key"], "type": f["type"], "expand": true, "factory_id": f["id"], "score": score,
				"margin": avg / int(f["level"]), "cost": VProductionSystem.build_cost(gs, tag, f["type"], true)})
	# --- tipos saturados en la nación: las fábricas que ya hay pierden dinero o no encuentran obreros
	var saturated := {}
	for si0 in instances:
		for f0 in si0["factories"]:
			if f0["open"] and int(f0.get("age", 0)) >= 6 and (float(f0.get("staffing", 1.0)) < 0.6 or int(f0.get("loss_months", 0)) >= 2):
				saturated[f0["type"]] = true
	# --- tipos candidatos para fábricas nuevas
	var fails := {}
	var types := []
	for t in gs.factory_types:
		var fr := ""
		var sig2 := {}
		if not VProductionSystem.can_build_type(gs, tag, t):
			fr = "technology_missing"
		else:
			sig2 = output_signal(gs, t)
			if not sig2["in_demand"]:
				fr = "insufficient_demand"
			elif not VProductionSystem.inputs_available(gs, tag, t):
				fr = "input_shortage"
		if fr != "":
			fails[fr] = int(fails.get(fr, 0)) + 1
			continue
		var m := VProductionSystem.expected_margin(gs, tag, t, true)
		if m <= 0.0:
			fails["no_profitable"] = int(fails.get("no_profitable", 0)) + 1
			continue
		if saturated.has(t):
			fails["no_profitable"] = int(fails.get("no_profitable", 0)) + 1
			continue
		types.append([t, m, sig2])
	if not types.is_empty():
		# mano de obra y plazas de las particiones más pobladas (una vez por llamada)
		# obreros que ya reservan los proyectos en construcción de cada partición
		var reserved := {}
		for pr in c.get("projects", []):
			if pr.get("kind", "factory") != "rgo":
				var wf: Dictionary = gs.factory_types.get(pr["type"], {}).get("workforce", {})
				reserved[pr["state_key"]] = float(reserved.get(pr["state_key"], 0.0)) + float(wf.get("craftsmen", 9000))
		var cand_si := []
		for si in instances.slice(0, int(r.get("states_considered", 25))):
			if si["factories"].size() >= state_slots(gs, si) or int(si.get("vacancy_craftsmen", 0)) > 1000:
				continue  # sin plazas, o con fábricas que aún no encuentran obreros
			var lab := labour(gs, si)
			lab["pool"] = float(lab["pool"]) - float(si.get("vacancy_craftsmen", 0)) - float(reserved.get(si["key"], 0.0))
			if float(lab["pool"]) + float(lab["idle_magi"]) * 3.0 < float(r.get("min_labour_pool", 9000)):
				continue
			cand_si.append([si, lab])
		if cand_si.is_empty():
			fails["no_labour" if not instances.is_empty() else "state_capacity_full"] = 1
		var magic := _magic_context(gs, tag)
		for tm in types:
			var t2: String = tm[0]
			var best_si := {}
			var best_lab := {}
			var best_local := -INF
			for e in cand_si:
				var si2: Dictionary = e[0]
				if pending.has("%s|%s" % [si2["key"], t2]):
					continue
				var lab2: Dictionary = e[1]
				if not (t2 in MAGIC_FACTORIES) and float(lab2["pool"]) < float(r.get("min_labour_pool", 9000)):
					continue
				var local := float(lab2["unemployment"]) * w_unemp + minf(1.0, float(lab2["pool"]) / 50000.0) * 0.3
				local += float(si2.get("_urban", 0.0)) * float(r.get("weight_urbanisation", 1.0))
				if t2 in MAGIC_FACTORIES:
					local += _magic_local_bonus(gs, si2)
				if local > best_local:
					best_local = local
					best_si = si2
					best_lab = lab2
			if best_si.is_empty():
				fails["same_type_pending"] = int(fails.get("same_type_pending", 0)) + 1
				continue
			var sig3: Dictionary = tm[2]
			var score2 := float(tm[1]) * (1.0 + float(sig3["shortage"]) * float(r.get("weight_shortage", 1.0)) + maxf(0.0, float(sig3["trend"]))
				+ best_local + w_unemp * unemp)
			if t2 in MAGIC_FACTORIES:
				score2 *= 1.0 + float(magic.get("bonus", 0.0))
			plans.append({"state_key": best_si["key"], "type": t2, "expand": false, "factory_id": 0, "score": score2, "margin": tm[1],
				"labour": best_lab["pool"], "local_unemployment": best_lab["unemployment"], "shortage": sig3["shortage"],
				"cost": VProductionSystem.build_cost(gs, tag, t2, false)})
	plans.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	if plans.is_empty():
		var top := "no_profitable"
		var top_n := -1
		for k in fails:
			if k != "technology_missing" and int(fails[k]) > top_n:
				top_n = int(fails[k])
				top = k
		if top_n < 0 and fails.has("technology_missing"):
			top = "technology_missing"
		why["reason"] = top
	why["fails"] = fails
	return plans.slice(0, max_plans)


## Bonos de la industria mágica para la nación (paro de magos, academias, yacimientos, escasez mágica).
static func _magic_context(gs: VGameState, tag: String) -> Dictionary:
	if not VMagicSystem.is_active(gs):
		return {}
	var c: Dictionary = gs.countries[tag]
	var info: Dictionary = c.get("_magi_info", {})
	var r := rules(gs)
	var b := float(info.get("unemployment", 0.0)) * float(r.get("magic_unemployment_bonus", 1.0))
	b += minf(3.0, float(VMageModel.academies(gs, tag))) * 0.1
	b += minf(1.0, float(VMagicSystem.country_deposit_provinces(gs, tag).size()) / 3.0) * 0.3
	if VMagicSystem.branch_level(gs, tag, "economy") > 0:
		b += 0.2 * VMagicSystem.branch_level(gs, tag, "economy")
	return {"bonus": b}


## Localización de la industria mágica: yacimientos, magos e infraestructura del estado.
static func _magic_local_bonus(gs: VGameState, si: Dictionary) -> float:
	var b := 0.0
	var ps := gs.pops
	for id in si["provinces"]:
		var p: Dictionary = gs.provinces[id]
		if float(p.get("magic", {}).get("deposit", 0.0)) > 0.0:
			b += 0.6
		for s: int in p["pop_slots"]:
			if ps.type_id[s] == ps.T_MAGI:
				b += minf(0.6, float(ps.size[s]) / 5000.0)
		b += 0.05 * float(p["infrastructure"])
	return minf(b, 2.0)


# ------------------------------------------------------------------ desarrollo rural (RGO)
static func max_development(gs: VGameState, p: Dictionary) -> int:
	var r := dev_rules(gs)
	var tag: String = p["owner"]
	return int(r.get("max_base", 2)) + int(p["infrastructure"]) * int(r.get("max_per_infrastructure", 1)) + int(gs.mod(tag, "rgo_development_max"))


## Mejor provincia para una mejora rural: paro rural, RGO rentable para sus trabajadores y demanda del bien.
static func rgo_plan(gs: VGameState, tag: String, pending: Dictionary) -> Dictionary:
	var c: Dictionary = gs.countries[tag]
	var r := dev_rules(gs)
	var needs: Dictionary = c.get("_needs", {})
	var best := {}
	var best_score := 0.0
	for id in c["provinces"]:
		var p: Dictionary = gs.provinces[id]
		if p["controller"] != tag or pending.has("rgo|%d" % int(id)):
			continue
		var rd: Dictionary = p.get("rgo_data", {})
		var total_workers := float(rd.get("max_workers", 0)) - float(p.get("rgo_free", 0))
		if total_workers <= 0.0:
			continue
		var surplus := maxf(0.0, -float(p.get("rgo_free", 0)))
		var rate := surplus / total_workers
		if rate < float(r.get("min_rural_unemployment", 0.08)):
			continue
		if int(p.get("rgo_dev", 0)) >= max_development(gs, p):
			continue
		var g: String = rd.get("good", p["rgo"])
		var per_worker := float(rd.get("revenue", 0.0)) / maxf(0.01, float(rd.get("workers", 0)) / VProductionSystem.UNIT)
		var wt := VProductionSystem.rgo_worker_type(gs, g)
		var life_cost := float(needs.get(wt, {}).get("cost", [5.0])[0])
		if per_worker < life_cost * float(r.get("min_profit_ratio", 1.0)):
			continue
		var sig := demand_signal(gs, g)
		if not sig["in_demand"] and VProductionSystem.avg_price(gs, g, 12) < float(gs.goods[g]["base_price"]) * float(r.get("min_price_ratio", 0.85)):
			continue
		var score := rate * per_worker / maxf(0.1, life_cost) * (1.0 + float(sig["shortage"]))
		if score > best_score:
			best_score = score
			best = {"prov": int(id), "good": g, "score": score, "rural_unemployment": rate, "cost": rgo_cost(gs, tag, p)}
	return best


static func rgo_goods(gs: VGameState, p: Dictionary) -> Dictionary:
	var r := dev_rules(gs)
	var scale := maxf(1.0, float(p.get("rgo_data", {}).get("base_size", 10.0)) / float(r.get("cost_size_unit", 10.0)))
	var out := {}
	var cg: Dictionary = r.get("cost_goods", {"lumber": 6.0, "fertilizer": 1.0})
	for g in cg:
		out[g] = float(cg[g]) * scale
	return out


static func rgo_cost(gs: VGameState, tag: String, p: Dictionary) -> float:
	var cost := 0.0
	var goods := rgo_goods(gs, p)
	for g in goods:
		cost += float(goods[g]) * VMarketSystem.buy_price(gs, tag, g)
	return cost


static func start_rgo_project(gs: VGameState, tag: String, plan: Dictionary, investor: String) -> void:
	var c: Dictionary = gs.countries[tag]
	var p: Dictionary = gs.provinces[int(plan["prov"])]
	var goods := rgo_goods(gs, p)
	c["projects"].append({"kind": "rgo", "prov": int(plan["prov"]), "state_key": "", "type": "rgo_development", "expand": false,
		"factory_id": 0, "goods_left": goods, "goods_total": goods.duplicate(), "progress": 0.0, "investor": investor})
	gs.log_event(tag, "%s: mejoras rurales en %s (%s)" % ["Aristócratas" if investor == "aristocrats" else "Gobierno", p["name"], gs.good_name(String(plan["good"]))])


static func complete_rgo_project(gs: VGameState, tag: String, pr: Dictionary) -> void:
	var p := gs.province(int(pr["prov"]))
	if p.is_empty() or p["owner"] != tag:
		return
	p["rgo_dev"] = int(p.get("rgo_dev", 0)) + 1
	gs.log_event(tag, "Mejoras rurales terminadas en %s (desarrollo %d)" % [p["name"], int(p["rgo_dev"])])


## Paga una inversión desde un grupo de POPs (capitalistas o aristócratas), proporcional a su riqueza.
## Devuelve false si el grupo no tiene capital suficiente (capital × ratio).
static func pay_from(gs: VGameState, c: Dictionary, slots: Array, cost: float, ratio: float) -> bool:
	var ps := gs.pops
	var pool := 0.0
	for s in slots:
		pool += ps.cash[s] + ps.bank[s]
	if pool < cost * ratio or cost <= 0.0:
		return false
	for s in slots:
		var w := (ps.cash[s] + ps.bank[s]) / pool
		var take := cost * w
		var from_cash: float = minf(ps.cash[s], take)
		ps.cash[s] -= from_cash
		var from_bank := take - from_cash
		ps.bank[s] = maxf(0.0, ps.bank[s] - from_bank)
		c["bank"]["deposits"] = maxf(0.0, float(c["bank"]["deposits"]) - from_bank)
	VMoney.destroyed(gs, cost, "investment")
	return true


# ------------------------------------------------------------------ mensual
static func monthly(gs: VGameState, tag: String, is_player: bool) -> void:
	var c: Dictionary = gs.countries[tag]
	var r := rules(gs)
	var policy := VProductionSystem.economic_policy(gs, tag)
	var er: Dictionary = gs.economy_rules
	c["_factory_levels"] = factory_levels(gs, tag)
	c["_capital_pool"] = capitalist_pool(gs, c)
	var cap := capacity(gs, tag)
	c["_inv_capacity"] = cap
	if gs.month_index % 12 == 0:
		c["_starts_year"] = 0
	var active := active_counts(c)
	var pending := pending_keys(c)
	# --- capitalistas → fábricas (capacidad privada; varios proyectos en paralelo)
	if not (policy in er.get("investment_policies", [])) or not c.get("civilized", true):
		VProductionSystem.note_reason(gs, c, "policy")
	elif int(active["private"]) >= int(cap["private"]) or int(c.get("_starts_year", 0)) >= int(cap["year_cap"]):
		VProductionSystem.note_reason(gs, c, "slots_full")
	else:
		var why := {}
		var plans := factory_plans(gs, tag, pending, why, int(cap["starts"]) + 2)
		var started := 0
		var started_si := {}
		if plans.is_empty():
			VProductionSystem.note_reason(gs, c, String(why.get("reason", "no_profitable")))
		for plan in plans:
			if started >= int(cap["starts"]) or int(active["private"]) >= int(cap["private"]) or int(c.get("_starts_year", 0)) >= int(cap["year_cap"]):
				break
			if pending.has("%s|%s" % [plan["state_key"], plan["type"]]) or (not plan["expand"] and started_si.has(plan["state_key"])):
				continue  # como mucho una fábrica nueva por estado y mes (la mano de obra es local)
			if not pay_from(gs, c, c.get("_capitalists", []), float(plan["cost"]), float(er.get("investment_capital_ratio", 2.5))):
				VProductionSystem.note_reason(gs, c, "insufficient_funds")
				break
			VProductionSystem.start_project(gs, tag, plan, "capitalists")
			VProductionSystem.note_stat(gs, c, "private_started")
			pending["%s|%s" % [plan["state_key"], plan["type"]]] = true
			active["private"] += 1
			started += 1
			started_si[plan["state_key"]] = true
			c["_starts_year"] = int(c.get("_starts_year", 0)) + 1
	# --- desarrollo rural (escalonado: cada 3 meses por nación)
	if (gs.month_index + absi(tag.hash())) % 3 == 0 and int(active["rgo"]) < int(cap["rgo"]):
		var rp := rgo_plan(gs, tag, pending)
		if not rp.is_empty():
			var ok := pay_from(gs, c, c.get("_aristocrats", []), float(rp["cost"]), float(dev_rules(gs).get("aristocrat_capital_ratio", 2.0)))
			var investor := "aristocrats"
			if not ok and not is_player and policy in er.get("government_build_policies", []) and _treasury_ok(gs, c, float(rp["cost"]), 6.0):
				VBudgetSystem.add_expense(gs, tag, "construction", float(rp["cost"]))
				ok = true
				investor = "government"
			if ok:
				start_rgo_project(gs, tag, rp, investor)
				VProductionSystem.note_stat(gs, c, "rgo_started")
	# --- Estado → fábricas (capacidad propia; programa industrial ante paro grave)
	if not is_player and policy in er.get("government_build_policies", []) and int(active["government"]) < int(cap["government"]) and int(c.get("_starts_year", 0)) < int(cap["year_cap"]):
		var crisis := float(c.get("unemployment", 0.0)) >= float(r.get("gov_unemployment_threshold", 0.08))
		var months := float(r.get("gov_reserve_months_crisis", 6.0)) if crisis else float(r.get("gov_reserve_months", 24.0))
		var monthly_exp := maxf(50.0, float(c.get("monthly_expense", 0.0)))
		if float(c["treasury"]) > monthly_exp * months:
			var why2 := {}
			var plans2 := factory_plans(gs, tag, pending, why2, 2)
			for plan2 in plans2:
				if pending.has("%s|%s" % [plan2["state_key"], plan2["type"]]):
					continue
				if _treasury_ok(gs, c, float(plan2["cost"]), months * 0.5):
					VBudgetSystem.add_expense(gs, tag, "construction", float(plan2["cost"]))
					VProductionSystem.start_project(gs, tag, plan2, "government")
					VProductionSystem.note_stat(gs, c, "government_started")
					c["_starts_year"] = int(c.get("_starts_year", 0)) + 1
					if crisis:
						VProductionSystem.note_stat(gs, c, "government_crisis_program")
				break
	# --- subvenciones temporales (IA, políticas que lo permiten)
	if not is_player and (gs.month_index + absi(tag.hash())) % 3 == 1 and policy in er.get("subsidy_policies", []):
		_ai_subsidies(gs, tag, c)


static func _treasury_ok(gs: VGameState, c: Dictionary, cost: float, reserve_months: float) -> bool:
	var monthly_exp := maxf(50.0, float(c.get("monthly_expense", 0.0)))
	return float(c["treasury"]) - float(c["acc"].get("construction", 0.0)) - cost > monthly_exp * reserve_months


## Subvenciona fábricas con pérdidas pero cerca de ser rentables (empleo importante); retira las inviables.
static func _ai_subsidies(gs: VGameState, tag: String, c: Dictionary) -> void:
	var r := rules(gs)
	var healthy := _treasury_ok(gs, c, 0.0, float(r.get("subsidy_reserve_months", 4.0)))
	var needs: Dictionary = c.get("_needs", {})
	var cr_cost: Array = needs.get("craftsmen", {}).get("cost", [5.0, 5.0, 5.0])
	var wage := (float(cr_cost[0]) + float(cr_cost[1])) * float(gs.economy_rules.get("factory_wage_multiplier", 1.6))
	for si in gs.country_state_instances(tag):
		for f in si["factories"]:
			if not f["open"]:
				continue
			var m := VProductionSystem.expected_margin(gs, tag, f["type"], true)
			if f["subsidized"]:
				if int(f.get("subsidy_until", 0)) <= gs.month_index or m < -wage * 0.5 or not healthy:
					f["subsidized"] = false
					VProductionSystem.note_stat(gs, c, "subsidies_ended")
			elif healthy and int(f.get("loss_months", 0)) >= 2 and float(f.get("staffing", 0.0)) >= 0.5 and m > -wage * float(r.get("subsidy_margin_tolerance", 0.3)):
				f["subsidized"] = true
				f["subsidy_until"] = gs.month_index + int(r.get("subsidy_months", 12))
				VProductionSystem.note_stat(gs, c, "subsidies_started")


## Explicación de una inversión para el jugador (tooltip): margen, demanda, insumos, mano de obra, paro.
static func explain(gs: VGameState, tag: String, ftype: String, si: Dictionary) -> String:
	var lines := []
	var m := VProductionSystem.expected_margin(gs, tag, ftype, true)
	lines.append("Margen esperado: %+.1f/mes por nivel (precios medios de 6 meses)" % m)
	var sig := output_signal(gs, ftype)
	lines.append("Demanda: %s (demanda/oferta mundial %.2f, tendencia %+.0f%%)" % ["alta" if sig["in_demand"] else "baja", float(sig["ratio"]), float(sig["trend"]) * 20.0])
	lines.append("Insumos: %s" % ("suficientes" if VProductionSystem.inputs_available(gs, tag, ftype) else "escasos"))
	if not VProductionSystem.can_build_type(gs, tag, ftype):
		lines.append("Falta tecnología")
	if not si.is_empty():
		var lab := labour(gs, si)
		lines.append("Trabajadores disponibles: %s · paro local %.0f%%" % [UiTheme.fmt_int(int(lab["pool"])), float(lab["unemployment"]) * 100.0])
		lines.append("Plazas de fábrica en el estado: %d/%d" % [si["factories"].size(), state_slots(gs, si)])
	return "\n".join(lines)
