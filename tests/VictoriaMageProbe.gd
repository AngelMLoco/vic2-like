## Sonda de calibración del modelo de magos (sin interfaz): activa la magia al inicio y muestra la curva.
##   godot --headless --path . -s tests/VictoriaMageProbe.gd -- <años>
extends SceneTree

func _init() -> void:
	pass

func _process(_d: float) -> bool:
	var years := 10
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			years = int(a)
	var gs := VDataLoader.new_game()
	var sim := VWorldSimulation.new(gs)
	VMagicSystem.activate(gs)
	var t0 := Time.get_ticks_msec()
	for y in years:
		sim.run_days(365)
		var tot := 0.0
		var tgt := 0.0
		var pop := 0.0
		var unemp := 0.0
		var rows := []
		for tag in gs.country_order:
			var c: Dictionary = gs.countries[tag]
			if c["provinces"].is_empty():
				continue
			var info: Dictionary = c.get("_magi_info", {})
			var m := float(c.get("type_sizes", {}).get("magi", 0))
			tot += m
			pop += float(c.get("population", 0))
			tgt += float(info.get("target", 0.0))
			unemp += m * float(info.get("unemployment", 0.0))
			if m > 0:
				rows.append([m, tag, info])
		rows.sort_custom(func(a, b): return a[0] > b[0])
		print("año %d: magos %d (%.4f%%) objetivo %d · paro magos %.2f · %d ms" % [y + 1, int(tot), tot / pop * 100.0, int(tgt), unemp / maxf(1.0, tot), Time.get_ticks_msec() - t0])
		for r in rows.slice(0, 6):
			var inf: Dictionary = r[2]
			var st: Dictionary = gs.countries[r[1]].get("magic_stats", {})
			print("   %s magos %d obj %d (%.3f%%) paro %.2f reg %s acad %d prom %d dem %d emig %d inm %d" % [r[1], int(r[0]), int(inf.get("target", 0)),
				float(inf.get("share", 0)) * 100.0, float(inf.get("unemployment", 0)), VMagicPolicy.level_id(gs, r[1]), VMageModel.academies(gs, r[1]),
				int(st.get("promoted", 0)), int(st.get("demoted", 0)), int(st.get("emigrated", 0)), int(st.get("immigrated", 0))])
	var mil: Dictionary = VPopulationSystem.cumulative_diagnosis(gs, "mil")
	print("diag mil acumulado: ", mil)
	print("diag con acumulado: ", VPopulationSystem.cumulative_diagnosis(gs, "con"))
	print("stats eventos: ", VScopedState.es(gs)["stats"])
	quit(0)
	return true
