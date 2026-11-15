extends Node
## Estabilidad a largo plazo (M5): N años (100 por defecto) con eventos y magia, informe cada 10 años y en el
## año 25. No es un benchmark: busca crecimientos desbocados (runaway) y estados degenerados.
##   godot --headless --path . res://tests/VictoriaLongRunTest.tscn -- [años]
## Variables: VBAL_EVENTS=0 (sin eventos ni magia) · VBAL_NO_MAGIC=1 (eventos sin despertar).

const Bal := preload("res://tests/VictoriaBalanceTest.gd")

var years := 100
var magi_hist := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		years = int(args[0])
	await get_tree().process_frame
	var gs := VDataLoader.new_game()
	gs.player_tag = ""
	if OS.get_environment("VBAL_EVENTS") == "0":
		gs.flags["events_disabled"] = true
	elif OS.get_environment("VBAL_NO_MAGIC") == "1":
		gs.event_defs.erase("magic.world.awakening")
		VEventSystem._build_index(gs)
	var sim := VWorldSimulation.new(gs)
	var gp_sets := {}
	var t0 := Time.get_ticks_msec()
	for y in years:
		sim.run_days(365)
		var yr := y + 1
		var gps := []
		for t in gs.country_order:
			if gs.countries[t].get("status", "") == "great_power":
				gps.append(t)
		gps.sort()
		gp_sets[",".join(gps)] = true
		magi_hist[yr] = world_magi(gs)
		if yr % 10 == 0 or yr == 25 or yr == years:
			report(gs, yr, Time.get_ticks_msec() - t0)
	print("\n== diagnóstico acumulado (media mensual por persona) ==")
	print("militancia: ", fmt_diag(VPopulationSystem.cumulative_diagnosis(gs, "mil")))
	print("conciencia: ", fmt_diag(VPopulationSystem.cumulative_diagnosis(gs, "con")))
	var failures: Array = Bal.degenerate_checks(gs) + Bal.m3_checks(gs, years, gp_sets.size()) + runaway_checks(gs)
	print("== largo plazo (%d años): %d problemas ==" % [years, failures.size()])
	for f in failures:
		print("   - ", f)
	get_tree().quit(1 if not failures.is_empty() else 0)


static func world_magi(gs: VGameState) -> float:
	var n := 0.0
	for t in gs.country_order:
		n += float(gs.countries[t].get("type_sizes", {}).get("magi", 0))
	return n


static func pct(arr: Array, q: float) -> float:
	if arr.is_empty():
		return 0.0
	var a := arr.duplicate()
	a.sort()
	return float(a[clampi(int(q * float(a.size() - 1)), 0, a.size() - 1)])


static func fmt_diag(d: Dictionary) -> String:
	var parts := []
	for k in d:
		if absf(float(d[k])) >= 0.00005:
			parts.append("%s %+.4f" % [k, float(d[k])])
	return ", ".join(parts)


func report(gs: VGameState, yr: int, ms: int) -> void:
	var s := Bal.stats(gs)
	var m := Bal.m3_stats(gs)
	var living := gs.living_countries()
	var mils := []
	var cons := []
	var wes := []
	var hi3 := 0
	var hi5 := 0
	var lo1 := 0
	var magi := 0.0
	var pop := 0.0
	var mu := 0.0
	var max_share := 0.0
	var max_tag := ""
	var top := []
	var regs := {}
	var magic_f := 0
	for t in living:
		var c: Dictionary = gs.countries[t]
		var mil := float(c.get("avg_militancy", 0.0))
		mils.append(mil)
		cons.append(float(c.get("avg_consciousness", 0.0)))
		wes.append(float(c.get("war_exhaustion", 0.0)))
		if mil > 3.0:
			hi3 += 1
		if mil > 5.0:
			hi5 += 1
		if mil < 1.0:
			lo1 += 1
		var mg := float(c.get("type_sizes", {}).get("magi", 0))
		var cp := float(c.get("population", 0))
		magi += mg
		pop += cp
		var info: Dictionary = c.get("_magi_info", {})
		mu += mg * float(info.get("unemployment", 0.0))
		if cp > 500000.0 and mg / cp > max_share:
			max_share = mg / cp
			max_tag = t
		if mg > 0.0:
			top.append([mg, t])
		if VMagicSystem.is_active(gs) and (mg > 0.0 or VMagicSystem.max_branch(gs, t) > 0):
			var lid := VMagicPolicy.level_id(gs, t)
			regs[lid] = int(regs.get(lid, 0)) + 1
		magic_f += int(VEventConditions.country_num(gs, t, VEventConditions.CNUM_FIELDS.find("magic_factories")))
	top.sort_custom(func(a, b): return a[0] > b[0])
	var deps := 0
	for id in range(1, gs.first_sea_id):
		if float(gs.provinces[id].get("magic", {}).get("deposit", 0.0)) > 0.0:
			deps += 1
	var st: Dictionary = VScopedState.es(gs)["stats"]
	var fired := int(st.get("fired", 0))
	print("\n== año %d (%.0f s, %.2f s/año) ==" % [yr, ms / 1000.0, ms / 1000.0 / float(yr)])
	print("  población %.1f M · vida %.2f · diario %.2f · paro %.2f · alfab %.2f · fábricas %d/%d · precio mediana %.2f" % [
		float(s["pop"]) / 1e6, s["life"], s["every"], s["unemp"], s["lit"], s["open"], s["closed"], s["pmed"]])
	print("  militancia media %.2f · por país p10 %.2f p50 %.2f p90 %.2f máx %.2f · >3: %d · >5: %d · <1: %d de %d" % [
		s["mil"], pct(mils, 0.1), pct(mils, 0.5), pct(mils, 0.9), pct(mils, 1.0), hi3, hi5, lo1, living.size()])
	print("  conciencia media %.2f · por país p50 %.2f p90 %.2f máx %.2f" % [s["con"], pct(cons, 0.5), pct(cons, 0.9), pct(cons, 1.0)])
	print("  guerras %d (activas %d, %d naciones) · cansancio bélico medio %.1f máx %.1f · facciones rebeldes %d · riesgo en %d naciones" % [
		m["wars_total"], m["wars_active"], m["at_war"], pct(wes, 0.5), pct(wes, 1.0), m["rebels"], m["rebel_risk"]])
	var tops := []
	for e in top.slice(0, 4):
		tops.append("%s %d" % [e[1], int(e[0])])
	print("  magos %d · %.4f%% del mundo · máx. nacional %.3f%% (%s) · paro de magos %.0f%% · %s" % [
		int(magi), magi / maxf(1.0, pop) * 100.0, max_share * 100.0, max_tag, mu / maxf(1.0, magi) * 100.0, ", ".join(tops)])
	print("  yacimientos %d · fábricas mágicas %d · regulación %s" % [deps, magic_f, str(regs)])
	print("  eventos %d (%.2f por país y año) · jugador major/normal/notif %d/%d/%d · IA visibles %d · ocultos %d · core %d magic %d country %d · decisiones %d · crónica %d" % [
		fired, float(fired) / maxf(1.0, float(living.size())) / float(yr), int(st.get("player_major", 0)), int(st.get("player_normal", 0)),
		int(st.get("player_notification", 0)), int(st.get("ai_visible", 0)), int(st.get("ai_hidden", 0)) + int(st.get("type_hidden", 0)) - int(st.get("ai_hidden", 0)),
		int(st.get("ns_core", 0)), int(st.get("ns_magic", 0)), int(st.get("ns_country", 0)), int(st.get("decisions", 0)), VScopedState.es(gs)["history"].size()])


## Crecimientos desbocados: magos exponenciales, militancia inevitable, mundo congelado.
func runaway_checks(gs: VGameState) -> Array:
	var out := []
	var living := gs.living_countries()
	var hi5 := 0
	var calm := 0
	for t in living:
		var mil := float(gs.countries[t].get("avg_militancy", 0.0))
		if mil > 5.0:
			hi5 += 1
		if mil < 0.3:
			calm += 1
	if hi5 > living.size() * 0.5:
		out.append("militancia > 5 en la mayoría de las naciones (%d/%d)" % [hi5, living.size()])
	if calm == living.size():
		out.append("ninguna tensión: todas las naciones con militancia < 0,3")
	var w := world_magi(gs)
	var pop := 0.0
	for t in living:
		pop += float(gs.countries[t].get("population", 0))
	if w / maxf(1.0, pop) > 0.005:
		out.append("proporción mundial de magos desbocada (%.3f%%)" % (w / pop * 100.0))
	# crecimiento por décadas: no debe acelerarse sin causa (exponencial)
	var decs := []
	for y in range(20, years + 1, 10):
		if magi_hist.has(y) and magi_hist.has(y - 10) and float(magi_hist[y - 10]) > 1000.0:
			decs.append(float(magi_hist[y]) / float(magi_hist[y - 10]))
	if decs.size() >= 3:
		var accel := 0
		for i in range(1, decs.size()):
			if float(decs[i]) > float(decs[i - 1]) * 1.05 and float(decs[i]) > 1.5:
				accel += 1
		if accel >= decs.size() - 1:
			out.append("los magos crecen cada década más deprisa (%s)" % str(decs))
	print("  crecimiento de magos por década: ", decs.map(func(x): return "×%.2f" % x))
	return out
