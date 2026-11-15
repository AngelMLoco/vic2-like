class_name VMobilitySystem
extends RefCounted
## Movilidad social y migración.
##
## Promoción/democión: reglas de data/victoria_mode/pops/promotion.json evaluadas con VConditions.
##   Las reglas con 'vacancy' quedan limitadas por las plazas libres reales (fábricas, RGO, Estado).
## Migración interna: POPs con paro o necesidades vitales insatisfechas se mudan a la provincia más
##   atractiva de su nación (empleo libre, vida de los pobres, infraestructura, militancia).
## Emigración internacional: POPs muy pobres y en paro emigran a naciones atractivas que los aceptan
##   según la política de ciudadanía del partido gobernante (residency / limited / full).

const STRATA_ORDER := {"poor": 0, "middle": 1, "rich": 2}
const MIN_MOVE := 20
const EMPTY := []
const MIGRANT_JOBS := {"rgo_farm": true, "rgo_mine": true, "factory_worker": true, "factory_clerk": true, "artisan": true}


## Reglas por tipo de origen, precompiladas: [destino, tasa, condiciones compiladas, clave de plaza o ""].
static func _rules_by_type(gs: VGameState) -> Dictionary:
	var cache: Dictionary = gs.market.get("_promotion_cache", {})
	if cache.is_empty():
		for r in gs.promotion_rules:
			if not cache.has(r["from"]):
				cache[r["from"]] = []
			var cond: Dictionary = r.get("conditions", {})
			cache[r["from"]].append([String(r["to"]), float(r.get("rate", 0.01)), VConditions.compile_pop(cond), String(cond.get("vacancy", ""))])
		gs.market["_promotion_cache"] = cache
	return cache


# ------------------------------------------------ proceso mensual (provincia)
static func process_province(gs: VGameState, id: int) -> void:
	var p: Dictionary = gs.provinces[id]
	var tag: String = p["owner"]
	if tag == "":
		return
	# cada provincia evalúa movilidad cada 2 meses (escalonado) con tasas dobles: mismo ritmo, mitad de coste
	if (gs.month_index + id) % 2 == 1:
		return
	var c: Dictionary = gs.countries[tag]
	var rules := _rules_by_type(gs)
	var vac := _vacancies(gs, p, tag, c)
	var ctx := {"vacancy": vac, "civilized": c.get("civilized", true), "military_spending": float(c["budget"].get("military", 0.0))}
	var stats: Dictionary = c["acc_mobility"]
	var moves := []
	var rgo_wt := VProductionSystem.rgo_worker_type(gs, p["rgo"])
	for pop in p["pops"]:
		var t: String = pop["type"]
		var rl: Array = rules.get(t, EMPTY)
		if rl.is_empty() or int(pop["size"]) < MIN_MOVE * 2:
			continue
		for rule in rl:
			var target: String = rule[0]
			var vkey: String = rule[3]
			if vkey == "rgo":
				vac["rgo"] = int(p.get("rgo_free", 0)) if rgo_wt == target else 0
			if not VConditions.pop_ok_compiled(gs, pop, rule[2], tag, ctx):
				continue
			var amount := int(float(pop["size"]) * minf(1.0, float(rule[1]) * 2.0))
			if vkey != "":
				amount = mini(amount, int(vac.get(vkey, 0)))
			if amount < MIN_MOVE:
				continue
			moves.append([pop, target, amount])
			if vkey != "":
				vac[vkey] = int(vac[vkey]) - amount
			break
	for mv in moves:
		var src: Dictionary = mv[0]
		var to: String = mv[1]
		var amount: int = mini(int(mv[2]), int(src["size"]) - 1)
		if amount < MIN_MOVE:
			continue
		var s_from := int(STRATA_ORDER.get(gs.pop_types[src["type"]].get("strata", "poor"), 0))
		var s_to := int(STRATA_ORDER.get(gs.pop_types.get(to, {}).get("strata", "poor"), 0))
		var key := "promoted" if s_to > s_from else ("demoted" if s_to < s_from else "changed_job")
		stats[key] = int(stats.get(key, 0)) + amount
		src["promotion_target"] = to
		_transfer(gs, src, p, to, amount)
		if amount > 3000:
			gs.log_event(tag, "%s %s: %s %s → %s en %s" % [
				{"promoted": "Promoción", "demoted": "Democión", "changed_job": "Cambio de oficio"}[key],
				UiTheme.fmt_int(amount), gs.pop_type_name(src["type"]), "", gs.pop_type_name(to), p["name"]])
	_migrate(gs, p, tag, c, stats)
	VPopulationSystem.recalc_province(gs, id)


static func _vacancies(gs: VGameState, p: Dictionary, tag: String, c: Dictionary) -> Dictionary:
	var si: Dictionary = gs.state_instances.get(gs.state_instance_key(p["state"], tag), {})
	var total := maxf(1.0, float(p["population"]))
	var types := {}
	for pop in p["pops"]:
		types[pop["type"]] = int(types.get(pop["type"], 0)) + int(pop["size"])
	var country_pop := maxf(1.0, float(c.get("population", 1)))
	var ct: Dictionary = c.get("type_sizes", {})
	var mil_target := 0.03 * float(c["budget"].get("military", 0.0)) / 0.5
	var share := 0.0
	if not si.is_empty():
		share = float(p["population"]) / maxf(1.0, float(si.get("_pop", gs.instance_population(si))))
	return {
		"factory_workers": int(float(si.get("vacancy_craftsmen", 0)) * share),
		"factory_clerks": int(float(si.get("vacancy_clerks", 0)) * share),
		"rgo": 0,
		"admin": int(maxf(0.0, 0.008 * country_pop - float(ct.get("bureaucrats", 0))) * total / country_pop),
		"clergy": int(maxf(0.0, 0.02 * total - float(types.get("clergy", 0)))),
		"military": int(maxf(0.0, mil_target * total - float(types.get("soldiers", 0)))),
		"officers": int(maxf(0.0, 0.1 * float(types.get("soldiers", 0)) - float(types.get("officers", 0)))),
	}


## Mueve 'amount' personas de src a un POP del tipo/provincia destino (lo crea si no existe).
static func _transfer(gs: VGameState, src: Dictionary, dest_province: Dictionary, to_type: String, amount: int) -> Dictionary:
	var dst := {}
	for pop in dest_province["pops"]:
		if pop["type"] == to_type and pop["culture"] == src["culture"] and pop["religion"] == src["religion"]:
			dst = pop
			break
	var frac := float(amount) / maxf(1.0, float(src["size"]))
	if dst.is_empty():
		dst = VPopulationSystem.make_pop(gs, to_type, 0, src["culture"], src["religion"], int(dest_province["id"]), 0.0)
		dst["literacy"] = src["literacy"]
		dst["consciousness"] = src["consciousness"]
		dst["militancy"] = src["militancy"]
		dst["ideology"] = src["ideology"].duplicate()
		dst["issues"] = src["issues"].duplicate()
		dst["needs_satisfaction"] = src["needs_satisfaction"].duplicate()
		dst["cash"] = 0.0
		dest_province["pops"].append(dst)
	var w_old := float(dst["size"])
	var w_new := float(amount)
	var tot := maxf(1.0, w_old + w_new)
	for k in ["literacy", "consciousness", "militancy"]:
		dst[k] = (float(dst[k]) * w_old + float(src[k]) * w_new) / tot
	for k in src["ideology"]:
		dst["ideology"][k] = (float(dst["ideology"].get(k, 0.0)) * w_old + float(src["ideology"][k]) * w_new) / tot
	var cash := float(src["cash"]) * frac
	src["cash"] = float(src["cash"]) - cash
	dst["cash"] = float(dst["cash"]) + cash
	src["size"] = int(src["size"]) - amount
	dst["size"] = int(dst["size"]) + amount
	return dst


# ------------------------------------------------------------- migración
static func _migrate(gs: VGameState, p: Dictionary, tag: String, c: Dictionary, stats: Dictionary) -> void:
	var targets: Dictionary = c.get("_migration_targets", {})
	var intl: Array = gs.market.get("_immigration_targets", [])
	# (los traslados añaden POPs a OTRAS provincias: se puede recorrer la lista sin copiarla)
	for pop in p["pops"]:
		var job: String = _job_of(gs, pop["type"])
		if not MIGRANT_JOBS.has(job):
			continue
		var unemp := 1.0 - float(pop["employment"])
		var life := float(pop["needs_satisfaction"]["life"])
		var push := unemp + maxf(0.0, 0.7 - life) + maxf(0.0, 0.15 - float(pop["needs_satisfaction"]["everyday"]))
		if push < 0.15 or int(pop["size"]) < 500:
			continue
		# internacional: solo con pobreza grave
		if life < 0.5 and unemp > 0.2 and not intl.is_empty():
			var amount := int(float(pop["size"]) * minf(0.02, 0.006 * push))
			if amount >= MIN_MOVE:
				for dest_tag in intl:
					if dest_tag == tag or not accepts(gs, dest_tag, pop["culture"]):
						continue
					var dt: Dictionary = gs.countries[dest_tag].get("_migration_targets", {})
					var lst: Array = dt.get(job, dt.get("any", []))
					if lst.is_empty():
						continue
					var dest: Dictionary = gs.provinces[lst[0]]
					_transfer(gs, pop, dest, pop["type"], amount)
					VPopulationSystem.recalc_province(gs, int(dest["id"]))
					pop["migration_target"] = int(dest["id"])
					stats["emigrated"] = int(stats.get("emigrated", 0)) + amount
					var ds: Dictionary = gs.countries[dest_tag]["acc_mobility"]
					ds["immigrated"] = int(ds.get("immigrated", 0)) + amount
					if amount > 2000:
						gs.log_event(tag, "Emigran %s %s de %s a %s" % [UiTheme.fmt_int(amount), gs.pop_type_name(pop["type"]).to_lower(), p["name"], gs.country_name(dest_tag)])
					break
				continue
		# interna
		var cands: Array = targets.get(job, targets.get("any", []))
		for dest_id in cands:
			if int(dest_id) == int(p["id"]):
				continue
			var amount2 := int(float(pop["size"]) * minf(0.03, 0.01 * push))
			if amount2 < MIN_MOVE:
				break
			var dest2: Dictionary = gs.provinces[dest_id]
			_transfer(gs, pop, dest2, pop["type"], amount2)
			VPopulationSystem.recalc_province(gs, int(dest_id))
			pop["migration_target"] = int(dest_id)
			stats["migrated"] = int(stats.get("migrated", 0)) + amount2
			break


static func _job_of(gs: VGameState, type_id: String) -> String:
	var jobs: Dictionary = gs.market.get("_job_by_type", {})
	if jobs.is_empty():
		for t in gs.pop_types:
			jobs[t] = String(gs.pop_types[t].get("job", ""))
		gs.market["_job_by_type"] = jobs
	return jobs.get(type_id, "")


static func accepts(gs: VGameState, tag: String, culture: String) -> bool:
	var c: Dictionary = gs.countries[tag]
	if culture == c["primary_culture"] or culture in c["accepted_cultures"]:
		return true
	var policy: String = VPoliticsSystem.ruling_party(gs, tag).get("policies", {}).get("citizenship_policy", "residency")
	if policy == "full_citizenship":
		return true
	if policy == "limited_citizenship":
		return gs.cultures.get(culture, {}).get("group", "") == gs.cultures.get(c["primary_culture"], {}).get("group", "?")
	return false


## Los n mejores [puntuación, id] por puntuación descendente (selección parcial, sin ordenar todo).
## Desempate como sort_custom estable no garantizado: se conserva el primero encontrado.
static func _top_ids(arr: Array, n: int) -> Array:
	var best := []
	for e in arr:
		var v := float(e[0])
		if best.size() == n and v <= float(best[-1][0]):
			continue
		var i := best.size()
		while i > 0 and float(best[i - 1][0]) < v:
			i -= 1
		best.insert(i, e)
		if best.size() > n:
			best.pop_back()
	var ids := []
	for e in best:
		ids.append(e[1])
	return ids


## Cálculo mensual de destinos: provincias atractivas por tipo de empleo y naciones atractivas.
static func monthly_targets(gs: VGameState) -> void:
	var country_scores := []
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		c["acc_mobility_last"] = c.get("acc_mobility", {})
		c["acc_mobility"] = {}
		if c["provinces"].is_empty():
			continue
		var lists := {"rgo_farm": [], "rgo_mine": [], "factory_worker": [], "factory_clerk": [], "artisan": [], "any": []}
		for id in c["provinces"]:
			var p: Dictionary = gs.provinces[id]
			if p["controller"] != tag:
				continue
			var pop_k := maxf(1.0, float(p["population"]) / 10000.0)
			var base := float(p.get("avg_life", 0.8)) * 0.8 + 0.1 * float(p["infrastructure"]) - float(p.get("unemployment", 0.0))
			var rgo_free := float(p.get("rgo_free", 0)) / 10000.0 / pop_k
			var si: Dictionary = gs.state_instances.get(gs.state_instance_key(p["state"], tag), {})
			var fac_free := float(si.get("vacancy_craftsmen", 0)) / 10000.0 / pop_k
			var wt := VProductionSystem.rgo_worker_type(gs, p["rgo"])
			if rgo_free > 0.02:
				lists["rgo_farm" if wt == "farmers" else "rgo_mine"].append([base + rgo_free, id])
			if fac_free > 0.02:
				lists["factory_worker"].append([base + fac_free, id])
				lists["factory_clerk"].append([base + fac_free * 0.5, id])
			lists["artisan"].append([base, id])
			lists["any"].append([base + rgo_free * 0.5, id])
		var out := {}
		for k in lists:
			out[k] = _top_ids(lists[k], 6)
		c["_migration_targets"] = out
		var att := float(c.get("avg_life", 0.8)) - float(c.get("unemployment", 0.0)) - float(c.get("avg_militancy", 0.0)) * 0.05
		country_scores.append([att, tag])
	country_scores.sort_custom(func(a, b): return a[0] > b[0])
	var intl := []
	for e in country_scores.slice(0, 6):
		intl.append(e[1])
	gs.market["_immigration_targets"] = intl
