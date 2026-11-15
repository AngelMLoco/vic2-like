class_name VCasusBelliSystem
extends RefCounted
## Casus belli (war/casus_belli.json) y justificación de guerra.
##
## Los objetivos territoriales operan sobre PARTICIONES DE ESTADO (estado × propietario): «Adquirir
## estado» pide la parte de un estado que posee el objetivo. El ámbito provincial solo se usa para
## cores concretos (restaurar territorio nacional).
##
## Justificar guerra: proceso de varios meses con probabilidad mensual de ser descubierto.
## Descubierto → toda la infamia del CB y −50 de relaciones con el objetivo (−10 con sus aliados).
## No descubierto → al completarse se aplica la mitad de la infamia.
## Al terminar se obtiene un CB temporal (duration_months).


static func cb_def(gs: VGameState, cb_id: String) -> Dictionary:
	return gs.cb_types.get(cb_id, {})


## ¿Cumple el par actor/objetivo las condiciones del tipo de CB? Devuelve "" o el motivo.
static func conditions_fail(gs: VGameState, actor: String, target: String, cb_id: String, state_id: int = 0) -> String:
	var d := cb_def(gs, cb_id)
	if d.is_empty():
		return "CB desconocido."
	if actor == target or not gs.countries.has(target) or gs.countries[target]["provinces"].is_empty():
		return "Objetivo no válido."
	for cond in d.get("conditions", []):
		match cond:
			"target_not_gp":
				if VInfluenceSystem.is_gp(gs, target):
					return "El objetivo es una Gran Potencia."
			"target_gp":
				if not VInfluenceSystem.is_gp(gs, target):
					return "El objetivo no es una Gran Potencia."
			"actor_gp":
				if not VInfluenceSystem.is_gp(gs, actor):
					return "Solo una Gran Potencia puede usar este CB."
			"target_neighbor":
				if not VDiplomacySystem.neighbors(gs, actor, target):
					return "El objetivo no es vecino."
			"target_uncivilized":
				if gs.countries[target].get("civilized", true):
					return "El objetivo es una nación civilizada."
			"actor_civilized":
				if not gs.countries[actor].get("civilized", true):
					return "Requiere ser una nación civilizada."
			"target_in_other_sphere":
				var l: String = gs.countries[target].get("sphere_leader", "")
				if l == "" or l == actor:
					return "El objetivo no está en la esfera de otra potencia."
			"target_has_actor_core":
				if state_id > 0 and actor_cores_in_state(gs, actor, target, state_id).is_empty():
					return "No tienes cores en ese estado."
	if d.get("scope", "") == "state":
		if state_id <= 0 or gs.state_part(state_id, target).is_empty():
			return "Elige un estado del objetivo."
		if cb_id == "acquire_state" and not state_borders(gs, actor, target, state_id):
			return "El estado debe lindar con tu territorio."
	return ""


static func actor_cores_in_state(gs: VGameState, actor: String, target: String, state_id: int) -> Array:
	var out := []
	for id in gs.state_part(state_id, target):
		if actor in gs.provinces[id].get("cores", []):
			out.append(id)
	return out


## ¿La parte del estado del objetivo toca alguna provincia del actor?
static func state_borders(gs: VGameState, actor: String, target: String, state_id: int) -> bool:
	for id in gs.state_part(state_id, target):
		for n in gs.provinces[id]["neighbors"]:
			if gs.is_land(n) and gs.provinces[n]["owner"] == actor:
				return true
	return false


## Estados del objetivo que lindan con el actor (para elegir objetivo de «Adquirir estado»).
static func bordering_states(gs: VGameState, actor: String, target: String) -> Array:
	var out := []
	for si in gs.country_state_instances(target):
		if state_borders(gs, actor, target, int(si["state"])):
			out.append(int(si["state"]))
	return out


static func has_cb(gs: VGameState, actor: String, target: String, cb_id: String = "", state_id: int = 0) -> Dictionary:
	for cb in gs.casus_belli:
		if cb["owner"] == actor and cb["target"] == target and (cb_id == "" or cb["type"] == cb_id) and (state_id == 0 or int(cb.get("state_id", 0)) == state_id):
			return cb
	return {}


static func cbs_of(gs: VGameState, actor: String) -> Array:
	var out := []
	for cb in gs.casus_belli:
		if cb["owner"] == actor:
			out.append(cb)
	return out


static func add_cb(gs: VGameState, actor: String, target: String, cb_id: String, state_id: int = 0) -> Dictionary:
	var d := cb_def(gs, cb_id)
	var cb := {"id": gs.new_id("cb"), "owner": actor, "target": target, "type": cb_id, "state_id": state_id,
		"expires": gs.month_index + int(d.get("duration_months", 24))}
	gs.casus_belli.append(cb)
	return cb


static func remove_cb(gs: VGameState, cb_id: int) -> void:
	for cb in gs.casus_belli.duplicate():
		if int(cb["id"]) == cb_id:
			gs.casus_belli.erase(cb)


static func can_justify(gs: VGameState, actor: String, target: String, cb_id: String, state_id: int = 0) -> String:
	var d := cb_def(gs, cb_id)
	if int(d.get("justify_months", 0)) <= 0:
		return "Este CB no se justifica: aparece cuando se cumplen sus condiciones."
	var fail := conditions_fail(gs, actor, target, cb_id, state_id)
	if fail != "":
		return fail
	for j in gs.justifications:
		if j["owner"] == actor:
			return "Ya estás justificando una guerra (contra %s)." % gs.country_name(j["target"])
	if not has_cb(gs, actor, target, cb_id, state_id).is_empty():
		return "Ya tienes ese casus belli."
	if VWarSystem.at_war_with(gs, actor, target):
		return "Ya estáis en guerra."
	if float(gs.countries[actor].get("infamy", 0.0)) + float(d.get("infamy", 0.0)) > float(gs.war_rules.get("max_infamy", 25.0)) * 1.2:
		return "La infamia resultante sería excesiva."
	if float(gs.countries[actor].get("diplo_points", 0.0)) < float(gs.diplo_rules.get("costs", {}).get("justify_war", 1.0)):
		return "Faltan puntos diplomáticos."
	return ""


static func start_justification(gs: VGameState, actor: String, target: String, cb_id: String, state_id: int = 0) -> String:
	var err := can_justify(gs, actor, target, cb_id, state_id)
	if err != "":
		return err
	gs.countries[actor]["diplo_points"] = float(gs.countries[actor]["diplo_points"]) - float(gs.diplo_rules.get("costs", {}).get("justify_war", 1.0))
	gs.justifications.append({"id": gs.new_id("justification"), "owner": actor, "target": target, "type": cb_id, "state_id": state_id,
		"progress": 0.0, "months": int(cb_def(gs, cb_id).get("justify_months", 12)), "discovered": false})
	gs.log_event(actor, "Empieza la justificación de guerra contra %s (%s)" % [gs.country_name(target), cb_def(gs, cb_id).get("name", cb_id)])
	return ""


static func cancel_justification(gs: VGameState, actor: String) -> void:
	for j in gs.justifications.duplicate():
		if j["owner"] == actor:
			gs.justifications.erase(j)


static func monthly(gs: VGameState) -> void:
	# CB caducados
	for cb in gs.casus_belli.duplicate():
		if int(cb["expires"]) <= gs.month_index or not gs.countries.has(cb["target"]) or gs.countries[cb["target"]]["provinces"].is_empty():
			gs.casus_belli.erase(cb)
	# CB automáticos de restaurar cores
	if gs.month_index % 6 == 0:
		_core_cbs(gs)
	var chance := float(gs.war_rules.get("justify_discovery_chance", 0.05))
	for j in gs.justifications.duplicate():
		var d := cb_def(gs, j["type"])
		if not gs.countries.has(j["target"]) or gs.countries[j["target"]]["provinces"].is_empty():
			gs.justifications.erase(j)
			continue
		j["progress"] = float(j["progress"]) + 1.0 / maxf(1.0, float(j["months"]))
		var actor: String = j["owner"]
		if not j["discovered"]:
			var roll := float(absi(("%d|%d|disc" % [int(j["id"]), gs.month_index]).hash()) % 10000) / 10000.0
			if roll < chance:
				j["discovered"] = true
				_add_infamy(gs, actor, float(d.get("infamy", 0.0)))
				gs.set_relation(actor, j["target"], gs.relation(actor, j["target"]) - 50)
				for al in gs.countries[j["target"]]["allies"]:
					gs.set_relation(actor, al, gs.relation(actor, al) - 10)
				gs.log_event(actor, "¡Descubierta nuestra justificación de guerra contra %s! (+%.1f infamia)" % [gs.country_name(j["target"]), float(d.get("infamy", 0.0))])
				gs.log_event(j["target"], "%s prepara una guerra contra nosotros" % gs.country_name(actor))
		if float(j["progress"]) >= 1.0:
			gs.justifications.erase(j)
			if not j["discovered"]:
				_add_infamy(gs, actor, float(d.get("infamy", 0.0)) * 0.5)
			add_cb(gs, actor, j["target"], j["type"], int(j.get("state_id", 0)))
			gs.log_event(actor, "Casus belli obtenido contra %s: %s" % [gs.country_name(j["target"]), d.get("name", j["type"])])


static func _add_infamy(gs: VGameState, tag: String, amount: float) -> void:
	gs.countries[tag]["infamy"] = float(gs.countries[tag].get("infamy", 0.0)) + amount


## Restaurar territorio: CB permanente si un país tiene cores en provincias de otro.
static func _core_cbs(gs: VGameState) -> void:
	for id in range(1, gs.first_sea_id):
		var p: Dictionary = gs.provinces[id]
		var owner: String = p["owner"]
		for core in p.get("cores", []):
			if core == owner or core == "" or not gs.countries.has(core) or gs.countries[core]["provinces"].is_empty():
				continue
			var sid := int(p["state"])
			if has_cb(gs, core, owner, "restore_core", sid).is_empty():
				add_cb(gs, core, owner, "restore_core", sid)


static func goal_name(gs: VGameState, goal: Dictionary) -> String:
	var d := cb_def(gs, goal["type"])
	var txt: String = d.get("name", goal["type"])
	if int(goal.get("state_id", 0)) > 0:
		txt += ": " + gs.states.get(int(goal["state_id"]), {}).get("name", "?")
	return "%s (%s → %s)" % [txt, gs.country_name(goal["actor"]), gs.country_name(goal["target"])]
