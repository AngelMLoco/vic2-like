class_name VEconomyDiagnostics
extends RefCounted
## Diagnóstico económico de largo plazo (M5.5). SOLO pruebas y depuración: recorre todo el mundo (caro).
## El juego normal no lo llama; los contadores baratos de inversión viven en VProductionSystem
## (note_reason / note_stat → c["_inv_reasons"], c["_inv_stats"], gs.market["_inv_reasons"/"_inv_stats"]).
##
## snapshot(gs) devuelve un diccionario con:
##   labour     oferta de trabajo, plazas y paro por clase (RGO, fábricas, oficinistas, artesanos, Estado, magos)
##   factories  fábricas, niveles, utilización, particiones llenas
##   capital    capital de capitalistas y aristócratas, proyectos activos/parados
##   wages      renta mensual por 10.000 y coste de vida por tipo de POP
##   life       descomposición del déficit de necesidades vitales de los pobres (paro, salarios, escasez)
##   shortages  10 bienes con más escasez (oferta, demanda, llenado, precio)
##   countries  10 con más paro, 10 más industrializados, 10 más pobres
##   urban      urbanización mundial

const RGO_TYPES := ["farmers", "labourers", "slaves"]
const STATE_TYPES := ["clergy", "bureaucrats", "soldiers", "officers"]
const URBAN_TYPES := ["craftsmen", "clerks", "capitalists", "artisans", "magi"]
const WAGE_TYPES := ["farmers", "labourers", "craftsmen", "clerks", "artisans", "clergy", "bureaucrats", "soldiers", "magi", "aristocrats", "capitalists"]


static func snapshot(gs: VGameState) -> Dictionary:
	var ps := gs.pops
	var by_type := {}  # tipo → [personas, empleadas, renta, vida·tamaño]
	var poor_def := {"total": 0.0, "unemployment": 0.0, "low_wages": 0.0, "shortage": 0.0, "war": 0.0, "weight": 0.0}
	var rgo_cap := 0.0
	var rgo_emp := 0.0
	var country_rows := []
	for tag in gs.living_countries():
		var c: Dictionary = gs.countries[tag]
		var needs: Array[float] = c.get("_needs_tid", [] as Array[float])
		var at_war: bool = not c.get("wars", []).is_empty()
		var cpop := 0.0
		var cunemp := 0.0
		var curban := 0.0
		for id in c["provinces"]:
			var p: Dictionary = gs.provinces[id]
			var rd: Dictionary = p.get("rgo_data", {})
			rgo_cap += float(rd.get("max_workers", 0))
			rgo_emp += float(rd.get("workers", 0))
			for s: int in p["pop_slots"]:
				var t: int = ps.type_id[s]
				var tn: String = ps.type_names[t]
				var sz := float(ps.size[s])
				var e: Array = by_type.get(tn, [0.0, 0.0, 0.0, 0.0])
				e[0] += sz
				e[1] += sz * ps.employment[s]
				e[2] += ps.income[s]
				e[3] += sz * ps.life[s]
				by_type[tn] = e
				cpop += sz
				cunemp += sz * (1.0 - ps.employment[s])
				if tn in URBAN_TYPES:
					curban += sz
				if ps.t_strata[t] == 0:
					var f0 := needs[t * 6 + 3] if t * 6 + 3 < needs.size() else 1.0
					var life := ps.life[s]
					var a := clampf(life / maxf(0.01, f0), 0.0, 1.0)
					var u := 1.0 - ps.employment[s]
					poor_def["total"] += sz * (1.0 - life)
					poor_def["unemployment"] += sz * (1.0 - a) * u
					poor_def["low_wages"] += sz * (1.0 - a) * (1.0 - u)
					poor_def["shortage"] += sz * a * (1.0 - f0)
					if at_war:
						poor_def["war"] += sz * (1.0 - life)
					poor_def["weight"] += sz
		var fl := 0
		for si in gs.country_state_instances(tag):
			for f in si["factories"]:
				if f["open"]:
					fl += int(f["level"])
		country_rows.append({"tag": tag, "pop": cpop, "unemp": cunemp / maxf(1.0, cpop), "life": float(c.get("avg_life", 0.0)),
			"industry": float(fl) / maxf(0.1, cpop / 1e6), "levels": fl, "urban": curban / maxf(1.0, cpop)})
	var out := {}
	# ---- trabajo
	var lab := {}
	var total := 0.0
	var employed := 0.0
	for tn in by_type:
		total += float(by_type[tn][0])
		employed += float(by_type[tn][1])
	lab["population"] = total
	lab["employed"] = employed
	lab["unemployment"] = 1.0 - employed / maxf(1.0, total)
	for grp in [["rgo", RGO_TYPES], ["state", STATE_TYPES]]:
		var n := 0.0
		var em := 0.0
		for tn in grp[1]:
			n += float(by_type.get(tn, [0.0, 0.0])[0])
			em += float(by_type.get(tn, [0.0, 0.0])[1])
		lab[grp[0] + "_workers"] = n
		lab[grp[0] + "_unemployment"] = 1.0 - em / maxf(1.0, n)
	lab["rgo_capacity"] = rgo_cap
	lab["rgo_employed"] = rgo_emp
	lab["rgo_utilisation"] = rgo_emp / maxf(1.0, rgo_cap)
	for tn in ["craftsmen", "clerks", "artisans", "magi"]:
		var e2: Array = by_type.get(tn, [0.0, 0.0])
		lab[tn] = float(e2[0])
		lab[tn + "_unemployment"] = 1.0 - float(e2[1]) / maxf(1.0, float(e2[0]))
	# ---- fábricas
	var fac := {"open": 0, "closed": 0, "levels": 0, "at_max_level": 0, "craft_capacity": 0.0, "craft_employed": 0.0,
		"clerk_capacity": 0.0, "clerk_employed": 0.0, "magi_capacity": 0.0, "magi_employed": 0.0, "states_full": 0, "states": 0, "magic": 0}
	var max_level := int(gs.economy_rules.get("factory_max_level", 10))
	for key in gs.state_instances:
		var si: Dictionary = gs.state_instances[key]
		if si["owner"] == "":
			continue
		fac["states"] += 1
		if si["factories"].size() >= VProductionSystem.state_factory_slots(gs, si):
			fac["states_full"] += 1
		for f in si["factories"]:
			if not f["open"]:
				fac["closed"] += 1
				continue
			var wf: Dictionary = gs.factory_types.get(f["type"], {}).get("workforce", {})
			fac["open"] += 1
			fac["levels"] += int(f["level"])
			if int(f["level"]) >= max_level:
				fac["at_max_level"] += 1
			if int(wf.get("magi", 0)) > 0:
				fac["magic"] += 1
			fac["craft_capacity"] += float(wf.get("craftsmen", 9000)) * int(f["level"])
			fac["craft_employed"] += float(f.get("craftsmen_employed", 0))
			fac["clerk_capacity"] += float(wf.get("clerks", 1000)) * int(f["level"])
			fac["clerk_employed"] += float(f.get("clerks_employed", 0))
			fac["magi_capacity"] += float(wf.get("magi", 0)) * int(f["level"])
			fac["magi_employed"] += float(f.get("magi_employed", 0))
	fac["utilisation"] = float(fac["craft_employed"]) / maxf(1.0, float(fac["craft_capacity"]))
	out["factories"] = fac
	lab["factory_jobs"] = fac["craft_capacity"]
	lab["clerk_jobs"] = fac["clerk_capacity"]
	lab["total_jobs"] = rgo_cap + float(fac["craft_capacity"]) + float(fac["clerk_capacity"])
	out["labour"] = lab
	# ---- capital y proyectos
	var cap := {"capitalists": 0.0, "aristocrats": 0.0, "projects": 0, "stalled": 0, "private": 0, "government": 0, "rgo": 0}
	for tag in gs.living_countries():
		var c2: Dictionary = gs.countries[tag]
		for s in c2.get("_capitalists", []):
			cap["capitalists"] += ps.cash[s] + ps.bank[s]
		for s in c2.get("_aristocrats", []):
			cap["aristocrats"] += ps.cash[s] + ps.bank[s]
		for pr in c2.get("projects", []):
			cap["projects"] += 1
			var inv: String = pr.get("investor", "")
			if inv == "government":
				cap["government"] += 1
			elif inv == "aristocrats" or pr.get("kind", "") == "rgo":
				cap["rgo"] += 1
			else:
				cap["private"] += 1
			if int(pr.get("stalled_months", 0)) >= 6:
				cap["stalled"] += 1
	out["capital"] = cap
	# ---- salarios (renta mensual por 10.000) frente al coste de vida
	var wages := {}
	for tn in WAGE_TYPES:
		var e3: Array = by_type.get(tn, [])
		if e3.is_empty() or float(e3[0]) <= 0.0:
			continue
		wages[tn] = {"income": float(e3[2]) / (float(e3[0]) / 10000.0), "life": float(e3[3]) / float(e3[0]), "employment": float(e3[1]) / float(e3[0])}
	out["wages"] = wages
	# ---- déficit de necesidades vitales de los pobres
	var w := maxf(1.0, float(poor_def["weight"]))
	var td := maxf(0.0001, float(poor_def["total"]))
	out["life"] = {"poor_life": 1.0 - float(poor_def["total"]) / w,
		"share_unemployment": float(poor_def["unemployment"]) / td, "share_low_wages": float(poor_def["low_wages"]) / td,
		"share_shortage": float(poor_def["shortage"]) / td, "share_at_war": float(poor_def["war"]) / td}
	# ---- escaseces
	var sh := []
	var world: Dictionary = gs.market.get("world", {})
	for g in gs.goods:
		if not VMarketSystem.is_available(gs, g):
			continue
		var sup := float(world.get("supply", {}).get(g, 0.0))
		var dem := float(world.get("demand", {}).get(g, 0.0))
		if dem <= 0.0:
			continue
		sh.append({"good": g, "supply": sup, "demand": dem, "fill": minf(1.0, sup / dem), "price": VMarketSystem.price(gs, g) / float(gs.goods[g]["base_price"])})
	sh.sort_custom(func(a, b): return float(a["fill"]) < float(b["fill"]))
	out["shortages"] = sh.slice(0, 10)
	# excedentes: bienes con más oferta que demanda (precio hacia el suelo)
	var gl := sh.duplicate()
	gl.sort_custom(func(a, b): return float(a["supply"]) / maxf(0.001, float(a["demand"])) > float(b["supply"]) / maxf(0.001, float(b["demand"])))
	out["gluts"] = gl.slice(0, 10)
	# ---- naciones
	var big := country_rows.filter(func(r): return float(r["pop"]) > 1e6)
	var by_u := big.duplicate()
	by_u.sort_custom(func(a, b): return float(a["unemp"]) > float(b["unemp"]))
	var by_i := big.duplicate()
	by_i.sort_custom(func(a, b): return float(a["industry"]) > float(b["industry"]))
	var by_l := big.duplicate()
	by_l.sort_custom(func(a, b): return float(a["life"]) < float(b["life"]))
	out["countries"] = {"unemployment": by_u.slice(0, 10), "industry": by_i.slice(0, 10), "poorest": by_l.slice(0, 10)}
	var urban := 0.0
	for tn in URBAN_TYPES:
		urban += float(by_type.get(tn, [0.0])[0])
	out["urban"] = urban / maxf(1.0, total)
	out["investment"] = {"reasons": gs.market.get("_inv_reasons", {}).duplicate(), "stats": gs.market.get("_inv_stats", {}).duplicate()}
	var mig := {"migrated": 0, "emigrated": 0}
	for tag in gs.living_countries():
		var m: Dictionary = gs.countries[tag].get("acc_mobility_last", {})
		mig["migrated"] += int(m.get("migrated", 0))
		mig["emigrated"] += int(m.get("emigrated", 0))
	out["migration"] = mig
	return out


## Informe legible de una instantánea (para pruebas de largo plazo).
static func report(snap: Dictionary, prev: Dictionary = {}, years: float = 1.0) -> String:
	var L: Dictionary = snap["labour"]
	var F: Dictionary = snap["factories"]
	var C: Dictionary = snap["capital"]
	var lines := []
	lines.append("  trabajo: población %.0f M · paro %.1f%% · urbanización %.1f%%" % [float(L["population"]) / 1e6, float(L["unemployment"]) * 100.0, float(snap["urban"]) * 100.0])
	lines.append("  RGO: trabajadores %.1f M · plazas %.1f M · ocupadas %.1f M (utilización %.0f%%) · paro rural %.1f%%" % [
		float(L["rgo_workers"]) / 1e6, float(L["rgo_capacity"]) / 1e6, float(L["rgo_employed"]) / 1e6, float(L["rgo_utilisation"]) * 100.0, float(L["rgo_unemployment"]) * 100.0])
	lines.append("  fábricas: obreros %.1f M (paro %.1f%%) · plazas %.1f M (ocupadas %.0f%%) · oficinistas %.1f M (paro %.1f%%) · plazas %.2f M" % [
		float(L["craftsmen"]) / 1e6, float(L["craftsmen_unemployment"]) * 100.0, float(F["craft_capacity"]) / 1e6, float(F["utilisation"]) * 100.0,
		float(L["clerks"]) / 1e6, float(L["clerks_unemployment"]) * 100.0, float(F["clerk_capacity"]) / 1e6])
	lines.append("  artesanos %.1f M (paro %.1f%%) · empleo estatal %.1f M · magos %.0f (paro %.0f%%, plazas en fábricas %.0f)" % [
		float(L["artisans"]) / 1e6, float(L["artisans_unemployment"]) * 100.0, float(L["state_workers"]) / 1e6, float(L["magi"]), float(L["magi_unemployment"]) * 100.0, float(F["magi_capacity"])])
	lines.append("  fábricas abiertas %d (cerradas %d) · niveles %d · al nivel máximo %d · particiones llenas %d/%d · mágicas %d" % [
		F["open"], F["closed"], F["levels"], F["at_max_level"], F["states_full"], F["states"], F["magic"]])
	var st: Dictionary = snap["investment"]["stats"]
	var pst: Dictionary = prev.get("investment", {}).get("stats", {})
	var per := []
	for k in ["private_started", "government_started", "rgo_started", "new_factories", "expansions", "rgo_completed"]:
		per.append("%s %.1f" % [k, (float(st.get(k, 0.0)) - float(pst.get(k, 0.0))) / years])
	lines.append("  proyectos/año: " + ", ".join(per) + " · activos %d (privados %d, Estado %d, RGO %d, parados %d)" % [C["projects"], C["private"], C["government"], C["rgo"], C["stalled"]])
	lines.append("  capital: capitalistas %.0f · aristócratas %.0f" % [C["capitalists"], C["aristocrats"]])
	var rs: Dictionary = snap["investment"]["reasons"]
	var prs: Dictionary = prev.get("investment", {}).get("reasons", {})
	var rr := []
	var rtot := 0.0
	for k in rs:
		rtot += float(rs[k]) - float(prs.get(k, 0))
	for k in rs:
		var v := float(rs[k]) - float(prs.get(k, 0))
		if v > 0.0:
			rr.append([v, k])
	rr.sort_custom(func(a, b): return a[0] > b[0])
	var rtxt := []
	for e in rr:
		rtxt.append("%s %.0f%%" % [e[1], e[0] / maxf(1.0, rtot) * 100.0])
	lines.append("  sin inversión privada (meses-nación): " + ", ".join(rtxt))
	var lf: Dictionary = snap["life"]
	lines.append("  necesidades vitales de los pobres %.2f · déficit: paro %.0f%% · salarios bajos %.0f%% · escasez %.0f%% · (en guerra %.0f%%)" % [
		lf["poor_life"], float(lf["share_unemployment"]) * 100.0, float(lf["share_low_wages"]) * 100.0, float(lf["share_shortage"]) * 100.0, float(lf["share_at_war"]) * 100.0])
	var wl := []
	for tn in snap["wages"]:
		var w: Dictionary = snap["wages"][tn]
		wl.append("%s %.0f (vida %.2f, empleo %.0f%%)" % [tn, w["income"], w["life"], float(w["employment"]) * 100.0])
	lines.append("  renta/10k: " + ", ".join(wl))
	var sl := []
	for e in snap["shortages"]:
		sl.append("%s %.0f%% (×%.2f)" % [e["good"], float(e["fill"]) * 100.0, e["price"]])
	lines.append("  escaseces: " + ", ".join(sl))
	var gtx := []
	for e in snap.get("gluts", []):
		gtx.append("%s oferta/demanda %.1f (×%.2f)" % [e["good"], float(e["supply"]) / maxf(0.001, float(e["demand"])), e["price"]])
	lines.append("  excedentes: " + ", ".join(gtx))
	for k in ["unemployment", "industry", "poorest"]:
		var cl := []
		for r in snap["countries"][k]:
			cl.append("%s %s" % [r["tag"], ("%.0f%%" % (float(r["unemp"]) * 100.0)) if k == "unemployment" else (("%.1f niv/M" % float(r["industry"])) if k == "industry" else ("%.2f" % float(r["life"])))])
		lines.append("  top %s: %s" % [k, ", ".join(cl)])
	lines.append("  migración (último mes): interna %d · emigración %d" % [snap["migration"]["migrated"], snap["migration"]["emigrated"]])
	return "\n".join(lines)
