class_name VPeaceSystem
extends RefCounted
## Negociación y efectos de paz.
##
## Dos modos: "demand" (el proponente exige objetivos de su bando) y "offer" (el proponente concede
## objetivos del bando contrario). Cada objetivo tiene un coste de warscore; la paz blanca no tiene
## objetivos. La IA decide con: warscore frente al coste, fuerza militar restante, cansancio bélico,
## capital ocupada, duración, aliados e importancia del objetivo — no acepta solo porque ws ≥ coste.
## SOLO aquí cambia la propiedad de las provincias (gs.change_owner → rebuild_territory →
## simulación y mapa se actualizan por la señal ownership_changed).


static func goal_cost(gs: VGameState, goal: Dictionary) -> float:
	var d := VCasusBelliSystem.cb_def(gs, goal["type"])
	var base := float(d.get("warscore_cost", 20))
	if int(goal.get("state_id", 0)) > 0:
		var part := gs.state_part(int(goal["state_id"]), goal["target"])
		var pop := 0.0
		for id in part:
			pop += float(gs.provinces[id]["population"])
		var tpop := maxf(1.0, float(gs.country_population(goal["target"])))
		base *= clampf(0.6 + 3.0 * pop / tpop, 0.6, 2.5)
	elif goal["type"] == "conquest":
		base = maxf(base, 60.0)
	return roundf(base)


## Objetivos que un bando puede exigir en esta guerra.
static func goals_for_side(gs: VGameState, w: Dictionary, side: String) -> Array:
	var out := []
	for g in w["war_goals"]:
		if VWarSystem.side_of(w, g["actor"]) == side and VWarSystem.side_of(w, g["target"]) != side and VWarSystem.side_of(w, g["target"]) != "":
			out.append(g)
	return out


static func _army_power(gs: VGameState, tags: Array) -> float:
	var t := 1.0
	for tag in tags:
		for a in VArmySystem.country_armies(gs, tag):
			t += VArmySystem.army_power(gs, a)
	return t


## Evalúa una propuesta. proposer = nación que propone; el receptor es el líder del bando contrario.
static func evaluate(gs: VGameState, w: Dictionary, proposer: String, mode: String, goals: Array) -> Dictionary:
	var side := VWarSystem.side_of(w, proposer)
	var other := "defenders" if side == "attackers" else "attackers"
	var receiver: String = w["primary_defender"] if side == "attackers" else w["primary_attacker"]
	var cost := 0.0
	for g in goals:
		cost += goal_cost(gs, g)
	var ws := VWarSystem.warscore_for(w, proposer)
	var reasons := []
	var score := 0.0
	var rc: Dictionary = gs.countries[receiver]
	var months := gs.month_index - int(w.get("start_month", gs.month_index))
	if mode == "demand":
		if goals.is_empty():
			score = 5.0 - absf(ws) * 0.4 + minf(10.0, float(months) * 0.5) + float(rc.get("war_exhaustion", 0.0)) * 0.3
			reasons.append("paz blanca (warscore %+.0f)" % ws)
		else:
			score = (ws - cost) * 1.5
			reasons.append("warscore %+.0f frente a coste %.0f" % [ws, cost])
			if ws < cost:
				score -= 10.0
		var we := float(rc.get("war_exhaustion", 0.0))
		score += we * 0.4
		if we > 0:
			reasons.append("cansancio bélico %.0f" % we)
		var cap := int(rc.get("capital", -1))
		if cap > 0 and VWarSystem.side_of(w, gs.provinces[cap]["controller"]) == side:
			score += 15.0
			reasons.append("su capital está ocupada")
		var ratio := _army_power(gs, w[other]) / _army_power(gs, w[side])
		if ratio > 1.2:
			score -= (ratio - 1.0) * 12.0
			reasons.append("aún tiene ejércitos superiores")
		elif ratio < 0.3:
			score += 10.0
			reasons.append("apenas le quedan ejércitos")
		score += minf(15.0, float(months) * 0.4)
		if months > 6:
			reasons.append("guerra de %d meses" % months)
		var allies: int = w[other].size() - 1
		if allies > 0:
			score -= float(allies) * 3.0
			reasons.append("%d aliado(s)" % allies)
		for g in goals:
			if g["type"] in ["conquest", "cut_down_to_size"]:
				score -= 8.0
				reasons.append("objetivo grave (%s)" % VCasusBelliSystem.cb_def(gs, g["type"]).get("name", ""))
	else:
		# ofrecer: el receptor gana los objetivos concedidos; acepta si compensan su ventaja
		var ws_r := -ws
		score = cost - maxf(0.0, ws_r) * 0.8 + 5.0 + float(rc.get("war_exhaustion", 0.0)) * 0.3
		reasons.append("concesiones %.0f frente a su warscore %+.0f" % [cost, ws_r])
		if goals.is_empty() and ws_r > 15.0:
			score -= 10.0
	var chance := clampf(50.0 + score * 3.0, 0.0, 100.0)
	return {"cost": cost, "warscore": ws, "score": score, "chance": chance, "accept": score > 0.0, "reasons": reasons, "receiver": receiver}


## Envía una propuesta. Si el receptor es el jugador queda pendiente (war.offer); si es IA decide ya.
static func propose(gs: VGameState, w: Dictionary, proposer: String, mode: String, goals: Array) -> Dictionary:
	var ev := evaluate(gs, w, proposer, mode, goals)
	if ev["receiver"] == gs.player_tag and proposer != gs.player_tag:
		w["offer"] = {"from": proposer, "mode": mode, "goals": goals, "month": gs.month_index}
		gs.log_event(gs.player_tag, "%s propone la paz en la %s" % [gs.country_name(proposer), w["name"]])
		return {"pending": true, "eval": ev}
	if not ev["accept"]:
		gs.log_event(proposer, "%s rechaza la propuesta de paz" % gs.country_name(ev["receiver"]))
		return {"accepted": false, "eval": ev}
	var winner_side := VWarSystem.side_of(w, proposer) if mode == "demand" else ("defenders" if VWarSystem.side_of(w, proposer) == "attackers" else "attackers")
	apply(gs, w, winner_side, goals)
	return {"accepted": true, "eval": ev}


## El jugador responde a una oferta pendiente.
static func answer_offer(gs: VGameState, w: Dictionary, accept: bool) -> void:
	var off: Dictionary = w.get("offer", {})
	if off.is_empty():
		return
	w["offer"] = {}
	if not accept:
		gs.set_relation(gs.player_tag, off["from"], gs.relation(gs.player_tag, off["from"]) - 10)
		return
	var side := VWarSystem.side_of(w, off["from"])
	var winner_side: String = side if off["mode"] == "demand" else ("defenders" if side == "attackers" else "attackers")
	apply(gs, w, winner_side, off["goals"])


static func apply(gs: VGameState, w: Dictionary, winner_side: String, goals: Array) -> void:
	var loser_side := "defenders" if winner_side == "attackers" else "attackers"
	var winner: String = w["primary_attacker"] if winner_side == "attackers" else w["primary_defender"]
	var loser: String = w["primary_defender"] if winner_side == "attackers" else w["primary_attacker"]
	var lines := []
	for g in goals:
		lines.append(_apply_goal(gs, w, g))
	if goals.is_empty():
		lines.append("paz blanca")
	var prestige := 0.0
	for g in goals:
		prestige += float(VCasusBelliSystem.cb_def(gs, g["type"]).get("prestige", 2))
	if gs.countries.has(winner):
		gs.countries[winner]["prestige"] = float(gs.countries[winner]["prestige"]) + prestige
	if gs.countries.has(loser):
		gs.countries[loser]["prestige"] = maxf(0.0, float(gs.countries[loser]["prestige"]) - prestige)
	VWarSystem.end_war(gs, w, "Paz en la %s: %s" % [w["name"], "; ".join(lines)])


static func _apply_goal(gs: VGameState, w: Dictionary, g: Dictionary) -> String:
	var actor: String = g["actor"]
	var target: String = g["target"]
	if not gs.countries.has(target) or gs.countries[target]["provinces"].is_empty():
		return "%s ya no existe" % gs.country_name(target)
	var d := VCasusBelliSystem.cb_def(gs, g["type"])
	match d.get("peace_effect", ""):
		"annex_state", "restore_core":
			var ids: Array = gs.state_part(int(g["state_id"]), target).duplicate()
			if d.get("peace_effect", "") == "restore_core":
				ids = VCasusBelliSystem.actor_cores_in_state(gs, actor, target, int(g["state_id"]))
			if ids.is_empty():
				return "estado ya no pertenece a %s" % gs.country_name(target)
			gs.change_owner(ids, actor)
			return "%s pasa a %s" % [gs.states[int(g["state_id"])]["name"], gs.country_name(actor)]
		"conquest":
			var all: Array = gs.countries[target]["provinces"].duplicate()
			gs.change_owner(all, actor)
			return "%s es anexionada por %s" % [gs.country_name(target), gs.country_name(actor)]
		"humiliate":
			gs.countries[target]["prestige"] = float(gs.countries[target]["prestige"]) * 0.8
			for t in gs.country_order:
				if gs.countries[t].get("sphere_leader", "") == target:
					gs.countries[t]["sphere_leader"] = ""
			return "%s humillada" % gs.country_name(target)
		"cut_down":
			gs.countries[target]["disarmed_until"] = gs.month_index + 60
			var armies := VArmySystem.country_armies(gs, target)
			for i in range(0, armies.size(), 2):
				VArmySystem.destroy_army(gs, armies[i], true)
			VArmySystem.update_counts(gs)
			return "%s desarmada y recortada" % gs.country_name(target)
		"reparations":
			var reps: Array = gs.countries[target].get("reparations", [])
			reps.append({"to": actor, "until": gs.month_index + 60, "share": 0.1})
			gs.countries[target]["reparations"] = reps
			return "%s pagará reparaciones a %s durante 5 años" % [gs.country_name(target), gs.country_name(actor)]
		"release_nation", "liberate_country":
			var rel := _release(gs, target)
			return rel if rel != "" else "no hay nación que liberar en %s" % gs.country_name(target)
		"place_in_sphere":
			if VInfluenceSystem.is_gp(gs, actor):
				gs.countries[target]["sphere_leader"] = actor
				VInfluenceSystem.entry(gs, actor, target)["opinion"] = 5
			return "%s entra en la esfera de %s" % [gs.country_name(target), gs.country_name(actor)]
		"free_from_sphere":
			gs.countries[target]["sphere_leader"] = ""
			return "%s sale de su esfera" % gs.country_name(target)
	return "objetivo sin efecto"


## Libera una nación latente (sin provincias) cuya cultura principal predomine en provincias del objetivo.
static func _release(gs: VGameState, target: String) -> String:
	var by_culture := {}
	for id in gs.countries[target]["provinces"]:
		var cul: String = gs.provinces[id]["culture"]
		if cul != gs.countries[target]["primary_culture"]:
			if not by_culture.has(cul):
				by_culture[cul] = []
			by_culture[cul].append(id)
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		if not c["provinces"].is_empty() or not by_culture.has(c["primary_culture"]):
			continue
		var ids: Array = by_culture[c["primary_culture"]]
		gs.change_owner(ids, tag)
		c["capital"] = int(ids[0])
		return "%s queda liberada" % gs.country_name(tag)
	return ""


## IA: el bando que va ganando exige sus objetivos; las guerras estancadas acaban en paz blanca.
static func ai_consider(gs: VGameState, w: Dictionary) -> void:
	var months := gs.month_index - int(w.get("start_month", gs.month_index))
	if months < 4:
		return
	for side in ["attackers", "defenders"]:
		var leader: String = w["primary_attacker"] if side == "attackers" else w["primary_defender"]
		if leader == gs.player_tag:
			continue
		var ws := VWarSystem.warscore_for(w, leader)
		var goals := goals_for_side(gs, w, side)
		if ws >= 10.0 and not goals.is_empty():
			var affordable := []
			var total := 0.0
			for g in goals:
				var cst := goal_cost(gs, g)
				if total + cst <= ws:
					affordable.append(g)
					total += cst
			if not affordable.is_empty():
				var res := propose(gs, w, leader, "demand", affordable)
				if res.get("accepted", false) or res.get("pending", false):
					return
		if (months >= 30 and absf(ws) < 15.0) or months >= 36:
			var res2 := propose(gs, w, leader, "demand", [])
			if res2.get("accepted", false) or res2.get("pending", false):
				return
