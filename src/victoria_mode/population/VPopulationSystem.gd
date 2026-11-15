class_name VPopulationSystem
extends RefCounted
## POPs: generación inicial, compra de necesidades y consecuencias sociales.
##
## Los datos viven en VPopStore (gs.pops, estructura de arrays; un POP = un slot entero). Este sistema solo
## contiene reglas. Ciclo de un POP (una vez al mes, repartido por cubos de provincias, ver VWorldSimulation):
##   trabajo (VProductionSystem) → renta (salario/beneficio/sueldo estatal, menos impuestos)
##   → compra necesidades: vida → diario → lujo (con el efectivo disponible y el llenado del mercado)
##   → ahorra/deposita el resto → crecimiento, alfabetización, conciencia, militancia, ideología, issues
##   → promoción/democión y migración (VMobilitySystem).
##
## Las cestas de necesidades están en pop_types.json (cantidades por 10.000 personas y mes).

const TIERS := ["life", "everyday", "luxury"]
const POP_UNIT := 10000.0
const EMPTY_D := {}
## Componentes de la militancia que se acumulan en el diagnóstico (gs.market["mil_diag"]).
const MIL_PARTS := ["life", "everyday", "unemployment", "luxury", "base_decay", "relaxation", "movement",
	"war_exhaustion", "modifiers", "reforms"]


# ------------------------------------------------------------ generación
static func generate_initial(gs: VGameState) -> void:
	var dist: Dictionary = gs.pop_distribution
	var headroom := float(dist.get("factory_staff_headroom", 1.05))
	# plazas de fábrica por provincia (obreros y oficinistas se reparten según población)
	var staff := {}
	for key in gs.state_instances:
		var si: Dictionary = gs.state_instances[key]
		var cr := 0.0
		var cl := 0.0
		for f in si["factories"]:
			var wf: Dictionary = gs.factory_types.get(f["type"], {}).get("workforce", {})
			cr += float(wf.get("craftsmen", 9000)) * int(f["level"])
			cl += float(wf.get("clerks", 1000)) * int(f["level"])
		if cr <= 0.0:
			continue
		var tot := 0.0
		for id in si["provinces"]:
			tot += float(gs.provinces[id]["population"])
		for id in si["provinces"]:
			var w := float(gs.provinces[id]["population"]) / maxf(1.0, tot)
			staff[id] = {"craftsmen": cr * w * headroom, "clerks": cl * w * headroom}
	for id in range(1, gs.first_sea_id):
		var p: Dictionary = gs.provinces[id]
		var total := int(p.get("base_population", p["population"]))
		var owner: String = p["owner"]
		var shares := {}
		var civilized := false
		if owner == "":
			shares = dist.get("unowned", {}).duplicate()
		else:
			civilized = gs.countries[owner].get("civilized", true)
			shares = dist.get("civilized" if civilized else "uncivilized", {}).duplicate()
			if int(gs.countries[owner].get("reforms", {}).get("slavery", 1)) == 0:
				shares["slaves"] = float(dist.get("slaves_if_allowed", 0.05))
		var counts := {}
		var used := 0
		for k in shares:
			counts[k] = int(total * float(shares[k]))
			used += counts[k]
		if staff.has(id):
			for k in ["craftsmen", "clerks"]:
				counts[k] = int(min(staff[id][k], float(total - used) * 0.5))
				used += counts[k]
		var good: Dictionary = gs.goods.get(p["rgo"], {})
		var worker := "farmers" if good.get("rgo", "farm") == "farm" else "labourers"
		counts[worker] = int(counts.get(worker, 0)) + max(0, total - used)
		var lit_base := 0.02 if owner == "" else float(gs.countries[owner]["literacy"])
		p["pop_slots"] = []
		for t in counts:
			if int(counts[t]) < 10:
				continue
			make_pop(gs, t, int(counts[t]), p["culture"], p["religion"], id, lit_base)
		recalc_province(gs, id)


## Crea un POP con los valores iniciales del modelo y devuelve su slot.
static func make_pop(gs: VGameState, type_id: String, size: int, culture: String, religion: String, province_id: int, lit_base: float) -> int:
	var ps := gs.pops
	var pt: Dictionary = gs.pop_types.get(type_id, {})
	var strata: String = pt.get("strata", "poor")
	var s := ps.allocate(gs, type_id, size, culture, religion, province_id)
	var ideo := {}
	for i in gs.ideologies:
		var w := float(gs.ideologies[i].get("strata_affinity", {}).get(strata, 0.0))
		if w > 0.0:
			ideo[i] = w
	_normalize(ideo)
	ps.set_ideology(s, ideo)
	var cash_pc := 0.002 if strata == "poor" else (0.012 if strata == "middle" else 0.06)
	ps.literacy[s] = clampf(lit_base * float(pt.get("literacy_mult", 1.0)), 0.0, 1.0)
	ps.consciousness[s] = 0.5 if strata == "poor" else 1.5
	ps.militancy[s] = 1.0
	ps.cash[s] = float(size) * cash_pc
	return s


static func _normalize(d: Dictionary) -> void:
	var t := 0.0
	for k in d:
		t += float(d[k])
	if t <= 0.0:
		return
	for k in d:
		d[k] = float(d[k]) / t


static func recalc_province(gs: VGameState, id: int) -> void:
	var p: Dictionary = gs.provinces[id]
	var sz := gs.pops.size
	var total := 0
	for s: int in p["pop_slots"]:
		total += sz[s]
	p["population"] = total


static func needs_basket(gs: VGameState, type_id: String, tier: String) -> Dictionary:
	return gs.pop_types.get(type_id, {}).get("needs", {}).get(tier, {})


# ---------------------------------------------------- caché de precios
## Al inicio de cada mes: coste por 10.000 de cada nivel de necesidades (a precio de compra
## con aranceles) y fracción esperada de llenado, por nación y tipo de POP.
## c["_needs_tid"]: matriz plana tipo × 6 [coste vida, diario, lujo, llenado vida, diario, lujo].
static func prepare_month(gs: VGameState) -> void:
	var ps := gs.pops
	var nt := ps.type_names.size()
	var prices: Dictionary = gs.market["price"]
	var all_shares: Dictionary = gs.market.get("import_share", {})
	var all_fills: Dictionary = gs.market.get("fill_buy", {})
	# cestas disponibles (sin bienes bloqueados) como [índice de bien, cantidad], una vez para todas las naciones
	var goods_idx := {}
	var goods_list: Array[String] = []
	var baskets := []
	for t in nt:
		var arr := []
		for i in 3:
			var basket := needs_basket(gs, ps.type_names[t], TIERS[i])
			var gi_list: Array[int] = []
			var q_list: Array[float] = []
			for g in basket:
				if VMarketSystem.is_available(gs, g):
					if not goods_idx.has(g):
						goods_idx[g] = goods_list.size()
						goods_list.append(g)
					gi_list.append(int(goods_idx[g]))
					q_list.append(float(basket[g]))
			arr.append([gi_list, q_list])
		baskets.append(arr)
	var ng := goods_list.size()
	var price_g: Array[float] = []
	price_g.resize(ng)
	for gi in ng:
		price_g[gi] = float(prices[goods_list[gi]])
	var mult_g: Array[float] = []
	mult_g.resize(ng)
	var fill_g: Array[float] = []
	fill_g.resize(ng)
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		if c["provinces"].is_empty():
			continue
		var tariff := float(c["budget"].get("tariffs", 0.0))
		var shares: Dictionary = all_shares.get(tag, {})
		var fills: Dictionary = all_fills.get(tag, {})
		for gi in ng:
			var g: String = goods_list[gi]
			mult_g[gi] = 1.0 + tariff * float(shares.get(g, 0.0))
			fill_g[gi] = float(fills.get(g, 1.0))
		var cache := {}
		var flat: Array[float] = []
		flat.resize(nt * 6)
		for t in nt:
			var costs := [0.0, 0.0, 0.0]
			var fl := [1.0, 1.0, 1.0]
			for i in 3:
				var bk: Array = baskets[t][i]
				var gl: Array[int] = bk[0]
				var ql: Array[float] = bk[1]
				var cost := 0.0
				var got := 0.0
				for j in gl.size():
					var gi: int = gl[j]
					var v := ql[j] * price_g[gi] * mult_g[gi]
					cost += v
					got += v * fill_g[gi]
				costs[i] = cost
				fl[i] = got / cost if cost > 0.0 else 1.0
				flat[t * 6 + i] = cost
				flat[t * 6 + 3 + i] = fl[i]
			cache[ps.type_names[t]] = {"cost": costs, "fill": fl}
		c["_needs"] = cache
		c["_needs_tid"] = flat
		var td: Array[float] = c.get("_td", [] as Array[float])
		if td.size() != nt * 3:
			td = []
			td.resize(nt * 3)
			c["_td"] = td
		c["_agg"] = new_agg(nt)
		c["_vote_rule"] = VPoliticsSystem.vote_rule(gs, tag) if gs.month_index % 3 == 2 else ""


## Al final del mes convierte la demanda agregada por niveles en demanda de bienes concretos.
static func flush_demand(gs: VGameState) -> void:
	var ps := gs.pops
	var nt := ps.type_names.size()
	var baskets := []
	for t in nt:
		var bl := []
		for i in 3:
			var clean := []
			var basket := needs_basket(gs, ps.type_names[t], TIERS[i])
			for g in basket:
				if VMarketSystem.is_available(gs, g):
					clean.append([g, float(basket[g])])
			bl.append(clean)
		baskets.append(bl)
	var acc_all: Dictionary = gs.market["acc_demand"]
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		var td: Array[float] = c.get("_td", [] as Array[float])
		if td.is_empty():
			continue
		if not acc_all.has(tag):
			acc_all[tag] = {}
		var acc: Dictionary = acc_all[tag]
		for t in mini(nt, td.size() / 3):
			for i in 3:
				var units := td[t * 3 + i]
				if units <= 0.0:
					continue
				td[t * 3 + i] = 0.0
				for e in baskets[t][i]:
					var q := float(e[1]) * units
					if q > 0.0:
						acc[e[0]] = float(acc.get(e[0], 0.0)) + q


# ------------------------------------------------- proceso mensual (provincia)
## Compra de necesidades y consecuencias para todos los POPs de una provincia (sobre los arrays del almacén).
static func process_province(gs: VGameState, id: int) -> void:
	var p: Dictionary = gs.provinces[id]
	var owner: String = p["owner"]
	if owner == "":
		_process_unowned(gs, p)
		return
	var ps := gs.pops
	var slots: Array = p["pop_slots"]
	var c: Dictionary = gs.countries[owner]
	var needs: Array[float] = c.get("_needs_tid", [] as Array[float])
	var td: Array[float] = c["_td"]
	var mods: Dictionary = c.get("mods", {})
	var budget: Dictionary = c["budget"]
	var bank_c: Dictionary = c["bank"]
	var deposit_share := float(gs.economy_rules.get("bank_deposit_share", 0.05))
	# alias locales de los arrays (referencias: leer/escribir sin búsquedas)
	var a_type := ps.type_id
	var a_size := ps.size
	var a_cash := ps.cash
	var a_bank := ps.bank
	var a_income := ps.income
	var a_inacc := ps.income_acc
	var a_emp := ps.employment
	var a_lit := ps.literacy
	var a_con := ps.consciousness
	var a_mil := ps.militancy
	var a_life := ps.life
	var a_every := ps.everyday
	var a_lux := ps.luxury
	var a_um := ps.unemployed_months
	var a_push := ps.movement_push
	var t_strata := ps.t_strata
	var t_spend := ps.t_spend
	var t_litf := ps.t_litf
	var t_manual := ps.t_manual
	# efecto del clero en la provincia (educación)
	var clergy := 0
	var total := 0
	var t_clergy := ps.T_CLERGY
	var t_clerks := ps.T_CLERKS
	var t_capit := ps.T_CAPITALISTS
	var t_aristo := ps.T_ARISTOCRATS
	for s: int in slots:
		total += a_size[s]
		if a_type[s] == t_clergy:
			clergy += a_size[s]
	var clergy_eff: float = clampf(float(clergy) / maxf(1.0, float(total)) / 0.016, 0.0, 1.5)
	var edu_factor := (0.2 + float(budget.get("education", 0.0))) * float(c.get("pay_ratio", 1.0))
	var lit_rate := 0.0011 * clergy_eff * edu_factor * (1.0 + float(mods.get("literacy_growth", 0.0)))
	var con_mod := 1.0 + float(mods.get("consciousness_growth", 0.0))
	var mil_mod := float(mods.get("militancy_growth", 0.0))
	var worker_mil := float(mods.get("worker_militancy", 0.0))
	var drift := 0.03 * float(mods.get("ideology_drift", 1.0))
	var socialist := 1.0 + float(mods.get("socialist_drift", 0.0))
	var growth_mod := float(mods.get("pop_growth", 0.0))
	# cansancio bélico → militancia (hook del milestone 3)
	var war_mil := float(c.get("war_exhaustion", 0.0)) / 100.0 * 0.05
	# modificadores temporales de provincia (eventos): crecimiento, militancia, alfabetización, conciencia
	var pmods: Dictionary = p.get("pmods", EMPTY_D)
	if not pmods.is_empty():
		growth_mod += float(pmods.get("pop_growth", 0.0))
		war_mil += float(pmods.get("militancy", 0.0))
		lit_rate *= 1.0 + float(pmods.get("literacy_growth", 0.0))
		con_mod += float(pmods.get("consciousness_growth", 0.0))
	# reformas sociales: el subsidio de paro cubre parte del descontento causado por el paro
	var unemp_relief := clampf(gs.mod(owner, "unemployment_benefit") * float(budget.get("social", 0.0)) * float(c.get("pay_ratio", 1.0)) * float(gs.economy_rules.get("unemployment_relief_factor", 0.0)), 0.0, 0.8)
	var mil_relax := float(gs.economy_rules.get("militancy_relaxation", 0.0))
	var con_relax := float(gs.economy_rules.get("consciousness_relaxation", 0.0))
	var lr := float(p["life_rating"])
	var do_issues := (gs.month_index + id) % 3 == 0
	# consecuencias lentas (crecimiento, alfabetización, conciencia, militancia) cada 2 meses con paso doble
	var do_slow := (gs.month_index + id) % 2 == 0
	# deriva ideológica trimestral, escalonada por provincia (misma velocidad media)
	var do_drift := (gs.month_index + id + 1) % 3 == 0
	var agg: Dictionary = c.get("_agg", {})
	if agg.is_empty():
		agg = new_agg(ps.type_names.size())
		c["_agg"] = agg
	agg["n"] = int(agg["n"]) + 1
	var vote_rule: String = c.get("_vote_rule", "")
	var agg_st: Array[int] = agg["st"]
	# tablas de deriva ideológica e issues (una vez por provincia)
	var ideo_bases := _ideo_bases(gs)
	var irules := _issue_rules(gs)
	var icache: Dictionary = gs.market.get("_issue_base_tid", {})
	if icache.is_empty():
		gs.market["_issue_base_tid"] = icache
	var a_ideo := ps.ideology
	var n_ideo := ps.n_ideo
	var drift_rate := drift * 3.0
	var d_lit_v := 0.0
	var d_con_v := 0.0
	var agg_ty: Array[int] = agg["ty"]
	var spent_total := 0.0
	var life_sum := 0.0
	var unemp_sum := 0.0
	var poor_size := 0.0
	var s_tot := 0
	var s_lit := 0.0
	var s_mil := 0.0
	var s_con := 0.0
	var s_unemp := 0.0
	var s_life := 0.0
	var s_every := 0.0
	# diagnóstico de militancia (contribuciones × tamaño, solo en los pasos lentos)
	var d_life := 0.0
	var d_every := 0.0
	var d_unemp := 0.0
	var d_lux := 0.0
	var d_base := 0.0
	var d_relax := 0.0
	var d_move := 0.0
	var d_war := 0.0
	var d_mods := 0.0
	var d_reform := 0.0
	var d_w := 0.0
	# el diagnóstico se muestrea un mes de cada tres (no afecta a la simulación)
	var diag_on := gs.month_index % 3 == 0
	for s: int in slots:
		var t: int = a_type[s]
		var units := float(a_size[s]) / POP_UNIT
		a_income[s] = a_inacc[s]
		a_inacc[s] = 0.0
		# --- compra de necesidades (costes/llenados planos por país × tipo)
		var nb := t * 6
		var c0 := 0.0
		var c1 := 0.0
		var c2 := 0.0
		var f0 := 1.0
		var f1 := 1.0
		var f2 := 1.0
		if nb + 5 < needs.size():
			c0 = needs[nb] * units
			c1 = needs[nb + 1] * units
			c2 = needs[nb + 2] * units
			f0 = needs[nb + 3]
			f1 = needs[nb + 4]
			f2 = needs[nb + 5]
		var cash := a_cash[s]
		var want_cash := (c0 + c1 + c2) * 1.5
		if cash < want_cash:
			var bank := a_bank[s]
			if bank > 0.0:
				var w: float = minf(bank, want_cash - cash)
				a_bank[s] = bank - w
				cash += w
				bank_c["deposits"] = maxf(0.0, float(bank_c["deposits"]) - w)
		var spend := cash * t_spend[t]
		var tb := t * 3
		var s0 := 0.0
		var s1 := 0.0
		var s2 := 0.0
		# nivel 0 (vida) → 1 (diario) → 2 (lujo); si un nivel no se completa, los siguientes no se compran
		var full_total := c0 + c1 + c2
		var a := 1.0 if c0 <= 0.0 else clampf(spend / c0, 0.0, 1.0)
		td[tb] += units * a
		var paid := c0 * a * f0
		spend -= paid
		cash -= paid
		spent_total += paid
		s0 = a * f0
		if a >= 1.0:
			a = 1.0 if c1 <= 0.0 else clampf(spend / c1, 0.0, 1.0)
			td[tb + 1] += units * a
			paid = c1 * a * f1
			spend -= paid
			cash -= paid
			spent_total += paid
			s1 = a * f1
			if a >= 1.0:
				a = 1.0 if c2 <= 0.0 else clampf(spend / c2, 0.0, 1.0)
				td[tb + 2] += units * a
				paid = c2 * a * f2
				spend -= paid
				cash -= paid
				spent_total += paid
				s2 = a * f2
		var strata: int = t_strata[t]
		# riqueza sobrante: más consumo de lujo (cestas adicionales) y después ahorro bancario
		var reserve := full_total * 2.0
		if s2 >= 0.99 and c2 > 0.0 and cash > reserve:
			var extra := (cash - reserve) * 0.35
			var k := extra / c2
			td[tb + 2] += units * k
			var paid_x := extra * f2
			cash -= paid_x
			spent_total += paid_x
			s2 = 1.0 + minf(1.0, k)
		if strata != 0:
			var excess := cash - reserve * 3.0
			if excess > 0.0:
				var dep := excess * deposit_share
				a_bank[s] += dep
				cash -= dep
				bank_c["deposits"] = float(bank_c["deposits"]) + dep
		a_cash[s] = cash
		var lux: float = minf(1.0, s2)
		a_life[s] = s0
		a_every[s] = s1
		a_lux[s] = lux
		# --- consecuencias
		var life: float = s0
		var every: float = s1
		var unemp := 1.0 - a_emp[s]
		if unemp > 0.1:
			a_um[s] += 1
		else:
			a_um[s] = 0
		if do_slow:
			var annual: float = 0.012 * clampf((life - 0.45) / 0.55, -1.5, 1.0) + (lr - 25.0) * 0.0004 + growth_mod
			if life < 0.25:
				annual -= 0.02
			a_size[s] = maxi(1, int(round(float(a_size[s]) * (1.0 + annual / 6.0))))
			var lit := a_lit[s]
			a_lit[s] = clampf(lit + 2.0 * lit_rate * (1.0 - lit) * t_litf[t], 0.0, 1.0)
			var con := a_con[s]
			# (M3.2) relajación proporcional: la conciencia tiende a un equilibrio que crece con la alfabetización y la
			# pobreza, en lugar de crecer sin límite hacia 10
			con += 2.0 * (0.03 * lit * con_mod + 0.04 * maxf(0.0, 0.8 - life) + 0.02 * maxf(0.0, 0.5 - every) + 0.01 * unemp - 0.02 - con_relax * con)
			con = clampf(con, 0.0, 10.0)
			a_con[s] = con
			var mil := a_mil[s]
			# contribuciones a la militancia (por paso de 1 mes; el paso lento las duplica)
			var m_life := 0.06 * maxf(0.0, 0.5 - life)
			var m_every := 0.02 * maxf(0.0, 0.3 - every) * (con / 5.0)
			var m_unemp_raw := 0.03 * unemp * (con / 5.0)
			var m_reform := -m_unemp_raw * unemp_relief
			var m_lux := -0.02 * lux
			var m_mods := mil_mod * 0.1 + (worker_mil if t_manual[t] else 0.0)
			var m_push := a_push[s]
			# relajación: el descontento se disipa en proporción a su nivel (equilibrio estable, no deriva)
			var m_relax := -mil_relax * mil
			var dmil := m_life + m_every + m_unemp_raw + m_reform + m_lux - 0.015 + m_mods + m_push + war_mil + m_relax
			a_mil[s] = clampf(mil + 2.0 * dmil, 0.0, 10.0)
			if diag_on:
				var fw := float(a_size[s])
				d_life += m_life * fw
				d_every += m_every * fw
				d_unemp += m_unemp_raw * fw
				d_reform += m_reform * fw
				d_lux += m_lux * fw
				d_base += -0.015 * fw
				d_relax += m_relax * fw
				d_move += m_push * fw
				d_war += war_mil * fw
				d_mods += m_mods * fw
				d_w += fw
			d_lit_v = lit
			d_con_v = con
		else:
			d_lit_v = a_lit[s]
			d_con_v = a_con[s]
		if do_drift:
			# deriva ideológica en línea (= _drift_ideology) con las tablas por estrato leídas una vez
			var entry: Array = ideo_bases[strata]
			var lit_d := d_lit_v
			var a_soc := 0.4 * maxf(0.0, 0.6 - every) * socialist if (lit_d > 0.15 and strata != 2) else 0.0
			var add1 := 0.3 * lit_d
			var add2 := 0.1 * d_con_v / 10.0 + 0.05 * lit_d
			var add4 := 0.25 * (1.0 - lit_d)
			var dtotal := float(entry[2]) + add1 + add2 + a_soc + add4
			if dtotal > 0.0:
				var keep := 1.0 - drift_rate
				var k_rate := drift_rate / dtotal
				var bvals: Array[float] = entry[0]
				var bslots: Array[int] = entry[1]
				var ib := s * n_ideo
				for i in n_ideo:
					var extra := 0.0
					match bslots[i]:
						1:
							extra = add1
						2:
							extra = add2
						3:
							extra = a_soc
						4:
							extra = add4
					a_ideo[ib + i] = a_ideo[ib + i] * keep + (bvals[i] + extra) * k_rate
		if do_issues:
			update_issues_fast(gs, ps, s, owner, irules, icache)
		var sz: int = a_size[s]
		if vote_rule != "":
			_agg_pop(gs, agg, s, t, vote_rule, sz)
		elif t == t_clergy:
			agg["clergy_lit"] = float(agg["clergy_lit"]) + float(sz) * a_lit[s]
		elif t == t_clerks:
			agg["clerks_lit"] = float(agg["clerks_lit"]) + float(sz) * a_lit[s]
		elif t == t_capit:
			agg["capitalists"].append(s)
		elif t == t_aristo:
			agg["aristocrats"].append(s)
		agg_st[strata] += sz
		agg_ty[t] += sz
		var fs := float(sz)
		s_tot += sz
		s_lit += a_lit[s] * fs
		s_mil += a_mil[s] * fs
		s_con += a_con[s] * fs
		s_unemp += unemp * fs
		s_life += life * fs
		s_every += every * fs
		if strata == 0:
			life_sum += life * fs
			unemp_sum += unemp * fs
			poor_size += fs
	agg["total"] = int(agg["total"]) + s_tot
	agg["lit"] = float(agg["lit"]) + s_lit
	agg["mil"] = float(agg["mil"]) + s_mil
	agg["con"] = float(agg["con"]) + s_con
	agg["unemp"] = float(agg["unemp"]) + s_unemp
	agg["life"] = float(agg["life"]) + s_life
	agg["every"] = float(agg.get("every", 0.0)) + s_every
	if d_w > 0.0:
		var diag: Array[float] = gs.market.get("mil_diag_acc", [] as Array[float])
		if diag.size() != MIL_PARTS.size() + 1:
			diag = []
			diag.resize(MIL_PARTS.size() + 1)
			gs.market["mil_diag_acc"] = diag
		diag[0] += d_life
		diag[1] += d_every
		diag[2] += d_unemp
		diag[3] += d_lux
		diag[4] += d_base
		diag[5] += d_relax
		diag[6] += d_move
		diag[7] += d_war
		diag[8] += d_mods
		diag[9] += d_reform
		diag[10] += d_w
	VMoney.destroyed(gs, spent_total, "pop_purchases")
	p["population"] = s_tot  # (= recalc_province: suma de tamaños tras el crecimiento)
	p["avg_life"] = life_sum / poor_size if poor_size > 0.0 else 1.0
	p["unemployment"] = unemp_sum / poor_size if poor_size > 0.0 else 0.0


## Diagnóstico de militancia del último mes completo: contribución media mensual por componente
## (ponderada por población; positivo = sube la militancia). Lo cierra VWorldSimulation.on_month.
static func close_militancy_diagnosis(gs: VGameState) -> void:
	var diag: Array[float] = gs.market.get("mil_diag_acc", [] as Array[float])
	if diag.size() != MIL_PARTS.size() + 1 or diag[MIL_PARTS.size()] <= 0.0:
		return
	var w := diag[MIL_PARTS.size()]
	var out := {}
	var net := 0.0
	for i in MIL_PARTS.size():
		out[MIL_PARTS[i]] = diag[i] / w
		net += diag[i] / w
		diag[i] = 0.0
	out["net"] = net
	diag[MIL_PARTS.size()] = 0.0
	gs.market["mil_diag"] = out


static func _process_unowned(gs: VGameState, p: Dictionary) -> void:
	var ps := gs.pops
	var lr := float(p["life_rating"])
	var annual := 0.003 + (lr - 25.0) * 0.0003
	for s: int in p["pop_slots"]:
		ps.life[s] = 0.8
		ps.everyday[s] = 0.1
		ps.luxury[s] = 0.0
		ps.size[s] = maxi(1, int(round(float(ps.size[s]) * (1.0 + annual / 12.0))))
	recalc_province(gs, int(p["id"]))


## Deriva ideológica hacia un objetivo que depende de estrato, alfabetización, necesidades y conciencia
## (sobre la matriz plana de ideologías; sin diccionarios).
static func _drift_ideology(gs: VGameState, s: int, strata: int, lit: float, con: float, every: float, rate: float, socialist: float) -> void:
	var ps := gs.pops
	var bases := _ideo_bases(gs)
	var entry: Array = bases[strata]
	var a_soc := 0.4 * maxf(0.0, 0.6 - every) * socialist if (lit > 0.15 and strata != 2) else 0.0
	var add0 := 0.0
	var add1 := 0.3 * lit
	var add2 := 0.1 * con / 10.0 + 0.05 * lit
	var add4 := 0.25 * (1.0 - lit)
	var total := float(entry[2]) + add1 + add2 + a_soc + add4
	if total <= 0.0:
		return
	var ideo := ps.ideology
	var base := s * ps.n_ideo
	var keep := 1.0 - rate
	var k_rate := rate / total
	var vals: Array[float] = entry[0]
	var slots_k: Array[int] = entry[1]
	for i in ps.n_ideo:
		var extra := add0
		match slots_k[i]:
			1:
				extra = add1
			2:
				extra = add2
			3:
				extra = a_soc
			4:
				extra = add4
		ideo[base + i] = ideo[base + i] * keep + (vals[i] + extra) * k_rate


## Tablas de deriva por estrato: [bases por ideología, ranura (0 ninguna, 1 liberal, 2 radical, 3 socialista,
## 4 tradicionalista), total].
static func _ideo_bases(gs: VGameState) -> Array:
	var bases: Array = gs.market.get("_ideo_base_tid", [])
	if bases.is_empty():
		var ps := gs.pops
		for st in VPopStore.STRATA.size():
			var vals: Array[float] = []
			var slots_k: Array[int] = []
			var tot := 0.0
			for i in ps.ideo_names:
				var v := float(gs.ideologies[i].get("strata_affinity", {}).get(VPopStore.STRATA[st], 0.0))
				vals.append(v)
				slots_k.append(int({"liberal": 1, "radical": 2, "socialista": 3, "tradicionalista": 4}.get(i, 0)))
				tot += v
			bases.append([vals, slots_k, tot])
		gs.market["_ideo_base_tid"] = bases
	return bases


## Nombre de la ideología dominante de un POP.
static func dominant_ideology(gs: VGameState, s: int) -> String:
	var k := gs.pops.dominant_ideology(s)
	return gs.pops.ideo_names[k] if k >= 0 else ""


## Posición preferida en cada cuestión: ideología dominante → sesgo del tipo → reglas condicionales.
## El resultado solo depende de (ideología dominante, tipo, máscara de reglas que se cumplen): se comparte
## entre POPs como diccionario de solo lectura.
static func update_issues(gs: VGameState, s: int, tag: String) -> void:
	var cache: Dictionary = gs.market.get("_issue_base_tid", {})
	if cache.is_empty():
		gs.market["_issue_base_tid"] = cache
	update_issues_fast(gs, gs.pops, s, tag, _issue_rules(gs), cache)


static func update_issues_fast(gs: VGameState, ps: VPopStore, s: int, tag: String, rules: Array, cache: Dictionary) -> void:
	var dom := ps.dominant_ideology(s)
	var t: int = ps.type_id[s]
	var mask := 0
	for ri in rules.size():
		var rule: Array = rules[ri]
		var kinds: PackedInt32Array = rule[2]
		var vals: PackedFloat64Array = rule[3]
		var ok := true
		for i in kinds.size():
			var v := vals[i]
			match kinds[i]:
				0:
					ok = ps.life[s] <= v
				1:
					ok = ps.life[s] >= v
				2:
					ok = ps.everyday[s] <= v
				3:
					ok = ps.literacy[s] >= v
				4:
					ok = ps.consciousness[s] >= v
				5:
					ok = ps.militancy[s] >= v
				_:
					ok = VConditions.pop_ok(gs, s, rule[4], tag, {})
			if not ok:
				break
		if ok:
			mask |= 1 << ri
	var key := (dom + 1) * 1000000 + t * 1000 + mask
	var result = cache.get(key)
	if result == null:
		var dom_name: String = ps.ideo_names[dom] if dom >= 0 else ""
		var res: Dictionary = gs.ideologies.get(dom_name, {}).get("issues", {}).duplicate()
		var bias: Dictionary = gs.pop_types.get(ps.type_names[t], {}).get("issue_bias", {})
		for k in bias:
			res[k] = bias[k]
		for ri in rules.size():
			if mask & (1 << ri):
				res[rules[ri][0]] = rules[ri][1]
		res.make_read_only()
		cache[key] = res
		result = res
	ps.issues[s] = result


const _COND_KIND := {"max_life": 0, "min_life": 1, "max_everyday": 2, "min_literacy": 3, "min_consciousness": 4, "min_militancy": 5}


## Reglas condicionales de issues precompiladas: [issue, posición, tipos, valores, condiciones no rápidas].
static func _issue_rules(gs: VGameState) -> Array:
	var rules: Array = gs.market.get("_issue_rules", [])
	if rules.is_empty() and not gs.issue_conditionals.is_empty():
		for rule in gs.issue_conditionals:
			var cond: Dictionary = rule.get("if", {})
			var kinds := PackedInt32Array()
			var vals := PackedFloat64Array()
			var slow := {}
			for ck in cond:
				if _COND_KIND.has(ck):
					kinds.append(int(_COND_KIND[ck]))
					vals.append(float(cond[ck]))
				else:
					slow[ck] = cond[ck]
			if not slow.is_empty():
				kinds.append(9)
				vals.append(0.0)
			rules.append([rule["issue"], rule["position"], kinds, vals, slow])
		gs.market["_issue_rules"] = rules
	return rules


## Estrato de un tipo de POP por nombre.
static func strata_of(gs: VGameState, type_name: String) -> String:
	var t := int(gs.pops.type_index.get(type_name, -1))
	return VPopStore.STRATA[gs.pops.t_strata[t]] if t >= 0 else "poor"


static func new_agg(n_types: int = 0) -> Dictionary:
	var ty: Array[int] = []
	ty.resize(n_types)
	var st: Array[int] = [0, 0, 0]
	return {"n": 0, "st": st, "ty": ty, "total": 0, "lit": 0.0, "mil": 0.0, "con": 0.0, "unemp": 0.0, "life": 0.0,
		"clergy_lit": 0.0, "clerks_lit": 0.0, "capitalists": [], "aristocrats": [], "voters": {}, "vote_total": 0.0}


## Parte del agregado que no son sumas simples (alfabetización del clero/oficinistas, listas de propietarios,
## votos). Las sumas las acumula el llamador.
static func _agg_pop(gs: VGameState, agg: Dictionary, s: int, t: int, vote_rule: String, sz: int) -> void:
	var ps := gs.pops
	if t == ps.T_CLERGY:
		agg["clergy_lit"] = float(agg["clergy_lit"]) + float(sz) * ps.literacy[s]
	elif t == ps.T_CLERKS:
		agg["clerks_lit"] = float(agg["clerks_lit"]) + float(sz) * ps.literacy[s]
	elif t == ps.T_CAPITALISTS:
		agg["capitalists"].append(s)
	elif t == ps.T_ARISTOCRATS:
		agg["aristocrats"].append(s)
	if vote_rule != "":
		var vw := VPoliticsSystem.vote_weight(gs, s, vote_rule)
		if vw > 0.0:
			agg["vote_total"] = float(agg["vote_total"]) + vw
			var voters: Dictionary = agg["voters"]
			var base := s * ps.n_ideo
			for k in ps.n_ideo:
				var v := ps.ideology[base + k]
				if v > 0.0:
					voters[ps.ideo_names[k]] = float(voters.get(ps.ideo_names[k], 0.0)) + v * vw


## Agregados nacionales al cierre del mes. Si el recorrido mensual por cubos cubrió todas las provincias
## de la nación se usan sus acumuladores (sin segunda pasada); si no (inicio, carga, cambios de territorio),
## se recorre la nación entera.
static func refresh_country_caches(gs: VGameState, force_full: bool = false) -> void:
	var ps := gs.pops
	var nt := ps.type_names.size()
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		var agg: Dictionary = c.get("_agg", {})
		if not force_full and not agg.is_empty() and int(agg["n"]) >= c["provinces"].size() and c["provinces"].size() > 0:
			_apply_agg(gs, c, agg, c.get("_vote_rule", "") != "")
			continue
		var full := new_agg(nt)
		var rule := VPoliticsSystem.vote_rule(gs, tag) if (not c["provinces"].is_empty() and (gs.month_index % 3 == 0 or not c.has("voter_ideology"))) else ""
		var st: Array[int] = full["st"]
		var ty: Array[int] = full["ty"]
		for id in c["provinces"]:
			for s: int in gs.provinces[id]["pop_slots"]:
				var t: int = ps.type_id[s]
				var sz: int = ps.size[s]
				_agg_pop(gs, full, s, t, rule, sz)
				st[ps.t_strata[t]] += sz
				ty[t] += sz
				var fs := float(sz)
				full["total"] = int(full["total"]) + sz
				full["lit"] = float(full["lit"]) + ps.literacy[s] * fs
				full["mil"] = float(full["mil"]) + ps.militancy[s] * fs
				full["con"] = float(full["con"]) + ps.consciousness[s] * fs
				full["unemp"] = float(full["unemp"]) + (1.0 - ps.employment[s]) * fs
				full["life"] = float(full["life"]) + ps.life[s] * fs
				full["every"] = float(full.get("every", 0.0)) + ps.everyday[s] * fs
		_apply_agg(gs, c, full, rule != "")


static func _apply_agg(gs: VGameState, c: Dictionary, agg: Dictionary, has_votes: bool) -> void:
	var ps := gs.pops
	var total := int(agg["total"])
	if has_votes and float(agg["vote_total"]) > 0.0:
		var voters: Dictionary = agg["voters"]
		for k in voters:
			voters[k] = float(voters[k]) / float(agg["vote_total"])
		c["voter_ideology"] = voters
	c["_clergy_literacy"] = agg["clergy_lit"]
	c["_clerks_literacy"] = agg["clerks_lit"]
	c["_capitalists"] = agg["capitalists"]
	c["_aristocrats"] = agg["aristocrats"]
	var st: Array[int] = agg["st"]
	c["strata_pop"] = {"poor": st[0], "middle": st[1], "rich": st[2]}
	var types := {}
	var ty: Array[int] = agg["ty"]
	for t in ty.size():
		if ty[t] > 0:
			types[ps.type_names[t]] = ty[t]
	c["type_sizes"] = types
	c["population"] = total
	if total > 0:
		c["literacy"] = float(agg["lit"]) / total
		c["avg_militancy"] = float(agg["mil"]) / total
		c["avg_consciousness"] = float(agg["con"]) / total
		c["unemployment"] = float(agg["unemp"]) / total
		c["avg_life"] = float(agg["life"]) / total
		c["avg_everyday"] = float(agg.get("every", 0.0)) / total


# ------------------------------------------------------- consultas para UI
## Tamaños por "type", "culture" o "religion" (claves con nombre).
static func sizes_by(gs: VGameState, province_ids: Array, field: String = "type") -> Dictionary:
	var ps := gs.pops
	var out := {}
	for id in province_ids:
		for s: int in gs.provinces[id]["pop_slots"]:
			var k: String
			match field:
				"culture":
					k = ps.culture_names[ps.culture_id[s]]
				"religion":
					k = ps.religion_names[ps.religion_id[s]]
				_:
					k = ps.type_names[ps.type_id[s]]
			out[k] = int(out.get(k, 0)) + ps.size[s]
	return out


static func ideology_mix(gs: VGameState, province_ids: Array) -> Dictionary:
	var ps := gs.pops
	var out := {}
	var total := 0.0
	for id in province_ids:
		for s: int in gs.provinces[id]["pop_slots"]:
			var fs := float(ps.size[s])
			total += fs
			for k in ps.n_ideo:
				var v := ps.ideology[s * ps.n_ideo + k]
				if v > 0.0:
					out[ps.ideo_names[k]] = float(out.get(ps.ideo_names[k], 0.0)) + v * fs
	if total > 0.0:
		for k in out:
			out[k] /= total
	return out


static func weighted_average(gs: VGameState, province_ids: Array, field: String) -> float:
	var ps := gs.pops
	var arr: Array
	match field:
		"militancy":
			arr = ps.militancy
		"literacy":
			arr = ps.literacy
		"consciousness":
			arr = ps.consciousness
		"employment":
			arr = ps.employment
		_:
			return 0.0
	var total := 0.0
	var acc := 0.0
	for id in province_ids:
		for s: int in gs.provinces[id]["pop_slots"]:
			var fs := float(ps.size[s])
			total += fs
			acc += float(arr[s]) * fs
	return acc / total if total > 0.0 else 0.0


static func needs_average(gs: VGameState, province_ids: Array, tier: String, type_filter: String = "") -> float:
	var ps := gs.pops
	var arr: Array = ps.life if tier == "life" else (ps.everyday if tier == "everyday" else ps.luxury)
	var tf := int(ps.type_index.get(type_filter, -2)) if type_filter != "" else -1
	var total := 0.0
	var acc := 0.0
	for id in province_ids:
		for s: int in gs.provinces[id]["pop_slots"]:
			if tf != -1 and ps.type_id[s] != tf:
				continue
			var fs := float(ps.size[s])
			total += fs
			acc += float(arr[s]) * fs
	return acc / total if total > 0.0 else 0.0


## Slots de los POPs de una nación.
static func country_pops(gs: VGameState, tag: String) -> Array:
	var out := []
	for id in gs.owned_provinces(tag):
		out.append_array(gs.provinces[id]["pop_slots"])
	return out


## Fusión controlada: POPs de la misma provincia, tipo, cultura y religión con ideología, issues,
## alfabetización, militancia y conciencia parecidas. VMobilitySystem ya traslada personas al POP coincidente,
## así que los duplicados son raros; esta pasada (anual) evita la fragmentación si aparecen.
static func merge_similar(gs: VGameState) -> int:
	var ps := gs.pops
	var merged := 0
	for id in range(1, gs.first_sea_id):
		var p = gs.provinces[id]
		if p == null:
			continue
		var slots: Array = p["pop_slots"]
		if slots.size() < 2:
			continue
		var seen := {}
		for s: int in slots.duplicate():
			if not ps.is_alive(s):
				continue
			var key := ps.type_id[s] * 1000000 + ps.culture_id[s] * 1000 + ps.religion_id[s]
			if not seen.has(key):
				seen[key] = s
				continue
			var d: int = seen[key]
			if _similar(ps, s, d):
				ps.merge(gs, s, d)
				merged += 1
	return merged


static func _similar(ps: VPopStore, a: int, b: int) -> bool:
	if absf(ps.literacy[a] - ps.literacy[b]) > 0.1 or absf(ps.militancy[a] - ps.militancy[b]) > 1.0 or absf(ps.consciousness[a] - ps.consciousness[b]) > 1.0:
		return false
	if not is_same(ps.issues[a], ps.issues[b]) and ps.issues[a] != ps.issues[b]:
		return false
	var diff := 0.0
	for k in ps.n_ideo:
		diff += absf(ps.ideology[a * ps.n_ideo + k] - ps.ideology[b * ps.n_ideo + k])
	return diff <= 0.2
