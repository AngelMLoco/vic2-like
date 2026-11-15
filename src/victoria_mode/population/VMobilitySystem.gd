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


## Las mismas reglas indexadas por type_id (sin buscar por nombre en cada POP).
static func _rules_by_tid(gs: VGameState) -> Array:
	var arr: Array = gs.market.get("_promotion_by_tid", [])
	if arr.size() != gs.pops.type_names.size():
		var by_name := _rules_by_type(gs)
		arr = []
		for t in gs.pops.type_names:
			arr.append(by_name.get(t, EMPTY))
		gs.market["_promotion_by_tid"] = arr
	return arr


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
	var ps := gs.pops
	var a_size := ps.size
	var rules_t := _rules_by_tid(gs)
	var a_type := ps.type_id
	var a_lit := ps.literacy
	var a_life := ps.life
	var a_every := ps.everyday
	var a_lux := ps.luxury
	var a_emp := ps.employment
	var a_cash := ps.cash
	var a_con := ps.consciousness
	var a_mil := ps.militancy
	for s: int in p["pop_slots"]:
		var rl: Array = rules_t[a_type[s]]
		if rl.is_empty() or a_size[s] < MIN_MOVE * 2:
			continue
		for rule in rl:
			var target: String = rule[0]
			var vkey: String = rule[3]
			if vkey == "rgo":
				vac["rgo"] = int(p.get("rgo_free", 0)) if rgo_wt == target else 0
			# sin plazas libres la regla fallaría igualmente: se descarta sin evaluar sus condiciones
			if vkey != "" and int(vac.get(vkey, 0)) <= 0:
				continue
			# condiciones compiladas evaluadas en línea (= VConditions.pop_ok_compiled) con alias locales
			var ok := true
			for e in rule[2]:
				var code: int = e[0]
				match code:
					0:
						ok = a_lit[s] >= e[1]
					1:
						ok = a_lit[s] <= e[1]
					2:
						ok = a_life[s] >= e[1]
					3:
						ok = a_life[s] <= e[1]
					4:
						ok = a_every[s] >= e[1]
					5:
						ok = a_every[s] <= e[1]
					6:
						ok = a_lux[s] >= e[1]
					7:
						ok = 1.0 - a_emp[s] >= e[1]
					8:
						ok = 1.0 - a_emp[s] <= e[1]
					9:
						ok = a_cash[s] / maxf(1.0, float(a_size[s])) >= e[1]
					10:
						ok = a_cash[s] / maxf(1.0, float(a_size[s])) <= e[1]
					11:
						ok = a_con[s] >= e[1]
					12:
						ok = a_mil[s] >= e[1]
					13:
						ok = a_mil[s] <= e[1]
					14:
						ok = int(vac.get(e[1], 0)) > 0
					_:
						ok = VConditions.pop_ok(gs, s, e[1], tag, ctx)
				if not ok:
					break
			if not ok:
				continue
			var amount := int(float(a_size[s]) * minf(1.0, float(rule[1]) * 2.0))
			if vkey != "":
				amount = mini(amount, int(vac.get(vkey, 0)))
			if amount < MIN_MOVE:
				continue
			moves.append([s, target, amount])
			if vkey != "":
				vac[vkey] = int(vac[vkey]) - amount
			break
	for mv in moves:
		var src: int = mv[0]
		var to: String = mv[1]
		var amount: int = mini(int(mv[2]), a_size[src] - 1)
		if amount < MIN_MOVE:
			continue
		var s_from: int = ps.t_strata[ps.type_id[src]]
		var s_to: int = ps.t_strata[ps.type_of(gs, to)]
		var key := "promoted" if s_to > s_from else ("demoted" if s_to < s_from else "changed_job")
		stats[key] = int(stats.get(key, 0)) + amount
		ps.promotion_target[src] = to
		_transfer(gs, src, p, to, amount)
		if amount > 3000:
			gs.log_event(tag, "%s %s: %s %s → %s en %s" % [
				{"promoted": "Promoción", "demoted": "Democión", "changed_job": "Cambio de oficio"}[key],
				UiTheme.fmt_int(amount), gs.pop_type_name(ps.type_name(src)), "", gs.pop_type_name(to), p["name"]])
	_migrate(gs, p, tag, c, stats)
	VPopulationSystem.recalc_province(gs, id)


static func _vacancies(gs: VGameState, p: Dictionary, tag: String, c: Dictionary) -> Dictionary:
	var si: Dictionary = gs.state_instances.get(gs.state_instance_key(p["state"], tag), {})
	var total := maxf(1.0, float(p["population"]))
	var ps := gs.pops
	var clergy := 0
	var soldiers := 0
	var officers := 0
	for s: int in p["pop_slots"]:
		var t: int = ps.type_id[s]
		if t == ps.T_CLERGY:
			clergy += ps.size[s]
		elif t == ps.T_SOLDIERS:
			soldiers += ps.size[s]
		elif t == ps.T_OFFICERS:
			officers += ps.size[s]
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
		"clergy": int(maxf(0.0, 0.02 * total - float(clergy))),
		"military": int(maxf(0.0, mil_target * total - float(soldiers))),
		"officers": int(maxf(0.0, 0.1 * float(soldiers) - float(officers))),
	}


## Mueve 'amount' personas del POP src a un POP del tipo/provincia destino (lo crea si no existe:
## mismo tipo, cultura y religión → nunca hay dos POPs iguales en una provincia). Devuelve el slot destino.
static func _transfer(gs: VGameState, src: int, dest_province: Dictionary, to_type: String, amount: int) -> int:
	var ps := gs.pops
	var tt := ps.type_of(gs, to_type)
	var cu: int = ps.culture_id[src]
	var re: int = ps.religion_id[src]
	var dst := -1
	for s in dest_province["pop_slots"]:
		if ps.type_id[s] == tt and ps.culture_id[s] == cu and ps.religion_id[s] == re:
			dst = s
			break
	var frac := float(amount) / maxf(1.0, float(ps.size[src]))
	if dst < 0:
		dst = ps.allocate(gs, to_type, 0, ps.culture_names[cu], ps.religion_names[re], int(dest_province["id"]))
		ps.literacy[dst] = ps.literacy[src]
		ps.consciousness[dst] = ps.consciousness[src]
		ps.militancy[dst] = ps.militancy[src]
		for k in ps.n_ideo:
			ps.ideology[dst * ps.n_ideo + k] = ps.ideology[src * ps.n_ideo + k]
		ps.issues[dst] = ps.issues[src]
		ps.life[dst] = ps.life[src]
		ps.everyday[dst] = ps.everyday[src]
		ps.luxury[dst] = ps.luxury[src]
		ps.stats["split"] = int(ps.stats["split"]) + 1
	var w_old := float(ps.size[dst])
	var w_new := float(amount)
	var tot := maxf(1.0, w_old + w_new)
	ps.literacy[dst] = (ps.literacy[dst] * w_old + ps.literacy[src] * w_new) / tot
	ps.consciousness[dst] = (ps.consciousness[dst] * w_old + ps.consciousness[src] * w_new) / tot
	ps.militancy[dst] = (ps.militancy[dst] * w_old + ps.militancy[src] * w_new) / tot
	for k in ps.n_ideo:
		ps.ideology[dst * ps.n_ideo + k] = (ps.ideology[dst * ps.n_ideo + k] * w_old + ps.ideology[src * ps.n_ideo + k] * w_new) / tot
	var cash := ps.cash[src] * frac
	ps.cash[src] -= cash
	ps.cash[dst] += cash
	ps.size[src] -= amount
	ps.size[dst] += amount
	return dst


# ------------------------------------------------------------- migración
static func _migrate(gs: VGameState, p: Dictionary, tag: String, c: Dictionary, stats: Dictionary) -> void:
	var targets: Dictionary = c.get("_migration_targets", {})
	var intl: Array = gs.market.get("_immigration_targets", [])
	# (los traslados añaden POPs a OTRAS provincias: se puede recorrer la lista sin copiarla)
	var ps := gs.pops
	for s: int in p["pop_slots"]:
		var t: int = ps.type_id[s]
		if not ps.t_migrant[t]:
			continue
		var job: String = ps.t_job[t]
		var unemp := 1.0 - ps.employment[s]
		var life := ps.life[s]
		var push := unemp + maxf(0.0, 0.7 - life) + maxf(0.0, 0.15 - ps.everyday[s])
		if push < 0.15 or ps.size[s] < 500:
			continue
		# internacional: solo con pobreza grave
		if life < 0.5 and unemp > 0.2 and not intl.is_empty():
			var amount := int(float(ps.size[s]) * minf(0.02, 0.006 * push))
			if amount >= MIN_MOVE:
				for dest_tag in intl:
					if dest_tag == tag or not accepts(gs, dest_tag, ps.culture_names[ps.culture_id[s]]):
						continue
					var dt: Dictionary = gs.countries[dest_tag].get("_migration_targets", {})
					var lst: Array = dt.get(job, dt.get("any", []))
					if lst.is_empty():
						continue
					var dest: Dictionary = gs.provinces[lst[0]]
					_transfer(gs, s, dest, ps.type_names[t], amount)
					VPopulationSystem.recalc_province(gs, int(dest["id"]))
					ps.migration_target[s] = int(dest["id"])
					stats["emigrated"] = int(stats.get("emigrated", 0)) + amount
					var ds: Dictionary = gs.countries[dest_tag]["acc_mobility"]
					ds["immigrated"] = int(ds.get("immigrated", 0)) + amount
					if amount > 2000:
						gs.log_event(tag, "Emigran %s %s de %s a %s" % [UiTheme.fmt_int(amount), gs.pop_type_name(ps.type_names[t]).to_lower(), p["name"], gs.country_name(dest_tag)])
					break
				continue
		# interna
		var cands: Array = targets.get(job, targets.get("any", []))
		for dest_id in cands:
			if int(dest_id) == int(p["id"]):
				continue
			var amount2 := int(float(ps.size[s]) * minf(0.03, 0.01 * push))
			if amount2 < MIN_MOVE:
				break
			var dest2: Dictionary = gs.provinces[dest_id]
			_transfer(gs, s, dest2, ps.type_names[t], amount2)
			VPopulationSystem.recalc_province(gs, int(dest_id))
			ps.migration_target[s] = int(dest_id)
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
