class_name VPoliticsSystem
extends RefCounted
## Política: partidos, gobierno, elecciones, cámara alta, reformas por niveles y movimientos.
##
## - Partidos: generados por plantillas (party_templates.json) para cada nación; cada uno con
##   ideología y políticas (económica, comercial, religiosa, ciudadanía, guerra). Solo pueden gobernar
##   los de ideologías permitidas por el gobierno.
## - Elecciones (gobiernos con elections): cada N meses; votan los POPs según el nivel de la reforma
##   de voto; el voto de un POP se reparte según su mezcla ideológica y su acuerdo con las políticas.
## - Cámara alta: deriva hacia la ideología de los votantes (o de los ricos si no hay elecciones).
## - Reformas: un nivel cada vez; requieren que el gobierno lo permita, respetar los topes del
##   gobierno, apoyo de la cámara alta (más presión de movimientos) y un tiempo de espera.
## - Movimientos: POPs con conciencia que desean un nivel mayor de una reforma; si se ignoran
##   ganan organización y radicalismo, que empuja la militancia de sus partidarios.

const POLICY_ISSUE := {"economic_policy": "economic_policy", "trade_policy": "trade", "religious_policy": "religious_policy",
	"citizenship_policy": "citizenship", "war_policy": "military_policy"}


static func setup_new_game(gs: VGameState) -> void:
	for tag in gs.countries:
		var c: Dictionary = gs.countries[tag]
		var reforms := {}
		for rid in gs.reform_order:
			reforms[rid] = int(gs.reforms[rid].get("default", 0))
		for rid in c.get("reforms", {}):
			reforms[rid] = int(c["reforms"][rid])
		c["reforms"] = reforms
		_apply_caps(gs, tag)
		c["parties"] = build_parties(gs, tag)
		var ruling_ideo: String = c.get("ruling_party", {}).get("ideology", "conservador")
		c["ruling_party_index"] = _party_index_for(gs, tag, ruling_ideo)
		_sync_ruling_party(gs, tag)
		var gov: Dictionary = gs.governments.get(c["government"], {})
		var interval := int(gov.get("election_interval_months", 48))
		c["next_election_month"] = (tag.hash() & 0x7fffffff) % interval + 6 if gov.get("elections", false) else -1
		c["last_election"] = {}
		c["upper_house"] = {}
		c["movements"] = {}
		c["reform_cooldown"] = 0
		c["acc_mobility"] = {}


static func _apply_caps(gs: VGameState, tag: String) -> void:
	var c: Dictionary = gs.countries[tag]
	var caps: Dictionary = gs.governments.get(c["government"], {}).get("reform_caps", {})
	for rid in caps:
		if c["reforms"].has(rid):
			c["reforms"][rid] = mini(int(c["reforms"][rid]), int(caps[rid]))


static func build_parties(gs: VGameState, tag: String) -> Array:
	var c: Dictionary = gs.countries[tag]
	if c.has("custom_parties"):
		return c["custom_parties"]
	var short := VMapLabels.short_name(c["name"])
	var out := []
	for t in gs.party_templates:
		out.append({"name": "%s de %s" % [t["name"], short], "ideology": t["ideology"], "policies": t["policies"].duplicate(),
			"requires_reform": t.get("requires_reform", {})})
	return out


static func party_available(gs: VGameState, tag: String, party: Dictionary) -> bool:
	var req: Dictionary = party.get("requires_reform", {})
	for r in req:
		if gs.reform_level(tag, r) < int(req[r]):
			return false
	return true


static func party_can_rule(gs: VGameState, tag: String, party: Dictionary) -> bool:
	var allowed: Array = gs.governments.get(gs.countries[tag]["government"], {}).get("allowed_parties", [])
	return party_available(gs, tag, party) and (allowed.is_empty() or party["ideology"] in allowed)


static func _party_index_for(gs: VGameState, tag: String, ideology: String) -> int:
	var parties: Array = gs.countries[tag]["parties"]
	for i in parties.size():
		if parties[i]["ideology"] == ideology:
			return i
	return 0


static func ruling_party(gs: VGameState, tag: String) -> Dictionary:
	var c: Dictionary = gs.countries.get(tag, {})
	var parties: Array = c.get("parties", [])
	var i := int(c.get("ruling_party_index", 0))
	return parties[i] if i >= 0 and i < parties.size() else {}


static func _sync_ruling_party(gs: VGameState, tag: String) -> void:
	var p := ruling_party(gs, tag)
	if not p.is_empty():
		gs.countries[tag]["ruling_party"] = {"name": p["name"], "ideology": p["ideology"]}


## Cambio de partido por designación (gobiernos sin elecciones).
static func appoint_party(gs: VGameState, tag: String, index: int) -> String:
	var c: Dictionary = gs.countries[tag]
	var gov: Dictionary = gs.governments.get(c["government"], {})
	if not gov.get("appoint_ruling_party", false):
		return "Este gobierno no designa partido: el gobierno sale de las elecciones."
	var party: Dictionary = c["parties"][index]
	if not party_can_rule(gs, tag, party):
		return "Ese partido no puede gobernar con la forma de gobierno o las reformas actuales."
	c["ruling_party_index"] = index
	_sync_ruling_party(gs, tag)
	gs.log_event(tag, "Nuevo gobierno: %s" % party["name"])
	return ""


# -------------------------------------------------------------- mensual
static func monthly(gs: VGameState, tag: String, is_player: bool) -> void:
	var c: Dictionary = gs.countries[tag]
	if c["provinces"].is_empty():
		return
	c["reform_cooldown"] = maxi(0, int(c["reform_cooldown"]) - 1)
	var voters: Dictionary = c.get("voter_ideology", {})
	if voters.is_empty():
		voters = _voter_mix(gs, tag)
	_update_upper_house(gs, tag, voters, 0.03)
	if (gs.month_index + tag.hash()) % 3 == 0:
		_update_movements(gs, tag)
	var gov: Dictionary = gs.governments.get(c["government"], {})
	if gov.get("elections", false) and int(c["next_election_month"]) >= 0 and gs.month_index >= int(c["next_election_month"]):
		hold_election(gs, tag)
	if not is_player:
		_ai_reforms(gs, tag)


## Mezcla ideológica de quienes votan (según la reforma de voto) o de los ricos si no hay voto.
static func _voter_mix(gs: VGameState, tag: String) -> Dictionary:
	var rule := vote_rule(gs, tag)
	var out := {}
	var total := 0.0
	for id in gs.countries[tag]["provinces"]:
		for pop in gs.provinces[id]["pops"]:
			var w := vote_weight(gs, pop, rule)
			if w <= 0.0:
				continue
			for k in pop["ideology"]:
				out[k] = float(out.get(k, 0.0)) + float(pop["ideology"][k]) * w
			total += w
	if total > 0.0:
		for k in out:
			out[k] = float(out[k]) / total
	return out


static func vote_rule(gs: VGameState, tag: String) -> String:
	var lvl := gs.reform_level(tag, "voting")
	var levels: Array = gs.reforms.get("voting", {}).get("levels", [])
	if lvl < levels.size():
		return levels[lvl].get("effects", {}).get("vote_rule", "rich_only")
	return "rich_only"


static func vote_weight(gs: VGameState, pop: Dictionary, rule: String) -> float:
	var pt: Dictionary = gs.pop_types.get(pop["type"], {})
	var base := float(pt.get("vote_weight", 1)) * float(pop["size"])
	if base <= 0.0:
		return 0.0
	match rule:
		"rich_only":
			return base if pt.get("strata", "") == "rich" else 0.0
		"wealth":
			return base if pt.get("strata", "") != "poor" else 0.0
		"weighted":
			return base
		"universal":
			return float(pop["size"])
	return 0.0


static func _update_upper_house(gs: VGameState, tag: String, voters: Dictionary, rate: float) -> void:
	var c: Dictionary = gs.countries[tag]
	var uh: Dictionary = c["upper_house"]
	if uh.is_empty():
		for k in voters:
			uh[k] = voters[k]
		return
	for k in voters:
		uh[k] = float(uh.get(k, 0.0)) * (1.0 - rate) + float(voters[k]) * rate
	for k in uh:
		if not voters.has(k):
			uh[k] = float(uh[k]) * (1.0 - rate)


## Elección: los POPs votan; el partido más votado (que pueda gobernar) forma gobierno.
static func hold_election(gs: VGameState, tag: String) -> Dictionary:
	var c: Dictionary = gs.countries[tag]
	var gov: Dictionary = gs.governments.get(c["government"], {})
	var rule := vote_rule(gs, tag)
	var parties: Array = c["parties"]
	var votes := []
	votes.resize(parties.size())
	votes.fill(0.0)
	var total := 0.0
	for id in c["provinces"]:
		for pop in gs.provinces[id]["pops"]:
			var w := vote_weight(gs, pop, rule)
			if w <= 0.0:
				continue
			var issues: Dictionary = pop.get("issues", {})
			var scores := []
			var ssum := 0.0
			for i in parties.size():
				var party: Dictionary = parties[i]
				if not party_available(gs, tag, party):
					scores.append(0.0)
					continue
				var s := float(pop["ideology"].get(party["ideology"], 0.0)) + 0.02
				for pol in party["policies"]:
					if issues.get(POLICY_ISSUE.get(pol, pol), "") == party["policies"][pol]:
						s += 0.08
				scores.append(s)
				ssum += s
			if ssum <= 0.0:
				continue
			for i in parties.size():
				votes[i] = float(votes[i]) + w * float(scores[i]) / ssum
			total += w
	var winner := int(c["ruling_party_index"])
	var best := -1.0
	for i in parties.size():
		if party_can_rule(gs, tag, parties[i]) and float(votes[i]) > best:
			best = float(votes[i])
			winner = i
	var result := {"month": gs.month_index, "date": gs.date.text(), "votes": votes, "total": total, "winner": winner}
	c["last_election"] = result
	var changed := winner != int(c["ruling_party_index"])
	c["ruling_party_index"] = winner
	_sync_ruling_party(gs, tag)
	c["next_election_month"] = gs.month_index + int(gov.get("election_interval_months", 48))
	# la cámara alta se renueva parcialmente con los votantes
	_update_upper_house(gs, tag, _voter_mix(gs, tag), 0.3)
	gs.log_event(tag, "Elecciones: gana %s (%.0f%%)%s" % [parties[winner]["name"], best / maxf(1.0, total) * 100.0, "" if changed else " — continúa en el gobierno"])
	return result


# ------------------------------------------------------------- reformas
## {"ok": bool, "reason": String, "support": float, "against": float}
static func can_change_reform(gs: VGameState, tag: String, rid: String, direction: int) -> Dictionary:
	var c: Dictionary = gs.countries[tag]
	var r: Dictionary = gs.reforms.get(rid, {})
	var gov: Dictionary = gs.governments.get(c["government"], {})
	var lvl := gs.reform_level(tag, rid)
	var new_lvl := lvl + direction
	var res := {"ok": false, "reason": "", "support": 0.0, "against": 0.0}
	if r.is_empty() or new_lvl < 0 or new_lvl >= r["levels"].size():
		res["reason"] = "No hay más niveles en esa dirección."
		return res
	if not gov.get("can_reform", true):
		res["reason"] = "Esta forma de gobierno no permite reformas."
		return res
	var caps: Dictionary = gov.get("reform_caps", {})
	if direction > 0 and caps.has(rid) and new_lvl > int(caps[rid]):
		res["reason"] = "El gobierno (%s) no permite superar «%s»." % [gov.get("name", ""), r["levels"][int(caps[rid])]["name"]]
		return res
	if int(c.get("reform_cooldown", 0)) > 0:
		res["reason"] = "Hay que esperar %d meses desde la última reforma." % int(c["reform_cooldown"])
		return res
	var kind: String = r.get("type", "political")
	var uh: Dictionary = c.get("upper_house", {})
	var support := 0.0
	var against := 0.0
	# presión social: con militancia alta los conservadores aceptan reformas para calmar al país
	var pressure := clampf(float(c.get("avg_militancy", 0.0)) / 4.0, 0.0, 1.0)
	for ideo in uh:
		var s := float(gs.ideologies.get(ideo, {}).get("reform_support", {}).get(kind, 0.0)) * float(direction)
		if direction > 0 and gs.ideologies.get(ideo, {}).get("group", "") == "conservative" and ideo != "tradicionalista":
			s += pressure * 0.8
		if s > 0.0:
			support += float(uh[ideo]) * s
		else:
			against += float(uh[ideo]) * -s
	if direction > 0:
		var mv: Dictionary = c.get("movements", {}).get(rid, {})
		support += float(mv.get("support", 0.0)) * 2.0 + float(mv.get("radicalism", 0.0)) * 0.2
	# el partido gobernante también pesa
	var rp := ruling_party(gs, tag)
	var rps := float(gs.ideologies.get(rp.get("ideology", ""), {}).get("reform_support", {}).get(kind, 0.0)) * float(direction)
	support += maxf(0.0, rps) * 0.15
	against += maxf(0.0, -rps) * 0.15
	res["support"] = support
	res["against"] = against
	if support <= against:
		res["reason"] = "La cámara alta no apoya el cambio (a favor %.0f%% · en contra %.0f%%)." % [support * 100.0, against * 100.0]
		return res
	res["ok"] = true
	return res


static func change_reform(gs: VGameState, tag: String, rid: String, direction: int) -> String:
	var chk := can_change_reform(gs, tag, rid, direction)
	if not chk["ok"]:
		return chk["reason"]
	var c: Dictionary = gs.countries[tag]
	var old := gs.reform_level(tag, rid)
	c["reforms"][rid] = old + direction
	c["reform_cooldown"] = int(gs.reform_meta.get("cooldown_months", 6))
	VModifiers.recompute(gs, tag)
	var r: Dictionary = gs.reforms[rid]
	if direction > 0 and c["movements"].has(rid):
		var mv: Dictionary = c["movements"][rid]
		mv["radicalism"] = float(mv.get("radicalism", 0.0)) * 0.3
		mv["organisation"] = float(mv.get("organisation", 0.0)) * 0.5
	# consciencia satisfecha: baja algo la militancia de los partidarios
	gs.log_event(tag, "Reforma: %s → %s" % [r["name"], r["levels"][old + direction]["name"]])
	if rid == "slavery" and old + direction >= 1:
		gs.log_event(tag, "Abolición de la esclavitud: los esclavos pasan a ser campesinos libres")
	return ""


# ------------------------------------------------------------ movimientos
static func _issue_index(gs: VGameState) -> Dictionary:
	var cache: Dictionary = gs.market.get("_issue_idx", {})
	if cache.is_empty():
		for iid in gs.issues:
			var m := {}
			var positions: Array = gs.issues[iid].get("positions", [])
			for i in positions.size():
				m[positions[i]["id"]] = i
			cache[iid] = m
		gs.market["_issue_idx"] = cache
	return cache


static func desired_level(gs: VGameState, pop: Dictionary, rid: String, current: int) -> int:
	var r: Dictionary = gs.reforms[rid]
	var issue: String = r.get("issue", "")
	var pos: String = pop.get("issues", {}).get(issue, "")
	if pos == "":
		return current
	var idx := int(_issue_index(gs).get(issue, {}).get(pos, -1))
	if idx < 0:
		return current
	var max_lvl: int = r["levels"].size() - 1
	if issue == "suffrage":
		return mini(idx, max_lvl)
	if issue == "slavery":
		return 1 if pos == "abolish_slavery" else 0
	# reforma política/social: ninguna = no pide más, moderada = +1, amplia = máximo
	if idx == 0:
		return current
	if idx == 1:
		return mini(current + 1, max_lvl)
	return max_lvl


## Recalcula apoyo/organización/radicalismo (una pasada por los POPs de la nación).
## La radicalización acumulada empuja la militancia de quienes apoyan el movimiento.
static func _update_movements(gs: VGameState, tag: String) -> void:
	var c: Dictionary = gs.countries[tag]
	var total := maxf(1.0, float(c.get("population", 1)))
	var mvs: Dictionary = c["movements"]
	var cur := {}
	for rid in gs.reform_order:
		cur[rid] = gs.reform_level(tag, rid)
	var support := {}
	for id in c["provinces"]:
		for pop in gs.provinces[id]["pops"]:
			var con := float(pop["consciousness"])
			if con < 1.5:
				pop["movement_push"] = 0.0
				continue
			var push := 0.0
			for rid in gs.reform_order:
				if desired_level(gs, pop, rid, int(cur[rid])) > int(cur[rid]):
					support[rid] = float(support.get(rid, 0.0)) + float(pop["size"]) * minf(1.0, con / 6.0)
					push = maxf(push, float(mvs.get(rid, {}).get("radicalism", 0.0)) * 0.03)
			pop["movement_push"] = push
	var names: Dictionary = gs.reform_meta.get("movement_names", {})
	for rid in gs.reform_order:
		var share := float(support.get(rid, 0.0)) / total
		var mv: Dictionary = mvs.get(rid, {"name": names.get(rid, rid), "support": 0.0, "organisation": 0.0, "radicalism": 0.0, "months": 0})
		mv["support"] = share
		if share > 0.03:
			mv["organisation"] = minf(1.0, float(mv["organisation"]) + 0.05 * share * 10.0)
			mv["months"] = int(mv["months"]) + 3
			if share > 0.08 and float(mv["organisation"]) > 0.3:
				mv["radicalism"] = minf(1.0, float(mv["radicalism"]) + 0.02 * float(mv["organisation"]))
		else:
			mv["organisation"] = maxf(0.0, float(mv["organisation"]) - 0.05)
			mv["radicalism"] = maxf(0.0, float(mv["radicalism"]) - 0.03)
		mv["rebel_risk"] = float(mv["radicalism"]) > 0.8
		if share > 0.001 or mvs.has(rid):
			mvs[rid] = mv


## IA: concede reformas reclamadas por movimientos fuertes si la cámara lo permite.
static func _ai_reforms(gs: VGameState, tag: String) -> void:
	var c: Dictionary = gs.countries[tag]
	if int(c.get("reform_cooldown", 0)) > 0:
		return
	var best := ""
	var best_v := 0.0
	for rid in c["movements"]:
		var mv: Dictionary = c["movements"][rid]
		var v := float(mv["support"]) + float(mv["radicalism"])
		if v > best_v and v > 0.12:
			best_v = v
			best = rid
	if best != "":
		change_reform(gs, tag, best, 1)
