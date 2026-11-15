class_name VDiplomacySystem
extends RefCounted
## Diplomacia: relaciones (−200…+200), alianzas, garantías, acceso militar y treguas.
##
## Cada acción tiene coste en puntos diplomáticos (se acumulan cada mes), validación con motivo
## de rechazo y, si la otra parte debe aceptar, una evaluación de la IA con sus razones:
##   check(gs, actor, action, target) -> {ok, reason, cost, accept, score, reasons[]}
##   perform(gs, actor, action, target) -> "" o motivo del fallo
## Acciones: improve_relations, decrease_relations, offer_alliance, break_alliance, guarantee,
## request_access, give_access, cancel_access.

const ACTION_NAMES := {
	"improve_relations": "Mejorar relaciones", "decrease_relations": "Empeorar relaciones",
	"offer_alliance": "Proponer alianza", "break_alliance": "Romper alianza",
	"guarantee": "Garantizar independencia", "request_access": "Pedir acceso militar",
	"give_access": "Dar acceso militar", "cancel_access": "Cancelar acceso militar",
}


static func setup_new_game(gs: VGameState) -> void:
	for tag in gs.countries:
		var c: Dictionary = gs.countries[tag]
		c["diplo_points"] = 3.0
		c["military_access"] = []  # naciones que NOS dan acceso
		c["guarantees"] = []  # naciones cuya independencia garantizamos
		c["truces"] = {}  # tag -> mes en que termina
		c["overlord"] = ""
		c["subjects"] = []
		c["wars"] = []  # ids de guerra
		# los aliados históricos se dan acceso mutuo
		for a in c["allies"]:
			if not (a in c["military_access"]):
				c["military_access"].append(a)


# --------------------------------------------------------------- consultas
static func are_allied(gs: VGameState, a: String, b: String) -> bool:
	return b in gs.countries.get(a, {}).get("allies", [])


static func has_access(gs: VGameState, actor: String, host: String) -> bool:
	return host in gs.countries.get(actor, {}).get("military_access", [])


static func truce_with(gs: VGameState, a: String, b: String) -> int:
	return int(gs.countries.get(a, {}).get("truces", {}).get(b, -1))


static func in_truce(gs: VGameState, a: String, b: String) -> bool:
	return truce_with(gs, a, b) > gs.month_index


static func set_truce(gs: VGameState, a: String, b: String, months: int) -> void:
	if not gs.countries.has(a) or not gs.countries.has(b):
		return
	gs.countries[a]["truces"][b] = gs.month_index + months
	gs.countries[b]["truces"][a] = gs.month_index + months


## ¿Comparten frontera terrestre (o paso)?
static func neighbors(gs: VGameState, a: String, b: String) -> bool:
	return b in neighbor_countries(gs, a)


static func neighbor_countries(gs: VGameState, tag: String) -> Array:
	var cache: Dictionary = gs.market.get("_neighbor_cache", {})
	var key := "%s@%d" % [tag, gs.month_index]
	if cache.has(key):
		return cache[key]
	var out := {}
	for id in gs.countries.get(tag, {}).get("provinces", []):
		for n in gs.provinces[id]["neighbors"]:
			if gs.is_land(n):
				var o: String = gs.provinces[n]["owner"]
				if o != "" and o != tag:
					out[o] = true
	var arr: Array = out.keys()
	if cache.size() > 400:
		cache.clear()
	cache[key] = arr
	gs.market["_neighbor_cache"] = cache
	return arr


## Fuerza militar aproximada (para decisiones de IA).
static func strength(gs: VGameState, tag: String) -> float:
	var c: Dictionary = gs.countries.get(tag, {})
	return float(c.get("military_score", 0.0)) + 1.0


# --------------------------------------------------------------- acciones
static func check(gs: VGameState, actor: String, action: String, target: String) -> Dictionary:
	var res := {"ok": false, "reason": "", "cost": 0.0, "accept": true, "score": 0.0, "reasons": []}
	if not gs.countries.has(actor) or not gs.countries.has(target) or actor == target:
		res["reason"] = "Objetivo no válido."
		return res
	var a: Dictionary = gs.countries[actor]
	var t: Dictionary = gs.countries[target]
	if t["provinces"].is_empty():
		res["reason"] = "La nación no existe."
		return res
	var cost := float(gs.diplo_rules.get("costs", {}).get(action, 1.0))
	res["cost"] = cost
	if float(a.get("diplo_points", 0.0)) < cost:
		res["reason"] = "Faltan puntos diplomáticos (%.1f / %.1f)." % [float(a.get("diplo_points", 0.0)), cost]
		return res
	var at_war := VWarSystem.at_war_with(gs, actor, target)
	var rel := gs.relation(actor, target)
	match action:
		"improve_relations":
			if rel >= 200:
				res["reason"] = "Las relaciones ya son máximas."
				return res
			if at_war:
				res["reason"] = "Estáis en guerra."
				return res
		"decrease_relations":
			if rel <= -200:
				res["reason"] = "Las relaciones ya son mínimas."
				return res
		"offer_alliance":
			if are_allied(gs, actor, target):
				res["reason"] = "Ya sois aliados."
				return res
			if at_war:
				res["reason"] = "Estáis en guerra."
				return res
			_ai_eval_alliance(gs, actor, target, res)
		"break_alliance":
			if not are_allied(gs, actor, target):
				res["reason"] = "No sois aliados."
				return res
			if VWarSystem.shared_war(gs, actor, target):
				res["reason"] = "Estáis luchando juntos en una guerra."
				return res
		"guarantee":
			if target in a["guarantees"]:
				res["reason"] = "Ya la garantizas."
				return res
			if at_war:
				res["reason"] = "Estáis en guerra."
				return res
		"request_access":
			if has_access(gs, actor, target):
				res["reason"] = "Ya tienes acceso militar."
				return res
			if at_war:
				res["reason"] = "Estáis en guerra."
				return res
			_ai_eval_access(gs, actor, target, res)
		"give_access":
			if has_access(gs, target, actor):
				res["reason"] = "Ya le das acceso militar."
				return res
		"cancel_access":
			if not has_access(gs, target, actor):
				res["reason"] = "No le das acceso militar."
				return res
		_:
			res["reason"] = "Acción desconocida."
			return res
	if not res["accept"]:
		res["reason"] = "%s no aceptaría: %s" % [gs.country_name(target), "; ".join(res["reasons"])]
		return res
	res["ok"] = true
	return res


static func _ai_eval_alliance(gs: VGameState, actor: String, target: String, res: Dictionary) -> void:
	var rel := gs.relation(actor, target)
	var score := 0.0
	var reasons := []
	score += float(rel) / 25.0
	reasons.append("relaciones %+d" % rel)
	var min_rel := int(gs.diplo_rules.get("alliance_min_relations", 50))
	if rel < min_rel:
		score -= 4.0
		reasons.append("relaciones por debajo de %d" % min_rel)
	var ratio := strength(gs, actor) / strength(gs, target)
	if ratio > 1.5:
		score += 2.0
		reasons.append("es una potencia más fuerte")
	elif ratio < 0.5:
		score -= 2.0
		reasons.append("es mucho más débil")
	var inf := float(gs.countries[actor].get("infamy", 0.0))
	if inf > 10.0:
		score -= inf / 5.0
		reasons.append("infamia %.1f" % inf)
	if neighbors(gs, actor, target):
		score += 1.0
		reasons.append("vecinos")
	for w in gs.countries[actor]["wars"]:
		score -= 3.0
		reasons.append("está en guerra")
		break
	for e in gs.countries[target].get("rivals", []):
		if e in gs.countries[actor]["allies"]:
			score -= 3.0
			reasons.append("es aliado de un rival")
	res["score"] = score
	res["reasons"] = reasons
	res["accept"] = score > 0.0


static func _ai_eval_access(gs: VGameState, actor: String, target: String, res: Dictionary) -> void:
	var rel := gs.relation(actor, target)
	var score := float(rel) / 30.0 + 1.0
	var reasons := ["relaciones %+d" % rel]
	if are_allied(gs, actor, target):
		score += 3.0
		reasons.append("aliados")
	for wid in gs.countries[actor]["wars"]:
		var w: Dictionary = gs.wars.get(wid, {})
		for enemy in VWarSystem.enemies_in_war(gs, w, actor):
			if gs.relation(target, enemy) > 50 or are_allied(gs, target, enemy):
				score -= 4.0
				reasons.append("es amiga de %s" % gs.country_name(enemy))
	res["score"] = score
	res["reasons"] = reasons
	res["accept"] = score > 0.0


static func perform(gs: VGameState, actor: String, action: String, target: String) -> String:
	var chk := check(gs, actor, action, target)
	if not chk["ok"]:
		return chk["reason"]
	var a: Dictionary = gs.countries[actor]
	var t: Dictionary = gs.countries[target]
	a["diplo_points"] = float(a["diplo_points"]) - float(chk["cost"])
	var step := int(gs.diplo_rules.get("relation_change", 15))
	match action:
		"improve_relations":
			gs.set_relation(actor, target, gs.relation(actor, target) + step)
		"decrease_relations":
			gs.set_relation(actor, target, gs.relation(actor, target) - step)
		"offer_alliance":
			a["allies"].append(target)
			t["allies"].append(actor)
			gs.set_relation(actor, target, gs.relation(actor, target) + 20)
			gs.log_event(actor, "Alianza con %s" % gs.country_name(target))
			gs.log_event(target, "Alianza con %s" % gs.country_name(actor))
		"break_alliance":
			a["allies"].erase(target)
			t["allies"].erase(actor)
			gs.set_relation(actor, target, gs.relation(actor, target) - 50)
			gs.log_event(actor, "Rota la alianza con %s" % gs.country_name(target))
		"guarantee":
			a["guarantees"].append(target)
			gs.set_relation(actor, target, gs.relation(actor, target) + 10)
		"request_access":
			a["military_access"].append(target)
		"give_access":
			t["military_access"].append(actor)
			gs.set_relation(actor, target, gs.relation(actor, target) + 5)
		"cancel_access":
			t["military_access"].erase(actor)
			gs.set_relation(actor, target, gs.relation(actor, target) - 10)
	if action in ["offer_alliance", "break_alliance", "request_access", "give_access", "cancel_access"]:
		VUnitIndex.bump_access(gs)
	return ""


# ----------------------------------------------------------------- mensual
static func monthly(gs: VGameState) -> void:
	var r: Dictionary = gs.diplo_rules
	var drift := int(r.get("relation_drift_per_month", 1))
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		if c["provinces"].is_empty():
			continue
		var gain := float(r.get("diplo_points_per_month", 0.6))
		if c.get("status", "") == "great_power":
			gain += float(r.get("diplo_points_gp_bonus", 0.4))
		c["diplo_points"] = minf(float(r.get("diplo_points_max", 9.0)), float(c.get("diplo_points", 0.0)) + gain)
		# las relaciones vuelven lentamente hacia 0 (salvo entre aliados)
		if (gs.month_index + tag.hash()) % 6 == 0:
			for other in c["relations"].keys():
				var v := int(c["relations"][other])
				if v == 0 or are_allied(gs, tag, other):
					continue
				gs.set_relation(tag, other, v - drift * signi(v))
		# limpiar treguas vencidas
		for other in c["truces"].keys():
			if int(c["truces"][other]) <= gs.month_index:
				c["truces"].erase(other)


## IA diplomática (trimestral y escalonada por nación).
static func ai_monthly(gs: VGameState) -> void:
	if gs.flags.get("ai_disabled", false):
		return
	for tag in gs.country_order:
		if tag == gs.player_tag or (gs.month_index + absi(tag.hash())) % 3 != 0:
			continue
		var c: Dictionary = gs.countries[tag]
		if c["provinces"].is_empty():
			continue
		var neigh := neighbor_countries(gs, tag)
		# mejorar relaciones con el vecino más importante con el que no se está en guerra
		var best := ""
		var best_v := -INF
		for n in neigh:
			if VWarSystem.at_war_with(gs, tag, n):
				continue
			var v := strength(gs, n) / maxf(1.0, strength(gs, tag)) * 10.0 - absf(float(gs.relation(tag, n)) - 80.0) / 40.0
			if v > best_v:
				best_v = v
				best = n
		if best != "" and gs.relation(tag, best) < 120 and float(c["diplo_points"]) >= 3.0:
			perform(gs, tag, "improve_relations", best)
		# buscar alianza con un vecino fuerte y amistoso
		if c["allies"].size() < 3 and float(c["diplo_points"]) >= 4.0:
			for n in neigh:
				if n == gs.player_tag:
					continue
				var chk := check(gs, tag, "offer_alliance", n)
				if chk["ok"] and gs.relation(tag, n) > 80:
					perform(gs, tag, "offer_alliance", n)
					break
		# dar acceso militar a los aliados
		for al in c["allies"]:
			if not has_access(gs, al, tag) and float(c["diplo_points"]) >= 1.0:
				perform(gs, tag, "give_access", al)
