class_name VMageModel
extends RefCounted
## Población mágica (M5): los magos crecen hacia la CAPACIDAD que la sociedad puede sostener, no a un ritmo fijo.
##
##   objetivo(nación) = población × base_share × f_rama × f_alfabetización × f_potencial × f_fe × (1 + mage_capacity)
##                      + academias × academy_capacity
##     f_rama          sin ramas mágicas ≈ 0 (talentos dispersos); crece con la suma de niveles de las ramas
##     f_alfabetización alfabetización / referencia (acotada)
##     f_potencial     0,5 + fracción de la población que vive en provincias con potencial mágico
##     f_fe            actitud de la religión de Estado × tradición mágica de la cultura principal (datos)
##     mage_capacity   modificador nacional: regulación (reforma magic_regulation), tecnologías, eventos
##
##   promoción mensual = (objetivo − actual) × convergence × (1 + mage_promotion + academias × academy_promotion)
##     solo con rama mágica o academia; se reparte entre POPs fuente alfabetizados de provincias con potencial,
##     ponderada por potencial, religión y cultura del POP. Cerca del objetivo la promoción se apaga sola.
##   por encima del objetivo (× excess_tolerance): no hay promoción; los magos SIN EMPLEO se degradan
##     (demote_to) o emigran si hay naciones que los atraen.
##
## Empleo (no hay magos gratis):
##   · fábricas mágicas: workforce.magi por nivel (VProductionSystem.process_state_instance, salario de fábrica);
##     sin magos, la fábrica produce menos;
##   · plazas del Estado: academias (docencia/investigación, presupuesto de educación), administración mágica
##     (mage_state_posts × población, administración) y ejército (mage_military_posts × soldados).
##   Sin plaza = paro real → necesidades → militancia → emigración → presión política (crisis de magos).
##
## Fuga de cerebros: cada mes se ordenan las naciones que reclutan magos (por debajo de su objetivo) por
## atractivo (regulación → mage_attraction, academias, empleo de magos, nivel de vida, paz). Los magos de
## naciones que los prohíben, persiguen o no les dan trabajo emigran hacia ellas (gancho «mage_brain_drain»).
##
## Estado: c["magic_stats"] (se guarda: contadores acumulados y anuales); c["_magi_info"], c["_magi_state"],
## c["_magi_acc"], c["_mil_extra"] son derivados (se recalculan en un mes).

const STAT_KEYS := ["promoted", "demoted", "emigrated", "immigrated"]


static func rules(gs: VGameState) -> Dictionary:
	return gs.magic_rules.get("mage_model", {})


## Tablas por id de religión y de cultura del almacén de POPs: [promoción_religión, tensión_religión, promoción_cultura].
static func faith_tables(gs: VGameState) -> Array:
	var ps := gs.pops
	var cache: Array = gs.market.get("_magic_faith", [])
	if cache.size() == 3 and (cache[0] as Array).size() == ps.religion_names.size() and (cache[2] as Array).size() == ps.culture_names.size():
		return cache
	var r := rules(gs)
	var att: Dictionary = r.get("religion_attitudes", {})
	var trad: Dictionary = r.get("culture_traditions", {})
	var rp: Array[float] = []
	var rt: Array[float] = []
	for rn in ps.religion_names:
		var a: Dictionary = att.get(String(gs.religions.get(rn, {}).get("magic_attitude", "accepted")), {})
		rp.append(float(a.get("promotion", 1.0)))
		rt.append(float(a.get("tension", 0.0)))
	var cp: Array[float] = []
	for cn in ps.culture_names:
		cp.append(float(trad.get(culture_tradition(gs, cn), 1.0)))
	cache = [rp, rt, cp]
	gs.market["_magic_faith"] = cache
	return cache


static func culture_tradition(gs: VGameState, culture: String) -> String:
	var cu: Dictionary = gs.cultures.get(culture, {})
	if cu.has("magic_tradition"):
		return String(cu["magic_tradition"])
	return String(gs.culture_groups.get(String(cu.get("group", "")), {}).get("magic_tradition", "common"))


static func religion_attitude(gs: VGameState, religion: String) -> String:
	return String(gs.religions.get(religion, {}).get("magic_attitude", "accepted"))


static func academies(gs: VGameState, tag: String) -> int:
	return int(VScopedState.get_variable(gs, tag, "arcane_academies"))


## Desglose del objetivo de magos de una nación (también para la interfaz y las pruebas).
static func capacity(gs: VGameState, tag: String) -> Dictionary:
	var c: Dictionary = gs.countries[tag]
	var r := rules(gs)
	var pop := country_population(gs, c)
	var bt := VMagicSystem.branch_total(gs, tag)
	var f_branch := float(r.get("no_branch_factor", 0.08)) if bt == 0 else float(r.get("branch_base", 0.3)) + float(r.get("branch_per_level", 0.35)) * bt
	var f_lit := clampf(float(c.get("literacy", 0.0)) / float(r.get("literacy_ref", 0.3)), float(r.get("literacy_min", 0.2)), float(r.get("literacy_max", 2.0)))
	var f_pot := 0.5 + float(c.get("_magic_pot_share", 0.0))
	var att: Dictionary = r.get("religion_attitudes", {}).get(religion_attitude(gs, String(c.get("religion", ""))), {})
	var f_faith := float(att.get("promotion", 1.0)) * float(r.get("culture_traditions", {}).get(culture_tradition(gs, String(c.get("primary_culture", ""))), 1.0))
	var f_policy := maxf(0.05, 1.0 + gs.mod(tag, "mage_capacity"))
	var ac := academies(gs, tag)
	# demanda laboral: con muchos magos sin plaza la sociedad sostiene menos (y viceversa)
	var unemp := float(c.get("_magi_info", {}).get("unemployment", 0.0))
	var f_jobs := 1.0 - float(r.get("jobs_weight", 0.4)) * unemp
	var social := pop * float(r.get("base_share", 0.00025)) * f_branch * f_lit * f_pot * f_faith * f_policy * f_jobs
	var acad := float(ac) * float(r.get("academy_capacity", 3000)) * maxf(0.2, f_policy)
	return {"target": social + acad, "social": social, "academies": ac, "academy_part": acad, "f_branch": f_branch,
		"f_lit": f_lit, "f_potential": f_pot, "f_faith": f_faith, "f_policy": f_policy, "f_jobs": f_jobs}


## Población de la nación (agregado mensual; antes del primer mes, suma de sus provincias).
static func country_population(gs: VGameState, c: Dictionary) -> float:
	if c.get("population") != null and float(c["population"]) > 0.0:
		return float(c["population"])
	var t := 0.0
	for id in c.get("provinces", []):
		t += float(gs.provinces[id]["population"])
	return t


## Promoción deseada este mes (personas) dada la población mágica actual y el objetivo.
static func promotion_amount(gs: VGameState, tag: String, magi: float, target: float) -> int:
	var gap := target - magi
	if gap <= 0.0:
		return 0
	var ac := academies(gs, tag)
	if VMagicSystem.max_branch(gs, tag) < int(gs.magic_rules.get("mage_min_branch", 1)) and ac <= 0:
		return 0
	var r := rules(gs)
	var mult := maxf(0.0, 1.0 + gs.mod(tag, "mage_promotion") + gs.mod(tag, "mage_emergence") * 0.25 + float(ac) * float(r.get("academy_promotion", 0.35)))
	# oportunidad: con magos en paro, pocos se forman (no hay a dónde ir)
	var unemp := float(gs.countries[tag].get("_magi_info", {}).get("unemployment", 0.0))
	mult *= maxf(0.1, 1.0 - 1.5 * unemp)
	if mult <= 0.0:
		return 0
	# naciones pequeñas: un mínimo mensual (sin pasarse del objetivo) para que también converjan
	var n := gap * float(r.get("convergence", 0.035)) * mult
	return int(maxf(n, minf(gap, float(r.get("min_promotion", 30)))))


# ------------------------------------------------------------------ mensual (cubo de la nación)
static func country_monthly(gs: VGameState, tag: String, provs: Array) -> void:
	var c: Dictionary = gs.countries[tag]
	var r := rules(gs)
	var ps := gs.pops
	var mt := ps.T_MAGI
	if mt < 0:
		return
	# 1) empleo del mes que termina (acumulado por las particiones de estado) → paro de magos
	var acc: Array = c.get("_magi_acc_cur", [0.0, 0.0, 0.0, 0.0])
	c["_magi_acc"] = acc
	c["_magi_acc_cur"] = [0.0, 0.0, 0.0, 0.0]
	c["_magi_life"] = float(acc[3]) / float(acc[0]) if float(acc[0]) > 0.0 else 0.8
	var magi := float(c.get("type_sizes", {}).get("magi", 0))
	var employed := float(acc[1]) + float(acc[2])
	var unemp := clampf(1.0 - employed / float(acc[0]), 0.0, 1.0) if float(acc[0]) > 0.0 else 0.0
	# 2) potencial: fracción de la población en provincias con capa mágica
	var pot_pop := 0.0
	for id in provs:
		pot_pop += float(gs.provinces[id]["population"]) * float(gs.provinces[id]["magic"].get("potential", 0.0))
	c["_magic_pot_share"] = clampf(pot_pop / maxf(1.0, country_population(gs, c)), 0.0, 1.0)
	var cap := capacity(gs, tag)
	var target: float = cap["target"]
	var st := _stats(c)
	for k in STAT_KEYS:
		st[k + "_y"] = float(st.get(k + "_y", 0.0)) * (11.0 / 12.0)
	# 3) promoción hacia el objetivo / degradación del exceso sin empleo
	var promo := promotion_amount(gs, tag, magi, target)
	if promo >= int(r.get("min_promotion", 30)):
		var done := _promote(gs, tag, promo, provs)
		_add_stat(st, "promoted", done)
		if done > 0:
			_note_acc(c, "magi", done)
	elif (magi > target * float(r.get("excess_tolerance", 1.1)) and unemp > 0.02) or unemp > float(r.get("unemployment_demotion", 0.35)):
		# exceso sobre el objetivo, o paro alto aunque no haya exceso: los magos sin empleo cambian de oficio
		var excess := maxf(magi - target, magi * (unemp - 0.2))
		var dem := int(minf(excess, magi * unemp) * float(r.get("demotion_rate", 0.03)))
		if dem >= 20:
			_add_stat(st, "demoted", _move_magi(gs, tag, provs, dem, "", String(r.get("demote_to", "clerks"))))
	# 4) fuga de cerebros: empuje = paro + hostilidad legal + pobreza
	var life := float(c.get("_magi_life", 0.8))
	var push := unemp + maxf(0.0, -gs.mod(tag, "mage_attraction")) * 0.5 + maxf(0.0, 0.6 - life)
	if push >= float(r.get("emigration_push_min", 0.2)) and magi > 500.0:
		_emigrate(gs, tag, provs, magi, push)
	# 5) la práctica privada del mes la pagan capitalistas y aristócratas (transferencia, no se crea dinero)
	_charge_practice(gs, c)
	# plazas del Estado y de práctica privada para el mes siguiente
	_state_posts(gs, tag, c, magi, float(acc[1]))
	# 6) tensión religiosa y descontento de los magos → militancia por tipo de POP (VPopulationSystem)
	var share := magi / maxf(1.0, country_population(gs, c))
	var rel_t := float(r.get("religion_attitudes", {}).get(religion_attitude(gs, String(c.get("religion", ""))), {}).get("tension", 0.0))
	var sf := clampf(share / float(r.get("tension_magi_share_ref", 0.0005)), 0.0, 2.0)
	var extra: Array[float] = []
	extra.resize(ps.type_names.size())
	extra[mt] = gs.mod(tag, "magi_militancy") + maxf(0.0, rel_t) * 0.5
	if ps.T_CLERGY >= 0:
		extra[ps.T_CLERGY] = (rel_t + gs.mod(tag, "religious_tension")) * sf
	c["_mil_extra"] = extra
	c["_magi_info"] = {"target": target, "magi": magi, "share": share, "unemployment": unemp, "ratio": magi / target if target > 0.0 else 0.0,
		"posts": float(c.get("_magi_state", {}).get("posts", 0.0)), "private_jobs": float(acc[1]), "state_jobs": float(acc[2]),
		"capacity": cap}


static func _stats(c: Dictionary) -> Dictionary:
	if not c.has("magic_stats"):
		c["magic_stats"] = {}
	return c["magic_stats"]


static func _add_stat(st: Dictionary, k: String, n: int) -> void:
	if n <= 0:
		return
	st[k] = int(st.get(k, 0)) + n
	st[k + "_y"] = float(st.get(k + "_y", 0.0)) + float(n)


static func _note_acc(c: Dictionary, k: String, n: int) -> void:
	var cs: Dictionary = c.get("acc_mobility", {})
	cs[k] = int(cs.get(k, 0)) + n
	c["acc_mobility"] = cs


## Reparte la promoción entre POPs fuente alfabetizados de provincias con potencial (dos pasadas).
static func _promote(gs: VGameState, tag: String, amount: int, provs: Array) -> int:
	var ps := gs.pops
	var r := gs.magic_rules
	var min_lit := float(r.get("mage_min_literacy", 0.25))
	var sources := {}
	for stn in r.get("mage_sources", ["clergy", "clerks"]):
		sources[int(ps.type_index.get(stn, -9))] = true
	var tb := faith_tables(gs)
	var rp: Array[float] = tb[0]
	var cp: Array[float] = tb[2]
	var cands := []
	var total_w := 0.0
	for id in provs:
		var p: Dictionary = gs.provinces[id]
		var pot := float(p["magic"].get("potential", 0.0))
		if pot <= 0.0 or p["controller"] != tag:
			continue
		for s: int in p["pop_slots"]:
			if sources.has(ps.type_id[s]) and ps.literacy[s] >= min_lit and ps.size[s] > 400:
				var w := float(ps.size[s]) * pot * rp[ps.religion_id[s]] * cp[ps.culture_id[s]]
				if w > 0.0:
					cands.append([s, id, w])
					total_w += w
	if total_w <= 0.0:
		return 0
	# de mayor a menor peso, con un mínimo por POP: así la promoción no se pierde repartida en restos
	cands.sort_custom(func(a, b): return float(a[2]) > float(b[2]))
	var max_share := float(rules(gs).get("max_pop_share_per_month", 0.01))
	var done := 0
	var left := amount
	for cd in cands:
		if left < 10:
			break
		var s2: int = cd[0]
		var n := mini(mini(maxi(10, int(ceilf(float(amount) * float(cd[2]) / total_w))), left), int(float(ps.size[s2]) * max_share))
		if n >= 10:
			VMobilitySystem._transfer(gs, s2, gs.provinces[cd[1]], "magi", n)
			done += n
			left -= n
	return done


## POPs de magos de la nación: provincias con potencial (donde surgen) y la capital (donde llegan los inmigrantes).
static func _magi_slots(gs: VGameState, tag: String, provs: Array) -> Array:
	var ps := gs.pops
	var out := []
	var seen := {}
	var lst: Array = provs.duplicate()
	var cap := int(gs.countries[tag].get("capital", -1))
	if cap > 0:
		lst.append(cap)
	for id in lst:
		if seen.has(id):
			continue
		seen[id] = true
		var p: Dictionary = gs.provinces[id]
		if p["owner"] != tag:
			continue
		for s: int in p["pop_slots"]:
			if ps.type_id[s] == ps.T_MAGI and ps.size[s] > 0:
				out.append([s, id])
	return out


## Mueve 'amount' magos (proporcional a cada POP) a otro tipo (degradación) o a otra nación (dest_tag).
static func _move_magi(gs: VGameState, tag: String, provs: Array, amount: int, dest_tag: String, to_type: String = "magi") -> int:
	var ps := gs.pops
	var slots := _magi_slots(gs, tag, provs)
	var total := 0
	for e in slots:
		total += ps.size[e[0]]
	if total <= 0:
		return 0
	var dest := {}
	if dest_tag != "":
		var dc := int(gs.countries[dest_tag].get("capital", -1))
		if dc <= 0:
			return 0
		dest = gs.provinces[dc]
	var done := 0
	for e in slots:
		var s: int = e[0]
		var n := mini(int(float(amount) * float(ps.size[s]) / float(total)), ps.size[s] - 1)
		if n < 10:
			continue
		VMobilitySystem._transfer(gs, s, dest if dest_tag != "" else gs.provinces[e[1]], to_type, n)
		done += n
	if dest_tag != "" and done > 0:
		VPopulationSystem.recalc_province(gs, int(dest["id"]))
	return done


static func _emigrate(gs: VGameState, tag: String, provs: Array, magi: float, push: float) -> void:
	var dests: Array = gs.market.get("_mage_destinations", [])
	if dests.is_empty():
		return
	var own := attractiveness(gs, tag)
	var r := rules(gs)
	for d in dests:
		var dt: String = d[0]
		if dt == tag or float(d[2]) < own + 0.2 or not gs.countries.has(dt) or gs.countries[dt]["provinces"].is_empty():
			continue
		var amount := int(minf(float(d[1]), magi * float(r.get("emigration_rate", 0.03)) * minf(1.5, push)))
		if amount < 50:
			return
		var done := _move_magi(gs, tag, provs, amount, dt)
		if done > 0:
			d[1] = float(d[1]) - done
			_add_stat(_stats(gs.countries[tag]), "emigrated", done)
			_add_stat(_stats(gs.countries[dt]), "immigrated", done)
			if done >= 500:
				gs.log_event(tag, "Fuga de cerebros: %s magos emigran a %s" % [UiTheme.fmt_int(done), gs.country_name(dt)])
				VEventSystem.notify(gs, "mage_brain_drain", {"tag": tag, "target": dt, "amount": done})
		return


## Atractivo de una nación para los magos.
static func attractiveness(gs: VGameState, tag: String) -> float:
	var c: Dictionary = gs.countries[tag]
	var info: Dictionary = c.get("_magi_info", {})
	var v := gs.mod(tag, "mage_attraction") + 0.3 * minf(1.0, float(academies(gs, tag))) + 0.5 * (1.0 - float(info.get("unemployment", 0.0)))
	v += 0.5 * float(c.get("avg_life", 0.8))
	if not c.get("wars", []).is_empty():
		v -= 0.2
	return v


## Mundial (cierre de mes): destinos de la fuga de cerebros = naciones por debajo de su objetivo, por atractivo.
static func world_monthly(gs: VGameState) -> void:
	if not VMagicSystem.is_active(gs):
		return
	var lst := []
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		var info: Dictionary = c.get("_magi_info", {})
		if info.is_empty() or c["provinces"].is_empty():
			continue
		var gap := float(info["target"]) - float(info["magi"])
		if gap > 200.0:
			lst.append([tag, gap * 0.5, attractiveness(gs, tag)])
	lst.sort_custom(func(a, b): return float(a[2]) > float(b[2]))
	gs.market["_mage_destinations"] = lst.slice(0, int(rules(gs).get("destinations", 6)))


## Plazas estatales de magos y su sueldo para el mes siguiente (las paga VProductionSystem por partición).
static func _state_posts(gs: VGameState, tag: String, c: Dictionary, magi: float, private_employed: float) -> void:
	var r := rules(gs)
	var ac := academies(gs, tag)
	var edu := float(ac) * float(r.get("academy_posts", 2500))
	var adm := float(c.get("population", 0)) * maxf(0.0, gs.mod(tag, "mage_state_posts"))
	var mil := float(c.get("type_sizes", {}).get("soldiers", 0)) * maxf(0.0, gs.mod(tag, "mage_military_posts"))
	# práctica privada (sanadores, adivinos, tasadores): la pagan los ricos; crece con su bienestar
	var prac := float(c.get("population", 0)) * float(r.get("practice_share", 0.0001)) * maxf(0.0, 1.0 + gs.mod(tag, "mage_practice")) * clampf(float(c.get("avg_everyday", 0.4)) * 2.0, 0.2, 1.5)
	var posts := edu + adm + mil + prac
	var remaining := maxf(0.0, magi - private_employed)
	var fill := minf(1.0, posts / remaining) if remaining > 0.0 else 0.0
	var ps := gs.pops
	var wage := ps.t_gov_wage[ps.T_MAGI] if ps.T_MAGI >= 0 else 0.0
	var split := {}
	var pay := 0.0
	if posts > 0.0:
		split = {"education": edu / posts, "administration": adm / posts, "military_wages": mil / posts, "practice": prac / posts}
		pay = wage * (split["education"] * VBudgetSystem.gov_pay_factor(c, "education")
			+ split["administration"] * VBudgetSystem.gov_pay_factor(c, "administration")
			+ split["military_wages"] * VBudgetSystem.gov_pay_factor(c, "military")
			+ split["practice"] * float(r.get("practice_pay", 0.6)))
	c["_magi_state"] = {"fill": fill, "pay": pay, "split": split, "posts": posts, "practice": prac}
	# M5.5: las academias consumen reactivos arcanos (laboratorios); lo paga el presupuesto de educación
	if ac > 0 and VMarketSystem.is_available(gs, "arcane_reagents"):
		var q := float(ac) * float(r.get("academy_reagents", 3.0))
		VMarketSystem.add_demand(gs, tag, "arcane_reagents", q)
		var cost := q * VMarketSystem.fill_buy(gs, tag, "arcane_reagents") * VMarketSystem.buy_price(gs, tag, "arcane_reagents")
		if cost > 0.0:
			VMoney.destroyed(gs, cost, "academy_supplies")
			VBudgetSystem.add_expense(gs, tag, "education", cost)
	# investigación arcana: magos de las academias efectivamente empleados
	c["_magi_research"] = minf(edu, remaining) * float(r.get("academy_research", 2.0))


## Cobra a los ricos lo que los magos ganaron en práctica privada (VProductionSystem._pay_magi lo anota).
static func _charge_practice(gs: VGameState, c: Dictionary) -> void:
	var due := float(c.get("_practice_due", 0.0))
	c["_practice_due"] = 0.0
	if due <= 0.0:
		return
	var ps := gs.pops
	var payers: Array = c.get("_capitalists", []) + c.get("_aristocrats", [])
	var wealth := 0.0
	for s in payers:
		wealth += maxf(0.0, ps.cash[s])
	if wealth <= 0.0:
		VMoney.created(gs, due, "magic_practice_unpaid")
		return
	var paid := minf(due, wealth * 0.5)
	for s in payers:
		ps.cash[s] -= paid * maxf(0.0, ps.cash[s]) / wealth
	if paid < due:
		VMoney.created(gs, due - paid, "magic_practice_unpaid")


## Fuga forzada por eventos (persecución, exilio): fracción de los magos de la nación.
static func force_emigration(gs: VGameState, tag: String, fraction: float) -> int:
	var magi := float(gs.countries[tag].get("type_sizes", {}).get("magi", 0))
	var dests: Array = gs.market.get("_mage_destinations", [])
	var provs := VMagicSystem.country_magic_provinces(gs, tag)
	for d in dests:
		if d[0] != tag:
			var done := _move_magi(gs, tag, provs, int(magi * fraction), d[0])
			_add_stat(_stats(gs.countries[tag]), "emigrated", done)
			_add_stat(_stats(gs.countries[d[0]]), "immigrated", done)
			return done
	return 0
