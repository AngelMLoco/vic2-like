extends Node
## Inversión y desarrollo (M5.5): capacidad por tamaño y capital, proyectos paralelos, el mismo tipo de fábrica
## en estados distintos, plazas de fábrica por estado, desarrollo rural, crecimiento gradual y dinero conservado.
##   godot --headless --path . res://tests/VictoriaInvestmentTest.tscn

var failures := 0
var gs: VGameState


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	await get_tree().process_frame
	gs = VDataLoader.new_game()
	gs.player_tag = ""
	var sim := VWorldSimulation.new(gs)
	sim.run_days(62)  # cachés de POPs, mercado e historial de precios
	test_capacity()
	test_parallel_and_same_type()
	test_state_slots()
	test_rgo_development()
	test_gradual_growth(sim)
	print("== %d fallos ==" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _allow(tag: String, policy: String) -> void:
	var rp := VPoliticsSystem.ruling_party(gs, tag)
	rp["policies"]["economic_policy"] = policy


func _rich(tag: String, amount: float) -> void:
	var caps: Array = gs.countries[tag].get("_capitalists", [])
	for s in caps:
		gs.pops.cash[s] += amount / maxf(1.0, float(caps.size()))


func test_capacity() -> void:
	print("-- capacidad de inversión")
	var big := "BRI"
	var small := "HIB"
	for t in [big, small]:
		gs.countries[t]["_factory_levels"] = VInvestmentSystem.factory_levels(gs, t)
		gs.countries[t]["_capital_pool"] = VInvestmentSystem.capitalist_pool(gs, gs.countries[t])
	var cb := VInvestmentSystem.capacity(gs, big)
	var cs := VInvestmentSystem.capacity(gs, small)
	check(int(cb["private"]) >= int(cs["private"]), "una potencia industrial tiene más capacidad privada (%d) que una nación pequeña (%d)" % [cb["private"], cs["private"]])
	gs.countries[big]["_capital_pool"] = 1e6
	gs.countries[big]["_factory_levels"] = 200
	var cr := VInvestmentSystem.capacity(gs, big)
	check(int(cr["private"]) >= 3 and int(cr["private"]) <= 10, "con capital e industria: varios proyectos privados (%d, con techo)" % cr["private"])
	check(int(cr["government"]) >= 1 and int(cr["rgo"]) >= 1, "capacidades estatal (%d) y rural (%d) separadas" % [cr["government"], cr["rgo"]])


func test_parallel_and_same_type() -> void:
	print("-- proyectos paralelos y mismo tipo en estados distintos")
	var tag := "FRK"
	var c: Dictionary = gs.countries[tag]
	_allow(tag, "interventionism")
	c["projects"] = []
	var insts := gs.country_state_instances(tag)
	check(insts.size() >= 3, "Frankia tiene varias particiones de estado (%d)" % insts.size())
	var ft := "lumber_mill"
	# fábrica de tipo X en el estado A y proyecto del mismo tipo en el estado B
	var a: Dictionary = insts[0]
	var b: Dictionary = insts[1]
	var e1 := VProductionSystem.government_build(gs, tag, b["key"], ft)
	c["treasury"] = 1e6
	var e2 := VProductionSystem.government_build(gs, tag, b["key"], ft)
	var e3 := VProductionSystem.government_build(gs, tag, insts[2]["key"], ft)
	check(e2 == "" or e1 == "", "proyecto de %s en el estado B (%s)" % [ft, e2 if e2 != "" else e1])
	check(e3 == "", "otro proyecto del mismo tipo en el estado C a la vez (%s)" % e3)
	var e4 := VProductionSystem.government_build(gs, tag, insts[2]["key"], ft)
	check(e4 != "", "pero no dos del mismo tipo en el mismo estado («%s»)" % e4)
	var n_same := 0
	for pr in c["projects"]:
		if pr["type"] == ft:
			n_same += 1
	check(n_same >= 2, "%d proyectos simultáneos del mismo tipo en estados distintos" % n_same)
	check(a["key"] != b["key"], "estados distintos")
	# la IA privada puede lanzar varios proyectos independientes con capital, obreros y demanda
	c["projects"] = []
	_rich(tag, 2e6)
	var why := {}
	var plans := VInvestmentSystem.factory_plans(gs, tag, {}, why, 6)
	var keys := {}
	for p in plans:
		keys["%s|%s" % [p["state_key"], p["type"]]] = true
	check(plans.size() == keys.size(), "los planes no repiten estado+tipo (%d planes)" % plans.size())
	for p in plans:
		check(float(p["margin"]) > 0.0, "plan %s en %s con margen positivo (%.1f)" % [p["type"], p["state_key"], p["margin"]])
	c["_starts_year"] = 0  # techo anual de inicios sin consumir (las construcciones anteriores de la prueba no cuentan)
	VInvestmentSystem.monthly(gs, tag, false)
	var priv := int(VInvestmentSystem.active_counts(c)["private"])
	check(plans.is_empty() or priv >= 1, "la IA privada inicia proyectos con capital (%d activos; motivo si no: %s)" % [priv, why.get("reason", "")])
	check(priv <= int(c["_inv_capacity"]["starts"]), "pero no más inicios por mes que su capacidad (%d ≤ %d)" % [priv, c["_inv_capacity"]["starts"]])


func test_state_slots() -> void:
	print("-- plazas de fábrica por estado (regla explícita)")
	var si: Dictionary = gs.country_state_instances("BRI")[0]
	var base := VInvestmentSystem.state_slots(gs, si)
	check(base >= 6, "plazas base de datos (%d)" % base)
	var id: int = si["provinces"][0]
	var old := int(gs.provinces[id]["infrastructure"])
	for pid in si["provinces"]:
		gs.provinces[pid]["infrastructure"] = old + 3
	check(VInvestmentSystem.state_slots(gs, si) > base, "la infraestructura amplía las plazas (%d → %d)" % [base, VInvestmentSystem.state_slots(gs, si)])
	for pid in si["provinces"]:
		gs.provinces[pid]["infrastructure"] = old


func test_rgo_development() -> void:
	print("-- desarrollo rural")
	var tag := "FRK"
	var c: Dictionary = gs.countries[tag]
	c["projects"] = []
	# provincia con RGO rentable y paro rural: añadimos campesinos sin plaza
	var best := -1
	for id in c["provinces"]:
		var rd: Dictionary = gs.provinces[id].get("rgo_data", {})
		if float(rd.get("revenue", 0.0)) > 0.0 and int(rd.get("workers", 0)) > 20000:
			best = int(id)
			break
	check(best > 0, "provincia agrícola de Frankia")
	var p: Dictionary = gs.provinces[best]
	var rd2: Dictionary = p["rgo_data"]
	var wt := VProductionSystem.rgo_worker_type(gs, rd2["good"])
	VPopulationSystem.make_pop(gs, wt, int(float(rd2["max_workers"]) * 0.4), p["culture"], p["religion"], best, 0.2)
	VProductionSystem.process_province(gs, best)
	check(int(p["rgo_free"]) < 0, "paro rural en %s (%d sin plaza)" % [p["name"], -int(p["rgo_free"])])
	# precio sano del bien y renta suficiente
	var hist: Array = gs.market.get("history", {}).get(rd2["good"], [])
	for i in hist.size():
		hist[i] = maxf(float(hist[i]), float(gs.goods[rd2["good"]]["base_price"]))
	var plan := VInvestmentSystem.rgo_plan(gs, tag, {})
	check(not plan.is_empty(), "hay un plan de mejora rural (%s)" % str(plan.get("prov", "-")))
	if plan.is_empty():
		return
	var aris: Array = c.get("_aristocrats", [])
	for s in aris:
		gs.pops.cash[s] += float(plan["cost"]) * 3.0 / maxf(1.0, float(aris.size()))
	check(VInvestmentSystem.pay_from(gs, c, aris, float(plan["cost"]), 2.0), "los aristócratas financian la mejora")
	VInvestmentSystem.start_rgo_project(gs, tag, plan, "aristocrats")
	var pp: Dictionary = gs.provinces[int(plan["prov"])]
	var max0 := int(pp["rgo_data"]["max_workers"])
	var dev0 := int(pp.get("rgo_dev", 0))
	VInvestmentSystem.complete_rgo_project(gs, tag, c["projects"][-1])
	VProductionSystem.process_province(gs, int(plan["prov"]))
	check(int(pp.get("rgo_dev", 0)) == dev0 + 1 and int(pp["rgo_data"]["max_workers"]) > max0, "más plazas rurales tras la mejora (%d → %d)" % [max0, int(pp["rgo_data"]["max_workers"])])
	check(int(pp["rgo_dev"]) <= VInvestmentSystem.max_development(gs, pp), "con límite por provincia (%d/%d)" % [int(pp["rgo_dev"]), VInvestmentSystem.max_development(gs, pp)])
	pp["rgo_dev"] = VInvestmentSystem.max_development(gs, pp)
	var none := VInvestmentSystem.rgo_plan(gs, tag, {})
	check(none.is_empty() or int(none["prov"]) != int(plan["prov"]), "una provincia al máximo de desarrollo ya no se mejora")


func test_gradual_growth(sim: VWorldSimulation) -> void:
	print("-- crecimiento gradual (sin explosión industrial)")
	var tag := "BRI"
	_allow(tag, "laissez_faire")
	_rich(tag, 5e6)
	var f0 := VInvestmentSystem.factory_levels(gs, tag)
	var st0 := float(gs.countries[tag].get("_inv_stats", {}).get("private_started", 0.0))
	gs.flags["money_audit"] = true
	sim.run_days(365)
	var started := float(gs.countries[tag].get("_inv_stats", {}).get("private_started", 0.0)) - st0
	var cap: Dictionary = gs.countries[tag].get("_inv_capacity", {})
	check(started <= float(cap.get("year_cap", 0)) + float(cap.get("starts", 1)), "con capital casi ilimitado, inicios en un año acotados (%d ≤ %d)" % [int(started), int(cap.get("year_cap", 0)) + int(cap.get("starts", 1))])
	var f1 := VInvestmentSystem.factory_levels(gs, tag)
	check(f1 <= f0 * 2 + 10, "la industria no se duplica en un año (%d → %d niveles)" % [f0, f1])
	var au: Dictionary = gs.market.get("money_audit", {})
	check(not au.has("residual_ratio") or float(au["residual_ratio"]) < 0.01, "auditoría monetaria sin residuo (%s)" % str(au.get("residual_ratio", "-")))
