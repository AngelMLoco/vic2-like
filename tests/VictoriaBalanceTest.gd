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
	gs.flags["money_audit"] = true
	# VBAL_EVENTS=0: sin motor de eventos ni magia · VBAL_NO_MAGIC=1: eventos sin despertar
	if OS.get_environment("VBAL_EVENTS") == "0":
		gs.flags["events_disabled"] = true
	elif OS.get_environment("VBAL_NO_MAGIC") == "1":
		gs.event_defs.erase("magic.awakening")
		VEventSystem._build_index(gs)
	var sim := VWorldSimulation.new(gs)
	print(header())
	print(row(gs, 0))
	var gp_sets := {}
	var failures := []
	var money_problems := []
	for y in years:
		var ty := Time.get_ticks_msec()
		sim.run_days(365)
		print(row(gs, y + 1) + "  (%.1f s)" % ((Time.get_ticks_msec() - ty) / 1000.0))
		print("      " + m3_row(gs))
		print("      " + pop_row(gs))
		print("      " + event_row(gs))
		var gps := []
		for t in gs.country_order:
			if gs.countries[t].get("status", "") == "great_power":
				gps.append(t)
		gps.sort()
		gp_sets[",".join(gps)] = true
		var au: Dictionary = gs.market.get("money_audit", {})
		print("      dinero: " + VMoney.describe(au).replace("
", " | "))
		if au.has("residual_ratio") and float(au["residual_ratio"]) > 0.01:
			money_problems.append("año %d: residuo monetario %.2f%% sin explicar" % [y + 1, float(au["residual_ratio"]) * 100.0])
	print(VProfiler.report(gs))
	if OS.get_environment("VBAL_DEBUG") != "":
		debug_dump(gs)
	failures = degenerate_checks(gs) + money_problems + m3_checks(gs, years, gp_sets.size())
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
		var ps := gs.pops
		for pop in p["pop_slots"]:
			var w := float(ps.size[pop])
			s["pop"] += w
			s["life"] += ps.life[pop] * w
			s["every"] += ps.everyday[pop] * w
			s["lux"] += ps.luxury[pop] * w
			s["unemp"] += (1.0 - ps.employment[pop]) * w
			s["mil"] += ps.militancy[pop] * w
			s["con"] += ps.consciousness[pop] * w
			s["lit"] += ps.literacy[pop] * w
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
		for pop in gs.provinces[id]["pop_slots"]:
			var tn: String = gs.pops.type_name(pop)
			var e: Array = by.get(tn, [0.0, 0.0, 0.0, 0.0, 0.0])
			var u := float(gs.pops.size[pop]) / 10000.0
			e[0] += u
			e[1] += gs.pops.cash[pop]
			e[2] += gs.pops.income[pop]
			e[3] += gs.pops.life[pop] * u
			e[4] += gs.pops.employment[pop] * u
			by[tn] = e
	print("--- FRK por tipo: unidades | cash/10k | renta/10k | vida | empleo")
	for t in by:
		var e: Array = by[t]
		print("%-12s %7.1f | %7.2f | %7.2f | %.2f | %.2f" % [t, e[0], e[1] / e[0], e[2] / e[0], e[3] / e[0], e[4] / e[0]])
	print("--- FRK presupuesto último mes: ", c["budget_last"])
	print("--- FRK tesoro %.0f deuda %.0f banco %s" % [float(c["treasury"]), float(c["debt"]), str(c["bank"])])


static func m3_stats(gs: VGameState) -> Dictionary:
	var at_war := 0
	var living := gs.living_countries()
	for t in living:
		if not gs.countries[t]["wars"].is_empty():
			at_war += 1
	var brig := 0
	var max_brig := 0
	for t in living:
		var n := int(gs.countries[t]["military"]["brigades"])
		brig += n
		max_brig = maxi(max_brig, n)
	var sphere := 0
	for t in living:
		if gs.countries[t].get("sphere_leader", "") != "":
			sphere += 1
	var risk := 0
	for t in living:
		for rid in gs.countries[t].get("movements", {}):
			if gs.countries[t]["movements"][rid].get("rebel_risk", false):
				risk += 1
				break
	return {"wars_total": int(gs.next_ids.get("war", 1)) - 1, "wars_active": gs.wars.size(), "at_war": at_war, "living": living.size(),
		"avg_brigades": float(brig) / maxf(1.0, float(living.size())), "max_brigades": max_brig, "sphere": sphere,
		"rebels": gs.rebel_factions.size(), "rebel_risk": risk, "armies": gs.armies.size(), "fleets": gs.fleets.size()}


## POPs (almacén) y diagnóstico de militancia del último mes (contribución media mensual por componente).
static func pop_row(gs: VGameState) -> String:
	var st: Dictionary = gs.pops.stats
	var d: Dictionary = gs.market.get("mil_diag", {})
	var parts := []
	for k in VPopulationSystem.MIL_PARTS:
		if absf(float(d.get(k, 0.0))) >= 0.0005:
			parts.append("%s %+.3f" % [k, float(d[k])])
	return "POPs %d (creados %d, fusionados %d, nuevos por traslado %d) · militancia/mes: %s · neto %+.4f" % [
		gs.pops.count(), int(st["created"]), int(st["merged"]), int(st["split"]), ", ".join(parts), float(d.get("net", 0.0))]


## Eventos, decisiones y magia (acumulado).
static func event_row(gs: VGameState) -> String:
	var st: Dictionary = VScopedState.es(gs)["stats"]
	var magi := 0
	var deps := 0
	for tag in gs.country_order:
		magi += int(gs.countries[tag].get("type_sizes", {}).get("magi", 0))
	for id in range(1, gs.first_sea_id):
		if float(gs.provinces[id].get("magic", {}).get("deposit", 0.0)) > 0.0:
			deps += 1
	return "eventos %d (IA %d) · decisiones %d · magia %s · magos %d · yacimientos %d · crónica %d" % [int(st.get("fired", 0)), int(st.get("ai", 0)),
		int(st.get("decisions", 0)), "sí" if gs.flags.get("GLOBAL_MAGIC_ACTIVATED", false) else "no", magi, deps, VScopedState.es(gs)["history"].size()]


static func m3_row(gs: VGameState) -> String:
	var m := m3_stats(gs)
	return "M3: guerras %d (activas %d, %d naciones en guerra) · brigadas media %.1f máx %d · ejércitos %d flotas %d · esferas %d miembros · rebeldes %d (riesgo en %d naciones)" % [
		m["wars_total"], m["wars_active"], m["at_war"], m["avg_brigades"], m["max_brigades"], m["armies"], m["fleets"], m["sphere"], m["rebels"], m["rebel_risk"]]


static func m3_checks(gs: VGameState, years: int, gp_sets: int) -> Array:
	var m := m3_stats(gs)
	var out := []
	if years >= 10 and int(m["wars_total"]) <= 1:
		out.append("no ha habido guerras nuevas en %d años" % years)
	if int(m["at_war"]) > int(m["living"]) * 0.6:
		out.append("demasiadas naciones en guerra (%d/%d)" % [m["at_war"], m["living"]])
	if float(m["avg_brigades"]) > 60.0 or int(m["max_brigades"]) > 400:
		out.append("tamaño de ejércitos implausible (media %.1f, máx %d)" % [m["avg_brigades"], m["max_brigades"]])
	if int(m["rebel_risk"]) > int(m["living"]) * 0.5:
		out.append("riesgo rebelde casi universal (%d naciones)" % m["rebel_risk"])
	if years >= 5 and int(m["sphere"]) == 0:
		out.append("no se ha formado ninguna esfera de influencia")
	return out
