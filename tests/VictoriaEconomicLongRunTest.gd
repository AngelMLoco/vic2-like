extends Node
## Economía de largo plazo (M5.5): N años (100 por defecto) con diagnóstico económico completo en los años
## 0, 25, 50, 75 y 100 y una línea breve cada 10 años. Comprueba que la economía responde al crecimiento
## demográfico (sin topes): paro, necesidades vitales, capacidad RGO/industrial, proyectos, riesgo rebelde.
##   godot --headless --path . res://tests/VictoriaEconomicLongRunTest.tscn -- [años]
## Corridas de control: VBAL_EVENTS=0 (sin eventos ni magia) · VBAL_NO_MAGIC=1 (eventos sin despertar).

const Bal := preload("res://tests/VictoriaBalanceTest.gd")
const CHECKPOINTS := [0, 25, 50, 75, 100]

var years := 100


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		years = int(args[0])
	await get_tree().process_frame
	var gs := VDataLoader.new_game()
	gs.player_tag = ""
	var mode := "normal"
	if OS.get_environment("VBAL_EVENTS") == "0":
		gs.flags["events_disabled"] = true
		mode = "sin eventos ni magia"
	elif OS.get_environment("VBAL_NO_MAGIC") == "1":
		gs.event_defs.erase("magic.world.awakening")
		VEventSystem._build_index(gs)
		mode = "eventos sin magia"
	var sim := VWorldSimulation.new(gs)
	print("== economía de largo plazo: %d años · %s ==" % [years, mode])
	var t0 := Time.get_ticks_msec()
	var prev := VEconomyDiagnostics.snapshot(gs)
	var prev_year := 0
	print("\n== año 0 ==\n" + VEconomyDiagnostics.report(prev))
	var factories0 := int(prev["factories"]["open"])
	var fac_hist := {0: factories0}
	var last := {}
	for y in years:
		sim.run_days(365)
		var yr := y + 1
		var s := Bal.stats(gs)
		var m := Bal.m3_stats(gs)
		fac_hist[yr] = int(s["open"])
		if yr % 5 == 0:
			var ms := VMoney.snapshot(gs)
			print("año %3d · pobl %.0f M · vida %.2f · paro %.2f · milit %.2f · conc %.2f · fábricas %d · precios %.2f · rebeldes %d (riesgo %d) · dinero %.0f (POPs %.0f, depósitos %.0f, fábricas %.0f, tesoros %.0f) · %.1f s/año" % [
				yr, float(s["pop"]) / 1e6, s["life"], s["unemp"], s["mil"], s["con"], s["open"], s["pmed"], m["rebels"], m["rebel_risk"],
				float(ms["total"]), float(ms["pop_cash"]), float(ms["pop_bank"]), float(ms["factory_cash"]), float(ms["treasury"]), (Time.get_ticks_msec() - t0) / 1000.0 / yr])
		if yr in CHECKPOINTS or yr == years:
			var snap := VEconomyDiagnostics.snapshot(gs)
			print("\n== año %d (%.1f s/año) ==" % [yr, (Time.get_ticks_msec() - t0) / 1000.0 / yr])
			print("  resumen: vida %.2f · diario %.2f · paro %.2f · militancia %.2f · conciencia %.2f · fábricas %d · mediana de precios %.2f · rebeldes %d · riesgo en %d de %d naciones" % [
				s["life"], s["every"], s["unemp"], s["mil"], s["con"], s["open"], s["pmed"], m["rebels"], m["rebel_risk"], m["living"]])
			print(VEconomyDiagnostics.report(snap, prev, float(yr - prev_year)))
			print("  dinero (último trimestre auditado): " + _ledger_text(gs))
			prev = snap
			prev_year = yr
			last = {"stats": s, "m3": m, "snap": snap}
	var fails := []
	# sin explosión industrial (la antigua de M2: 119 → 920 fábricas en 10 años)
	for y in range(10, years + 1, 10):
		if fac_hist.has(y) and fac_hist.has(y - 10) and int(fac_hist[y]) > int(fac_hist[y - 10]) * 2 + 40:
			fails.append("explosión industrial: %d → %d fábricas en 10 años (año %d)" % [fac_hist[y - 10], fac_hist[y], y])
	fails += Bal.degenerate_checks(gs)
	print("\n== economía de largo plazo (%s): %d problemas ==" % [mode, fails.size()])
	for f in fails:
		print("   - ", f)
	get_tree().quit(1 if not fails.is_empty() else 0)


## Mayores flujos de creación y destrucción de dinero del último trimestre auditado.
static func _ledger_text(gs: VGameState) -> String:
	var au: Dictionary = gs.market.get("money_audit", {})
	var parts := []
	for side in ["created", "destroyed"]:
		var d: Dictionary = au.get(side, {})
		var ks := d.keys()
		ks.sort_custom(func(a, b): return float(d[a]) > float(d[b]))
		var top := []
		for k in ks.slice(0, 6):
			top.append("%s %.0f" % [k, float(d[k])])
		parts.append(("creado: " if side == "created" else "destruido: ") + ", ".join(top))
	return " | ".join(parts)

