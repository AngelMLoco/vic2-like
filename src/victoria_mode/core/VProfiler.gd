class_name VProfiler
extends RefCounted
## Medición de rendimiento: media móvil exponencial y máximo por sección (ms).
## Uso: var t := VProfiler.begin()  …  VProfiler.end(gs, "daily_tick", t)


static func begin() -> int:
	return Time.get_ticks_usec()


static func end(gs: VGameState, section: String, t0: int) -> float:
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var e: Dictionary = gs.profile.get(section, {"avg": ms, "max": ms, "last": ms, "n": 0})
	e["avg"] = ms if int(e["n"]) == 0 else float(e["avg"]) * 0.9 + ms * 0.1
	e["max"] = max(float(e["max"]), ms)
	e["last"] = ms
	e["n"] = int(e["n"]) + 1
	gs.profile[section] = e
	return ms


static func report(gs: VGameState) -> String:
	var lines := []
	var keys := gs.profile.keys()
	keys.sort()
	for k in keys:
		var e: Dictionary = gs.profile[k]
		lines.append("%-18s media %7.2f ms · máx %7.2f ms · n=%d" % [k, float(e["avg"]), float(e["max"]), int(e["n"])])
	return "\n".join(lines)
