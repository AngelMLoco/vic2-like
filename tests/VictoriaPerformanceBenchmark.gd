extends Node
## Benchmark fijo de rendimiento (sin interfaz, IA activa, sin jugador, simulación determinista):
##   godot --headless --path . res://tests/VictoriaPerformanceBenchmark.tscn -- [años=10]
## Puntos de control en 1, 5 y 10 años de la MISMA ejecución (mismo estado inicial).
## Imprime tiempo total, ms/año, desglose por sistema y contadores (rutas, IA).
##
## Huella de determinismo: al terminar guarda indicadores (población, fábricas, guerras, esferas,
## brigadas, bajas, rebeliones, vida, precios) en user://bench_last_<años>.json y los compara con
## user://bench_baseline_<años>.json si existe. VBENCH_SET_BASELINE=1 fija la línea base.
##
## Regresión: NO falla por tiempo absoluto (otro equipo puede ser más lento). Comprueba ratios
## (peso de la IA militar, aciertos de caché de rutas, peso del cierre de mes) y avisa si empeoran.

const CHECKPOINTS := [1, 5, 10, 20, 30]

## grupos del informe → secciones de VProfiler que suman (sin solapes)
const GROUPS := {
	"daily_tick": ["daily_tick"],
	"monthly_tick": ["monthly_tick"],
	"military (día)": ["military_day"],
	"· army_movement": ["army_movement"],
	"· combat": ["combat"],
	"· supply": ["supply"],
	"· reinforcement": ["reinforcement"],
	"· sieges": ["sieges"],
	"· war_score": ["war_score"],
	"· navy": ["navy"],
	"· military_ai_land": ["military_ai_land"],
	"· military_ai_navy": ["military_ai_navy"],
	"·· pathfinding (anidado)": ["pathfinding"],
	"economy": ["production", "m_market", "m_budget", "m_production_invest"],
	"· fábricas (cubos)": ["production_factories"],
	"· RGO/artesanos/empleo (cubos)": ["production_provinces"],
	"population": ["population", "m_population_flush", "m_population_caches", "m_population_prepare"],
	"mobility": ["mobility", "m_mobility_targets"],
	"politics": ["m_politics"],
	"technology": ["m_technology"],
	"diplomacy": ["m_diplomacy"],
	"influence": ["m_influence"],
	"war (mes)": ["m_war"],
	"leaders": ["m_leaders"],
	"rebels": ["m_rebels"],
	"ranking": ["m_ranking"],
	"unit counts": ["m_unit_counts"],
	"money audit": ["m_money_audit"],
}

var years := 10


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		years = int(args[0])
	await get_tree().process_frame
	var tl := Time.get_ticks_msec()
	var gs := VDataLoader.new_game()
	var load_ms := Time.get_ticks_msec() - tl
	gs.player_tag = ""
	var sim := VWorldSimulation.new(gs)
	VProfiler.reset(gs)
	print("== Benchmark de rendimiento: %d años · %d naciones · %d provincias terrestres · %d zonas marítimas · carga %d ms ==" % [
		years, gs.living_countries().size(), gs.first_sea_id - 1, gs.provinces.size() - gs.first_sea_id, load_ms])
	var t_start := Time.get_ticks_usec()
	var last_cp_us := t_start
	var last_cp_year := 0
	var last_snap := _snapshot(gs)
	var year_ms := []
	for y in range(1, years + 1):
		var ty := Time.get_ticks_usec()
		sim.run_days(365)
		year_ms.append((Time.get_ticks_usec() - ty) / 1000.0)
		if y in CHECKPOINTS or y == years:
			var now := Time.get_ticks_usec()
			var snap := _snapshot(gs)
			var seg_years := y - last_cp_year
			print("\n-- %d año(s): total %.1f s · tramo %d→%d: %.0f ms/año" % [y, (now - t_start) / 1000000.0, last_cp_year, y, (now - last_cp_us) / 1000.0 / seg_years])
			_print_groups(snap, last_snap, seg_years)
			last_snap = snap
			last_cp_us = now
			last_cp_year = y
	var total_s := (Time.get_ticks_usec() - t_start) / 1000000.0
	print("\n== Total %d años: %.1f s · media %.0f ms/año · año más lento %.0f ms ==" % [years, total_s, total_s * 1000.0 / years, year_ms.max()])
	print("ms por año: " + ", ".join(year_ms.map(func(v): return "%.0f" % v)))
	print("\n" + VProfiler.report(gs))
	print("\n" + _path_summary(gs))
	var fp := fingerprint(gs)
	print("\nHuella: " + JSON.stringify(fp))
	_compare_baseline(fp)
	var warnings := _ratio_checks(gs)
	for w in warnings:
		print("AVISO: " + w)
	print("== benchmark: %d avisos ==" % warnings.size())
	get_tree().quit(0)


func _snapshot(gs: VGameState) -> Dictionary:
	var s := {}
	for k in GROUPS:
		var t := 0.0
		for sec in GROUPS[k]:
			t += VProfiler.total(gs, sec)
		s[k] = t
	return s


func _print_groups(now: Dictionary, prev: Dictionary, seg_years: int) -> void:
	var sim_total := float(now["daily_tick"]) - float(prev["daily_tick"]) + float(now["monthly_tick"]) - float(prev["monthly_tick"])
	print("   %-26s %10s %8s" % ["sistema", "ms/año", "% sim"])
	for k in GROUPS:
		var v := (float(now[k]) - float(prev[k])) / seg_years
		print("   %-26s %10.0f %7.1f%%" % [k, v, v * seg_years / maxf(0.001, sim_total) * 100.0])


static func _path_summary(gs: VGameState) -> String:
	var c := gs.perf_counters
	var req := int(c.get("path_requests", 0))
	var hits := int(c.get("path_cache_hits", 0)) + int(c.get("path_fail_cache_hits", 0))
	var searched := int(c.get("path_successful", 0)) + int(c.get("path_failed", 0))
	return "Rutas: %d peticiones · %d aciertos de caché (%.0f%%) · %d búsquedas A* (%d con éxito, %d fallidas) · nodos %d (media %.0f, máx %d) · encoladas %d\nIA: %d naciones evaluadas · %d ejércitos evaluados" % [
		req, hits, 100.0 * hits / maxf(1.0, req), searched, int(c.get("path_successful", 0)), int(c.get("path_failed", 0)),
		int(c.get("path_nodes_expanded", 0)), float(c.get("path_nodes_expanded", 0)) / maxf(1.0, searched), int(c.get("path_max_nodes", 0)),
		int(c.get("path_queued", 0)), int(c.get("ai_countries_evaluated", 0)), int(c.get("ai_armies_evaluated", 0))]


## Indicadores para comparar simulaciones antes/después de una optimización.
static func fingerprint(gs: VGameState) -> Dictionary:
	var bal: Script = load("res://tests/VictoriaBalanceTest.gd")
	var s: Dictionary = bal.stats(gs)
	var m: Dictionary = bal.m3_stats(gs)
	var cas := 0
	var brig := 0
	for t in gs.countries:
		cas += int(gs.countries[t].get("casualties", 0))
		brig += int(gs.countries[t]["military"]["brigades"])
	return {"population_m": snappedf(float(s["pop"]) / 1e6, 0.1), "life": snappedf(float(s["life"]), 0.001), "everyday": snappedf(float(s["every"]), 0.001),
		"factories": int(s["open"]), "price_median": snappedf(float(s["pmed"]), 0.001), "wars_total": int(m["wars_total"]),
		"sphere_members": int(m["sphere"]), "brigades": brig, "max_brigades": int(m["max_brigades"]), "casualties": cas,
		"rebel_factions_total": int(gs.next_ids.get("rebel", 1)) - 1, "armies": int(m["armies"]),
		"pops": gs.pops.count(), "militancy": snappedf(float(s["mil"]), 0.01)}


func _compare_baseline(fp: Dictionary) -> void:
	var last := "user://bench_last_%d.json" % years
	var base := "user://bench_baseline_%d.json" % years
	var f := FileAccess.open(last, FileAccess.WRITE)
	f.store_string(JSON.stringify(fp))
	f.close()
	if OS.get_environment("VBENCH_SET_BASELINE") != "":
		var fb := FileAccess.open(base, FileAccess.WRITE)
		fb.store_string(JSON.stringify(fp))
		fb.close()
		print("línea base guardada en " + ProjectSettings.globalize_path(base))
		return
	if not FileAccess.file_exists(base):
		print("(sin línea base; VBENCH_SET_BASELINE=1 para fijarla)")
		return
	var b: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base))
	print("Comparación con la línea base (%s):" % ProjectSettings.globalize_path(base))
	for k in fp:
		var v0 := float(b.get(k, 0.0))
		var v1 := float(fp[k])
		var rel := (v1 - v0) / maxf(absf(v0), 1e-6)
		var flag := "" if absf(rel) <= 0.15 or absf(v1 - v0) <= 3.0 else "   <-- diferencia > 15%"
		print("   %-22s %12s → %12s  (%+.1f%%)%s" % [k, str(b.get(k, "-")), str(fp[k]), rel * 100.0, flag])


## Comprobaciones por proporciones (portables entre equipos). Devuelve avisos, no fallos.
static func _ratio_checks(gs: VGameState) -> Array:
	var out := []
	var sim := VProfiler.total(gs, "daily_tick") + VProfiler.total(gs, "monthly_tick")
	var ai := VProfiler.total(gs, "military_ai_land") + VProfiler.total(gs, "military_ai_navy")
	if ai > sim * 0.15:
		out.append("la IA militar supone el %.0f%% de la simulación (umbral 15%%)" % (ai / sim * 100.0))
	var mil := VProfiler.total(gs, "military_day")
	if mil > sim * 0.40:
		out.append("la capa militar diaria supone el %.0f%% de la simulación (umbral 40%%)" % (mil / sim * 100.0))
	var month := VProfiler.total(gs, "monthly_tick")
	if month > sim * 0.40:
		out.append("el cierre de mes domina (%.0f%% de la simulación, umbral 40%%)" % (month / sim * 100.0))
	var c := gs.perf_counters
	var req := int(c.get("path_requests", 0))
	var hits := int(c.get("path_cache_hits", 0)) + int(c.get("path_fail_cache_hits", 0))
	if req > 500 and float(hits) / req < 0.3:
		out.append("aciertos de caché de rutas bajos (%.0f%%, umbral 30%%)" % (100.0 * hits / req))
	var searched := int(c.get("path_successful", 0)) + int(c.get("path_failed", 0))
	if searched > 0 and float(c.get("path_nodes_expanded", 0)) / searched > 400.0:
		out.append("A* expande de media %.0f nodos por búsqueda (umbral 400)" % (float(c.get("path_nodes_expanded", 0)) / searched))
	var dmax := float(gs.profile.get("daily_tick", {}).get("max", 0.0))
	var davg := VProfiler.total(gs, "daily_tick") / maxf(1.0, VProfiler.calls(gs, "daily_tick"))
	if dmax > davg * 12.0:
		out.append("pico diario %.0f ms = %.0f× la media (umbral 12×)" % [dmax, dmax / davg])
	return out
