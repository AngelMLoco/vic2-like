class_name VProfiler
extends RefCounted
## Medición de rendimiento por sección: llamadas, tiempo total, media real, máximo y media móvil
## (la media móvil la usa la interfaz). También contadores (rutas pedidas, nodos expandidos…).
## Uso: var t := VProfiler.begin()  …  VProfiler.end(gs, "daily_tick", t)
##      VProfiler.count(gs, "path_requests")
## Las secciones pueden anidarse (p. ej. «pathfinding» dentro de «military_ai_land»): el informe
## muestra cada una por separado, sin restar las anidadas.


static func begin() -> int:
	return Time.get_ticks_usec()


static func end(gs: VGameState, section: String, t0: int) -> float:
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var e: Dictionary = gs.profile.get(section, {})
	if e.is_empty():
		e = {"avg": ms, "max": ms, "last": ms, "n": 0, "total": 0.0}
		gs.profile[section] = e
	else:
		e["avg"] = float(e["avg"]) * 0.9 + ms * 0.1
		if ms > float(e["max"]):
			e["max"] = ms
		e["last"] = ms
	e["n"] = int(e["n"]) + 1
	e["total"] = float(e["total"]) + ms
	return ms


## Acumula un tiempo ya medido (para bucles internos sin coste de diccionario por iteración).
static func add(gs: VGameState, section: String, ms: float, n_calls: int = 1) -> void:
	var e: Dictionary = gs.profile.get(section, {})
	if e.is_empty():
		e = {"avg": ms, "max": ms, "last": ms, "n": 0, "total": 0.0}
		gs.profile[section] = e
	e["n"] = int(e["n"]) + n_calls
	e["total"] = float(e["total"]) + ms
	e["last"] = ms
	if ms > float(e["max"]):
		e["max"] = ms


static func count(gs: VGameState, key: String, n: int = 1) -> void:
	gs.perf_counters[key] = int(gs.perf_counters.get(key, 0)) + n


static func count_max(gs: VGameState, key: String, v: int) -> void:
	if v > int(gs.perf_counters.get(key, 0)):
		gs.perf_counters[key] = v


static func reset(gs: VGameState) -> void:
	gs.profile.clear()
	gs.perf_counters.clear()


static func total(gs: VGameState, section: String) -> float:
	return float(gs.profile.get(section, {}).get("total", 0.0))


static func calls(gs: VGameState, section: String) -> int:
	return int(gs.profile.get(section, {}).get("n", 0))


static func report(gs: VGameState) -> String:
	var lines := ["%-24s %8s %11s %9s %9s" % ["sección", "llamadas", "total ms", "media ms", "máx ms"]]
	var keys := gs.profile.keys()
	keys.sort()
	for k in keys:
		var e: Dictionary = gs.profile[k]
		var n := int(e["n"])
		lines.append("%-24s %8d %11.1f %9.3f %9.2f" % [k, n, float(e.get("total", 0.0)), float(e.get("total", 0.0)) / maxf(1.0, float(n)), float(e["max"])])
	if not gs.perf_counters.is_empty():
		var ck := gs.perf_counters.keys()
		ck.sort()
		for k in ck:
			lines.append("  #%-22s %d" % [k, int(gs.perf_counters[k])])
	return "\n".join(lines)
