class_name VInfluenceSystem
extends RefCounted
## Influencia y esferas (estilo Victoria II).
##
## Solo las Grandes Potencias (VRankingSystem) generan influencia. Cada mes reparten sus puntos
## entre sus objetivos según la prioridad (0–3). Con puntos acumulados en un objetivo pueden:
##   increase_opinion, decrease_opinion (de otra GP), discredit, expel_advisors, ban_embassy,
##   add_to_sphere (requiere opinión «amistoso»), remove_from_sphere.
## Opinión: 0 hostil · 1 contrario · 2 neutral · 3 cordial · 4 amistoso · 5 en la esfera.
## Meter un país en la esfera fija country.sphere_leader = GP, y VMarketSystem ya hace que comercie
## dentro de la esfera antes de acudir al mercado mundial.
## Si una GP deja de serlo, tras un periodo de gracia pierde su esfera y deja de generar influencia.

const ACTIONS := ["increase_opinion", "decrease_opinion", "discredit", "expel_advisors", "ban_embassy", "add_to_sphere", "remove_from_sphere"]
const ACTION_NAMES := {"increase_opinion": "Mejorar opinión", "decrease_opinion": "Empeorar opinión (de otra potencia)",
	"discredit": "Desacreditar", "expel_advisors": "Expulsar consejeros", "ban_embassy": "Prohibir embajada",
	"add_to_sphere": "Añadir a la esfera", "remove_from_sphere": "Sacar de la esfera"}


static func setup_new_game(gs: VGameState) -> void:
	for tag in gs.countries:
		var c: Dictionary = gs.countries[tag]
		c["influence"] = {}  # solo para GPs: target -> entrada
		c["sphere_leader"] = c.get("sphere_leader", "")
		c["gp_grace"] = 0


static func rules(gs: VGameState) -> Dictionary:
	return gs.diplo_rules.get("influence", {})


static func is_gp(gs: VGameState, tag: String) -> bool:
	return gs.countries.get(tag, {}).get("status", "") == "great_power"


static func entry(gs: VGameState, gp: String, target: String) -> Dictionary:
	var inf: Dictionary = gs.countries[gp]["influence"]
	if not inf.has(target):
		inf[target] = {"points": 0.0, "opinion": 2, "priority": 0, "banned_until": -1, "discredited_until": -1}
	return inf[target]


static func opinion_name(gs: VGameState, level: int) -> String:
	var levels: Array = rules(gs).get("opinion_levels", [])
	var names: Dictionary = rules(gs).get("opinion_names", {})
	if level >= 0 and level < levels.size():
		return names.get(levels[level], levels[level])
	return "?"


## Opinión de 'target' sobre la potencia 'gp' (si no hay entrada, neutral; si está en su esfera, 5).
static func opinion(gs: VGameState, gp: String, target: String) -> int:
	if gs.countries.get(target, {}).get("sphere_leader", "") == gp:
		return 5
	return int(gs.countries.get(gp, {}).get("influence", {}).get(target, {}).get("opinion", 2))


static func valid_target(gs: VGameState, gp: String, target: String) -> bool:
	if gp == target or not gs.countries.has(target) or gs.countries[target]["provinces"].is_empty():
		return false
	return not is_gp(gs, target)


static func set_priority(gs: VGameState, gp: String, target: String, priority: int) -> String:
	if not is_gp(gs, gp):
		return "Solo las Grandes Potencias ejercen influencia."
	if not valid_target(gs, gp, target):
		return "No se puede influir sobre otra Gran Potencia."
	var inf: Dictionary = gs.countries[gp]["influence"]
	var active := 0
	for t in inf:
		if int(inf[t]["priority"]) > 0 and t != target:
			active += 1
	if priority > 0 and active >= int(rules(gs).get("max_targets", 8)):
		return "Demasiados objetivos de influencia activos."
	entry(gs, gp, target)["priority"] = clampi(priority, 0, 3)
	return ""


# ----------------------------------------------------------------- mensual
static func monthly(gs: VGameState) -> void:
	var r := rules(gs)
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		if c["provinces"].is_empty():
			continue
		if is_gp(gs, tag):
			c["gp_grace"] = int(r.get("gp_grace_months", 6))
			_gain(gs, tag, r)
		elif int(c.get("gp_grace", 0)) > 0:
			c["gp_grace"] = int(c["gp_grace"]) - 1
			if int(c["gp_grace"]) == 0:
				_lose_gp(gs, tag)
	# miembros de esfera cuyo líder ya no existe
	for tag in gs.country_order:
		var leader: String = gs.countries[tag].get("sphere_leader", "")
		if leader != "" and (not gs.countries.has(leader) or gs.countries[leader]["provinces"].is_empty()):
			gs.countries[tag]["sphere_leader"] = ""


static func _gain(gs: VGameState, gp: String, r: Dictionary) -> void:
	var c: Dictionary = gs.countries[gp]
	var inf: Dictionary = c["influence"]
	var total_pri := 0
	for t in inf:
		if valid_target(gs, gp, t) and int(inf[t]["banned_until"]) <= gs.month_index:
			total_pri += int(inf[t]["priority"])
	if total_pri == 0:
		return
	var points := float(r.get("base_per_month", 6.0)) + float(c.get("prestige", 0.0)) * float(r.get("prestige_factor", 0.05))
	var cap := float(r.get("points_cap", 200))
	for t in inf:
		var e: Dictionary = inf[t]
		if not valid_target(gs, gp, t) or int(e["banned_until"]) > gs.month_index or int(e["priority"]) == 0:
			continue
		var share := points * float(e["priority"]) / float(total_pri)
		if int(e["discredited_until"]) > gs.month_index:
			share *= 0.25
		e["points"] = minf(cap, float(e["points"]) + share)


static func _lose_gp(gs: VGameState, tag: String) -> void:
	for t in gs.country_order:
		if gs.countries[t].get("sphere_leader", "") == tag:
			gs.countries[t]["sphere_leader"] = ""
			gs.log_event(tag, "%s sale de la esfera al perder %s el rango de Gran Potencia" % [gs.country_name(t), gs.country_name(tag)])
	for t in gs.countries[tag]["influence"]:
		gs.countries[tag]["influence"][t]["priority"] = 0


# ----------------------------------------------------------------- acciones
static func check(gs: VGameState, gp: String, action: String, target: String, other_gp: String = "") -> Dictionary:
	var res := {"ok": false, "reason": "", "cost": 0.0}
	if not is_gp(gs, gp):
		res["reason"] = "Solo las Grandes Potencias pueden usar influencia."
		return res
	if not valid_target(gs, gp, target):
		res["reason"] = "Objetivo no válido (no se puede influir sobre otra Gran Potencia)."
		return res
	var cost := float(rules(gs).get("costs", {}).get(action, 50))
	res["cost"] = cost
	var e := entry(gs, gp, target)
	if float(e["points"]) < cost:
		res["reason"] = "Faltan puntos de influencia en %s (%.0f / %.0f)." % [gs.country_name(target), float(e["points"]), cost]
		return res
	if int(e["banned_until"]) > gs.month_index:
		res["reason"] = "Tu embajada está prohibida hasta dentro de %d meses." % (int(e["banned_until"]) - gs.month_index)
		return res
	var t: Dictionary = gs.countries[target]
	var leader: String = t.get("sphere_leader", "")
	match action:
		"increase_opinion":
			if opinion(gs, gp, target) >= 4:
				res["reason"] = "La opinión ya es «amistoso» o mejor."
				return res
			if leader != "" and leader != gp:
				pass
		"decrease_opinion", "discredit", "expel_advisors", "ban_embassy":
			if other_gp == "" or not is_gp(gs, other_gp) or other_gp == gp:
				res["reason"] = "Elige otra Gran Potencia que influya sobre %s." % gs.country_name(target)
				return res
			if action == "decrease_opinion" and opinion(gs, other_gp, target) <= 0:
				res["reason"] = "La opinión de esa potencia ya es hostil."
				return res
			if opinion(gs, gp, target) < (3 if action == "decrease_opinion" else 2):
				res["reason"] = "Necesitas opinión «%s» o mejor." % opinion_name(gs, 3 if action == "decrease_opinion" else 2)
				return res
			if leader == other_gp and action == "expel_advisors":
				res["reason"] = "No se puede expulsar a los consejeros del líder de su esfera."
				return res
		"add_to_sphere":
			if leader == gp:
				res["reason"] = "Ya está en tu esfera."
				return res
			if leader != "":
				res["reason"] = "Está en la esfera de %s: primero hay que sacarla." % gs.country_name(leader)
				return res
			if opinion(gs, gp, target) < 4:
				res["reason"] = "Necesitas opinión «amistoso» (ahora: %s)." % opinion_name(gs, opinion(gs, gp, target))
				return res
		"remove_from_sphere":
			if leader == "":
				res["reason"] = "No está en ninguna esfera."
				return res
			if leader != gp and opinion(gs, gp, target) < 4:
				res["reason"] = "Necesitas opinión «amistoso» para sacarla de otra esfera."
				return res
		_:
			res["reason"] = "Acción desconocida."
			return res
	res["ok"] = true
	return res


static func perform(gs: VGameState, gp: String, action: String, target: String, other_gp: String = "") -> String:
	var chk := check(gs, gp, action, target, other_gp)
	if not chk["ok"]:
		return chk["reason"]
	var e := entry(gs, gp, target)
	e["points"] = float(e["points"]) - float(chk["cost"])
	var r := rules(gs)
	match action:
		"increase_opinion":
			e["opinion"] = mini(4, int(e["opinion"]) + 1)
		"decrease_opinion":
			var oe := entry(gs, other_gp, target)
			oe["opinion"] = maxi(0, int(oe["opinion"]) - 1)
			gs.set_relation(gp, other_gp, gs.relation(gp, other_gp) - 10)
		"discredit":
			entry(gs, other_gp, target)["discredited_until"] = gs.month_index + int(r.get("discredit_months", 6))
			gs.set_relation(gp, other_gp, gs.relation(gp, other_gp) - 5)
		"expel_advisors":
			entry(gs, other_gp, target)["points"] = 0.0
			gs.set_relation(gp, other_gp, gs.relation(gp, other_gp) - 15)
		"ban_embassy":
			var be := entry(gs, other_gp, target)
			be["points"] = 0.0
			be["banned_until"] = gs.month_index + int(r.get("ban_months", 12))
			gs.set_relation(gp, other_gp, gs.relation(gp, other_gp) - 25)
		"add_to_sphere":
			gs.countries[target]["sphere_leader"] = gp
			e["opinion"] = 5
			gs.log_event(gp, "%s entra en nuestra esfera de influencia" % gs.country_name(target))
			gs.log_event(target, "Entramos en la esfera de %s" % gs.country_name(gp))
		"remove_from_sphere":
			var old: String = gs.countries[target]["sphere_leader"]
			gs.countries[target]["sphere_leader"] = ""
			if old != "" and gs.countries.has(old):
				entry(gs, old, target)["opinion"] = 3
				if old != gp:
					gs.set_relation(gp, old, gs.relation(gp, old) - 30)
			gs.log_event(gp, "%s sale de la esfera de %s" % [gs.country_name(target), gs.country_name(old)])
	return ""


## Potencias que influyen sobre un país (para la UI de naciones no GP).
static func competitors(gs: VGameState, target: String) -> Array:
	var out := []
	for gp in gs.country_order:
		if not is_gp(gs, gp):
			continue
		var e: Dictionary = gs.countries[gp].get("influence", {}).get(target, {})
		if not e.is_empty() and (int(e.get("priority", 0)) > 0 or float(e.get("points", 0.0)) > 0.0 or int(e.get("opinion", 2)) != 2):
			out.append({"gp": gp, "points": float(e["points"]), "opinion": opinion(gs, gp, target), "priority": int(e["priority"])})
	out.sort_custom(func(a, b): return a["opinion"] * 1000 + a["points"] > b["opinion"] * 1000 + b["points"])
	return out


## IA: cada GP elige objetivos (vecinos y socios no GP), sube opinión y los mete en su esfera.
static func ai_monthly(gs: VGameState) -> void:
	if gs.flags.get("ai_disabled", false):
		return
	for gp in gs.country_order:
		if gp == gs.player_tag or not is_gp(gs, gp):
			continue
		var c: Dictionary = gs.countries[gp]
		var inf: Dictionary = c["influence"]
		var active := 0
		for t in inf:
			if int(inf[t]["priority"]) > 0:
				if not valid_target(gs, gp, t):
					inf[t]["priority"] = 0
				else:
					active += 1
		if active < 4 and (gs.month_index + absi(gp.hash())) % 4 == 0:
			var best := ""
			var best_v := -INF
			for n in VDiplomacySystem.neighbor_countries(gs, gp):
				if not valid_target(gs, gp, n) or int(entry(gs, gp, n)["priority"]) > 0:
					continue
				var v := float(gs.relation(gp, n)) / 50.0 + float(gs.countries[n].get("population", 0)) / 5e6
				if gs.countries[n].get("sphere_leader", "") != "":
					v -= 2.0
				if v > best_v:
					best_v = v
					best = n
			if best != "":
				set_priority(gs, gp, best, 2)
		for t in inf.keys():
			if int(inf[t]["priority"]) == 0:
				continue
			var leader: String = gs.countries[t].get("sphere_leader", "")
			if leader == gp:
				continue
			if leader != "" and opinion(gs, gp, t) >= 4:
				perform(gs, gp, "remove_from_sphere", t)
			elif opinion(gs, gp, t) >= 4:
				perform(gs, gp, "add_to_sphere", t)
			else:
				perform(gs, gp, "increase_opinion", t)
