class_name VWarSystem
extends RefCounted
## Guerras como entidades reales.
##
## War: id, name, start, attackers[], defenders[], primary_attacker/defender, war_goals[],
## battle_ws, occupation_ws, blockade_ws, ticking_ws, total_ws (perspectiva del atacante, −100…+100).
## country.wars = [ids].
##
## Ocupación (asedio): un ejército quieto en una provincia controlada por un enemigo, sin ejércitos
## enemigos presentes, hace avanzar province.occupation según su tamaño, ingenieros/asedio,
## reconocimiento, fortificación y terreno. Al 100 % cambia province.controller — NUNCA owner.
## La propiedad solo cambia en VPeaceSystem.


# ------------------------------------------------------------------ consultas
## Caché de relaciones bélicas (enemigos / mismo bando) por nación, válida mientras no cambie
## gs.access_version (se incrementa al declarar, unirse, retirarse, firmar la paz o cambiar propiedad).
static func _relations(gs: VGameState) -> Dictionary:
	var wc := gs.war_cache
	if not wc.is_empty() and int(wc["ver"]) == gs.access_version:
		return wc
	var enemies := {}
	var friends := {}
	for wid in gs.wars:
		var w: Dictionary = gs.wars[wid]
		for pair in [[w["attackers"], w["defenders"]], [w["defenders"], w["attackers"]]]:
			for a in pair[0]:
				if not enemies.has(a):
					enemies[a] = {}
					friends[a] = {}
				for b in pair[1]:
					enemies[a][b] = true
				for b in pair[0]:
					friends[a][b] = true
	wc = {"ver": gs.access_version, "enemies": enemies, "friends": friends}
	gs.war_cache = wc
	return wc


static func at_war_with(gs: VGameState, a: String, b: String) -> bool:
	if a == "" or b == "" or a == b:
		return false
	var e: Dictionary = _relations(gs)["enemies"].get(a, {})
	return e.has(b)


static func war_between(gs: VGameState, a: String, b: String) -> int:
	if not gs.countries.has(a):
		return 0
	for wid in gs.countries[a].get("wars", []):
		var w: Dictionary = gs.wars.get(int(wid), {})
		if not w.is_empty() and ((a in w["attackers"] and b in w["defenders"]) or (a in w["defenders"] and b in w["attackers"])):
			return int(wid)
	return 0


static func shared_war(gs: VGameState, a: String, b: String) -> bool:
	var f: Dictionary = _relations(gs)["friends"].get(a, {})
	return f.has(b)


## Enemigos actuales de 'a' (diccionario tag → true de la caché; no modificar).
static func enemies_of(gs: VGameState, a: String) -> Dictionary:
	return _relations(gs)["enemies"].get(a, {})


static func side_of(w: Dictionary, tag: String) -> String:
	if tag in w.get("attackers", []):
		return "attackers"
	if tag in w.get("defenders", []):
		return "defenders"
	return ""


static func enemies_in_war(gs: VGameState, w: Dictionary, tag: String) -> Array:
	var s := side_of(w, tag)
	if s == "":
		return []
	return w["defenders"] if s == "attackers" else w["attackers"]


static func is_at_war(gs: VGameState, tag: String) -> bool:
	return not gs.countries.get(tag, {}).get("wars", []).is_empty()


## Warscore desde la perspectiva de 'tag'.
static func warscore_for(w: Dictionary, tag: String) -> float:
	var ws := float(w.get("total_ws", 0.0))
	return ws if side_of(w, tag) == "attackers" else -ws


# --------------------------------------------------------------- inicio
static func setup_new_game(gs: VGameState, history_wars: Array) -> void:
	for hw in history_wars:
		var att: Array = hw.get("attackers", [])
		var dfn: Array = hw.get("defenders", [])
		if att.is_empty() or dfn.is_empty() or not gs.countries.has(att[0]) or not gs.countries.has(dfn[0]):
			continue
		var w := _new_war(gs, att[0], dfn[0], hw.get("name", ""))
		for t in att.slice(1):
			_join(gs, w, t, "attackers")
		for t in dfn.slice(1):
			_join(gs, w, t, "defenders")
		w["war_goals"].append({"id": gs.new_id("goal"), "type": "humiliate", "actor": att[0], "target": dfn[0], "state_id": 0})


static func _new_war(gs: VGameState, attacker: String, defender: String, war_name: String = "") -> Dictionary:
	var id := gs.new_id("war")
	var w := {"id": id, "name": war_name if war_name != "" else "Guerra %s–%s" % [VMapLabels.short_name(gs.country_name(attacker)), VMapLabels.short_name(gs.country_name(defender))],
		"start": gs.date.text(), "start_month": gs.month_index, "start_ordinal": gs.date.ordinal(),
		"attackers": [], "defenders": [], "primary_attacker": attacker, "primary_defender": defender, "war_goals": [],
		"battle_ws": 0.0, "occupation_ws": 0.0, "blockade_ws": 0.0, "ticking_ws": 0.0, "total_ws": 0.0, "offer": {}}
	gs.wars[id] = w
	_join(gs, w, attacker, "attackers")
	_join(gs, w, defender, "defenders")
	return w


static func _join(gs: VGameState, w: Dictionary, tag: String, side: String) -> void:
	if tag in w["attackers"] or tag in w["defenders"]:
		return
	w[side].append(tag)
	gs.countries[tag]["wars"].append(int(w["id"]))
	VUnitIndex.bump_access(gs)


static func can_declare(gs: VGameState, actor: String, cb: Dictionary) -> String:
	var target: String = cb.get("target", "")
	if not gs.countries.has(target) or gs.countries[target]["provinces"].is_empty():
		return "El objetivo ya no existe."
	if cb.get("owner", "") != actor:
		return "Ese casus belli no es tuyo."
	if at_war_with(gs, actor, target):
		return "Ya estáis en guerra."
	if VDiplomacySystem.are_allied(gs, actor, target):
		return "Primero hay que romper la alianza."
	if VDiplomacySystem.in_truce(gs, actor, target):
		return "Hay una tregua vigente con %s durante %d meses más." % [gs.country_name(target), VDiplomacySystem.truce_with(gs, actor, target) - gs.month_index]
	if gs.countries[actor].get("overlord", "") == target:
		return "No puedes declarar la guerra a tu señor."
	var cost := float(gs.diplo_rules.get("costs", {}).get("declare_war", 2.0))
	if float(gs.countries[actor].get("diplo_points", 0.0)) < cost:
		return "Faltan puntos diplomáticos (%.1f)." % cost
	return ""


## Declara la guerra usando un CB (se consume). Llama a los aliados de ambos bandos.
static func declare_war(gs: VGameState, actor: String, cb: Dictionary) -> Dictionary:
	var err := can_declare(gs, actor, cb)
	if err != "":
		return {"error": err}
	var target: String = cb["target"]
	gs.countries[actor]["diplo_points"] = float(gs.countries[actor]["diplo_points"]) - float(gs.diplo_rules.get("costs", {}).get("declare_war", 2.0))
	var w := _new_war(gs, actor, target)
	w["war_goals"].append({"id": gs.new_id("goal"), "type": cb["type"], "actor": actor, "target": target, "state_id": int(cb.get("state_id", 0))})
	VCasusBelliSystem.remove_cb(gs, int(cb["id"]))
	gs.set_relation(actor, target, gs.relation(actor, target) - 100)
	gs.log_event(actor, "Declaramos la guerra a %s (%s)" % [gs.country_name(target), VCasusBelliSystem.cb_def(gs, cb["type"]).get("name", "")])
	gs.log_event(target, "¡%s nos declara la guerra!" % gs.country_name(actor))
	VEventSystem.notify(gs, "war_declared", {"tag": actor, "target": target, "war": int(w["id"])})
	VEventSystem.notify(gs, "war_declared", {"tag": target, "target": actor, "from": actor, "war": int(w["id"])})
	# defensores: aliados y garantes del objetivo
	for t in gs.country_order:
		if t == target or t == actor or gs.countries[t]["provinces"].is_empty():
			continue
		var c: Dictionary = gs.countries[t]
		if target in c["allies"] or target in c.get("guarantees", []):
			call_ally(gs, w, target, t)
	for al in gs.countries[actor]["allies"].duplicate():
		call_ally(gs, w, actor, al)
	return {"war": w}


## Llamada a un aliado: la IA decide según relaciones, amenaza, fuerza, infamia, vecindad y objetivo.
static func call_ally(gs: VGameState, w: Dictionary, caller: String, ally: String) -> Dictionary:
	var side := side_of(w, caller)
	if side == "" or side_of(w, ally) != "" or not gs.countries.has(ally) or gs.countries[ally]["provinces"].is_empty():
		return {"joined": false, "reasons": ["no aplicable"]}
	var enemies: Array = w["defenders"] if side == "attackers" else w["attackers"]
	for e in enemies:
		if VDiplomacySystem.are_allied(gs, ally, e) or VDiplomacySystem.in_truce(gs, ally, e):
			return {"joined": false, "reasons": ["aliado o en tregua con el enemigo"]}
	var reasons := []
	var score := float(gs.relation(ally, caller)) / 40.0
	reasons.append("relaciones %+d" % gs.relation(ally, caller))
	if VDiplomacySystem.are_allied(gs, ally, caller):
		score += 3.0
		reasons.append("alianza")
	if caller in gs.countries[ally].get("guarantees", []):
		score += 2.0
		reasons.append("garantía")
	var enemy_power := 0.0
	for e in enemies:
		enemy_power += VDiplomacySystem.strength(gs, e)
		if VDiplomacySystem.neighbors(gs, ally, e):
			score += 0.5
			reasons.append("amenaza vecina")
		score += float(gs.relation(ally, e)) / -80.0
	var own := VDiplomacySystem.strength(gs, ally) + VDiplomacySystem.strength(gs, caller)
	if enemy_power > own * 1.5:
		score -= 2.0
		reasons.append("enemigo muy superior")
	if is_at_war(gs, ally):
		score -= 3.0
		reasons.append("ya está en guerra")
	if side == "defenders":
		score += float(gs.countries[w["primary_attacker"]].get("infamy", 0.0)) / 8.0 + 1.0
		reasons.append("guerra defensiva")
	var joined := score > 0.0 or ally == gs.player_tag
	if joined:
		_join(gs, w, ally, side)
		gs.log_event(ally, "Entramos en la %s junto a %s" % [w["name"], gs.country_name(caller)])
	else:
		gs.log_event(caller, "%s rechaza unirse a la %s" % [gs.country_name(ally), w["name"]])
		if VDiplomacySystem.are_allied(gs, ally, caller):
			gs.set_relation(ally, caller, gs.relation(ally, caller) - 30)
	return {"joined": joined, "reasons": reasons, "score": score}


# ------------------------------------------------------------ objetivos
static func jingoism_support(gs: VGameState, tag: String) -> float:
	var t := 0.0
	var j := 0.0
	var ps := gs.pops
	for id in gs.countries[tag]["provinces"]:
		for ps_s in gs.provinces[id]["pop_slots"]:
			var s := float(ps.size[ps_s])
			t += s
			var mp: String = ps.issues[ps_s].get("military_policy", "")
			if mp == "jingoism" or mp == "pro_military":
				j += s
	return j / t if t > 0.0 else 0.0


## Añadir objetivo durante la guerra: requiere CB contra un enemigo de la guerra, o bien
## (sin CB) apoyo belicista ≥ 35 %, warscore ≥ 10 y las condiciones del CB; con más infamia.
static func can_add_wargoal(gs: VGameState, war_id: int, actor: String, cb_type: String, target: String, state_id: int = 0) -> Dictionary:
	var res := {"ok": false, "reason": "", "infamy": 0.0}
	var w: Dictionary = gs.wars.get(war_id, {})
	if w.is_empty() or side_of(w, actor) == "":
		res["reason"] = "No participas en esa guerra."
		return res
	if not (target in enemies_in_war(gs, w, actor)):
		res["reason"] = "El objetivo no es un enemigo en esta guerra."
		return res
	for g in w["war_goals"]:
		if g["actor"] == actor and g["type"] == cb_type and g["target"] == target and int(g.get("state_id", 0)) == state_id:
			res["reason"] = "Ese objetivo ya está en la guerra."
			return res
	var d := VCasusBelliSystem.cb_def(gs, cb_type)
	var infamy := float(d.get("infamy", 0.0))
	var own_cb := VCasusBelliSystem.has_cb(gs, actor, target, cb_type, state_id)
	if own_cb.is_empty():
		var fail := VCasusBelliSystem.conditions_fail(gs, actor, target, cb_type, state_id)
		if fail != "":
			res["reason"] = fail
			return res
		var jingo := jingoism_support(gs, actor)
		if jingo < 0.35:
			res["reason"] = "Sin casus belli hace falta apoyo belicista ≥ 35 %% (ahora %.0f %%)." % (jingo * 100.0)
			return res
		if warscore_for(w, actor) < 10.0:
			res["reason"] = "Sin casus belli hace falta ir ganando la guerra (warscore ≥ 10)."
			return res
		infamy *= 1.5
	if float(gs.countries[actor].get("infamy", 0.0)) + infamy > float(gs.war_rules.get("max_infamy", 25.0)):
		res["reason"] = "La infamia superaría el máximo (%.1f)." % float(gs.war_rules.get("max_infamy", 25.0))
		return res
	res["ok"] = true
	res["infamy"] = infamy
	return res


static func add_wargoal(gs: VGameState, war_id: int, actor: String, cb_type: String, target: String, state_id: int = 0) -> String:
	var chk := can_add_wargoal(gs, war_id, actor, cb_type, target, state_id)
	if not chk["ok"]:
		return chk["reason"]
	var w: Dictionary = gs.wars[war_id]
	w["war_goals"].append({"id": gs.new_id("goal"), "type": cb_type, "actor": actor, "target": target, "state_id": state_id})
	gs.countries[actor]["infamy"] = float(gs.countries[actor].get("infamy", 0.0)) + float(chk["infamy"])
	var own_cb := VCasusBelliSystem.has_cb(gs, actor, target, cb_type, state_id)
	if not own_cb.is_empty():
		VCasusBelliSystem.remove_cb(gs, int(own_cb["id"]))
	gs.log_event(actor, "Nuevo objetivo de guerra: %s" % VCasusBelliSystem.goal_name(gs, {"type": cb_type, "actor": actor, "target": target, "state_id": state_id}))
	return ""


# --------------------------------------------------------- warscore diario
static func on_battle_end(gs: VGameState, bt: Dictionary, winner: String) -> void:
	var wid := int(bt.get("war", 0))
	if wid <= 0 or not gs.wars.has(wid):
		return
	var w: Dictionary = gs.wars[wid]
	var loser_losses := int(bt["losses"]["defender" if winner == "attacker" else "attacker"])
	var delta := clampf(1.0 + float(loser_losses) / 2500.0, 1.0, 8.0)
	var winner_tag: String = bt["att_tag"] if winner == "attacker" else bt["def_tag"]
	var sign := 1.0 if side_of(w, winner_tag) == "attackers" else -1.0
	w["battle_ws"] = clampf(float(w["battle_ws"]) + delta * sign, -40.0, 40.0)
	var loser_tag: String = bt["def_tag"] if winner == "attacker" else bt["att_tag"]
	VEventSystem.notify(gs, "battle_won", {"tag": winner_tag, "target": loser_tag, "prov": int(bt["province"])})
	VEventSystem.notify(gs, "battle_lost", {"tag": loser_tag, "target": winner_tag, "prov": int(bt["province"])})


## Cambio de controlador (único punto): mantiene la ocupación agregada por nación y la versión.
static func set_controller(gs: VGameState, id: int, ctrl: String) -> void:
	var p: Dictionary = gs.provinces[id]
	var old: String = p["controller"]
	if old == ctrl:
		return
	p["controller"] = ctrl
	gs.controller_version += 1
	var owner: String = p["owner"]
	if gs.ws_values_month < 0 or not gs.countries.has(owner):
		return
	var occ: Dictionary = gs.countries[owner].get("_occ", {})
	var v := float(p.get("_wsv", 0.0))
	if old != owner:
		occ[old] = float(occ.get(old, 0.0)) - v
		if float(occ[old]) <= 1e-6:
			occ.erase(old)
	if ctrl != owner:
		occ[ctrl] = float(occ.get(ctrl, 0.0)) + v
	gs.countries[owner]["_occ"] = occ


## Valores de warscore por provincia y agregados por nación (valor total, valor ocupado por cada
## controlador, provincias costeras). Se recalculan una vez al mes (la población cambia) o tras un
## cambio de propiedad; entre medias se mantienen con set_controller().
static func ensure_ws_values(gs: VGameState) -> void:
	if gs.ws_values_month == gs.month_index:
		return
	for tag in gs.countries:
		var c: Dictionary = gs.countries[tag]
		c["_ws_total"] = 0.0
		c["_occ"] = {}
		c["_coastal"] = 0
	for id in range(1, gs.first_sea_id):
		var p = gs.provinces[id]
		if p == null:
			continue
		var owner: String = p["owner"]
		if owner == "" or not gs.countries.has(owner):
			continue
		var c: Dictionary = gs.countries[owner]
		var v := _province_value(gs, p)
		p["_wsv"] = v
		c["_ws_total"] = float(c["_ws_total"]) + v
		if p.get("coastal", false):
			c["_coastal"] = int(c["_coastal"]) + 1
		var ctrl: String = p["controller"]
		if ctrl != owner:
			c["_occ"][ctrl] = float(c["_occ"].get(ctrl, 0.0)) + v
	gs.ws_values_month = gs.month_index


static func _province_value(gs: VGameState, p: Dictionary) -> float:
	var v := 1.0 + float(p["population"]) / 100000.0
	var owner: String = p["owner"]
	if gs.countries.has(owner) and int(gs.countries[owner].get("capital", -1)) == int(p["id"]):
		v *= 3.0
	return v


## Recalcula warscore, cansancio bélico y estado de cada guerra (diario).
static func daily(gs: VGameState) -> void:
	var t := VProfiler.begin()
	_daily_sieges(gs)
	VProfiler.end(gs, "sieges", t)
	t = VProfiler.begin()
	_daily_warscore(gs)
	VProfiler.end(gs, "war_score", t)


static func _daily_warscore(gs: VGameState) -> void:
	ensure_ws_values(gs)
	for wid in gs.wars.keys():
		var w: Dictionary = gs.wars.get(wid, {})
		if w.is_empty():
			continue
		# eliminar participantes desaparecidos
		for side in ["attackers", "defenders"]:
			for t in w[side].duplicate():
				if not gs.countries.has(t) or gs.countries[t]["provinces"].is_empty():
					w[side].erase(t)
					VUnitIndex.bump_access(gs)
		if w["attackers"].is_empty() or w["defenders"].is_empty() or not (w["primary_attacker"] in w["attackers"]) or not (w["primary_defender"] in w["defenders"]):
			end_war(gs, w, "La guerra termina: uno de los bandos ha desaparecido.")
			continue
		var occ_a := _occupation_share(gs, w["defenders"], w["attackers"])
		var occ_d := _occupation_share(gs, w["attackers"], w["defenders"])
		w["occupation_ws"] = (occ_a - occ_d) * 100.0
		var bl_a := _blockade_share(gs, w["defenders"], w["attackers"])
		var bl_d := _blockade_share(gs, w["attackers"], w["defenders"])
		w["blockade_ws"] = (bl_a - bl_d) * 10.0
		# ticking: objetivos territoriales del atacante controlados (se recuentan solo si cambió algún
		# controlador o la composición de la guerra; si no, se reutiliza el resultado)
		for g in w["war_goals"]:
			if int(g.get("state_id", 0)) > 0 and side_of(w, g["actor"]) == "attackers":
				if int(g.get("_cv", -1)) != gs.controller_version or int(g.get("_av", -1)) != gs.access_version:
					g["_cv"] = gs.controller_version
					g["_av"] = gs.access_version
					var part := gs.state_part(int(g["state_id"]), g["target"])
					var all := not part.is_empty()
					for id in part:
						if side_of(w, gs.provinces[id]["controller"]) != "attackers":
							all = false
							break
					g["_all"] = all
				if g.get("_all", false):
					w["ticking_ws"] = minf(25.0, float(w["ticking_ws"]) + 0.1)
		# el defensor gana warscore si resiste más de un año sin perder el objetivo
		var days := gs.date.ordinal() - int(w.get("start_ordinal", gs.date.ordinal()))
		if days > 365 and occ_a < 0.05:
			w["ticking_ws"] = maxf(-15.0, float(w["ticking_ws"]) - 0.03)
		w["total_ws"] = clampf(float(w["battle_ws"]) + float(w["occupation_ws"]) + float(w["blockade_ws"]) + float(w["ticking_ws"]), -100.0, 100.0)
		# cansancio bélico diario
		for side in ["attackers", "defenders"]:
			var occ := occ_d if side == "attackers" else occ_a
			var bl := bl_d if side == "attackers" else bl_a
			for t in w[side]:
				var c: Dictionary = gs.countries[t]
				c["war_exhaustion"] = clampf(float(c.get("war_exhaustion", 0.0)) + occ * 0.05 + bl * 0.02 + 0.003, 0.0, 100.0)


## Parte (por valor) del territorio de 'owners' controlada por 'occupiers'. O(participantes²).
static func _occupation_share(gs: VGameState, owners: Array, occupiers: Array) -> float:
	var total := 0.0
	var occ := 0.0
	for t in owners:
		var c: Dictionary = gs.countries[t]
		total += float(c.get("_ws_total", 0.0))
		var o: Dictionary = c.get("_occ", {})
		for q in o:
			if q in occupiers:
				occ += float(o[q])
	return occ / total if total > 0.0 else 0.0


## Parte de las costas de 'owners' bloqueada por 'blockers' (recuentos de VNavySystem._blockades).
static func _blockade_share(gs: VGameState, owners: Array, blockers: Array) -> float:
	var total := 0
	var bl := 0
	for t in owners:
		var c: Dictionary = gs.countries[t]
		total += int(c.get("_coastal", 0))
		var by: Dictionary = c.get("_bl_by", {})
		for q in by:
			if q in blockers:
				bl += int(by[q])
	return float(bl) / float(total) if total > 0 else 0.0


## Asedios: avance de la ocupación y cambio de controlador (no de propietario).
## Solo se recorren los ejércitos del índice de asedio (en provincias de otro controlador o rebeldes).
static func _daily_sieges(gs: VGameState) -> void:
	var besieged := {}
	var sg := VUnitIndex.sieging_armies(gs)
	for aid in sg.keys():
		var a: Dictionary = gs.armies.get(aid, {})
		if a.is_empty() or int(a["embarked"]) > 0:
			sg.erase(aid)
			continue
		if int(a.get("rebel_faction", 0)) == 0 and gs.provinces[int(a["province"])]["controller"] == a["country"]:
			sg.erase(aid)
			continue
		if int(a["battle"]) > 0 or not a["path"].is_empty() or a.get("retreating", false):
			continue
		var prov := int(a["province"])
		var p := gs.province(prov)
		if p.is_empty():
			continue
		var new_ctrl := _siege_result(gs, a, p)
		if new_ctrl == "" or VCombatSystem.hostile_present(gs, a, prov):
			continue
		var e: Dictionary = besieged.get(prov, {"brigades": 0, "siege": 0.0, "recon": 0.0, "ctrl": new_ctrl, "faction": int(a.get("rebel_faction", 0))})
		for bid in a["brigades"]:
			var b: Dictionary = gs.brigades[bid]
			var ut: Dictionary = gs.unit_types.get(b["type"], {})
			e["brigades"] = int(e["brigades"]) + 1
			e["siege"] = float(e["siege"]) + float(ut.get("siege", 0.0))
			e["recon"] = float(e["recon"]) + float(ut.get("recon", 0.0))
		e["recon"] = float(e["recon"]) + VArmySystem.leader_stat(gs, a, "recon")
		besieged[prov] = e
	for prov in besieged:
		var p: Dictionary = gs.provinces[prov]
		var e: Dictionary = besieged[prov]
		var terr := 0.6 if p.get("terrain", "") in ["mountains", "hills", "jungle", "marsh"] else 1.0
		var rate := 0.04 * sqrt(float(e["brigades"])) * (1.0 + float(e["siege"]) * 0.3 + float(e["recon"]) * 0.1) / (1.0 + float(p.get("fort", 0)) * 2.0) * terr
		if p.get("occupation_by", "") != e["ctrl"]:
			p["occupation"] = 0.0
			p["occupation_by"] = e["ctrl"]
		p["occupation"] = float(p.get("occupation", 0.0)) + rate
		if float(p["occupation"]) >= 1.0:
			var old: String = p["controller"]
			set_controller(gs, int(prov), e["ctrl"])
			p["rebel_faction"] = int(e["faction"]) if e["ctrl"] == VGameState.REBEL_TAG else 0
			p["occupation"] = 0.0
			p["occupation_by"] = ""
			gs.flags["_overlay_dirty"] = true
			if e["ctrl"] == p["owner"]:
				gs.log_event(p["owner"], "Liberada %s" % p["name"])
			else:
				gs.log_event(p["owner"], "%s ocupada por %s" % [p["name"], gs.country_name(e["ctrl"])])
				VEventSystem.notify(gs, "province_occupied", {"tag": p["owner"], "target": e["ctrl"], "prov": int(prov)})
				if gs.countries.has(e["ctrl"]):
					gs.log_event(e["ctrl"], "Ocupamos %s (de %s)" % [p["name"], gs.country_name(old)])
	# los asedios sin ejército se pierden
	for id in gs.market.get("_sieging", {}):
		if not besieged.has(id) and gs.provinces[id].get("occupation", 0.0) > 0.0:
			gs.provinces[id]["occupation"] = 0.0
			gs.provinces[id]["occupation_by"] = ""
	var keys := {}
	for k in besieged:
		keys[k] = true
	gs.market["_sieging"] = keys


## Qué controlador resultaría de asediar 'p' con el ejército 'a' ("" si no procede).
static func _siege_result(gs: VGameState, a: Dictionary, p: Dictionary) -> String:
	var tag: String = a["country"]
	var ctrl: String = p["controller"]
	var owner: String = p["owner"]
	var rf := int(a.get("rebel_faction", 0))
	if rf > 0:
		var f: Dictionary = gs.rebel_factions.get(rf, {})
		if not f.is_empty() and owner == f["country"] and ctrl != VGameState.REBEL_TAG:
			return VGameState.REBEL_TAG
		return ""
	if ctrl == tag:
		return ""
	# liberar territorio propio o aliado ocupado
	if ctrl == VGameState.REBEL_TAG and owner == tag:
		return owner
	if at_war_with(gs, tag, ctrl):
		if owner == tag or shared_war(gs, tag, owner):
			return owner
		return tag
	return ""


# ------------------------------------------------------------------ mensual
static func monthly(gs: VGameState) -> void:
	VCasusBelliSystem.monthly(gs)
	var decay := float(gs.war_rules.get("infamy_decay_per_month", 0.1))
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		if c["provinces"].is_empty():
			continue
		c["infamy"] = maxf(0.0, float(c.get("infamy", 0.0)) - decay)
		# bajas del mes → cansancio
		var cas := int(c.get("casualties", 0))
		var last := int(c.get("_casualties_seen", 0))
		var soldiers := maxf(1000.0, float(c.get("type_sizes", {}).get("soldiers", 0)))
		if is_at_war(gs, tag):
			c["war_exhaustion"] = clampf(float(c.get("war_exhaustion", 0.0)) + float(cas - last) / soldiers * 20.0, 0.0, 100.0)
		else:
			c["war_exhaustion"] = maxf(0.0, float(c.get("war_exhaustion", 0.0)) - 1.0)
		c["_casualties_seen"] = cas


## Fin de una guerra: treguas, se restaura el control, los ejércitos en territorio ajeno vuelven a casa.
static func end_war(gs: VGameState, w: Dictionary, text: String) -> void:
	var parts: Array = w["attackers"] + w["defenders"]
	for t in parts:
		if gs.countries.has(t):
			gs.countries[t]["wars"].erase(int(w["id"]))
			gs.log_event(t, text)
	VUnitIndex.bump_access(gs)
	for a in w["attackers"]:
		for d in w["defenders"]:
			VDiplomacySystem.set_truce(gs, a, d, int(gs.war_rules.get("truce_months", 60)))
	for t in parts:
		if not gs.countries.has(t):
			continue
		for id in gs.countries[t]["provinces"]:
			var p: Dictionary = gs.provinces[id]
			if p["controller"] != t and p["controller"] in parts and not at_war_with(gs, t, p["controller"]):
				set_controller(gs, int(id), t)
				p["occupation"] = 0.0
				p["occupation_by"] = ""
	for bid in gs.battles.keys():
		var bt: Dictionary = gs.battles[bid]
		if int(bt.get("war", 0)) == int(w["id"]):
			for side in ["attackers", "defenders"]:
				for aid in bt[side]:
					if gs.armies.has(aid):
						gs.armies[aid]["battle"] = 0
			gs.battles.erase(bid)
	for aid in gs.armies.keys():
		var a: Dictionary = gs.armies.get(aid, {})
		if a.is_empty() or not (a["country"] in parts) or int(a["embarked"]) > 0:
			continue
		var p2 := gs.province(int(a["province"]))
		if not p2.is_empty() and not VArmySystem.can_enter(gs, a["country"], int(a["province"])):
			var cap := int(gs.countries[a["country"]].get("capital", -1))
			if cap > 0:
				a["path"] = []
				a["retreating"] = false
				if VArmySystem.order_move(gs, a, cap) != "":
					VUnitIndex.move_army(gs, a, cap)
	gs.wars.erase(int(w["id"]))
	for t2 in parts:
		if gs.countries.has(t2) and not gs.countries[t2]["provinces"].is_empty():
			VEventSystem.notify(gs, "war_ended", {"tag": t2})
	VUnitIndex.bump_access(gs)
	gs.flags["_overlay_dirty"] = true


# ----------------------------------------------------------------- IA
## IA bélica: justificar guerras contra vecinos débiles, declarar con CB y fuerza, y hacer la paz.
static func ai_monthly(gs: VGameState) -> void:
	if gs.flags.get("ai_disabled", false):
		return
	for tag in gs.country_order:
		if tag == gs.player_tag:
			continue
		var c: Dictionary = gs.countries[tag]
		if c["provinces"].is_empty() or (gs.month_index + absi(tag.hash())) % 2 != 0:
			continue
		if not is_at_war(gs, tag):
			_ai_seek_war(gs, tag)
	for wid in gs.wars.keys():
		var w: Dictionary = gs.wars.get(wid, {})
		if not w.is_empty():
			VPeaceSystem.ai_consider(gs, w)


static func _ai_seek_war(gs: VGameState, tag: String) -> void:
	var c: Dictionary = gs.countries[tag]
	if float(c.get("infamy", 0.0)) > 10.0 or float(c.get("war_exhaustion", 0.0)) > 10.0:
		return
	# ¿ya tiene CB? declarar si sigue siendo más fuerte
	for cb in VCasusBelliSystem.cbs_of(gs, tag):
		var t: String = cb["target"]
		if _allied_strength(gs, tag) > _allied_strength(gs, t) * 1.2:
			if can_declare(gs, tag, cb) == "":
				declare_war(gs, tag, cb)
				return
	for j in gs.justifications:
		if j["owner"] == tag:
			return
	# empezar a justificar: probabilidad baja y determinista
	var roll := float(absi(("%s|%d|seek" % [tag, gs.month_index]).hash()) % 1000) / 1000.0
	if roll > 0.08:
		return
	var best := ""
	var best_ratio := 1.4
	for n in VDiplomacySystem.neighbor_countries(gs, tag):
		if n == gs.player_tag and gs.month_index < 24:
			continue
		if VDiplomacySystem.are_allied(gs, tag, n) or VDiplomacySystem.in_truce(gs, tag, n) or gs.countries[n].get("sphere_leader", "") == tag:
			continue
		if VInfluenceSystem.is_gp(gs, n) and not VInfluenceSystem.is_gp(gs, tag):
			continue
		# fuerza propia (con media de la de los aliados) frente a la del objetivo con media de sus aliados
		var ratio := _allied_strength(gs, tag) / maxf(1.0, _allied_strength(gs, n))
		if ratio > best_ratio:
			best_ratio = ratio
			best = n
	if best == "":
		return
	var states := VCasusBelliSystem.bordering_states(gs, tag, best)
	if states.is_empty():
		return
	VCasusBelliSystem.start_justification(gs, tag, best, "acquire_state", int(states[0]))


static func _allied_strength(gs: VGameState, tag: String) -> float:
	var s := VDiplomacySystem.strength(gs, tag)
	for al in gs.countries[tag]["allies"]:
		s += VDiplomacySystem.strength(gs, al) * 0.5
	return s
