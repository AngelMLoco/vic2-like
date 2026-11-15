extends Node
## Simulación automática sin interfaz para balance y rendimiento:
##   godot --headless --path . res://tests/VictoriaBalanceTest.tscn -- [años]
## Imprime indicadores anuales y comprueba que no haya estados degenerados.

var years := 10


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		years = int(args[0])
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	var gs := VDataLoader.new_game()
	print("carga del mundo: %d ms" % (Time.get_ticks_msec() - t0))
	gs.player_tag = ""
	var sim := VWorldSimulation.new(gs)
	print(header())
	print(row(gs, 0))
	var failures := []
	for y in years:
		var ty := Time.get_ticks_msec()
		sim.run_days(365)
		print(row(gs, y + 1) + "  (%.1f s)" % ((Time.get_ticks_msec() - ty) / 1000.0))
	print(VProfiler.report(gs))
	if OS.get_environment("VBAL_DEBUG") != "":
		debug_dump(gs)
	failures = degenerate_checks(gs)
	print("== balance: %d problemas ==" % failures.size())
	for f in failures:
		print("   - ", f)
	get_tree().quit(1 if not failures.is_empty() else 0)


static func header() -> String:
	return "año | pobl.(M) | vida  diario lujo | paro | milit conc  alfab | fábr.abiertas/cerr | precio min/med/max | tesoro med | deuda | promo/demo/migr/emig | elecc | reformas | techs | inventos"


static func stats(gs: VGameState) -> Dictionary:
	var s := {"pop": 0.0, "life": 0.0, "every": 0.0, "lux": 0.0, "unemp": 0.0, "mil": 0.0, "con": 0.0, "lit": 0.0}
	for id in range(1, gs.first_sea_id):
		var p: Dictionary = gs.provinces[id]
		if p["owner"] == "":
			continue
		for pop in p["pops"]:
			var w := float(pop["size"])
			s["pop"] += w
			s["life"] += float(pop["needs_satisfaction"]["life"]) * w
			s["every"] += float(pop["needs_satisfaction"]["everyday"]) * w
			s["lux"] += float(pop["needs_satisfaction"]["luxury"]) * w
			s["unemp"] += (1.0 - float(pop["employment"])) * w
			s["mil"] += float(pop["militancy"]) * w
			s["con"] += float(pop["consciousness"]) * w
			s["lit"] += float(pop["literacy"]) * w
	for k in ["life", "every", "lux", "unemp", "mil", "con", "lit"]:
		s[k] = float(s[k]) / maxf(1.0, float(s["pop"]))
	var open := 0
	var closed := 0
	for key in gs.state_instances:
		for f in gs.state_instances[key]["factories"]:
			if f["open"]:
				open += 1
			else:
				closed += 1
	s["open"] = open
	s["closed"] = closed
	var ratios := []
	for g in gs.market["price"]:
		if VMarketSystem.is_available(gs, g):
			ratios.append(float(gs.market["price"][g]) / float(gs.market["base"][g]))
	ratios.sort()
	s["pmin"] = ratios[0]
	s["pmed"] = ratios[ratios.size() / 2]
	s["pmax"] = ratios[-1]
	var treasuries := []
	var debtors := 0
	var promo := 0
	var demo := 0
	var migr := 0
	var emig := 0
	var elections := 0
	var reforms := 0
	var techs := 0
	var invs := 0
	for tag in gs.living_countries():
		var c: Dictionary = gs.countries[tag]
		treasuries.append(float(c["treasury"]))
		if float(c.get("debt", 0.0)) > 0.0:
			debtors += 1
		var m: Dictionary = c.get("acc_mobility_last", {})
		promo += int(m.get("promoted", 0))
		demo += int(m.get("demoted", 0))
		migr += int(m.get("migrated", 0))
		emig += int(m.get("emigrated", 0))
		if not c.get("last_election", {}).is_empty():
			elections += 1
		for r in c["reforms"]:
			if int(c["reforms"][r]) != int(gs.reforms[r].get("default", 0)):
				reforms += 1
		techs += c["technologies"].size()
		invs += c["inventions"].size()
	treasuries.sort()
	s["treasury_med"] = treasuries[treasuries.size() / 2] if not treasuries.is_empty() else 0.0
	s["debtors"] = debtors
	s["mob"] = [promo, demo, migr, emig]
	s["elections"] = elections
	s["reforms"] = reforms
	s["techs"] = techs
	s["inventions"] = invs
	return s


static func row(gs: VGameState, y: int) -> String:
	var s := stats(gs)
	return "%3d | %8.1f | %.2f  %.2f  %.2f | %.2f | %.2f %.2f  %.2f | %d/%d | %.2f/%.2f/%.2f | %9.0f | %d | %s | %d | %d | %d | %d" % [
		y, float(s["pop"]) / 1e6, s["life"], s["every"], s["lux"], s["unemp"], s["mil"], s["con"], s["lit"],
		s["open"], s["closed"], s["pmin"], s["pmed"], s["pmax"], s["treasury_med"], s["debtors"],
		"/".join(s["mob"].map(func(x): return str(x))), s["elections"], s["reforms"], s["techs"], s["inventions"]]


## Comprobaciones de estados degenerados (sección 42 del encargo).
static func degenerate_checks(gs: VGameState) -> Array:
	var s := stats(gs)
	var out := []
	if float(s["pop"]) < 1e8:
		out.append("la población se ha desplomado")
	if float(s["life"]) < 0.3:
		out.append("necesidades vitales casi nulas en el mundo")
	if float(s["lux"]) > 0.9:
		out.append("todos los POPs son ricos (lujo > 90 %)")
	if float(s["pmed"]) < 0.3 or float(s["pmed"]) > 3.0:
		out.append("nivel general de precios degenerado (mediana %.2f x base)" % float(s["pmed"]))
	if int(s["open"]) == 0:
		out.append("todas las fábricas han cerrado")
	if float(s["unemp"]) > 0.6:
		out.append("desempleo masivo")
	if float(s["mil"]) > 6.0:
		out.append("militancia mundial extrema")
	var profit_all_positive := true
	for key in gs.state_instances:
		for f in gs.state_instances[key]["factories"]:
			if f["open"] and float(f["profit"]) < 0.0:
				profit_all_positive = false
	if profit_all_positive and int(s["open"]) > 50:
		out.append("todas las fábricas ganan dinero (ninguna pierde)")
	return out


static func debug_dump(gs: VGameState) -> void:
	print("--- bienes: precio/base | oferta mundial | demanda mundial")
	var w: Dictionary = gs.market["world"]
	for g in gs.goods:
		print("%-22s %5.2f | %9.1f | %9.1f" % [g, float(gs.market["price"][g]) / float(gs.market["base"][g]), float(w["supply"].get(g, 0.0)), float(w["demand"].get(g, 0.0))])
	var c: Dictionary = gs.countries["FRK"]
	print("--- FRK necesidades (coste/llenado por 10k):")
	for t in c["_needs"]:
		print("%-12s cost %s fill %s" % [t, str(c["_needs"][t]["cost"]), str(c["_needs"][t]["fill"])])
	var by := {}
	for id in c["provinces"]:
		for pop in gs.provinces[id]["pops"]:
			var e: Array = by.get(pop["type"], [0.0, 0.0, 0.0, 0.0, 0.0])
			var u := float(pop["size"]) / 10000.0
			e[0] += u
			e[1] += float(pop["cash"])
			e[2] += float(pop["income"])
			e[3] += float(pop["needs_satisfaction"]["life"]) * u
			e[4] += float(pop["employment"]) * u
			by[pop["type"]] = e
	print("--- FRK por tipo: unidades | cash/10k | renta/10k | vida | empleo")
	for t in by:
		var e: Array = by[t]
		print("%-12s %7.1f | %7.2f | %7.2f | %.2f | %.2f" % [t, e[0], e[1] / e[0], e[2] / e[0], e[3] / e[0], e[4] / e[0]])
	print("--- FRK presupuesto último mes: ", c["budget_last"])
	print("--- FRK tesoro %.0f deuda %.0f banco %s" % [float(c["treasury"]), float(c["debt"]), str(c["bank"])])
