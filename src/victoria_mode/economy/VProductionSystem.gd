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
		for pop in p["pops"]:
			if pop["type"] == wt or pop["type"] == "slaves":
				workers += int(pop["size"])
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
		for pop in p["pops"]:
			var units := float(pop["size"]) / UNIT
			var weights: Array = rules.get("calibration_tier_weights", [1.0, 0.5, 0.1])
			for i in 3:
				var basket := VPopulationSystem.needs_basket(gs, pop["type"], VPopulationSystem.TIERS[i])
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
		for pop in gs.provinces[id]["pops"]:
			if pop["type"] == "artisans":
				art_units += float(pop["size"]) / UNIT
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
		for pop in gs.provinces[id]["pops"]:
			if pop["type"] == "artisans":
				pop["product"] = options[(int(pop["id"]) * 7 + id) % options.size()]


# ------------------------------------------------- proceso mensual (provincia)
static func process_province(gs: VGameState, id: int) -> void:
	var p: Dictionary = gs.provinces[id]
	var tag: String = p["owner"]
	if tag == "":
		return
	var c: Dictionary = gs.countries[tag]
	var pops: Array = p["pops"]
	var ptc := VPopulationSystem._type_cache(gs)
	var mk := _market_ctx(gs, tag, c)
	# ---------------- RGO: recuento de trabajadores y propietarios
	var rd: Dictionary = p["rgo_data"]
	var good: String = rd["good"]
	var wt := rgo_worker_type(gs, good)
	var workers := 0
	var aristos := []
	var aristo_size := 0
	for pop in pops:
		var t0: String = pop["type"]
		if t0 == wt or t0 == "slaves":
			workers += int(pop["size"])
		elif t0 == "aristocrats":
			aristos.append(pop)
			aristo_size += int(pop["size"])
	var size := float(rd["base_size"]) * (1.0 + gs.mod(tag, "rgo_size"))
	var max_workers := int(size * UNIT)
	var employed: int = mini(workers, max_workers)
	var ratio := float(employed) / float(workers) if workers > 0 else 0.0
	var eff := float(gs.terrain_types.get(p["terrain"], {}).get("rgo_efficiency", 1.0)) * (1.0 + gs.mod(tag, "rgo_efficiency")) * (1.0 + 0.05 * int(p["infrastructure"]))
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
	# ---------------- empleo estatal y prestaciones: factores por provincia
	var social := float(c["budget"].get("social", 0.0)) * float(c.get("pay_ratio", 1.0))
	var benefit_rate := gs.mod(tag, "unemployment_benefit") * social
	var pension_rate := gs.mod(tag, "pension") * social
	var health_cost := gs.mod(tag, "social_cost") * social
	var transfers := benefit_rate > 0.0 or pension_rate > 0.0
	var needs: Dictionary = c.get("_needs", {})
	var pay_f := {}
	for job in VBudgetSystem.EXPENSE_FOR_JOB:
		pay_f[job] = VBudgetSystem.gov_pay_factor(c, job)
	var exp_acc := {}
	var social_spent := 0.0
	var prov_units := 0.0
	# impuestos en línea (igual que VBudgetSystem.credit_income): tipo por estrato y acumulado local
	var tax_eff := float(c.get("tax_efficiency", 0.8))
	var budget: Dictionary = c["budget"]
	var tax_rate := {"poor": float(budget.get("tax_poor", 0.0)) * tax_eff, "middle": float(budget.get("tax_middle", 0.0)) * tax_eff,
		"rich": float(budget.get("tax_rich", 0.0)) * tax_eff}
	var tax_acc := {"poor": 0.0, "middle": 0.0, "rich": 0.0}
	# ---------------- una pasada por POP: RGO → artesano → empleo estatal → prestaciones
	# (mismo orden por POP que las tres pasadas originales: el resultado no cambia)
	for pop in pops:
		var t: String = pop["type"]
		var tc: Array = ptc.get(t, ptc["_default"])
		var units := float(pop["size"]) / UNIT
		prov_units += units
		if t == wt or t == "slaves":
			pop["employment"] = ratio
			pop["employer"] = "rgo"
			if employed > 0:
				var share := worker_pool * float(pop["size"]) * ratio / float(employed)
				if t == "slaves" and aristo_size > 0:
					VBudgetSystem.transfer(pop, share * 0.3)
					owner_pool += share * 0.7
					paid_out += share * 0.3
				elif share > 0.0:
					var net := share
					if not occupied:
						var tx := share * float(tax_rate[tc[1]])
						tax_acc[tc[1]] = float(tax_acc[tc[1]]) + tx
						net = share - tx
					pop["cash"] = float(pop["cash"]) + net
					pop["income_acc"] = float(pop.get("income_acc", 0.0)) + net
					paid_out += share
		elif t == "farmers" or t == "labourers":
			pop["employment"] = 0.0
			pop["employer"] = ""
		elif t == "artisans":
			_artisan(gs, pop, tag, c, mk)
		var job: String = tc[4]
		if pay_f.has(job):
			var pay := float(tc[5]) * units * float(pay_f[job])
			pop["employment"] = 1.0 if pay > 0.0 else 0.0
			pop["employer"] = "estado"
			if pay > 0.0:
				var tx2 := pay * float(tax_rate[tc[1]])
				tax_acc[tc[1]] = float(tax_acc[tc[1]]) + tx2
				pop["cash"] = float(pop["cash"]) + pay - tx2
				pop["income_acc"] = float(pop.get("income_acc", 0.0)) + pay - tx2
				var ek: String = VBudgetSystem.EXPENSE_FOR_JOB[job]
				exp_acc[ek] = float(exp_acc.get(ek, 0.0)) + pay
		elif job == "investor":
			pop["employment"] = 1.0
			pop["employer"] = "inversión"
		if transfers and tc[1] == "poor":
			var life_cost := float(needs.get(t, {}).get("cost", [0.0])[0]) * units
			var amount := life_cost * (benefit_rate * (1.0 - float(pop["employment"])) + pension_rate)
			if amount > 0.0:
				VBudgetSystem.transfer(pop, amount)
				social_spent += amount
	for ar in aristos:
		ar["employment"] = 1.0
		ar["employer"] = "rgo_owner"
		var ashare := owner_pool * float(ar["size"]) / float(aristo_size)
		VBudgetSystem.credit_income(gs, tax_tag, ar, ashare)
		paid_out += ashare
	VMoney.created(gs, paid_out, "rgo_sales")
	var acc: Dictionary = c["acc"]
	for st in tax_acc:
		acc["tax_" + st] = float(acc["tax_" + st]) + float(tax_acc[st])
	for ek in exp_acc:
		VBudgetSystem.add_expense(gs, tag, ek, float(exp_acc[ek]))
	social_spent += health_cost * prov_units * 0.6
	VBudgetSystem.add_expense(gs, tag, "social", social_spent)


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


static var _artisan_employer := {}


## Un POP de artesanos: elige producto, compra insumos con capital circulante, produce y vende.
static func _artisan(gs: VGameState, pop: Dictionary, tag: String, c: Dictionary, mk: Dictionary) -> void:
	var rates: Dictionary = mk["rates"]
	var best: String = c.get("artisan_best", "")
	var profits: Dictionary = c.get("artisan_profit", {})
	var choices: Array = c.get("artisan_choices", [])
	var product: String = pop.get("product", "")
	if best != "" and product != best and not choices.is_empty():
		var cur := float(profits.get(product, -1.0))
		if cur < float(profits.get(best, 0.0)) * 0.7 and (int(pop["id"]) + gs.month_index) % int(1.0 / float(mk["switch"])) == 0:
			# reparto ponderado por beneficio entre los productos rentables (evita que todos elijan el mismo)
			var roll := float(absi(("%d|%d" % [int(pop["id"]), gs.month_index]).hash()) % 10000) / 10000.0 * float(c.get("artisan_choice_total", 1.0))
			for ch in choices:
				roll -= float(ch[1])
				if roll <= 0.0:
					product = ch[0]
					break
			pop["product"] = product
	if not rates.has(product):
		product = rates.keys()[0]
		pop["product"] = product
	var ft: Dictionary = gs.factory_types[product]
	var inputs: Dictionary = ft["inputs"]
	var outputs: Dictionary = ft["outputs"]
	var fb: Dictionary = mk["fb"]
	var recipes := float(pop["size"]) / UNIT * float(rates[product]) * float(mk["eff_mod"])
	var in_cost := 0.0
	for g in inputs:
		in_cost += float(inputs[g]) * _buy_price(mk, g)
	# capital circulante: los insumos se pagan con lo que se vende este mes más el efectivo
	var expected := 0.0
	for g in outputs:
		expected += float(outputs[g]) * recipes * _price(mk, g) * _fill_sell(mk, g)
	var cash := float(pop["cash"])
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
	VMoney.created(gs, revenue, "artisan_sales")
	VMoney.destroyed(gs, paid, "artisan_inputs")
	if revenue >= paid:
		VBudgetSystem.credit_income(gs, tag, pop, revenue - paid)
	else:
		var loss := paid - revenue
		if loss > cash:
			VMoney.created(gs, loss - cash, "artisan_loss_forgiven")
		pop["cash"] = maxf(0.0, cash - loss)
	pop["employment"] = clampf(scale * fill, 0.0, 1.0) if revenue > paid else clampf(scale * fill * 0.5, 0.0, 1.0)
	var emp: String = _artisan_employer.get(product, "")
	if emp == "":
		emp = "artisan:" + product
		_artisan_employer[product] = emp
	pop["employer"] = emp


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
	var cr_total := 0
	var cl_total := 0
	var infra := 0.0
	var inst_pop := 0
	for id in si["provinces"]:
		infra += float(gs.provinces[id]["infrastructure"])
		inst_pop += int(gs.provinces[id]["population"])
		for pop in gs.provinces[id]["pops"]:
			match pop["type"]:
				"craftsmen":
					craftsmen.append(pop)
					cr_total += int(pop["size"])
				"clerks":
					clerks.append(pop)
					cl_total += int(pop["size"])
				"capitalists":
					capitalists.append(pop)
	infra /= maxf(1.0, float(si["provinces"].size()))
	si["_pop"] = inst_pop
	# plazas
	var cr_slots := 0.0
	var cl_slots := 0.0
	for f in si["factories"]:
		if not f["open"]:
			continue
		var wf: Dictionary = gs.factory_types.get(f["type"], {}).get("workforce", {})
		cr_slots += float(wf.get("craftsmen", 9000)) * int(f["level"]) * float(f["hiring"])
		cl_slots += float(wf.get("clerks", 1000)) * int(f["level"]) * float(f["hiring"])
	var cr_fill := minf(1.0, float(cr_total) / cr_slots) if cr_slots > 0.0 else 0.0
	var cl_fill := minf(1.0, float(cl_total) / cl_slots) if cl_slots > 0.0 else 0.0
	si["vacancy_craftsmen"] = int(maxf(0.0, cr_slots - float(cr_total)))
	si["vacancy_clerks"] = int(maxf(0.0, cl_slots - float(cl_total)))
	var needs: Dictionary = c.get("_needs", {})
	var wage_mult := float(rules.get("factory_wage_multiplier", 1.6)) * (1.0 + gs.mod(tag, "factory_wage"))
	var cr_cost: Array = needs.get("craftsmen", {}).get("cost", [5.0, 5.0, 5.0])
	var cl_cost: Array = needs.get("clerks", {}).get("cost", [15.0, 15.0, 15.0])
	var cr_wage := (float(cr_cost[0]) + float(cr_cost[1])) * wage_mult
	var cl_wage := (float(cl_cost[0]) + float(cl_cost[1])) * wage_mult
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
				continue
		else:
			f["unstaffed_months"] = 0
		var clerk_ratio := emp_cl / max_cl if max_cl > 0.0 else 0.0
		var recipes := float(rates.get(f["type"], 0.0)) * int(f["level"]) * staffing * (0.75 + 0.5 * clerk_ratio) * eff_base
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
		wages_cr += w_cr
		wages_cl += w_cl
		var expenses := input_cost + w_cr + w_cl
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
	# salarios a los POPs (proporcional a su tamaño y al empleo de la partición)
	var cr_emp_frac := minf(1.0, cr_slots / float(cr_total)) if cr_total > 0 else 0.0
	var cl_emp_frac := minf(1.0, cl_slots / float(cl_total)) if cl_total > 0 else 0.0
	for pop in craftsmen:
		pop["employment"] = cr_emp_frac
		pop["employer"] = "fábrica" if cr_emp_frac > 0.0 else ""
		if cr_total > 0:
			VBudgetSystem.credit_income(gs, tag, pop, wages_cr * float(pop["size"]) / float(cr_total))
	for pop in clerks:
		pop["employment"] = cl_emp_frac
		pop["employer"] = "fábrica" if cl_emp_frac > 0.0 else ""
		if cl_total > 0:
			VBudgetSystem.credit_income(gs, tag, pop, wages_cl * float(pop["size"]) / float(cl_total))
	# beneficio a capitalistas del estado (si no hay, a los del país)
	if profit_total > 0.0:
		if capitalists.is_empty():
			capitalists = c.get("_capitalists", [])
		var cap_size := 0
		for pop in capitalists:
			cap_size += int(pop["size"])
		if cap_size > 0:
			for pop in capitalists:
				VBudgetSystem.credit_income(gs, tag, pop, profit_total * float(pop["size"]) / float(cap_size))
		else:
			c["treasury"] = float(c["treasury"]) + profit_total * 0.5
			VMoney.destroyed(gs, profit_total * 0.5, "profit_without_owner")


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
	var rules: Dictionary = gs.economy_rules
	var policy := economic_policy(gs, tag)
	c["invest_cooldown"] = maxi(0, int(c.get("invest_cooldown", 0)) - 1)
	var max_projects := 1 + int(float(c.get("_factory_count", 0)) / float(rules.get("factories_per_parallel_project", 40)))
	# inversión privada: solo capitalistas (los aristócratas viven de la renta del RGO y ahorran)
	if policy in rules.get("investment_policies", []) and c.get("civilized", true) and int(c["invest_cooldown"]) == 0 and c["projects"].size() < max_projects:
		var capitalists: Array = c.get("_capitalists", [])
		var pool := 0.0
		for pop in capitalists:
			pool += float(pop["cash"]) + float(pop.get("bank", 0.0))
		var plan := best_investment(gs, tag)
		if not plan.is_empty() and pool >= float(plan["cost"]) * float(rules.get("investment_capital_ratio", 2.5)):
			var cost := float(plan["cost"])
			for pop in capitalists:
				var w := (float(pop["cash"]) + float(pop.get("bank", 0.0))) / pool
				var take := cost * w
				var from_cash: float = minf(float(pop["cash"]), take)
				pop["cash"] = float(pop["cash"]) - from_cash
				var from_bank := take - from_cash
				pop["bank"] = maxf(0.0, float(pop.get("bank", 0.0)) - from_bank)
				c["bank"]["deposits"] = maxf(0.0, float(c["bank"]["deposits"]) - from_bank)
			VMoney.destroyed(gs, cost, "investment")
			start_project(gs, tag, plan, "capitalists")
			c["invest_cooldown"] = int(rules.get("investment_cooldown_months", 3))
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
	# IA de gobierno: construir si la política lo permite y sobra mucho dinero
	if not is_player and policy in rules.get("government_build_policies", []) and int(c["invest_cooldown"]) == 0 and c["projects"].size() < max_projects:
		var monthly_exp := maxf(50.0, float(c.get("monthly_expense", 0.0)))
		if float(c["treasury"]) > monthly_exp * 12.0:
			var plan2 := best_investment(gs, tag)
			if not plan2.is_empty() and float(c["treasury"]) - float(plan2["cost"]) > monthly_exp * 6.0:
				VBudgetSystem.add_expense(gs, tag, "construction", float(plan2["cost"]))
				start_project(gs, tag, plan2, "government")
				c["invest_cooldown"] = int(rules.get("investment_cooldown_months", 3)) * 2


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
	return req == "" or req in gs.countries[tag].get("technologies", [])


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
static func best_investment(gs: VGameState, tag: String) -> Dictionary:
	var c: Dictionary = gs.countries[tag]
	var instances := gs.country_state_instances(tag)
	var max_level := int(gs.economy_rules.get("factory_max_level", 10))
	var pending := {}
	for pr in c.get("projects", []):
		pending[pr["type"]] = true
	var best := {}
	var best_score := 0.0
	for si in instances:
		if int(si.get("vacancy_craftsmen", 0)) > 1000:
			continue
		for f in si["factories"]:
			if not f["open"] or int(f.get("age", 0)) < 12 or int(f["level"]) >= max_level or pending.has(f["type"]):
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
			if avg <= 0.0 or worst < -0.25 * absf(avg) or not output_in_demand(gs, f["type"]):
				continue
			var score := avg / int(f["level"])
			if score > best_score:
				best_score = score
				best = {"state_key": si["key"], "type": f["type"], "expand": true, "factory_id": f["id"], "cost": build_cost(gs, tag, f["type"], true)}
	var type_best := ""
	var type_score := 0.0
	for t in gs.factory_types:
		if pending.has(t) or not can_build_type(gs, tag, t) or not output_in_demand(gs, t) or not inputs_available(gs, tag, t):
			continue
		var m := expected_margin(gs, tag, t, true)
		if m > type_score:
			type_score = m
			type_best = t
	if type_best != "" and type_score > best_score:
		var target := {}
		var labour := 0.0
		for si in instances.slice(0, 15):
			if si["factories"].size() >= 6 or int(si.get("vacancy_craftsmen", 0)) > 1000:
				continue
			var pool := 0.0
			for id in si["provinces"]:
				for pop in gs.provinces[id]["pops"]:
					match pop["type"]:
						"craftsmen":
							pool += float(pop["size"]) * (1.0 - float(pop["employment"]))
						"farmers", "labourers":
							pool += float(pop["size"]) * 0.02 * minf(1.0, float(pop["literacy"]) * 5.0) * (0.5 + float(1.0 - float(pop["employment"])))
			if pool > labour:
				labour = pool
				target = si
		if not target.is_empty() and labour > 9000.0:
			best = {"state_key": target["key"], "type": type_best, "expand": false, "factory_id": 0, "cost": build_cost(gs, tag, type_best, false)}
	return best


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
		pr["progress"] = 1.0 - rem / maxf(0.001, tot)
		if rem <= 0.01 * tot:
			done.append(pr)
	for pr in done:
		c["projects"].erase(pr)
		_complete_project(gs, tag, pr)


static func _complete_project(gs: VGameState, tag: String, pr: Dictionary) -> void:
	var si: Dictionary = gs.state_instances.get(pr["state_key"], {})
	if si.is_empty() or si["owner"] != tag:
		return
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
