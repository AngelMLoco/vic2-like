class_name VEventConditions
extends RefCounted
## Condiciones de eventos y decisiones: el JSON se COMPILA al cargar a nodos [código, args…] y se evalúa sin
## interpretar el diccionario (ni eval). VConditions (POPs, inventos) no cambia.
##
## Contexto de evaluación (ctx): {"tag": nación del ámbito, "prov": provincia (ámbito provincia), "state": clave
## de instancia de estado, "target": nación objetivo, "from": nación que origina (on_action)}.
## En ámbito provincia las condiciones de nación se evalúan sobre el propietario.
##
## Esquema (ver docs/VictoriaModeDataSchemas.md → M4):
##   lógica: "and": [..] | {..}, "or": [{..}, ..], "not": {..}, "target": {..} (en la nación objetivo),
##           "owner": {..} (nación propietaria), "any_neighbor": {..}, "count_countries": {"min": n, "where": {..}}
##   numéricas: "<campo>": x  → campo ≥ x ;  "<campo>_below": x → campo < x
##   resto: ver COUNTRY_BOOL / PROVINCE_* abajo.

enum {AND, OR, NOT, TARGET, OWNER, COUNT, ANY_NEIGHBOR,
	CNUM, PNUM, GNUM,
	GFLAG, CFLAG, PFLAG, YEAR, MONTH, TAG, CIVILIZED, GP, SECONDARY, RANK, GOVERNMENT, RULING_IDEO, REFORM,
	HAS_TECH, HAS_INV, AT_WAR, HAS_SPHERE, IN_SPHERE, TARGET_REL, OWNS_PROV, OWNS_STATE, CONTROLS_PROV,
	CONTROLS_STATE, HAS_CORE, FACTORY_TYPE, GOOD_PRICE, GOOD_SHORTAGE, REBEL_RISK, REBEL_FACTION, MAGIC_BRANCH,
	VAR, MOVEMENT, POP_TYPE, IS_PLAYER, HAS_MOD, MAGIC_ANY, P_OWNER_IS, P_CONTROLLER_IS, P_TERRAIN, P_COASTAL,
	P_RGO, P_CULTURE, P_RELIGION, P_OCCUPIED, P_BLOCKADED, P_DEPOSIT, P_STATE, P_CAPITAL, HAS_TARGET, GOOD_AVAILABLE,
	CTX_NUM, CTX_STR, CAP_OCC, MAGIC_REG, REL_ATT, CUL_TRAD, MAGIC_PATH, IS_RIVAL}

## campos numéricos de nación
const CNUM_FIELDS := ["prestige", "military_score", "industry_score", "treasury", "debt", "literacy", "militancy",
	"consciousness", "unemployment", "avg_life", "avg_everyday", "population", "war_exhaustion", "infamy",
	"factory_count", "research_points", "wars", "brigades", "provinces", "magi",
	"magi_share", "magi_unemployment", "magi_target_ratio", "mage_emigration", "mage_immigration", "arcane_academies",
	"immigration", "emigration", "war_months", "magic_factories", "arcane_deposits"]
## campos numéricos de provincia
const PNUM_FIELDS := ["province_population", "province_unemployment", "province_militancy", "life_rating", "fort",
	"naval_base", "infrastructure", "magic_potential", "province_life"]
## campos numéricos globales
const GNUM_FIELDS := ["number_of_wars", "world_literacy", "world_militancy", "world_avg_life", "great_powers_at_war"]

## nombres legibles (tooltips / motivos de no disponibilidad)
const FIELD_NAMES := {"prestige": "prestigio", "military_score": "puntuación militar", "industry_score": "puntuación industrial",
	"treasury": "tesoro", "debt": "deuda", "literacy": "alfabetización", "militancy": "militancia media",
	"consciousness": "conciencia media", "unemployment": "paro", "avg_life": "necesidades vitales",
	"avg_everyday": "necesidades diarias", "population": "población", "war_exhaustion": "cansancio bélico",
	"infamy": "infamia", "factory_count": "fábricas", "research_points": "puntos de investigación", "wars": "guerras activas",
	"brigades": "brigadas", "provinces": "provincias", "magi": "magos",
	"magi_share": "proporción de magos", "magi_unemployment": "paro de los magos", "magi_target_ratio": "magos / capacidad",
	"mage_emigration": "magos emigrados (año)", "mage_immigration": "magos inmigrados (año)", "arcane_academies": "academias arcanas",
	"arcane_deposits": "yacimientos arcanos", "immigration": "inmigrantes (mes)", "emigration": "emigrantes (mes)", "war_months": "meses de guerra", "magic_factories": "fábricas mágicas", "province_population": "población de la provincia",
	"province_unemployment": "paro de la provincia", "province_militancy": "militancia de la provincia",
	"life_rating": "calidad de vida", "fort": "fuerte", "naval_base": "base naval", "infrastructure": "infraestructura",
	"magic_potential": "potencial mágico", "province_life": "necesidades vitales de la provincia",
	"number_of_wars": "guerras en el mundo", "world_literacy": "alfabetización mundial", "world_militancy": "militancia mundial",
	"world_avg_life": "necesidades vitales mundiales", "great_powers_at_war": "grandes potencias en guerra"}


# ------------------------------------------------------------------ compilación
## Compila un diccionario de condiciones. Los errores (clave desconocida, país/bien/tecnología inexistente) se
## añaden a 'errors' con 'where' como contexto. Devuelve el nodo raíz (AND).
static func compile(gs: VGameState, cond, errors: Array, where: String) -> Array:
	var children := []
	if cond is Array:
		for c in cond:
			children.append(compile(gs, c, errors, where))
		return [AND, children]
	if not (cond is Dictionary):
		errors.append("%s: condición no válida (%s)" % [where, str(cond)])
		return [AND, []]
	for k in cond:
		var node := _compile_key(gs, String(k), cond[k], errors, where)
		if not node.is_empty():
			children.append(node)
	return [AND, children]


static func _compile_key(gs: VGameState, k: String, v, errors: Array, where: String) -> Array:
	match k:
		"and":
			return compile(gs, v, errors, where)
		"or":
			var ch := []
			for c in (v if v is Array else [v]):
				ch.append(compile(gs, c, errors, where))
			return [OR, ch]
		"not":
			return [NOT, compile(gs, v, errors, where)]
		"target":
			return [TARGET, compile(gs, v, errors, where)]
		"owner":
			return [OWNER, compile(gs, v, errors, where)]
		"any_neighbor":
			return [ANY_NEIGHBOR, compile(gs, v, errors, where)]
		"count_countries":
			return [COUNT, int(v.get("min", 1)), compile(gs, v.get("where", {}), errors, where)]
		"flag", "global_flag":
			return [GFLAG, String(v), true]
		"not_flag", "not_global_flag":
			return [GFLAG, String(v), false]
		"country_flag":
			return [CFLAG, String(v), true]
		"not_country_flag":
			return [CFLAG, String(v), false]
		"province_flag", "has_province_flag":
			return [PFLAG, String(v), true]
		"not_province_flag":
			return [PFLAG, String(v), false]
		"year":
			return [YEAR, 0, int(v)]
		"year_below":
			return [YEAR, 1, int(v)]
		"month":
			return [MONTH, int(v)]
		"tag":
			var tags: Array = v if v is Array else [v]
			for t in tags:
				if not gs.countries.has(t):
					errors.append("%s: país desconocido «%s»" % [where, t])
			return [TAG, tags]
		"civilized":
			return [CIVILIZED, bool(v)]
		"great_power":
			return [GP, bool(v)]
		"secondary_power":
			return [SECONDARY, bool(v)]
		"rank_above":
			return [RANK, 1, int(v)]
		"rank_below":
			return [RANK, 0, int(v)]
		"government":
			if not gs.governments.has(v):
				errors.append("%s: gobierno desconocido «%s»" % [where, v])
			return [GOVERNMENT, String(v)]
		"ruling_ideology", "ruling_party", "ideology":
			var ideos: Array = v if v is Array else [v]
			var chi := []
			for iv in ideos:
				if not gs.ideologies.has(iv):
					errors.append("%s: ideología desconocida «%s»" % [where, iv])
				chi.append([RULING_IDEO, String(iv)])
			return chi[0] if chi.size() == 1 else [OR, chi]
		"reform_min", "reform_max":
			var ch2 := []
			for rid in v:
				if not gs.reforms.has(rid):
					errors.append("%s: reforma desconocida «%s»" % [where, rid])
				ch2.append([REFORM, String(rid), 0 if k == "reform_min" else 1, int(v[rid])])
			return [AND, ch2]
		"has_technology":
			if not gs.technologies.has(v):
				errors.append("%s: tecnología desconocida «%s»" % [where, v])
			return [HAS_TECH, String(v)]
		"has_invention":
			if not gs.inventions.has(v):
				errors.append("%s: invento desconocido «%s»" % [where, v])
			return [HAS_INV, String(v)]
		"at_war":
			return [AT_WAR, bool(v)]
		"has_sphere":
			return [HAS_SPHERE, bool(v)]
		"in_sphere":
			return [IN_SPHERE, v]
		"has_target":
			return [HAS_TARGET, bool(v)]
		"relation_with_target", "target_relation":
			return [TARGET_REL, 0, int(v)]
		"relation_with_target_below", "target_relation_below":
			return [TARGET_REL, 1, int(v)]
		"owns_province":
			return [OWNS_PROV, int(v)]
		"owns_state":
			return [OWNS_STATE, int(v)]
		"controls_province":
			return [CONTROLS_PROV, int(v)]
		"controls_state":
			return [CONTROLS_STATE, int(v)]
		"has_core":
			return [HAS_CORE, int(v)]
		"factory_type_count":
			var ch3 := []
			for ft in v:
				if not gs.factory_types.has(ft):
					errors.append("%s: tipo de fábrica desconocido «%s»" % [where, ft])
				ch3.append([FACTORY_TYPE, String(ft), int(v[ft])])
			return [AND, ch3]
		"good_price", "good_price_below":
			var ch4 := []
			for g in v:
				if not gs.goods.has(g):
					errors.append("%s: bien desconocido «%s»" % [where, g])
				ch4.append([GOOD_PRICE, String(g), 0 if k == "good_price" else 1, float(v[g])])
			return [AND, ch4]
		"good_shortage":
			var ch5 := []
			var goods_list: Array = v if v is Array else ([v] if v is String else v.keys())
			for g in goods_list:
				if not gs.goods.has(g):
					errors.append("%s: bien desconocido «%s»" % [where, g])
				ch5.append([GOOD_SHORTAGE, String(g), float(v.get(g, 0.8)) if v is Dictionary else 0.8])
			return [AND, ch5]
		"good_available":
			if not gs.goods.has(v):
				errors.append("%s: bien desconocido «%s»" % [where, v])
			return [GOOD_AVAILABLE, String(v)]
		"rebel_risk":
			return [REBEL_RISK, bool(v)]
		"rebel_faction_exists":
			return [REBEL_FACTION, bool(v)]
		"magic_branch":
			var ch6 := []
			for b in v:
				if not (b in VMagicSystem.BRANCHES):
					errors.append("%s: rama mágica desconocida «%s»" % [where, b])
				ch6.append([MAGIC_BRANCH, String(b), int(v[b])])
			return [AND, ch6]
		"magic_any_branch":
			return [MAGIC_ANY, int(v)]
		"variable", "variable_below":
			var ch7 := []
			for n in v:
				ch7.append([VAR, String(n), 0 if k == "variable" else 1, float(v[n])])
			return [AND, ch7]
		"movement_support":
			var ch8 := []
			for rid2 in v:
				if not gs.reforms.has(rid2):
					errors.append("%s: reforma desconocida «%s»" % [where, rid2])
				ch8.append([MOVEMENT, String(rid2), float(v[rid2])])
			return [AND, ch8]
		"pop_type_size":
			var ch9 := []
			for pt in v:
				if not gs.pop_types.has(pt):
					errors.append("%s: tipo de POP desconocido «%s»" % [where, pt])
				ch9.append([POP_TYPE, String(pt), float(v[pt])])
			return [AND, ch9]
		"is_player":
			return [IS_PLAYER, bool(v)]
		"has_modifier":
			return [HAS_MOD, String(v)]
		# ---- provincia
		"owner_is":
			return [P_OWNER_IS, String(v)]
		"controller_is":
			return [P_CONTROLLER_IS, String(v)]
		"terrain":
			var ts: Array = v if v is Array else [v]
			for tr in ts:
				if not gs.terrain_types.has(tr):
					errors.append("%s: terreno desconocido «%s»" % [where, tr])
			return [P_TERRAIN, ts]
		"coastal":
			return [P_COASTAL, bool(v)]
		"rgo":
			if not gs.goods.has(v):
				errors.append("%s: bien desconocido «%s»" % [where, v])
			return [P_RGO, String(v)]
		"culture":
			return [P_CULTURE, String(v)]
		"religion":
			return [P_RELIGION, String(v)]
		"occupied":
			return [P_OCCUPIED, bool(v)]
		"blockaded":
			return [P_BLOCKADED, bool(v)]
		"has_magic_deposit":
			return [P_DEPOSIT, bool(v)]
		"state":
			return [P_STATE, int(v)]
		"is_capital":
			return [P_CAPITAL, bool(v)]
		# M5: contexto de on_action (batallas, paz), capital ocupada, política y sociedad mágicas
		"battle_losses", "battle_losses_below":
			return [CTX_NUM, "losses", 1 if k.ends_with("_below") else 0, float(v)]
		"own_losses", "own_losses_below":
			return [CTX_NUM, "own_losses", 1 if k.ends_with("_below") else 0, float(v)]
		"peace_goals", "peace_goals_below":
			return [CTX_NUM, "goals", 1 if k.ends_with("_below") else 0, float(v)]
		"war_result":
			if not (String(v) in ["victory", "defeat", "white_peace"]):
				errors.append("%s: war_result debe ser victory, defeat o white_peace" % where)
			return [CTX_STR, "result", String(v)]
		"capital_occupied":
			return [CAP_OCC, bool(v)]
		"magic_regulation":
			var idxs := []
			for lid in (v if v is Array else [v]):
				var li := VMagicPolicy.level_index(gs, String(lid))
				if li < 0:
					errors.append("%s: nivel de regulación mágica desconocido «%s»" % [where, lid])
				idxs.append(li)
			return [MAGIC_REG, idxs]
		"religion_magic_attitude":
			for a in (v if v is Array else [v]):
				if not (String(a) in VLoreLoader.MAGIC_ATTITUDES):
					errors.append("%s: actitud mágica desconocida «%s»" % [where, a])
			return [REL_ATT, v if v is Array else [v]]
		"magic_tradition":
			return [CUL_TRAD, v if v is Array else [v]]
		"magic_path":
			var chp := []
			for b in v:
				chp.append([MAGIC_PATH, String(b), String(v[b])])
			return [AND, chp]
		"is_rival":
			return [IS_RIVAL, bool(v)]
	# numéricos con sufijo _below
	var below := k.ends_with("_below")
	var base := k.trim_suffix("_below") if below else k
	if base in CNUM_FIELDS:
		return [CNUM, CNUM_FIELDS.find(base), 1 if below else 0, float(v)]
	if base in PNUM_FIELDS:
		return [PNUM, PNUM_FIELDS.find(base), 1 if below else 0, float(v)]
	if base in GNUM_FIELDS:
		return [GNUM, GNUM_FIELDS.find(base), 1 if below else 0, float(v)]
	errors.append("%s: condición desconocida «%s»" % [where, k])
	return []


# ------------------------------------------------------------------ evaluación
static func check(gs: VGameState, node: Array, ctx: Dictionary) -> bool:
	match int(node[0]):
		AND:
			for ch in node[1]:
				if not check(gs, ch, ctx):
					return false
			return true
		OR:
			for ch in node[1]:
				if check(gs, ch, ctx):
					return true
			return node[1].is_empty()
		NOT:
			return not check(gs, node[1], ctx)
		TARGET:
			var t: String = ctx.get("target", "")
			if t == "" or not gs.countries.has(t):
				return false
			return check(gs, node[1], {"tag": t, "target": ctx.get("tag", ""), "from": ctx.get("tag", "")})
		OWNER:
			return check(gs, node[1], {"tag": _tag(gs, ctx), "target": ctx.get("target", "")})
		ANY_NEIGHBOR:
			for n in VDiplomacySystem.neighbor_countries(gs, _tag(gs, ctx)):
				if check(gs, node[1], {"tag": n, "target": _tag(gs, ctx)}):
					return true
			return false
		COUNT:
			var need := int(node[1])
			var n2 := 0
			for tag in gs.country_order:
				if not gs.countries[tag]["provinces"].is_empty() and check(gs, node[2], {"tag": tag}):
					n2 += 1
					if n2 >= need:
						return true
			return false
		CNUM:
			return _cmp(country_num(gs, _tag(gs, ctx), int(node[1])), int(node[2]), float(node[3]))
		PNUM:
			return _cmp(province_num(gs, int(ctx.get("prov", 0)), int(node[1])), int(node[2]), float(node[3]))
		GNUM:
			return _cmp(global_num(gs, int(node[1])), int(node[2]), float(node[3]))
		GFLAG:
			return bool(gs.flags.get(node[1], false)) == bool(node[2])
		CFLAG:
			return VScopedState.has_country_flag(gs, _tag(gs, ctx), node[1]) == bool(node[2])
		PFLAG:
			return VScopedState.has_province_flag(gs, int(ctx.get("prov", 0)), node[1]) == bool(node[2])
		YEAR:
			return _cmp(float(gs.date.year), int(node[1]), float(node[2]))
		MONTH:
			return gs.date.month == int(node[1])
		TAG:
			return _tag(gs, ctx) in node[1]
	return _check_country(gs, node, ctx)


static func _check_country(gs: VGameState, node: Array, ctx: Dictionary) -> bool:
	var tag := _tag(gs, ctx)
	var c: Dictionary = gs.countries.get(tag, {})
	if c.is_empty():
		return false
	match int(node[0]):
		CTX_NUM:
			return _cmp(float(ctx.get(node[1], 0.0)), int(node[2]), float(node[3]))
		CTX_STR:
			return String(ctx.get(node[1], "")) == node[2]
		CAP_OCC:
			var cp := gs.province(int(c.get("capital", -1)))
			return (not cp.is_empty() and cp["controller"] != tag) == bool(node[1])
		MAGIC_REG:
			return gs.reform_level(tag, VMagicPolicy.REFORM) in node[1]
		REL_ATT:
			return VMageModel.religion_attitude(gs, String(c.get("religion", ""))) in node[1]
		CUL_TRAD:
			return VMageModel.culture_tradition(gs, String(c.get("primary_culture", ""))) in node[1]
		MAGIC_PATH:
			return node[2] in VMagicSystem.branch_paths(gs, tag, node[1])
		IS_RIVAL:
			return (String(ctx.get("target", "")) in c.get("rivals", [])) == bool(node[1])
		CIVILIZED:
			return bool(c.get("civilized", true)) == bool(node[1])
		GP:
			return (c.get("status", "") == "great_power") == bool(node[1])
		SECONDARY:
			return (c.get("status", "") == "secondary_power") == bool(node[1])
		RANK:
			var r := int(c.get("rank", 999))
			return r < int(node[2]) if int(node[1]) == 1 else r > int(node[2])
		GOVERNMENT:
			return c.get("government", "") == node[1]
		RULING_IDEO:
			return VPoliticsSystem.ruling_party(gs, tag).get("ideology", "") == node[1]
		REFORM:
			var lvl := gs.reform_level(tag, node[1])
			return lvl >= int(node[3]) if int(node[2]) == 0 else lvl <= int(node[3])
		HAS_TECH:
			return node[1] in c.get("technologies", [])
		HAS_INV:
			return node[1] in c.get("inventions", [])
		AT_WAR:
			return (not c.get("wars", []).is_empty()) == bool(node[1])
		HAS_SPHERE:
			var has := false
			for t in gs.country_order:
				if gs.countries[t].get("sphere_leader", "") == tag:
					has = true
					break
			return has == bool(node[1])
		IN_SPHERE:
			var sl: String = c.get("sphere_leader", "")
			if node[1] is bool:
				return (sl != "") == bool(node[1])
			return sl == (ctx.get("target", "") if node[1] == "target" else String(node[1]))
		HAS_TARGET:
			return (ctx.get("target", "") != "") == bool(node[1])
		TARGET_REL:
			var t2: String = ctx.get("target", "")
			if t2 == "":
				return false
			return _cmp(float(gs.relation(tag, t2)), int(node[1]), float(node[2]))
		OWNS_PROV:
			var p := gs.province(int(node[1]))
			return not p.is_empty() and p["owner"] == tag
		OWNS_STATE:
			return not gs.state_part(int(node[1]), tag).is_empty()
		CONTROLS_PROV:
			var p2 := gs.province(int(node[1]))
			return not p2.is_empty() and p2["controller"] == tag
		CONTROLS_STATE:
			var part := gs.state_part(int(node[1]), tag)
			if part.is_empty():
				return false
			for id in part:
				if gs.provinces[id]["controller"] != tag:
					return false
			return true
		HAS_CORE:
			var p3 := gs.province(int(node[1]))
			return not p3.is_empty() and tag in p3.get("cores", [])
		FACTORY_TYPE:
			return factory_type_count(gs, tag, node[1]) >= int(node[2])
		GOOD_PRICE:
			var ratio := VMarketSystem.price(gs, node[1]) / maxf(0.001, float(gs.goods.get(node[1], {}).get("base_price", 1.0)))
			return _cmp(ratio, int(node[2]), float(node[3]))
		GOOD_SHORTAGE:
			return VMarketSystem.is_available(gs, node[1]) and VMarketSystem.fill_buy(gs, tag, node[1]) < float(node[2])
		GOOD_AVAILABLE:
			return VMarketSystem.is_available(gs, node[1])
		REBEL_RISK:
			var risk := false
			for rid in c.get("movements", {}):
				if c["movements"][rid].get("rebel_risk", false):
					risk = true
					break
			return risk == bool(node[1])
		REBEL_FACTION:
			return (not VRebelSystem.country_factions(gs, tag).is_empty()) == bool(node[1])
		MAGIC_BRANCH:
			return VMagicSystem.branch_level(gs, tag, node[1]) >= int(node[2])
		MAGIC_ANY:
			return VMagicSystem.max_branch(gs, tag) >= int(node[1])
		VAR:
			return _cmp(VScopedState.get_variable(gs, tag, node[1]), int(node[2]), float(node[3]))
		MOVEMENT:
			return float(c.get("movements", {}).get(node[1], {}).get("support", 0.0)) >= float(node[2])
		POP_TYPE:
			return float(c.get("type_sizes", {}).get(node[1], 0)) >= float(node[2])
		IS_PLAYER:
			return (tag == gs.player_tag) == bool(node[1])
		HAS_MOD:
			return VScopedState.has_country_modifier(gs, tag, node[1])
	return _check_province(gs, node, ctx)


static func _check_province(gs: VGameState, node: Array, ctx: Dictionary) -> bool:
	var p := gs.province(int(ctx.get("prov", 0)))
	if p.is_empty():
		return false
	match int(node[0]):
		P_OWNER_IS:
			return p["owner"] == _resolve_tag(ctx, node[1])
		P_CONTROLLER_IS:
			return p["controller"] == _resolve_tag(ctx, node[1])
		P_TERRAIN:
			return p.get("terrain", "") in node[1]
		P_COASTAL:
			return bool(p.get("coastal", false)) == bool(node[1])
		P_RGO:
			return p.get("rgo", "") == node[1]
		P_CULTURE:
			return p.get("culture", "") == node[1]
		P_RELIGION:
			return p.get("religion", "") == node[1]
		P_OCCUPIED:
			return (p["controller"] != p["owner"]) == bool(node[1])
		P_BLOCKADED:
			return (String(p.get("blockaded_by", "")) != "") == bool(node[1])
		P_DEPOSIT:
			return (not p.get("magic", {}).is_empty() and float(p["magic"].get("deposit", 0.0)) > 0.0) == bool(node[1])
		P_STATE:
			return int(p["state"]) == int(node[1])
		P_CAPITAL:
			var cap := int(gs.countries.get(p["owner"], {}).get("capital", -1))
			return (cap == int(p["id"])) == bool(node[1])
	return false


static func _tag(gs: VGameState, ctx: Dictionary) -> String:
	var t: String = ctx.get("tag", "")
	if t == "" and int(ctx.get("prov", 0)) > 0:
		t = gs.provinces[int(ctx["prov"])]["owner"]
	return t


static func _resolve_tag(ctx: Dictionary, v: String) -> String:
	match v:
		"self", "this":
			return ctx.get("tag", "")
		"target":
			return ctx.get("target", "")
		"from":
			return ctx.get("from", "")
	return v


static func _cmp(value: float, mode: int, ref: float) -> bool:
	return value >= ref if mode == 0 else value < ref


# ------------------------------------------------------------------ valores
static func country_num(gs: VGameState, tag: String, fid: int) -> float:
	var c: Dictionary = gs.countries.get(tag, {})
	if c.is_empty():
		return 0.0
	match fid:
		0:
			return float(c.get("prestige", 0.0))
		1:
			return float(c.get("military_score", 0.0))
		2:
			return float(c.get("industry_score", 0.0))
		3:
			return float(c.get("treasury", 0.0))
		4:
			return float(c.get("debt", 0.0))
		5:
			return float(c.get("literacy", 0.0))
		6:
			return float(c.get("avg_militancy", 0.0))
		7:
			return float(c.get("avg_consciousness", 0.0))
		8:
			return float(c.get("unemployment", 0.0))
		9:
			return float(c.get("avg_life", 1.0))
		10:
			return float(c.get("avg_everyday", 0.5))
		11:
			return float(c.get("population", 0))
		12:
			return float(c.get("war_exhaustion", 0.0))
		13:
			return float(c.get("infamy", 0.0))
		14:
			return float(c.get("_factory_count", 0))
		15:
			return float(c.get("research_points_monthly", 0.0))
		16:
			return float(c.get("wars", []).size())
		17:
			return float(c.get("military", {}).get("brigades", 0))
		18:
			return float(c.get("provinces", []).size())
		19:
			return float(c.get("type_sizes", {}).get("magi", 0))
		20:
			return float(c.get("_magi_info", {}).get("share", 0.0))
		21:
			return float(c.get("_magi_info", {}).get("unemployment", 0.0))
		22:
			return float(c.get("_magi_info", {}).get("ratio", 0.0))
		23:
			return float(c.get("magic_stats", {}).get("emigrated_y", 0.0))
		24:
			return float(c.get("magic_stats", {}).get("immigrated_y", 0.0))
		25:
			return VScopedState.get_variable(gs, tag, "arcane_academies")
		26:
			return float(c.get("acc_mobility_last", {}).get("immigrated", 0))
		27:
			return float(c.get("acc_mobility_last", {}).get("emigrated", 0))
		28:
			var longest := 0
			for wid in c.get("wars", []):
				longest = maxi(longest, gs.month_index - int(gs.wars.get(int(wid), {}).get("start_month", gs.month_index)))
			return float(longest)
		29:
			var n := 0
			for ft in gs.factory_types:
				if int(gs.factory_types[ft].get("workforce", {}).get("magi", 0)) > 0:
					n += factory_type_count(gs, tag, ft)
			return float(n)
		30:
			return float(VMagicSystem.country_deposit_provinces(gs, tag).size())
	return 0.0


static func province_num(gs: VGameState, id: int, fid: int) -> float:
	var p := gs.province(id)
	if p.is_empty():
		return 0.0
	match fid:
		0:
			return float(p.get("population", 0))
		1:
			return float(p.get("unemployment", 0.0))
		2:
			return VPopulationSystem.weighted_average(gs, [id], "militancy")
		3:
			return float(p.get("life_rating", 0))
		4:
			return float(p.get("fort", 0))
		5:
			return float(p.get("naval_base", 0))
		6:
			return float(p.get("infrastructure", 0))
		7:
			return float(p.get("magic", {}).get("potential", 0.0))
		8:
			return float(p.get("avg_life", 1.0))
	return 0.0


static func global_num(gs: VGameState, fid: int) -> float:
	match fid:
		0:
			return float(gs.wars.size())
		1, 2, 3:
			var field: String = ["literacy", "avg_militancy", "avg_life"][fid - 1]
			var tot := 0.0
			var w := 0.0
			for tag in gs.country_order:
				var c: Dictionary = gs.countries[tag]
				var pop := float(c.get("population", 0))
				tot += float(c.get(field, 0.0)) * pop
				w += pop
			return tot / w if w > 0.0 else 0.0
		4:
			var n := 0
			for tag in gs.country_order:
				var c2: Dictionary = gs.countries[tag]
				if c2.get("status", "") == "great_power" and not c2.get("wars", []).is_empty():
					n += 1
			return float(n)
	return 0.0


static func factory_type_count(gs: VGameState, tag: String, ftype: String) -> int:
	var n := 0
	for si in gs.country_state_instances(tag):
		for f in si["factories"]:
			if f["type"] == ftype and f["open"]:
				n += 1
	return n


# ------------------------------------------------------------------ explicación (UI)
## Primera condición que falla, en texto legible ("" si se cumplen todas).
static func explain_fail(gs: VGameState, node: Array, ctx: Dictionary) -> String:
	if int(node[0]) == AND:
		for ch in node[1]:
			var r := explain_fail(gs, ch, ctx)
			if r != "":
				return r
		return ""
	if check(gs, node, ctx):
		return ""
	return describe(gs, node)


static func describe(gs: VGameState, node: Array) -> String:
	match int(node[0]):
		AND:
			var parts := []
			for ch in node[1]:
				parts.append(describe(gs, ch))
			return ", ".join(parts)
		OR:
			var parts2 := []
			for ch in node[1]:
				parts2.append(describe(gs, ch))
			return "una de: " + " / ".join(parts2)
		NOT:
			return "no (" + describe(gs, node[1]) + ")"
		TARGET:
			return "el país objetivo: " + describe(gs, node[1])
		OWNER:
			return "el propietario: " + describe(gs, node[1])
		ANY_NEIGHBOR:
			return "algún vecino: " + describe(gs, node[1])
		COUNT:
			return "al menos %d países con: %s" % [int(node[1]), describe(gs, node[2])]
		CNUM:
			return "%s %s %s" % [FIELD_NAMES.get(CNUM_FIELDS[int(node[1])], "?"), "≥" if int(node[2]) == 0 else "<", _num(float(node[3]))]
		PNUM:
			return "%s %s %s" % [FIELD_NAMES.get(PNUM_FIELDS[int(node[1])], "?"), "≥" if int(node[2]) == 0 else "<", _num(float(node[3]))]
		GNUM:
			return "%s %s %s" % [FIELD_NAMES.get(GNUM_FIELDS[int(node[1])], "?"), "≥" if int(node[2]) == 0 else "<", _num(float(node[3]))]
		GFLAG:
			return ("" if node[2] else "sin ") + "«%s»" % node[1]
		CFLAG:
			return ("" if node[2] else "sin ") + "«%s» (nación)" % node[1]
		PFLAG:
			return ("" if node[2] else "sin ") + "«%s» (provincia)" % node[1]
		YEAR:
			return "año %s %d" % ["≥" if int(node[1]) == 0 else "<", int(node[2])]
		TAG:
			return "solo " + ", ".join(node[1])
		CIVILIZED:
			return "civilizada" if node[1] else "no civilizada"
		GP:
			return "gran potencia" if node[1] else "no ser gran potencia"
		AT_WAR:
			return "en guerra" if node[1] else "en paz"
		HAS_TECH:
			return "tecnología «%s»" % gs.technologies.get(node[1], {}).get("name", node[1])
		HAS_INV:
			return "invento «%s»" % gs.inventions.get(node[1], {}).get("name", node[1])
		REFORM:
			return "reforma %s %s nivel %d" % [gs.reforms.get(node[1], {}).get("name", node[1]), "≥" if int(node[2]) == 0 else "≤", int(node[3])]
		MAGIC_BRANCH:
			return "rama mágica de %s ≥ %d" % [VMagicSystem.BRANCH_NAMES.get(node[1], node[1]), int(node[2])]
		MAGIC_ANY:
			return "alguna rama mágica ≥ %d" % int(node[1])
		GOOD_SHORTAGE:
			return "escasez de %s" % gs.goods.get(node[1], {}).get("name", node[1])
		GOOD_PRICE:
			return "precio de %s %s %.0f%% del base" % [gs.goods.get(node[1], {}).get("name", node[1]), "≥" if int(node[2]) == 0 else "<", float(node[3]) * 100.0]
		FACTORY_TYPE:
			return "%d fábricas de %s" % [int(node[2]), gs.factory_types.get(node[1], {}).get("name", node[1])]
		HAS_MOD:
			return "modificador «%s»" % node[1]
		MOVEMENT:
			return "movimiento por %s con apoyo ≥ %.0f%%" % [gs.reforms.get(node[1], {}).get("name", node[1]), float(node[2]) * 100.0]
		POP_TYPE:
			return "%s ≥ %s" % [gs.pop_types.get(node[1], {}).get("name", node[1]), _num(float(node[2]))]
		VAR:
			return "variable %s %s %s" % [node[1], "≥" if int(node[2]) == 0 else "<", _num(float(node[3]))]
		MONTH:
			return "mes %d" % int(node[1])
		SECONDARY:
			return "potencia secundaria" if node[1] else "no ser potencia secundaria"
		RANK:
			return "puesto %s %d" % ["≤" if int(node[1]) == 1 else ">", int(node[2])]
		GOVERNMENT:
			return "gobierno %s" % node[1]
		RULING_IDEO:
			return "ideología gobernante %s" % node[1]
		HAS_SPHERE:
			return "tener esfera" if node[1] else "sin esfera"
		IN_SPHERE:
			return "en una esfera" if typeof(node[1]) == TYPE_BOOL and node[1] else "esfera de %s" % str(node[1])
		HAS_TARGET:
			return "tener país objetivo" if node[1] else "sin país objetivo"
		TARGET_REL:
			return "relación %s %d" % ["≥" if int(node[1]) == 0 else "<", int(node[2])]
		OWNS_PROV, CONTROLS_PROV:
			return "%s la provincia %d" % ["poseer" if int(node[0]) == OWNS_PROV else "controlar", int(node[1])]
		OWNS_STATE, CONTROLS_STATE:
			return "%s el estado %d" % ["poseer" if int(node[0]) == OWNS_STATE else "controlar", int(node[1])]
		HAS_CORE:
			return "núcleo en la provincia %d" % int(node[1])
		GOOD_AVAILABLE:
			return "%s disponible" % gs.goods.get(node[1], {}).get("name", node[1])
		REBEL_RISK:
			return "riesgo de rebelión" if node[1] else "sin riesgo de rebelión"
		REBEL_FACTION:
			return "facción rebelde activa" if node[1] else "sin facciones rebeldes"
		IS_PLAYER:
			return "nación del jugador" if node[1] else "nación de la IA"
		P_OCCUPIED:
			return "provincia ocupada" if node[1] else "provincia no ocupada"
		P_COASTAL:
			return "provincia costera" if node[1] else "provincia interior"
		P_DEPOSIT:
			return "yacimiento mágico" if node[1] else "sin yacimiento mágico"
		P_CAPITAL:
			return "capital" if node[1] else "no capital"
		CTX_NUM:
			return "%s %s %s" % [{"losses": "bajas enemigas", "own_losses": "bajas propias", "goals": "objetivos de paz"}.get(node[1], node[1]), "≥" if int(node[2]) == 0 else "<", _num(float(node[3]))]
		CTX_STR:
			return {"victory": "paz victoriosa", "defeat": "paz de derrota", "white_peace": "paz blanca"}.get(node[2], node[2])
		CAP_OCC:
			return "capital ocupada" if node[1] else "capital libre"
		MAGIC_REG:
			var names := []
			for li in node[1]:
				if li >= 0 and li < VMagicPolicy.levels(gs).size():
					names.append(String(VMagicPolicy.levels(gs)[li]["name"]).to_lower())
			return "magia " + " o ".join(names)
		REL_ATT:
			return "religión con actitud mágica: " + ", ".join(node[1])
		CUL_TRAD:
			return "tradición mágica: " + ", ".join(node[1])
		MAGIC_PATH:
			return "senda mágica «%s» (%s)" % [node[2], node[1]]
		IS_RIVAL:
			return "rival" if node[1] else "no rival"
	return "condición de provincia" if int(node[0]) >= P_OWNER_IS else "condición %d" % int(node[0])


static func _num(v: float) -> String:
	return ("%.0f" % v) if absf(v) >= 10.0 else ("%.2f" % v)
