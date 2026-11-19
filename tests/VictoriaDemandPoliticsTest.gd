extends Node
## M5.6: demanda por renta (Engel), respuesta de la oferta (utilización del RGO), conciencia frente a revuelta,
## cauce político, empleo estatal funcional y liquidación de compras (lo pagado sin recibir se devuelve).
##   godot --headless --path . res://tests/VictoriaDemandPoliticsTest.tscn

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
	sim.run_days(62)
	test_engel()
	test_supply_response()
	test_revolt_risk()
	test_outlet()
	test_state_jobs()
	test_settlement(sim)
	print("== %d fallos ==" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func test_engel() -> void:
	print("-- demanda por renta (Engel)")
	var e: Dictionary = gs.economy_rules["engel"]
	var k := float(e["k"])
	var mult := func(ratio: float, tier: String) -> float:
		return 1.0 + float(e[tier]) * (1.0 - exp(-k * maxf(0.0, ratio - 1.0)))
	check(mult.call(3.0, "luxury") > mult.call(1.0, "luxury"), "un POP rico consume más lujo que uno justo (%.2f vs %.2f)" % [mult.call(3.0, "luxury"), mult.call(1.0, "luxury")])
	check(mult.call(3.0, "life") - 1.0 < mult.call(3.0, "everyday") - 1.0 and mult.call(3.0, "everyday") - 1.0 < mult.call(3.0, "luxury") - 1.0,
		"vida crece poco (%.2f) · diario más (%.2f) · lujo más (%.2f)" % [mult.call(3.0, "life"), mult.call(3.0, "everyday"), mult.call(3.0, "luxury")])
	check(mult.call(40.0, "luxury") - mult.call(20.0, "luxury") < 0.01, "saturación: el doble de renta casi no añade consumo (%.3f → %.3f)" % [mult.call(20.0, "luxury"), mult.call(40.0, "luxury")])
	# integración: dos POPs iguales salvo la renta, en la misma provincia
	var tag := "FRK"
	var prov := int(gs.countries[tag]["capital"])
	var p: Dictionary = gs.provinces[prov]
	var a := VPopulationSystem.make_pop(gs, "clerks", 20000, p["culture"], p["religion"], prov, 0.5)
	var b := VPopulationSystem.make_pop(gs, "clerks", 20000, p["culture"], p["religion"], prov, 0.5)
	var ps := gs.pops
	VPopulationSystem.recalc_province(gs, prov)
	for s in [a, b]:
		ps.cash[s] = 5000.0
		ps.bank[s] = 0.0
	ps.income_acc[a] = 5.0     # renta pobre (por debajo del coste de la cesta)
	ps.income_acc[b] = 4000.0  # renta alta
	VPopulationSystem.process_province(gs, prov)
	var spent_a := 5000.0 - ps.cash[a] - ps.bank[a]
	var spent_b := 5000.0 - ps.cash[b] - ps.bank[b]
	check(spent_b > spent_a, "con el mismo efectivo, el POP de renta alta gasta más (%.1f vs %.1f)" % [spent_b, spent_a])


func test_supply_response() -> void:
	print("-- respuesta de la oferta (utilización del RGO)")
	var p: Dictionary = {}
	for id in gs.countries["FRK"]["provinces"]:
		if not gs.provinces[id].get("rgo_data", {}).is_empty():
			p = gs.provinces[id]
			break
	var good: String = p["rgo_data"]["good"]
	p["rgo_util"] = 1.0
	# exceso de oferta persistente y precio muy bajo
	for i in 12:
		gs.market["_good_signal"] = {"_month": gs.month_index, good: [0.3, 2.0]}
		VProductionSystem._rgo_utilisation(gs, p, good)
	var u_low := float(p["rgo_util"])
	check(u_low < 1.0 and u_low > 0.5, "con exceso de oferta la utilización baja despacio (%.2f en 12 meses)" % u_low)
	var max0 := int(p["rgo_data"].get("max_workers", 0))
	gs.market["_good_signal"] = {"_month": gs.month_index, good: [0.3, 2.0]}
	VProductionSystem.process_province(gs, int(p["id"]))
	check(int(p["rgo_data"]["max_workers"]) <= max0, "menos plazas: contratan menos trabajadores (%d → %d)" % [max0, int(p["rgo_data"]["max_workers"])])
	# escasez: no debe caer aunque el precio sea bajo
	var u0 := float(p["rgo_util"])
	for i in 6:
		gs.market["_good_signal"] = {"_month": gs.month_index, good: [0.4, 0.9]}
		VProductionSystem._rgo_utilisation(gs, p, good)
	check(float(p["rgo_util"]) >= u0, "si la demanda supera a la oferta, la utilización no cae (%.2f → %.2f)" % [u0, float(p["rgo_util"])])
	for i in 60:
		gs.market["_good_signal"] = {"_month": gs.month_index, good: [1.0, 0.95]}
		VProductionSystem._rgo_utilisation(gs, p, good)
	check(is_equal_approx(float(p["rgo_util"]), 1.0), "con demanda se recupera hasta el 100 %")
	for i in 200:
		gs.market["_good_signal"] = {"_month": gs.month_index, good: [0.1, 5.0]}
		VProductionSystem._rgo_utilisation(gs, p, good)
	check(float(p["rgo_util"]) >= float(gs.economy_rules["rgo_utilisation"]["min"]), "la tierra no desaparece (mínimo %.2f)" % float(p["rgo_util"]))
	p["rgo_util"] = 1.0
	gs.market.erase("_good_signal")


## Prepara un movimiento por el sufragio en una nación: todos los POPs con conciencia alta lo apoyan.
func _setup_movement(tag: String, militancy: float) -> Dictionary:
	var c: Dictionary = gs.countries[tag]
	c["reforms"]["voting"] = 0
	var ps := gs.pops
	for id in c["provinces"]:
		for s in gs.provinces[id]["pop_slots"]:
			ps.consciousness[s] = 7.0
			ps.militancy[s] = militancy
			var iss: Dictionary = ps.issues[s].duplicate()  # los diccionarios de issues pueden ser compartidos (caché)
			iss["suffrage"] = "universal_voting"
			ps.issues[s] = iss
	return c


func test_revolt_risk() -> void:
	print("-- conciencia alta no es revuelta")
	var c := _setup_movement("BAY", 0.5)
	c["movements"] = {"voting": {"name": "sufragio", "support": 0.5, "organisation": 0.9, "radicalism": 0.95, "months": 24}}
	VPoliticsSystem._update_movements(gs, "BAY")
	var mv: Dictionary = c["movements"]["voting"]
	check(float(mv["support"]) > 0.3, "conciencia 7 → mucho apoyo al movimiento (%.0f%%)" % (float(mv["support"]) * 100.0))
	check(int(mv["level"]) >= 1, "presión política sí (nivel %d)" % int(mv["level"]))
	check(not mv["rebel_risk"], "con militancia 0,5 no hay riesgo de revuelta (partidarios militantes %.0f%%)" % (float(mv["militant_share"]) * 100.0))
	print("-- radicalismo + organización + militantes = riesgo")
	var c2 := _setup_movement("BAY", 6.0)
	c2["movements"]["voting"]["radicalism"] = 0.95
	c2["movements"]["voting"]["organisation"] = 0.9
	VPoliticsSystem._update_movements(gs, "BAY")
	var mv2: Dictionary = c2["movements"]["voting"]
	check(mv2["rebel_risk"] and int(mv2["level"]) == 3, "riesgo de revuelta con partidarios militantes (%.0f%%, militancia media %.1f)" % [float(mv2["militant_share"]) * 100.0, float(mv2["avg_militancy"])])
	var ps := gs.pops
	for id in c2["provinces"]:
		for s in gs.provinces[id]["pop_slots"]:
			ps.militancy[s] = 0.5
	c2["movements"] = {}


func test_outlet() -> void:
	print("-- cauce político frente a represión")
	var free_rad := _radicalisation("BAV_free", 1)
	var rep_rad := _radicalisation("BAV_rep", 0)
	check(rep_rad > free_rad, "con la misma demanda, la represión radicaliza más deprisa (%.3f vs %.3f por mes)" % [rep_rad, free_rad])


func _radicalisation(_label: String, freedom: int) -> float:
	var tag := "BAY"
	var c := _setup_movement(tag, 1.0)
	for rid in ["press", "public_meetings", "political_parties"]:
		c["reforms"][rid] = gs.reforms[rid]["levels"].size() - 1 if freedom == 1 else 0
	c["movements"] = {"voting": {"name": "sufragio", "support": 0.5, "organisation": 0.8, "radicalism": 0.3, "months": 24}}
	VPoliticsSystem._update_movements(gs, tag)
	var r := float(c["movements"]["voting"]["radicalism"]) - 0.3
	c["movements"] = {}
	return r


func test_state_jobs() -> void:
	print("-- empleo estatal funcional")
	var tag := "FRK"
	var c: Dictionary = gs.countries[tag]
	var p: Dictionary = gs.provinces[int(c["capital"])]
	var lit0 := float(c["literacy"])
	c["literacy"] = 0.1
	var v_low := VMobilitySystem._vacancies(gs, p, tag, c)
	c["literacy"] = 0.95
	var v_high := VMobilitySystem._vacancies(gs, p, tag, c)
	c["literacy"] = lit0
	check(int(v_high["clergy"]) <= int(v_low["clergy"]), "con alfabetización alta se necesita menos clero (%d ≤ %d)" % [int(v_high["clergy"]), int(v_low["clergy"])])
	var b0: int = c["military"]["brigades"]
	c["military"]["brigades"] = 0
	var v0 := VMobilitySystem._vacancies(gs, p, tag, c)
	c["military"]["brigades"] = 200
	var v1 := VMobilitySystem._vacancies(gs, p, tag, c)
	c["military"]["brigades"] = b0
	check(int(v1["military"]) > int(v0["military"]), "los soldados dependen del ejército real (%d con 0 brigadas, %d con 200)" % [int(v0["military"]), int(v1["military"])])
	var adm0 := float(c["budget"]["administration"])
	c["budget"]["administration"] = 0.0
	var a0 := VMobilitySystem._vacancies(gs, p, tag, c)
	c["budget"]["administration"] = 1.0
	var a1 := VMobilitySystem._vacancies(gs, p, tag, c)
	c["budget"]["administration"] = adm0
	check(int(a1["admin"]) >= int(a0["admin"]), "la administración depende del presupuesto (%d → %d)" % [int(a0["admin"]), int(a1["admin"])])
	check(v0.has("military_excess") and v0.has("clergy_excess"), "existe salida gradual del empleo estatal sobrante")


func test_settlement(sim: VWorldSimulation) -> void:
	print("-- liquidación de compras")
	VMoney.audit(gs)
	# los compradores creen que recibirán todo (estimación 1,0): lo que no llegue se les devuelve
	var fb: Dictionary = gs.market.get("fill_buy", {})
	for t in fb:
		for g in fb[t]:
			fb[t][g] = 1.0
	VMarketSystem.clear_month(gs)
	var refund := float(gs.market["money_ledger"]["created"].get("market_refund", 0.0))
	check(refund > 0.0, "lo pagado por bienes que no llegaron vuelve a los POPs (%.0f)" % refund)
	var au := VMoney.audit(gs)
	check(float(au.get("residual_ratio", 1.0)) < 0.01, "la masa monetaria cuadra (residuo %.4f)" % float(au.get("residual_ratio", 1.0)))
	gs.flags["money_audit"] = true
	sim.run_days(62)
	var au2: Dictionary = gs.market.get("money_audit", {})
	check(not au2.has("residual_ratio") or float(au2["residual_ratio"]) < 0.01, "y en la simulación normal también (%s)" % str(au2.get("residual_ratio", "-")))
