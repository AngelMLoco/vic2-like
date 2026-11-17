class_name VProductionSystem
extends RefCounted
## Producción y empleo.
##
##  RGO (provincia): campesinos/jornaleros (y esclavos) trabajan hasta max_workers; la producción
##    depende de trabajadores × productividad del bien × terreno × tecnología × infraestructura.
##    El ingreso se reparte entre trabajadores (salario) y aristócratas (parte del propietario).
##  Fábricas (partición de estado = estado × propietario): emplean obreros y oficinistas del estado,
##    compran insumos para su stock, producen, pagan salarios y reparten beneficio a capitalistas.
##    Con pérdidas: despidos → (subvención si la hay) → cierre.
##  Artesanos: producen sin fábrica el bien más rentable que puedan; cambian de producto.
##  Empleo estatal: clero, burócratas, soldados y oficiales cobran del presupuesto.
##  Inversión: capitalistas (según la política económica del partido gobernante) y gobierno
##    construyen/amplían fábricas mediante proyectos que compran bienes de construcción.

const UNIT := 10000.0


# ----------------------------------------------------------------- setup
static func setup_new_game(gs: VGameState) -> void:
	var rules: Dictionary = gs.economy_rules
	var headroom := float(rules.get("rgo_headroom", 1.1))
	for id in range(1, gs.first_sea_id):
		var p: Dictionary = gs.provinces[id]
		var wt := rgo_worker_type(gs, p["rgo"])
		var workers := 0
		var wt_id := int(gs.pops.type_index.get(wt, -2))
		for ps_s: int in p["pop_slots"]:
			var tt: int = gs.pops.type_id[ps_s]
			if tt == wt_id or tt == gs.pops.T_SLAVES:
				workers += gs.pops.size[ps_s]
		p["rgo_data"] = {"good": p["rgo"], "base_size": float(workers) / UNIT * headroom, "current_size": 0.0,
			"workers": workers, "max_workers": 0, "efficiency": 1.0, "output": 0.0, "revenue": 0.0}
	_calibrate(gs)
	derive_rates(gs)
	var fid := 1
	for key in gs.state_instances:
		for f in gs.state_instances[key]["factories"]:
			_normalize_factory(f, fid)
			fid += 1
	gs.market["next_factory_id"] = fid
	_assign_initial_artisans(gs)
	for tag in gs.countries:
		gs.countries[tag]["projects"] = []
		gs.countries[tag]["artisan_profit"] = {}


static func _normalize_factory(f: Dictionary, fid: int) -> void:
	f["id"] = int(f.get("id", fid))
	f["level"] = int(f.get("level", 1))
	f["open"] = bool(f.get("open", true))
	f["hiring"] = float(f.get("hiring", 1.0))
	f["stock"] = f.get("stock", {})
	f["cash"] = float(f.get("cash", 120.0 * int(f["level"])))
	f["revenue"] = float(f.get("revenue", 0.0))
	f["expenses"] = float(f.get("expenses", 0.0))
	f["profit"] = float(f.get("profit", 0.0))
	f["subsidized"] = bool(f.get("subsidized", false))
	f["loss_months"] = int(f.get("loss_months", 0))
	f["craftsmen_employed"] = int(f.get("craftsmen_employed", 0))
	f["clerks_employed"] = int(f.get("clerks_employed", 0))
	f["max_workers"] = int(f.get("max_workers", 0))
	f["output"] = float(f.get("output", 0.0))
	f.erase("employment")


static func rgo_worker_type(gs: VGameState, good: String) -> String:
	return "farmers" if gs.goods.get(good, {}).get("rgo", "farm") == "farm" else "labourers"


## Productividad de cada bien primario: valor objetivo / precio base × calibración.
## La calibración ajusta la oferta inicial a la demanda estimada (dentro de límites) para que el
## escenario de prueba arranque cerca del equilibrio; después mandan los precios.
static func _calibrate(gs: VGameState) -> void:
	var rules: Dictionary = gs.economy_rules
	var value := float(rules.get("rgo_value_per_10k", 26.0))
	var supply := {}
	var demand := {}
	for id in range(1, gs.first_sea_id):
		var p: Dictionary = gs.provinces[id]
		if p["owner"] == "":
			continue
		var g: String = p["rgo"]
		var eff := float(gs.terrain_types.get(p["terrain"], {}).get("rgo_efficiency", 1.0))
		supply[g] = float(supply.get(g, 0.0)) + float(p["rgo_data"]["workers"]) / UNIT * value / float(gs.goods[g]["base_price"]) * eff
		for ps_s: int in p["pop_slots"]:
			var units := float(gs.pops.size[ps_s]) / UNIT
			var weights: Array = rules.get("calibration_tier_weights", [1.0, 0.5, 0.1])
			for i in 3:
				var basket := VPopulationSystem.needs_basket(gs, gs.pops.type_name(ps_s), VPopulationSystem.TIERS[i])
				for good in basket:
					demand[good] = float(demand.get(good, 0.0)) + float(basket[good]) * units * weights[i]
	# insumos de fábricas existentes y de artesanos (estimación)
	var tmp_rates := _recipe_rates(gs)
	for key in gs.state_instances:
		for f in gs.state_instances[key]["factories"]:
			var ft: Dictionary = gs.factory_types.get(f["type"], {})
			for good in ft.get("inputs", {}):
				demand[good] = float(demand.get(good, 0.0)) + float(ft["inputs"][good]) * float(tmp_rates["factory"].get(f["type"], 0.0)) * int(f["level"])
	var art_units := 0.0
	for id in range(1, gs.first_sea_id):
		if gs.provinces[id]["owner"] == "":
			continue
		for ps_s: int in gs.provinces[id]["pop_slots"]:
			if gs.pops.type_id[ps_s] == gs.pops.T_ARTISANS:
				art_units += float(gs.pops.size[ps_s]) / UNIT
	var art_rates: Dictionary = tmp_rates["artisan"]
	for t in art_rates:
		var ft2: Dictionary = gs.factory_types[t]
		for good in ft2.get("inputs", {}):
			demand[good] = float(demand.get(good, 0.0)) + float(ft2["inputs"][good]) * float(art_rates[t]) * art_units / float(art_rates.size())
	var cal := {}
	for g in supply:
		if float(supply[g]) <= 0.0:
			continue
		cal[g] = clampf(float(demand.get(g, 0.0)) / float(supply[g]), float(rules.get("rgo_calibration_min", 0.35)), float(rules.get("rgo_calibration_max", 3.0)))
	gs.market["calibration"] = cal


static func _recipe_rates(gs: VGameState) -> Dictionary:
	var rules: Dictionary = gs.economy_rules
	var fr := {}
	var ar := {}
	for t in gs.factory_types:
		var ft: Dictionary = gs.factory_types[t]
		var out_value := 0.0
		for g in ft.get("outputs", {}):
			out_value += float(ft["outputs"][g]) * float(gs.goods[g]["base_price"])
		if out_value <= 0.0:
			continue
		fr[t] = float(rules.get("factory_value_per_level", 300.0)) / out_value
		if ft.get("artisan", false):
			ar[t] = float(rules.get("artisan_value_per_10k", 150.0)) / out_value
	return {"factory": fr, "artisan": ar}


## Calentamiento del escenario: durante el primer año la productividad de cada RGO se corrige
## suavemente hacia la demanda real observada (el mapa de prueba reparte recursos al azar).
static func warmup_recalibrate(gs: VGameState) -> void:
	var w: Dictionary = gs.market.get("world", {})
	var cal: Dictionary = gs.market["calibration"]
	var rules: Dictionary = gs.economy_rules
	for g in cal:
		var s := float(w.get("supply", {}).get(g, 0.0))
		var d := float(w.get("demand", {}).get(g, 0.0))
		if s <= 0.0:
			continue
		var f := clampf(sqrt(maxf(d, 0.01) / s), 0.8, 1.25)
		cal[g] = clampf(float(cal[g]) * f, 0.05, float(rules.get("rgo_calibration_max", 3.0)))
	derive_rates(gs)


## Tasas derivadas (no se guardan: se recalculan de los datos y de la calibración guardada).
static func derive_rates(gs: VGameState) -> void:
	var value := float(gs.economy_rules.get("rgo_value_per_10k", 26.0))
	var out := {}
	for g in gs.goods:
		if gs.goods[g].get("rgo") == null:
			continue
		out[g] = value / float(gs.goods[g]["base_price"]) * float(gs.market["calibration"].get(g, 1.0))
	gs.market["rgo_output"] = out
	var r := _recipe_rates(gs)
	gs.market["factory_rate"] = r["factory"]
	gs.market["artisan_rate"] = r["artisan"]


static func _assign_initial_artisans(gs: VGameState) -> void:
	var options: Array = gs.market["artisan_rate"].keys()
	options.sort()
	for id in range(1, gs.first_sea_id):
		for ps_s: int in gs.provinces[id]["pop_slots"]:
			if gs.pops.type_id[ps_s] == gs.pops.T_ARTISANS:
				gs.pops.product[ps_s] = options[(gs.pops.id[ps_s] * 7 + id) % options.size()]


# ------------------------------------------------- proceso mensual (provincia)
static func process_province(gs: VGameState, id: int) -> void:
	var p: Dictionary = gs.provinces[id]
	var tag: String = p["owner"]
	if tag == "":
		return
	var c: Dictionary = gs.countries[tag]
	var ps := gs.pops
	var slots: Array = p["pop_slots"]
	var a_type := ps.type_id
	var a_size := ps.size
	var a_emp := ps.employment
	var a_employer := ps.employer
	var a_cash := ps.cash
	var a_inacc := ps.income_acc
	var t_strata := ps.t_strata
	var t_job := ps.t_job
	var t_wage := ps.t_gov_wage
	var cx := _country_ctx(gs, tag, c)
	var mk: Dictionary = cx["mk"]
	# ---------------- RGO: recuento de trabajadores y propietarios
	var rd: Dictionary = p["rgo_data"]
	var good: String = rd["good"]
	var wt := int(ps.type_index.get(rgo_worker_type(gs, good), -2))
	var t_slaves := ps.T_SLAVES
	var t_aristo := ps.T_ARISTOCRATS
	var t_farm := ps.T_FARMERS
	var t_lab := ps.T_LABOURERS
	var t_art := ps.T_ARTISANS
	var workers := 0
	var aristos := []
	var aristo_size := 0
	for s0: int in slots:
		var t0: int = a_type[s0]
		if t0 == wt or t0 == t_slaves:
			workers += a_size[s0]
		elif t0 == t_aristo:
			aristos.append(s0)
			aristo_size += a_size[s0]
	var pm: Dictionary = p.get("pmods", {})
	# M5.5: desarrollo del RGO (mejoras rurales financiadas por aristócratas o el Estado): más plazas y algo
	# más de productividad, con un límite por infraestructura y tecnología
	var dev := float(p.get("rgo_dev", 0.0))
	var size := float(rd["base_size"]) * (float(cx["rgo_size"]) + float(pm.get("rgo_size", 0.0))) * (1.0 + float(cx["dev_size"]) * dev)
	var max_workers := int(size * UNIT)
	var employed: int = mini(workers, max_workers)
	var ratio := float(employed) / float(workers) if workers > 0 else 0.0
	var eff := float(gs.terrain_types.get(p["terrain"], {}).get("rgo_efficiency", 1.0)) * (float(cx["rgo_eff"]) + float(pm.get("rgo_efficiency", 0.0))) * (1.0 + 0.05 * int(p["infrastructure"])) * (1.0 + float(cx["dev_eff"]) * dev)
	var output := float(employed) / UNIT * float(gs.market["rgo_output"].get(good, 1.0)) * eff
	# ocupación enemiga: la producción cae y el propietario no recauda impuestos aquí
	var occupied: bool = p["controller"] != tag
	if occupied:
		output *= 0.4
	var tax_tag := "" if occupied else tag
	VMarketSystem.add_supply(gs, tag, good, output)
	var revenue := output * _price(mk, good) * _fill_sell(mk, good)
	rd["current_size"] = size
	rd["workers"] = employed
	rd["max_workers"] = max_workers
	rd["efficiency"] = eff
	rd["output"] = output
	rd["revenue"] = revenue
	p["rgo_free"] = max_workers - workers
	var owner_share := float(gs.economy_rules.get("rgo_owner_share", 0.2)) if aristo_size > 0 else 0.0
	var worker_pool := revenue * (1.0 - owner_share)
	var owner_pool := revenue * owner_share
	var paid_out := 0.0
	# ---------------- empleo estatal, prestaciones e impuestos: contexto por país (cacheado, ver _country_ctx)
	var social_spent := 0.0
	var prov_units := 0.0
	var benefit_rate: float = cx["benefit_rate"]
	var pension_rate: float = cx["pension_rate"]
	var health_cost: float = cx["health_cost"]
	var transfers: bool = cx["transfers"]
	var needs: Array[float] = c.get("_needs_tid", [] as Array[float])
	var pay_by_type: Array[float] = cx["pay_by_type"]
	var exp_by_type: Array[int] = cx["exp_by_type"]
	var exp_keys: Array[String] = cx["exp_keys"]
	var exp_vals: Array[float] = (cx["exp_zero"] as Array[float]).duplicate()
	var state_job: Array[bool] = cx["state_job"]
	var investor: Array[bool] = cx["investor"]
	var tax_rate: Array[float] = cx["tax_rate"]
	var tax_acc: Array[float] = [0.0, 0.0, 0.0]
	# ---------------- una pasada por POP: RGO → artesano → empleo estatal → prestaciones
	# (mismo orden por POP que las tres pasadas originales: el resultado no cambia)
	for s: int in slots:
		var t: int = a_type[s]
		var units := float(a_size[s]) / UNIT
		prov_units += units
		var st: int = t_strata[t]
		if t == wt or t == t_slaves:
			a_emp[s] = ratio
			a_employer[s] = VPopStore.EMP_RGO
			if employed > 0:
				var share := worker_pool * float(a_size[s]) * ratio / float(employed)
				if t == t_slaves and aristo_size > 0:
					a_cash[s] += share * 0.3
					a_inacc[s] += share * 0.3
					owner_pool += share * 0.7
					paid_out += share * 0.3
				elif share > 0.0:
					var net := share
					if not occupied:
						var tx := share * tax_rate[st]
						tax_acc[st] += tx
						net = share - tx
					a_cash[s] += net
					a_inacc[s] += net
					paid_out += share
		elif t == t_farm or t == t_lab:
			a_emp[s] = 0.0
			a_employer[s] = VPopStore.EMP_NONE
		elif t == t_art:
			_artisan(gs, s, tag, c, mk)
		if state_job[t]:
			var pay := pay_by_type[t] * units
			a_emp[s] = 1.0 if pay > 0.0 else 0.0
			a_employer[s] = VPopStore.EMP_STATE
			if pay > 0.0:
				var tx2 := pay * tax_rate[st]
				tax_acc[st] += tx2
				a_cash[s] += pay - tx2
				a_inacc[s] += pay - tx2
				exp_vals[exp_by_type[t]] += pay
		elif investor[t]:
			a_emp[s] = 1.0
			a_employer[s] = VPopStore.EMP_INVEST
		if transfers and st == 0:
			var life_cost := (needs[t * 6] if t * 6 < needs.size() else 0.0) * units
			var amount := life_cost * (benefit_rate * (1.0 - a_emp[s]) + pension_rate)
			if amount > 0.0:
				a_cash[s] += amount
				a_inacc[s] += amount
				social_spent += amount
	for ar in aristos:
		a_emp[ar] = 1.0
		a_employer[ar] = VPopStore.EMP_OWNER
		var ashare := owner_pool * float(a_size[ar]) / float(aristo_size)
		VBudgetSystem.credit_income(gs, tax_tag, ar, ashare)
		paid_out += ashare
	VMoney.created(gs, paid_out, "rgo_sales")
	# libro de dinero de los artesanos: un apunte por provincia
	if mk.has("art_sales"):
		VMoney.created(gs, float(mk["art_sales"]), "artisan_sales")
		VMoney.destroyed(gs, float(mk["art_inputs"]), "artisan_inputs")
		mk.erase("art_sales")
		mk.erase("art_inputs")
	var acc: Dictionary = c["acc"]
	acc["tax_poor"] = float(acc["tax_poor"]) + tax_acc[0]
	acc["tax_middle"] = float(acc["tax_middle"]) + tax_acc[1]
	acc["tax_rich"] = float(acc["tax_rich"]) + tax_acc[2]
	for ki in exp_keys.size():
		VBudgetSystem.add_expense(gs, tag, exp_keys[ki], exp_vals[ki])
	social_spent += health_cost * prov_units * 0.6
	VBudgetSystem.add_expense(gs, tag, "social", social_spent)


## Contexto de la nación para el bucle de provincia: mercado, sueldos estatales y gasto por tipo de POP,
## prestaciones, impuestos y modificadores. Es constante dentro del mes salvo que cambien el presupuesto
## (sliders), los modificadores, la capacidad de pago o la eficiencia fiscal: la clave incluye sus hashes,
## así que un cambio del jugador se aplica en la siguiente provincia procesada, igual que antes.
static func _country_ctx(gs: VGameState, tag: String, c: Dictionary) -> Dictionary:
	var key := [gs.month_index, c["budget"].hash(), c.get("mods", {}).hash(), float(c.get("pay_ratio", 1.0)), float(c.get("tax_efficiency", 0.8))]
	var cx: Dictionary = c.get("_pctx", {})
	if not cx.is_empty() and cx["key"] == key:
		return cx
	var ps := gs.pops
	var social := float(c["budget"].get("social", 0.0)) * float(c.get("pay_ratio", 1.0))
	var nt := ps.type_names.size()
	var pay_by_type: Array[float] = []
	pay_by_type.resize(nt)
	var exp_by_type: Array[int] = []
	exp_by_type.resize(nt)
	var exp_keys: Array[String] = []
	var exp_zero: Array[float] = []
	var state_job: Array[bool] = []
	state_job.resize(nt)
	var investor: Array[bool] = []
	investor.resize(nt)
	for tt in nt:
		var job0: String = ps.t_job[tt]
		investor[tt] = job0 == "investor"
		if VBudgetSystem.EXPENSE_FOR_JOB.has(job0):
			state_job[tt] = true
			pay_by_type[tt] = ps.t_gov_wage[tt] * VBudgetSystem.gov_pay_factor(c, job0)
			var ek0: String = VBudgetSystem.EXPENSE_FOR_JOB[job0]
			var ki := exp_keys.find(ek0)
			if ki < 0:
				ki = exp_keys.size()
				exp_keys.append(ek0)
				exp_zero.append(0.0)
			exp_by_type[tt] = ki
	var tax_eff := float(c.get("tax_efficiency", 0.8))
	var budget: Dictionary = c["budget"]
	var tax_rate: Array[float] = [float(budget.get("tax_poor", 0.0)) * tax_eff, float(budget.get("tax_middle", 0.0)) * tax_eff,
		float(budget.get("tax_rich", 0.0)) * tax_eff]
	var benefit_rate := gs.mod(tag, "unemployment_benefit") * social
	var pension_rate := gs.mod(tag, "pension") * social
	cx = {"key": key, "mk": _market_ctx(gs, tag, c), "benefit_rate": benefit_rate, "pension_rate": pension_rate,
		"health_cost": gs.mod(tag, "social_cost") * social, "transfers": benefit_rate > 0.0 or pension_rate > 0.0,
		"pay_by_type": pay_by_type, "exp_by_type": exp_by_type, "exp_keys": exp_keys, "exp_zero": exp_zero,
		"state_job": state_job, "investor": investor, "tax_rate": tax_rate,
		"rgo_size": 1.0 + gs.mod(tag, "rgo_size"), "rgo_eff": 1.0 + gs.mod(tag, "rgo_efficiency"),
		"dev_size": float(gs.economy_rules.get("rgo_development", {}).get("size_per_level", 0.15)),
		"dev_eff": float(gs.economy_rules.get("rgo_development", {}).get("efficiency_per_level", 0.02))}
	c["_pctx"] = cx
	return cx


## Contexto de mercado de la nación para el bucle de provincia (diccionarios ya resueltos).
static func _market_ctx(gs: VGameState, tag: String, c: Dictionary) -> Dictionary:
	var m: Dictionary = gs.market
	return {"price": m["price"], "fs": m["fill_sell"].get(tag, {}), "fb": m["fill_buy"].get(tag, {}),
		"share": m["import_share"].get(tag, {}), "tariff": float(c["budget"].get("tariffs", 0.0)),
		"rates": m["artisan_rate"], "eff_mod": 1.0 + gs.mod(tag, "artisan_efficiency"),
		"switch": float(gs.economy_rules.get("artisan_switch_rate", 0.15))}


static func _price(mk: Dictionary, g: String) -> float:
	return float(mk["price"].get(g, 1.0))


static func _fill_sell(mk: Dictionary, g: String) -> float:
	return float(mk["fs"].get(g, 1.0))


## Igual que VMarketSystem.buy_price (el arancel encarece la parte importada).
static func _buy_price(mk: Dictionary, g: String) -> float:
	return float(mk["price"].get(g, 1.0)) * (1.0 + float(mk["tariff"]) * float(mk["share"].get(g, 0.0)))


## Un POP de artesanos: elige producto, compra insumos con capital circulante, produce y vende.
static func _artisan(gs: VGameState, s: int, tag: String, c: Dictionary, mk: Dictionary) -> void:
	var ps := gs.pops
	var rates: Dictionary = mk["rates"]
	var best: String = c.get("artisan_best", "")
	var profits: Dictionary = c.get("artisan_profit", {})
	var choices: Array = c.get("artisan_choices", [])
	var product: String = ps.product[s]
	var pid: int = ps.id[s]
	if best != "" and product != best and not choices.is_empty():
		var cur := float(profits.get(product, -1.0))
		if cur < float(profits.get(best, 0.0)) * 0.7 and (pid + gs.month_index) % int(1.0 / float(mk["switch"])) == 0:
			# reparto ponderado por beneficio entre los productos rentables (evita que todos elijan el mismo)
			var roll := float(absi(("%d|%d" % [pid, gs.month_index]).hash()) % 10000) / 10000.0 * float(c.get("artisan_choice_total", 1.0))
			for ch in choices:
				roll -= float(ch[1])
				if roll <= 0.0:
					product = ch[0]
					break
			ps.product[s] = product
	if not rates.has(product):
		product = rates.keys()[0]
		ps.product[s] = product
	var ft: Dictionary = gs.factory_types[product]
	var inputs: Dictionary = ft["inputs"]
	var outputs: Dictionary = ft["outputs"]
	var fb: Dictionary = mk["fb"]
	var recipes := float(ps.size[s]) / UNIT * float(rates[product]) * float(mk["eff_mod"])
	var in_cost := 0.0
	for g in inputs:
		in_cost += float(inputs[g]) * _buy_price(mk, g)
	# capital circulante: los insumos se pagan con lo que se vende este mes más el efectivo
	var expected := 0.0
	for g in outputs:
		expected += float(outputs[g]) * recipes * _price(mk, g) * _fill_sell(mk, g)
	var cash := ps.cash[s]
	var scale := 1.0
	if in_cost * recipes > cash + expected and in_cost > 0.0:
		scale = clampf((cash + expected) / (in_cost * recipes), 0.0, 1.0)
	var fill := 1.0
	var paid := 0.0
	for g in inputs:
		var q := float(inputs[g]) * recipes * scale
		VMarketSystem.add_demand(gs, tag, g, q)
		var fbg := float(fb.get(g, 1.0))
		fill = minf(fill, fbg)
		paid += q * fbg * _buy_price(mk, g)
	var produced := recipes * scale * fill
	var revenue := 0.0
	for g in outputs:
		var q := float(outputs[g]) * produced
		VMarketSystem.add_supply(gs, tag, g, q)
		revenue += q * _price(mk, g) * _fill_sell(mk, g)
	mk["art_sales"] = float(mk.get("art_sales", 0.0)) + revenue
	mk["art_inputs"] = float(mk.get("art_inputs", 0.0)) + paid
	if revenue >= paid:
		VBudgetSystem.credit_income(gs, tag, s, revenue - paid)
	else:
		var loss := paid - revenue
		if loss > cash:
			VMoney.created(gs, loss - cash, "artisan_loss_forgiven")
		ps.cash[s] = maxf(0.0, cash - loss)
	ps.employment[s] = clampf(scale * fill, 0.0, 1.0) if revenue > paid else clampf(scale * fill * 0.5, 0.0, 1.0)
	ps.employer[s] = ps.employer_of("artisan:" + product)


# ---------------------------------------------------- fábricas (estado)
## Procesa las fábricas de una partición de estado: plantilla, insumos, producción, salarios, beneficio.
static func process_state_instance(gs: VGameState, si: Dictionary) -> void:
	var tag: String = si["owner"]
	if tag == "":
		return
	var c: Dictionary = gs.countries[tag]
	var rules: Dictionary = gs.economy_rules
	var craftsmen := []
	var clerks := []
	var capitalists := []
	var magi := []
	var cr_total := 0
	var cl_total := 0
	var mg_total := 0
	var t_magi := gs.pops.T_MAGI
	var infra := 0.0
	var inst_pop := 0
	for id in si["provinces"]:
		infra += float(gs.provinces[id]["infrastructure"])
		inst_pop += int(gs.provinces[id]["population"])
		for ps_s: int in gs.provinces[id]["pop_slots"]:
			var tt: int = gs.pops.type_id[ps_s]
			if tt == gs.pops.T_CRAFTSMEN:
				craftsmen.append(ps_s)
				cr_total += gs.pops.size[ps_s]
			elif tt == gs.pops.T_CLERKS:
				clerks.append(ps_s)
				cl_total += gs.pops.size[ps_s]
			elif tt == gs.pops.T_CAPITALISTS:
				capitalists.append(ps_s)
			elif tt == t_magi:
				magi.append(ps_s)
				mg_total += gs.pops.size[ps_s]
	infra /= maxf(1.0, float(si["provinces"].size()))
	si["_pop"] = inst_pop
	si["_urban"] = float(cr_total + cl_total + mg_total) / maxf(1.0, float(inst_pop))
	# plazas
	var cr_slots := 0.0
	var cl_slots := 0.0
	var mg_slots := 0.0
	for f in si["factories"]:
		if not f["open"]:
			continue
		var wf: Dictionary = gs.factory_types.get(f["type"], {}).get("workforce", {})
		cr_slots += float(wf.get("craftsmen", 9000)) * int(f["level"]) * float(f["hiring"])
		cl_slots += float(wf.get("clerks", 1000)) * int(f["level"]) * float(f["hiring"])
		mg_slots += float(wf.get("magi", 0)) * int(f["level"]) * float(f["hiring"])
	var cr_fill := minf(1.0, float(cr_total) / cr_slots) if cr_slots > 0.0 else 0.0
	var cl_fill := minf(1.0, float(cl_total) / cl_slots) if cl_slots > 0.0 else 0.0
	si["vacancy_craftsmen"] = int(maxf(0.0, cr_slots - float(cr_total)))
	si["vacancy_clerks"] = int(maxf(0.0, cl_slots - float(cl_total)))
	# M5: magos en fábricas mágicas (workforce.magi): sin magos la fábrica rinde menos
	var mg_fill := minf(1.0, float(mg_total) / mg_slots) if mg_slots > 0.0 else 0.0
	si["vacancy_magi"] = int(maxf(0.0, mg_slots - float(mg_total)))
	var needs: Dictionary = c.get("_needs", {})
	var wage_mult := float(rules.get("factory_wage_multiplier", 1.6)) * (1.0 + gs.mod(tag, "factory_wage"))
	var cr_cost: Array = needs.get("craftsmen", {}).get("cost", [5.0, 5.0, 5.0])
	var cl_cost: Array = needs.get("clerks", {}).get("cost", [15.0, 15.0, 15.0])
	var cr_wage := (float(cr_cost[0]) + float(cr_cost[1])) * wage_mult
	var cl_wage := (float(cl_cost[0]) + float(cl_cost[1])) * wage_mult
	var mg_wage := cl_wage * float(VMageModel.rules(gs).get("factory_wage_multiplier", 1.4))
	var magic_eff := 1.0 + gs.mod(tag, "magic_factory_efficiency")
	var occ := 0
	for id in si["provinces"]:
		if gs.provinces[id]["controller"] != tag:
			occ += 1
	var occ_share := float(occ) / maxf(1.0, float(si["provinces"].size()))
	var we := float(c.get("war_exhaustion", 0.0))
	var eff_base := (1.0 + gs.mod(tag, "factory_efficiency")) * (1.0 + 0.05 * infra) * (1.0 + gs.mod(tag, "factory_throughput")) * (1.0 - 0.6 * occ_share) * (1.0 - we / 400.0)
	var rates: Dictionary = gs.market["factory_rate"]
	var stock_months := float(rules.get("factory_input_stock_months", 1.0))
	var wages_cr := 0.0
	var wages_cl := 0.0
	var wages_mg := 0.0
	var profit_total := 0.0
	var policy := economic_policy(gs, tag)
	var can_subsidize: bool = policy in rules.get("subsidy_policies", [])
	for f in si["factories"]:
		var ft: Dictionary = gs.factory_types.get(f["type"], {})
		var wf: Dictionary = ft.get("workforce", {})
		if not f["open"]:
			f["craftsmen_employed"] = 0
			f["clerks_employed"] = 0
			f["revenue"] = 0.0
			f["expenses"] = 0.0
			f["profit"] = 0.0
			f["output"] = 0.0
			continue
		var max_cr := float(wf.get("craftsmen", 9000)) * int(f["level"])
		var max_cl := float(wf.get("clerks", 1000)) * int(f["level"])
		var emp_cr := max_cr * float(f["hiring"]) * cr_fill
		var emp_cl := max_cl * float(f["hiring"]) * cl_fill
		f["craftsmen_employed"] = int(emp_cr)
		f["clerks_employed"] = int(emp_cl)
		f["max_workers"] = int(max_cr + max_cl)
		var staffing := emp_cr / max_cr if max_cr > 0.0 else 0.0
		if staffing < 0.1:
			f["unstaffed_months"] = int(f.get("unstaffed_months", 0)) + 1
			if int(f["unstaffed_months"]) >= 12:
				f["open"] = false
				f["unstaffed_months"] = 0
				gs.log_event(tag, "Cierra %s en %s: no encuentra obreros" % [ft.get("name", f["type"]), gs.states[si["state"]]["name"]])
				VEventSystem.notify(gs, "factory_closed", {"tag": tag})
				continue
		else:
			f["unstaffed_months"] = 0
		var clerk_ratio := emp_cl / max_cl if max_cl > 0.0 else 0.0
		var recipes := float(rates.get(f["type"], 0.0)) * int(f["level"]) * staffing * (0.75 + 0.5 * clerk_ratio) * eff_base
		var max_mg := float(wf.get("magi", 0)) * int(f["level"])
		var emp_mg := 0.0
		if max_mg > 0.0:
			emp_mg = max_mg * float(f["hiring"]) * mg_fill
			recipes *= (0.35 + 0.65 * emp_mg / max_mg) * maxf(0.1, magic_eff)
		f["magi_employed"] = int(emp_mg)
		# insumos: consumir del stock, reponer comprando al mercado
		var stock: Dictionary = f["stock"]
		var avail := 1.0
		for g in ft.get("inputs", {}):
			var need := float(ft["inputs"][g]) * recipes
			if need > 0.0:
				avail = minf(avail, float(stock.get(g, 0.0)) / need)
		var produced := recipes * clampf(avail, 0.0, 1.0)
		var input_cost := 0.0
		var target_recipes := float(rates.get(f["type"], 0.0)) * int(f["level"]) * float(f["hiring"]) * eff_base * stock_months
		for g in ft.get("inputs", {}):
			var per := float(ft["inputs"][g])
			stock[g] = maxf(0.0, float(stock.get(g, 0.0)) - per * produced)
			var want := maxf(0.0, per * target_recipes - float(stock[g]))
			if want > 0.0:
				VMarketSystem.add_demand(gs, tag, g, want)
				var got := want * VMarketSystem.fill_buy(gs, tag, g)
				stock[g] = float(stock[g]) + got
				input_cost += got * VMarketSystem.buy_price(gs, tag, g)
		var revenue := 0.0
		for g in ft.get("outputs", {}):
			var q := float(ft["outputs"][g]) * produced
			VMarketSystem.add_supply(gs, tag, g, q)
			revenue += q * VMarketSystem.price(gs, g) * VMarketSystem.fill_sell(gs, tag, g)
		VMoney.created(gs, revenue, "factory_sales")
		VMoney.destroyed(gs, input_cost, "factory_inputs")
		var w_cr := emp_cr / UNIT * cr_wage
		var w_cl := emp_cl / UNIT * cl_wage
		var w_mg := emp_mg / UNIT * mg_wage
		# M5.5: una fábrica sin caja no paga salarios que nadie financia (antes el déficit se «perdonaba»
		# creando dinero: con muchas fábricas en pérdidas eso imprimía dinero cada mes). Si no está
		# subvencionada, recorta los salarios a lo que cubren sus ventas y su caja.
		var w_tot := w_cr + w_cl + w_mg
		var can_pay := revenue - input_cost + maxf(0.0, float(f["cash"]))
		f["wage_cut"] = 1.0
		if w_tot > 0.0 and w_tot > can_pay and not (f["subsidized"] and can_subsidize):
			var k := clampf(can_pay / w_tot, 0.0, 1.0)
			w_cr *= k
			w_cl *= k
			w_mg *= k
			f["wage_cut"] = k
		wages_cr += w_cr
		wages_cl += w_cl
		wages_mg += w_mg
		var expenses := input_cost + w_cr + w_cl + w_mg
		var profit := revenue - expenses
		f["output"] = produced
		f["revenue"] = revenue
		f["expenses"] = expenses
		f["profit"] = profit
		f["age"] = int(f.get("age", 24)) + 1
		var hist: Array = f.get("profit_hist", [])
		hist.append(profit)
		if hist.size() > 12:
			hist.remove_at(0)
		f["profit_hist"] = hist
		f["staffing"] = staffing
		if profit >= 0.0:
			var reinvest := profit * float(rules.get("factory_reinvest_share", 0.3))
			f["cash"] = float(f["cash"]) + reinvest
			profit_total += profit - reinvest
			# colchón de caja: hasta N meses de gastos; el exceso se reparte a los propietarios
			var buffer := maxf(100.0, expenses * float(rules.get("factory_cash_buffer_months", 3.0)))
			if float(f["cash"]) > buffer:
				profit_total += float(f["cash"]) - buffer
				f["cash"] = buffer
			f["loss_months"] = 0
			f["hiring"] = minf(1.0, float(f["hiring"]) + 0.1)
		else:
			f["cash"] = float(f["cash"]) + profit
			f["loss_months"] = int(f["loss_months"]) + 1
			if float(f["cash"]) < 0.0:
				if f["subsidized"] and can_subsidize:
					VBudgetSystem.add_expense(gs, tag, "subsidies", -float(f["cash"]))
					f["cash"] = 0.0
				else:
					f["hiring"] = maxf(0.1, float(f["hiring"]) * 0.75)
					VMoney.created(gs, -float(f["cash"]), "factory_loss_forgiven")
					f["cash"] = 0.0
					if int(f["loss_months"]) >= int(rules.get("factory_close_months", 6)) and float(f["hiring"]) <= 0.15:
						f["open"] = false
						gs.log_event(tag, "Cierra %s en %s por pérdidas" % [ft.get("name", f["type"]), gs.states[si["state"]]["name"]])
						VEventSystem.notify(gs, "factory_closed", {"tag": tag})
	# salarios a los POPs (proporcional a su tamaño y al empleo de la partición)
	var cr_emp_frac := minf(1.0, cr_slots / float(cr_total)) if cr_total > 0 else 0.0
	var cl_emp_frac := minf(1.0, cl_slots / float(cl_total)) if cl_total > 0 else 0.0
	var ps := gs.pops
	for s in craftsmen:
		ps.employment[s] = cr_emp_frac
		ps.employer[s] = VPopStore.EMP_FACTORY if cr_emp_frac > 0.0 else VPopStore.EMP_NONE
		if cr_total > 0:
			VBudgetSystem.credit_income(gs, tag, s, wages_cr * float(ps.size[s]) / float(cr_total))
	for s in clerks:
		ps.employment[s] = cl_emp_frac
		ps.employer[s] = VPopStore.EMP_FACTORY if cl_emp_frac > 0.0 else VPopStore.EMP_NONE
		if cl_total > 0:
			VBudgetSystem.credit_income(gs, tag, s, wages_cl * float(ps.size[s]) / float(cl_total))
	if mg_total > 0:
		_pay_magi(gs, tag, c, magi, mg_total, mg_slots, wages_mg)
	# beneficio a capitalistas del estado (si no hay, a los del país)
	if profit_total > 0.0:
		if capitalists.is_empty():
			capitalists = c.get("_capitalists", [])
		var cap_size := 0
		for s in capitalists:
			cap_size += ps.size[s]
		if cap_size > 0:
			for s in capitalists:
				VBudgetSystem.credit_income(gs, tag, s, profit_total * float(ps.size[s]) / float(cap_size))
		else:
			c["treasury"] = float(c["treasury"]) + profit_total * 0.5
			VMoney.destroyed(gs, profit_total * 0.5, "profit_without_owner")


## M5: empleo y salario de los magos de la partición: primero las plazas de fábricas mágicas (salario de la
## fábrica), después las plazas del Estado (academias, administración, ejército; VMageModel._state_posts) con
## la misma tasa de cobertura en toda la nación. Acumula [magos, empleo privado, empleo estatal, vida] del mes.
static func _pay_magi(gs: VGameState, tag: String, c: Dictionary, magi: Array, mg_total: int, mg_slots: float, wages_mg: float) -> void:
	var ps := gs.pops
	var priv := minf(1.0, mg_slots / float(mg_total))
	var ms: Dictionary = c.get("_magi_state", {})
	var st_frac := (1.0 - priv) * float(ms.get("fill", 0.0))
	var pay_unit := float(ms.get("pay", 0.0))
	var split: Dictionary = ms.get("split", {})
	var acc: Array = c.get("_magi_acc_cur", [0.0, 0.0, 0.0, 0.0])
	var state_pay := 0.0
	var life := 0.0
	for s in magi:
		var sz := float(ps.size[s])
		ps.employment[s] = priv + st_frac
		ps.employer[s] = VPopStore.EMP_FACTORY if priv > 0.0 else (VPopStore.EMP_STATE if st_frac > 0.0 else VPopStore.EMP_NONE)
		if wages_mg > 0.0:
			VBudgetSystem.credit_income(gs, tag, s, wages_mg * sz / float(mg_total))
		var pay := sz / UNIT * st_frac * pay_unit
		if pay > 0.0:
			VBudgetSystem.credit_income(gs, tag, s, pay)
			state_pay += pay
		life += sz * ps.life[s]
	for k in split:
		var part := state_pay * float(split[k])
		if k == "practice":
			# práctica privada: la pagan los ricos de la nación (VMageModel._charge_practice)
			c["_practice_due"] = float(c.get("_practice_due", 0.0)) + part
		else:
			VBudgetSystem.add_expense(gs, tag, k, part)
	acc[0] = float(acc[0]) + float(mg_total)
	acc[1] = float(acc[1]) + float(mg_total) * priv
	acc[2] = float(acc[2]) + float(mg_total) * st_frac
	acc[3] = float(acc[3]) + life
	c["_magi_acc_cur"] = acc


static func economic_policy(gs: VGameState, tag: String) -> String:
	var c: Dictionary = gs.countries[tag]
	var party: Dictionary = VPoliticsSystem.ruling_party(gs, tag)
	return party.get("policies", {}).get("economic_policy", "interventionism") if not party.is_empty() else "interventionism"


# --------------------------------------------------- inversión (mensual)
static func monthly_country(gs: VGameState, tag: String, is_player: bool) -> void:
	var c: Dictionary = gs.countries[tag]
	if c["provinces"].is_empty():
		return
	_update_artisan_profit(gs, tag)
	_progress_projects(gs, tag)
	# M5.5: inversión por capacidad (privada, estatal y rural); ver VInvestmentSystem
	VInvestmentSystem.monthly(gs, tag, is_player)
	# reabrir fábricas cerradas que vuelvan a ser rentables (con historial de precios, no un pico)
	if (gs.month_index + tag.hash()) % 6 == 0:
		for si in gs.country_state_instances(tag):
			for f in si["factories"]:
				if not f["open"] and expected_margin(gs, tag, f["type"], true) > 0.0:
					f["open"] = true
					f["hiring"] = 0.4
					f["loss_months"] = 0
					VMoney.created(gs, 50.0 - float(f["cash"]), "factory_reopen")
					f["cash"] = 50.0


## Margen mensual esperado por nivel (ingresos − insumos − salarios).
## Con smoothed = true usa la media de los últimos 6 meses del precio de venta (evita invertir por un pico).
static func expected_margin(gs: VGameState, tag: String, ftype: String, smoothed: bool = false) -> float:
	var ft: Dictionary = gs.factory_types.get(ftype, {})
	var rate := float(gs.market["factory_rate"].get(ftype, 0.0))
	var out := 0.0
	for g in ft.get("outputs", {}):
		out += float(ft["outputs"][g]) * (avg_price(gs, g, 6) if smoothed else VMarketSystem.price(gs, g))
	var inp := 0.0
	for g in ft.get("inputs", {}):
		inp += float(ft["inputs"][g]) * VMarketSystem.buy_price(gs, tag, g)
	var needs: Dictionary = gs.countries[tag].get("_needs", {})
	var cr_cost: Array = needs.get("craftsmen", {}).get("cost", [5.0, 5.0, 5.0])
	var wages := (float(cr_cost[0]) + float(cr_cost[1])) * float(gs.economy_rules.get("factory_wage_multiplier", 1.6)) * 1.0
	return (out - inp) * rate - wages


static func can_build_type(gs: VGameState, tag: String, ftype: String) -> bool:
	var req: String = gs.factory_types.get(ftype, {}).get("requires_tech", "")
	return (req == "" or req in gs.countries[tag].get("technologies", [])) and goods_unlocked(gs, ftype)


## ¿Están disponibles en el mercado todos los bienes de la receta? (los mágicos esperan al Despertar)
static func goods_unlocked(gs: VGameState, ftype: String) -> bool:
	var ft: Dictionary = gs.factory_types.get(ftype, {})
	for g in ft.get("inputs", {}):
		if not VMarketSystem.is_available(gs, g):
			return false
	for g in ft.get("outputs", {}):
		if not VMarketSystem.is_available(gs, g):
			return false
	return true


static func build_cost(gs: VGameState, tag: String, ftype: String, expand: bool) -> float:
	var cost := 0.0
	var bc: Dictionary = gs.factory_types.get(ftype, {}).get("build_cost", {})
	for g in bc:
		cost += float(bc[g]) * VMarketSystem.buy_price(gs, tag, g)
	return cost * (0.6 if expand else 1.0)


static func avg_price(gs: VGameState, good: String, months: int) -> float:
	var hist: Array = gs.market.get("history", {}).get(good, [])
	if hist.is_empty():
		return VMarketSystem.price(gs, good)
	var n := mini(months, hist.size())
	var t := 0.0
	for i in range(hist.size() - n, hist.size()):
		t += float(hist[i])
	return t / float(n)


## ¿El mercado pide más de este producto? (demanda mundial por encima de la oferta, o precio medio alto)
static func output_in_demand(gs: VGameState, ftype: String) -> bool:
	var w: Dictionary = gs.market.get("world", {})
	for g in gs.factory_types.get(ftype, {}).get("outputs", {}):
		var sup := float(w.get("supply", {}).get(g, 0.0))
		var dem := float(w.get("demand", {}).get(g, 0.0))
		var base := float(gs.goods[g]["base_price"])
		if dem > sup * 1.05 or avg_price(gs, g, 6) > base * 1.15:
			return true
	return false


## ¿Hay insumos suficientes en el mercado (nacional y mundial)?
static func inputs_available(gs: VGameState, tag: String, ftype: String) -> bool:
	var w: Dictionary = gs.market.get("world", {})
	for g in gs.factory_types.get(ftype, {}).get("inputs", {}):
		if VMarketSystem.fill_buy(gs, tag, g) < 0.85:
			return false
		var sup := float(w.get("supply", {}).get(g, 0.0))
		var dem := float(w.get("demand", {}).get(g, 0.0))
		if sup < dem * 0.95:
			return false
	return true


## Mejor inversión disponible. Ampliar exige rentabilidad persistente (12 meses de antigüedad,
## beneficio medio positivo en el historial, plantilla completa y demanda del producto). Construir exige
## demanda real del producto, margen positivo con precios medios, insumos disponibles, tecnología,
## mano de obra libre en el estado y que no haya ya un proyecto del mismo tipo.
## Diagnóstico de inversión: motivo por el que un mes no se inicia un proyecto (contadores por nación y mundo).
static func note_reason(gs: VGameState, c: Dictionary, reason: String) -> void:
	var r: Dictionary = c.get("_inv_reasons", {})
	r[reason] = int(r.get(reason, 0)) + 1
	c["_inv_reasons"] = r
	var w: Dictionary = gs.market.get("_inv_reasons", {})
	w[reason] = int(w.get(reason, 0)) + 1
	gs.market["_inv_reasons"] = w


static func note_stat(gs: VGameState, c: Dictionary, key: String, n: float = 1.0) -> void:
	var st: Dictionary = c.get("_inv_stats", {})
	st[key] = float(st.get(key, 0.0)) + n
	c["_inv_stats"] = st
	var w: Dictionary = gs.market.get("_inv_stats", {})
	w[key] = float(w.get(key, 0.0)) + n
	gs.market["_inv_stats"] = w


## Plazas de fábrica de una partición de estado (M5.5: regla explícita; se amplía en el modelo nuevo).
static func state_factory_slots(gs: VGameState, si: Dictionary) -> int:
	return VInvestmentSystem.state_slots(gs, si)


## Mejor plan de fábrica (compatibilidad): el primero de VInvestmentSystem.factory_plans.
static func best_investment(gs: VGameState, tag: String, why: Dictionary = {}) -> Dictionary:
	var plans := VInvestmentSystem.factory_plans(gs, tag, VInvestmentSystem.pending_keys(gs.countries[tag]), why, 1)
	return plans[0] if not plans.is_empty() else {}


static func start_project(gs: VGameState, tag: String, plan: Dictionary, investor: String) -> void:
	var c: Dictionary = gs.countries[tag]
	var bc: Dictionary = gs.factory_types.get(plan["type"], {}).get("build_cost", {})
	var goods := {}
	var mult := 0.6 if plan["expand"] else 1.0
	for g in bc:
		goods[g] = float(bc[g]) * mult
	c["projects"].append({"state_key": plan["state_key"], "type": plan["type"], "expand": plan["expand"],
		"factory_id": int(plan.get("factory_id", 0)), "goods_left": goods, "goods_total": goods.duplicate(),
		"progress": 0.0, "investor": investor})
	var st_name: String = gs.states[int(plan["state_key"].split(":")[0])]["name"]
	gs.log_event(tag, "%s: %s %s en %s" % ["Capitalistas" if investor == "capitalists" else "Gobierno",
		"amplían" if plan["expand"] else "construyen", gs.factory_types[plan["type"]]["name"], st_name])


## Construcción ordenada por el jugador (paga el Estado). Devuelve "" o el motivo del rechazo.
static func government_build(gs: VGameState, tag: String, state_key: String, ftype: String, factory_id: int = 0) -> String:
	var c: Dictionary = gs.countries[tag]
	var policy := economic_policy(gs, tag)
	if not (policy in gs.economy_rules.get("government_build_policies", [])):
		return "La política económica del partido gobernante (laissez-faire) no permite al Estado construir."
	if not can_build_type(gs, tag, ftype):
		return "Falta la tecnología necesaria."
	var expand := factory_id > 0
	var si: Dictionary = gs.state_instances.get(state_key, {})
	if not expand and not si.is_empty() and si["factories"].size() >= VInvestmentSystem.state_slots(gs, si):
		return "El estado no tiene plazas de fábrica libres (%d/%d)." % [si["factories"].size(), VInvestmentSystem.state_slots(gs, si)]
	if VInvestmentSystem.pending_keys(c).has("%s|%s" % [state_key, ftype]):
		return "Ya hay un proyecto de ese tipo en este estado."
	var cost := build_cost(gs, tag, ftype, expand)
	if float(c["treasury"]) - float(c["acc"]["construction"]) < cost:
		return "Tesoro insuficiente (%.0f necesarios)." % cost
	VBudgetSystem.add_expense(gs, tag, "construction", cost)
	start_project(gs, tag, {"state_key": state_key, "type": ftype, "expand": expand, "factory_id": factory_id, "cost": cost}, "government")
	return ""


static func set_subsidy(gs: VGameState, tag: String, factory: Dictionary, on: bool) -> String:
	var policy := economic_policy(gs, tag)
	if on and not (policy in gs.economy_rules.get("subsidy_policies", [])):
		return "La política económica actual no permite subvenciones."
	factory["subsidized"] = on
	return ""


static func _progress_projects(gs: VGameState, tag: String) -> void:
	var c: Dictionary = gs.countries[tag]
	var months := float(gs.economy_rules.get("construction_months", 6))
	var done := []
	for pr in c["projects"]:
		var left: Dictionary = pr["goods_left"]
		var total: Dictionary = pr["goods_total"]
		var tot := 0.0
		var rem := 0.0
		for g in left:
			var q := minf(float(left[g]), float(total[g]) / months)
			VMarketSystem.add_demand(gs, tag, g, q)
			left[g] = float(left[g]) - q * VMarketSystem.fill_buy(gs, tag, g)
			tot += float(total[g])
			rem += maxf(0.0, float(left[g]))
		var newp := 1.0 - rem / maxf(0.001, tot)
		# estancado: los bienes de construcción no llegan (escasez); a los 24 meses se abandona
		pr["stalled_months"] = int(pr.get("stalled_months", 0)) + 1 if newp - float(pr["progress"]) < 0.005 else 0
		pr["progress"] = newp
		if rem <= 0.01 * tot:
			done.append(pr)
		elif int(pr["stalled_months"]) >= 24:
			done.append(pr)
			pr["abandoned"] = true
	for pr in done:
		c["projects"].erase(pr)
		if pr.get("abandoned", false):
			note_stat(gs, c, "projects_abandoned")
			continue
		if pr.get("kind", "factory") == "rgo":
			VInvestmentSystem.complete_rgo_project(gs, tag, pr)
			note_stat(gs, c, "rgo_completed")
			continue
		_complete_project(gs, tag, pr)
		note_stat(gs, c, "expansions" if pr["expand"] else "new_factories")


static func _complete_project(gs: VGameState, tag: String, pr: Dictionary) -> void:
	var si: Dictionary = gs.state_instances.get(pr["state_key"], {})
	if si.is_empty() or si["owner"] != tag:
		return
	VEventSystem.notify(gs, "factory_built", {"tag": tag, "factory_type": pr.get("type", "")})
	if pr["expand"]:
		for f in si["factories"]:
			if int(f["id"]) == int(pr["factory_id"]):
				f["level"] = int(f["level"]) + 1
				f["age"] = 0
				f["profit_hist"] = []
				gs.log_event(tag, "Ampliada %s (nivel %d)" % [gs.factory_types[f["type"]]["name"], f["level"]])
				return
	var fid := int(gs.market.get("next_factory_id", 1))
	gs.market["next_factory_id"] = fid + 1
	var f2 := {"type": pr["type"], "level": 1}
	_normalize_factory(f2, fid)
	f2["hiring"] = 0.5
	f2["age"] = 0
	si["factories"].append(f2)
	gs.log_event(tag, "Abre %s en %s" % [gs.factory_types[pr["type"]]["name"], gs.states[si["state"]]["name"]])


static func _update_artisan_profit(gs: VGameState, tag: String) -> void:
	var c: Dictionary = gs.countries[tag]
	var profits := {}
	var best := ""
	var best_v := -INF
	for t in gs.market["artisan_rate"]:
		var ft: Dictionary = gs.factory_types[t]
		var v := 0.0
		for g in ft["outputs"]:
			v += float(ft["outputs"][g]) * VMarketSystem.price(gs, g) * VMarketSystem.fill_sell(gs, tag, g)
		for g in ft["inputs"]:
			v -= float(ft["inputs"][g]) * VMarketSystem.buy_price(gs, tag, g)
		# la falta de insumos reduce lo que realmente se puede producir y vender
		var fill := 1.0
		for g in ft["inputs"]:
			fill = minf(fill, VMarketSystem.fill_buy(gs, tag, g))
		v *= float(gs.market["artisan_rate"][t]) * fill
		profits[t] = v
		if v > best_v:
			best_v = v
			best = t
	var choices := []
	var total := 0.0
	for t in profits:
		if float(profits[t]) > 0.0:
			var w := float(profits[t]) * float(profits[t])
			choices.append([t, w])
			total += w
	c["artisan_profit"] = profits
	c["artisan_best"] = best
	c["artisan_choices"] = choices
	c["artisan_choice_total"] = total
