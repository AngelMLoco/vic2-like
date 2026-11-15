class_name VDecisionSystem
extends RefCounted
## Decisiones nacionales (data/victoria_mode/decisions/*.json y magic/decisions/*.json), separadas de los eventos.
##
## Decisión: id, name, desc, category, tags (naciones), requires_flag (bandera global), visible {cond},
## available {cond}, cost {treasury, prestige, research}, effects, ai_weight (número o {base, modifiers}),
## cooldown (meses), once. Visible = se muestra en Política; disponible = se puede tomar ahora (si no, la UI
## explica la primera condición que falla). La IA las evalúa trimestralmente, escalonadas por nación.


static func load_definitions(gs: VGameState, root: String) -> void:
	var errors: Array = gs.data_errors
	gs.decision_defs = {}
	for dir in ["decisions/", "magic/decisions/"]:
		var d := DirAccess.open(root + dir)
		if d == null:
			continue
		var files := []
		for f in d.get_files():
			if f.ends_with(".json"):
				files.append(f)
		files.sort()
		for f in files:
			for dec in VJson.load_array(root + dir + f, "decisions"):
				var id: String = dec.get("id", "")
				var where := "decisión %s" % id
				if id == "" or gs.decision_defs.has(id):
					errors.append("%s: decisión sin id o duplicada «%s»" % [f, id])
					continue
				var tags := {}
				for t in dec.get("tags", []):
					if not gs.countries.has(t):
						errors.append("%s: país desconocido «%s»" % [where, t])
					tags[t] = true
				var aiw = dec.get("ai_weight", 1.0)
				var ai_mods := []
				var ai_base := float(aiw.get("base", 1.0)) if aiw is Dictionary else float(aiw)
				if aiw is Dictionary:
					for m in aiw.get("modifiers", []):
						var cond: Dictionary = m.duplicate()
						var fct := float(cond.get("factor", 1.0))
						cond.erase("factor")
						ai_mods.append([fct, VEventConditions.compile(gs, cond, errors, where + ".ai_weight")])
				var cost: Dictionary = dec.get("cost", {})
				for k in cost:
					if not (k in ["treasury", "prestige", "research"]):
						errors.append("%s: coste desconocido «%s»" % [where, k])
				gs.decision_defs[id] = {"id": id, "name": dec.get("name", id), "desc": dec.get("desc", ""),
					"category": dec.get("category", "political"), "tags": tags, "requires_flag": dec.get("requires_flag", ""),
					"visible": VEventConditions.compile(gs, dec.get("visible", {}), errors, where + ".visible"),
					"available": VEventConditions.compile(gs, dec.get("available", {}), errors, where + ".available"),
					"cost": cost, "effects": VEventEffects.validate(gs, dec.get("effects", {}), errors, where),
					"ai_base": ai_base, "ai_mods": ai_mods, "cooldown": int(dec.get("cooldown", 0)), "once": bool(dec.get("once", true))}


static func taken_month(gs: VGameState, tag: String, id: String) -> int:
	return int(VScopedState.es(gs)["decisions"].get(tag, {}).get(id, -1))


static func is_visible(gs: VGameState, tag: String, d: Dictionary) -> bool:
	if not d["tags"].is_empty() and not d["tags"].has(tag):
		return false
	if d["requires_flag"] != "" and not gs.flags.get(d["requires_flag"], false):
		return false
	if d["once"] and taken_month(gs, tag, d["id"]) >= 0:
		return false
	return VEventConditions.check(gs, d["visible"], {"tag": tag})


## "" si se puede tomar; si no, el motivo legible.
static func unavailable_reason(gs: VGameState, tag: String, d: Dictionary) -> String:
	var last := taken_month(gs, tag, d["id"])
	if last >= 0 and d["cooldown"] > 0 and gs.month_index - last < d["cooldown"]:
		return "Hay que esperar %d meses" % (d["cooldown"] - (gs.month_index - last))
	var c: Dictionary = gs.countries[tag]
	var cost: Dictionary = d["cost"]
	if float(cost.get("treasury", 0.0)) > 0.0 and float(c["treasury"]) < float(cost["treasury"]):
		return "Tesoro insuficiente (%s)" % UiTheme.fmt_money(float(cost["treasury"]))
	if float(cost.get("prestige", 0.0)) > 0.0 and float(c.get("prestige", 0.0)) < float(cost["prestige"]):
		return "Prestigio insuficiente (%.0f)" % float(cost["prestige"])
	if float(cost.get("research", 0.0)) > 0.0 and float(c.get("research_progress", 0.0)) < float(cost["research"]):
		return "Investigación acumulada insuficiente (%.0f)" % float(cost["research"])
	var why := VEventConditions.explain_fail(gs, d["available"], {"tag": tag})
	return ("Requiere: " + why) if why != "" else ""


## Toma la decisión: paga el coste, aplica efectos, registra. Devuelve "" o el motivo del fallo.
static func take(gs: VGameState, tag: String, id: String) -> String:
	var d: Dictionary = gs.decision_defs.get(id, {})
	if d.is_empty():
		return "Decisión desconocida."
	if not is_visible(gs, tag, d):
		return "La decisión no está disponible para esta nación."
	var why := unavailable_reason(gs, tag, d)
	if why != "":
		return why
	var c: Dictionary = gs.countries[tag]
	var cost: Dictionary = d["cost"]
	if float(cost.get("treasury", 0.0)) > 0.0:
		VEventEffects.spend(gs, tag, float(cost["treasury"]))
	c["prestige"] = maxf(0.0, float(c.get("prestige", 0.0)) - float(cost.get("prestige", 0.0)))
	c["research_progress"] = maxf(0.0, float(c.get("research_progress", 0.0)) - float(cost.get("research", 0.0)))
	var es := VScopedState.es(gs)
	if not es["decisions"].has(tag):
		es["decisions"][tag] = {}
	es["decisions"][tag][id] = gs.month_index
	VEventEffects.apply(gs, d["effects"], {"tag": tag, "source": "decision:" + id})
	VScopedState.chronicle(gs, "decision", id, tag, d["name"], "", true)
	gs.log_event(tag, "Decisión: %s" % d["name"])
	var st: Dictionary = es["stats"]
	st["decisions"] = int(st.get("decisions", 0)) + 1
	VEventSystem.notify(gs, "decision_taken", {"tag": tag})
	return ""


## Listas para la UI: disponibles, potenciales (visibles pero no disponibles, con motivo) y tomadas.
static func list_for(gs: VGameState, tag: String) -> Dictionary:
	var out := {"available": [], "potential": [], "taken": []}
	for id in gs.decision_defs:
		var d: Dictionary = gs.decision_defs[id]
		if taken_month(gs, tag, id) >= 0:
			out["taken"].append(d)
		if not is_visible(gs, tag, d):
			continue
		var why := unavailable_reason(gs, tag, d)
		if why == "":
			out["available"].append(d)
		else:
			out["potential"].append([d, why])
	return out


## IA: cada nación revisa sus decisiones una vez por trimestre (en su cubo diario).
static func ai_country(gs: VGameState, tag: String, idx: int) -> void:
	if tag == gs.player_tag or gs.flags.get("ai_disabled", false) or (gs.month_index + idx) % 3 != 1:
		return
	for id in gs.decision_defs:
		var d: Dictionary = gs.decision_defs[id]
		if not is_visible(gs, tag, d) or unavailable_reason(gs, tag, d) != "":
			continue
		var w := float(d["ai_base"])
		for m in d["ai_mods"]:
			if VEventConditions.check(gs, m[1], {"tag": tag}):
				w *= float(m[0])
		# peso = probabilidad por trimestre (0…1); tirada determinista
		var roll := VEventSystem.roll01("%s|%s|%d|dec" % [id, tag, gs.month_index])
		if roll < clampf(w, 0.0, 1.0):
			take(gs, tag, id)
			return  # una decisión por trimestre y nación


static func debug_take(gs: VGameState, tag: String, id: String) -> String:
	return take(gs, tag, id)


static func list_available(gs: VGameState, tag: String) -> Array:
	var out := []
	for d in list_for(gs, tag)["available"]:
		out.append(d["id"])
	return out
