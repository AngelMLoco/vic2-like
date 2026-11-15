class_name VEventEffects
extends RefCounted
## Efectos de eventos y decisiones. Se validan al cargar (claves desconocidas, países, bienes, tecnologías,
## modificadores…) y se aplican usando las APIs de cada sistema (nunca tocando estructuras a mano cuando existe
## una función: cambio de dueño → gs.change_owner, controlador → VWarSystem.set_controller, reformas →
## VPoliticsSystem.change_reform, guerra → VWarSystem.declare_war…).
##
## Ámbito: los efectos de nación se aplican a ctx.tag (en ámbito provincia, al propietario); los de provincia
## a ctx.prov. Cambios de ámbito: "target" {…}, "owner" {…}, "capital" {…}, "every_owned_province"
## {"limit": {cond}, "effects": {…}}, "random_owned_province" {"limit": {cond}, "effects": {…}}.

const KEYS := ["add_treasury", "add_treasury_ratio", "add_prestige", "add_infamy", "change_relation", "add_militancy", "add_consciousness",
	"change_reform", "add_country_modifier", "remove_country_modifier", "add_province_modifier", "set_flag", "clear_flag",
	"set_country_flag", "clear_country_flag", "set_province_flag", "clear_province_flag", "set_variable",
	"change_variable", "add_core", "remove_core", "change_owner", "change_controller", "add_technology", "add_invention",
	"start_research", "add_research_points", "add_good_stockpile", "build_factory", "close_factory", "change_rgo",
	"add_population", "kill_population", "spawn_rebels", "create_casus_belli", "start_war", "add_war_exhaustion",
	"add_influence", "add_to_sphere", "remove_from_sphere", "trigger_event", "change_budget", "activate_magic",
	"add_magic_deposit", "discover_magic_deposit", "convert_pops", "log",
	"target", "owner", "capital", "every_owned_province", "random_owned_province"]


## efectos que admiten una lista de valores (una clave JSON no puede repetirse)
const LISTABLE := ["set_flag", "clear_flag", "set_country_flag", "clear_country_flag", "set_province_flag",
	"clear_province_flag", "add_country_modifier", "remove_country_modifier", "add_province_modifier"]


# ------------------------------------------------------------------ validación
static func validate(gs: VGameState, eff, errors: Array, where: String) -> Dictionary:
	if not (eff is Dictionary):
		errors.append("%s: efectos no válidos" % where)
		return {}
	var out := {}
	for k in eff:
		var v = eff[k]
		if v is Array and k in LISTABLE:
			var lst := []
			for item in v:
				var one := validate(gs, {k: item}, errors, where)
				if one.has(k):
					lst.append(one[k])
			out[k] = lst
			continue
		if not (k in KEYS):
			errors.append("%s: efecto desconocido «%s»" % [where, k])
			continue
		match k:
			"target", "owner", "capital":
				v = validate(gs, v, errors, where + "." + k)
			"every_owned_province", "random_owned_province":
				v = {"limit": VEventConditions.compile(gs, v.get("limit", {}), errors, where + "." + k + ".limit"),
					"effects": validate(gs, v.get("effects", {}), errors, where + "." + k)}
			"add_country_modifier", "add_province_modifier":
				if v is Dictionary and not v.has("effects") and not gs.event_modifiers.has(v.get("id", "")):
					errors.append("%s: modificador desconocido «%s»" % [where, v.get("id", "")])
				elif v is String and not gs.event_modifiers.has(v):
					errors.append("%s: modificador desconocido «%s»" % [where, v])
			"add_technology", "start_research":
				if not gs.technologies.has(v):
					errors.append("%s: tecnología desconocida «%s»" % [where, v])
			"add_invention":
				if not gs.inventions.has(v):
					errors.append("%s: invento desconocido «%s»" % [where, v])
			"add_good_stockpile":
				for g in v:
					if not gs.goods.has(g):
						errors.append("%s: bien desconocido «%s»" % [where, g])
			"build_factory", "close_factory":
				var ft: String = v.get("type", "") if v is Dictionary else String(v)
				if ft != "any" and not gs.factory_types.has(ft):
					errors.append("%s: tipo de fábrica desconocido «%s»" % [where, ft])
			"change_rgo":
				if not gs.goods.has(v):
					errors.append("%s: bien desconocido «%s»" % [where, v])
			"change_reform":
				for rid in v:
					if not gs.reforms.has(rid):
						errors.append("%s: reforma desconocida «%s»" % [where, rid])
			"create_casus_belli", "start_war":
				var cb: String = v.get("cb", "") if v is Dictionary else String(v)
				if VCasusBelliSystem.cb_def(gs, cb).is_empty():
					errors.append("%s: casus belli desconocido «%s»" % [where, cb])
			"spawn_rebels":
				if not gs.reforms.has(String(v.get("movement", "")) if v is Dictionary else String(v)):
					errors.append("%s: movimiento desconocido para rebeldes" % where)
			"convert_pops":
				for f in ["from", "to"]:
					for pt in (v[f] if v[f] is Array else [v[f]]):
						if not gs.pop_types.has(pt):
							errors.append("%s: tipo de POP desconocido «%s»" % [where, pt])
			"change_owner", "change_controller":
				if v is String and not (v in ["target", "from", "self"]) and not gs.countries.has(v):
					errors.append("%s: país desconocido «%s»" % [where, v])
		out[k] = v
	return out


# ------------------------------------------------------------------ aplicación
static func apply(gs: VGameState, eff: Dictionary, ctx: Dictionary) -> void:
	var tag := VEventConditions._tag(gs, ctx)
	var c: Dictionary = gs.countries.get(tag, {})
	var prov := int(ctx.get("prov", 0))
	for k in eff:
		var v = eff[k]
		if v is Array and k in LISTABLE:
			for item in v:
				apply(gs, {k: item}, ctx)
			continue
		match k:
			"target":
				var t: String = ctx.get("target", "")
				if t != "" and gs.countries.has(t):
					apply(gs, v, {"tag": t, "target": tag, "from": tag})
			"owner":
				apply(gs, v, {"tag": tag, "target": ctx.get("target", "")})
			"capital":
				var cap := int(c.get("capital", -1))
				if cap > 0:
					apply(gs, v, {"tag": tag, "prov": cap, "target": ctx.get("target", "")})
			"every_owned_province", "random_owned_province":
				var picked := []
				for id in c.get("provinces", []):
					if VEventConditions.check(gs, v["limit"], {"tag": tag, "prov": int(id), "target": ctx.get("target", "")}):
						picked.append(int(id))
				if k == "random_owned_province" and not picked.is_empty():
					picked = [picked[int(VEventSystem.roll01("%s|%d|%d" % [tag, gs.month_index, picked.size()]) * picked.size()) % picked.size()]]
				for id2 in picked:
					apply(gs, v["effects"], {"tag": tag, "prov": id2, "target": ctx.get("target", "")})
			"add_treasury":
				if c.is_empty():
					continue
				var amount := float(v)
				if amount >= 0.0:
					c["treasury"] = float(c["treasury"]) + amount
					VMoney.created(gs, amount, "events")
				else:
					spend(gs, tag, -amount)
			"add_treasury_ratio":
				# fracción del tesoro actual (las cifras absolutas no escalan entre naciones muy distintas)
				if c.is_empty():
					continue
				var amt := maxf(0.0, float(c["treasury"])) * float(v)
				if amt >= 0.0:
					c["treasury"] = float(c["treasury"]) + amt
					VMoney.created(gs, amt, "events")
				else:
					spend(gs, tag, -amt)
			"add_prestige":
				c["prestige"] = maxf(0.0, float(c.get("prestige", 0.0)) + float(v))
			"add_infamy":
				c["infamy"] = maxf(0.0, float(c.get("infamy", 0.0)) + float(v))
			"change_relation":
				var t2: String = ctx.get("target", "")
				if t2 != "":
					gs.set_relation(tag, t2, gs.relation(tag, t2) + int(v))
			"add_militancy", "add_consciousness":
				_change_pops(gs, tag, prov, "militancy" if k == "add_militancy" else "consciousness", v)
			"change_reform":
				for rid in v:
					var err := VPoliticsSystem.change_reform(gs, tag, rid, int(v[rid]))
					if err != "":
						gs.log_event(tag, "No se pudo cambiar la reforma: %s" % err)
			"add_country_modifier":
				var d: Dictionary = v if v is Dictionary else {"id": v}
				VScopedState.add_country_modifier(gs, tag, d["id"], int(d.get("months", 0)), String(ctx.get("source", "event")), d.get("effects", {}))
			"remove_country_modifier":
				VScopedState.remove_country_modifier(gs, tag, String(v))
			"add_province_modifier":
				if prov > 0:
					var d2: Dictionary = v if v is Dictionary else {"id": v}
					VScopedState.add_province_modifier(gs, prov, d2["id"], int(d2.get("months", 0)), String(ctx.get("source", "event")), d2.get("effects", {}))
			"set_flag":
				gs.flags[String(v)] = true
			"clear_flag":
				gs.flags.erase(String(v))
			"set_country_flag":
				VScopedState.set_country_flag(gs, tag, String(v))
			"clear_country_flag":
				VScopedState.set_country_flag(gs, tag, String(v), false)
			"set_province_flag":
				if prov > 0:
					VScopedState.set_province_flag(gs, prov, String(v))
			"clear_province_flag":
				if prov > 0:
					VScopedState.set_province_flag(gs, prov, String(v), false)
			"set_variable":
				for n in v:
					VScopedState.change_variable(gs, tag, n, float(v[n]), true)
			"change_variable":
				for n in v:
					VScopedState.change_variable(gs, tag, n, float(v[n]))
			"add_core", "remove_core":
				var pid := prov if not (v is int or v is float) else int(v)
				var p := gs.province(pid)
				if not p.is_empty():
					var cores: Array = p.get("cores", [])
					if k == "add_core" and not (tag in cores):
						cores.append(tag)
					elif k == "remove_core":
						cores.erase(tag)
					p["cores"] = cores
			"change_owner":
				var to := VEventConditions._resolve_tag(ctx, String(v))
				if prov > 0 and gs.countries.has(to):
					gs.change_owner([prov], to)
			"change_controller":
				var to2 := VEventConditions._resolve_tag(ctx, String(v))
				if prov > 0:
					VWarSystem.set_controller(gs, prov, to2)
			"add_technology":
				VTechnologySystem.complete(gs, tag, String(v))
			"add_invention":
				VTechnologySystem.activate_invention(gs, tag, String(v))
			"start_research":
				VTechnologySystem.set_research(gs, tag, String(v))
			"add_research_points":
				c["research_progress"] = float(c.get("research_progress", 0.0)) + float(v)
			"add_good_stockpile":
				var stock: Dictionary = c.get("stockpile", {})
				for g in v:
					stock[g] = maxf(0.0, float(stock.get(g, 0.0)) + float(v[g]))
				c["stockpile"] = stock
			"build_factory":
				_build_factory(gs, tag, v.get("type", "") if v is Dictionary else String(v))
			"close_factory":
				_close_factory(gs, tag, v.get("type", "any") if v is Dictionary else String(v))
			"change_rgo":
				var p2 := gs.province(prov)
				if not p2.is_empty():
					p2["rgo"] = String(v)
					p2["rgo_data"]["good"] = String(v)
			"add_population", "kill_population":
				var factor := float(v) if k == "add_population" else -absf(float(v))
				_scale_population(gs, tag, prov, factor)
			"spawn_rebels":
				var rid2: String = v.get("movement", "") if v is Dictionary else String(v)
				var supporters := []
				var ps := gs.pops
				for id3 in c.get("provinces", []):
					for s in gs.provinces[id3]["pop_slots"]:
						if ps.militancy[s] >= 3.0:
							supporters.append(ps.id[s])
				if not supporters.is_empty() and VRebelSystem.faction_for(gs, tag, rid2).is_empty():
					var f := VRebelSystem.form_faction(gs, tag, rid2, supporters)
					VRebelSystem.rise(gs, f)
			"create_casus_belli":
				var t3: String = ctx.get("target", "")
				if t3 != "":
					var cbid: String = v.get("cb", "") if v is Dictionary else String(v)
					VCasusBelliSystem.add_cb(gs, tag, t3, cbid, int(v.get("state", 0)) if v is Dictionary else 0)
			"start_war":
				var t4: String = ctx.get("target", "")
				if t4 != "" and not VWarSystem.at_war_with(gs, tag, t4):
					var cbid2: String = v.get("cb", "") if v is Dictionary else String(v)
					var st := int(v.get("state", 0)) if v is Dictionary else 0
					if st == 0:
						var bs := VCasusBelliSystem.bordering_states(gs, tag, t4)
						st = int(bs[0]) if not bs.is_empty() else 0
					var cbd := VCasusBelliSystem.add_cb(gs, tag, t4, cbid2, st)
					if not cbd.is_empty():
						VWarSystem.declare_war(gs, tag, cbd)
			"add_war_exhaustion":
				c["war_exhaustion"] = clampf(float(c.get("war_exhaustion", 0.0)) + float(v), 0.0, 100.0)
			"add_influence":
				var t5: String = ctx.get("target", "")
				if t5 != "" and VInfluenceSystem.is_gp(gs, tag):
					var en := VInfluenceSystem.entry(gs, tag, t5)
					en["points"] = maxf(0.0, float(en.get("points", 0.0)) + float(v))
			"add_to_sphere":
				var t6: String = ctx.get("target", "")
				if t6 != "" and VInfluenceSystem.perform(gs, tag, "add_to_sphere", t6) != "":
					gs.countries[t6]["sphere_leader"] = tag
					VEventSystem.notify(gs, "country_enters_sphere", {"tag": t6, "target": tag})
			"remove_from_sphere":
				var t7: String = ctx.get("target", "")
				if t7 != "" and gs.countries[t7].get("sphere_leader", "") != "":
					var old: String = gs.countries[t7]["sphere_leader"]
					gs.countries[t7]["sphere_leader"] = ""
					VEventSystem.notify(gs, "country_leaves_sphere", {"tag": t7, "target": old})
			"trigger_event":
				var d3: Dictionary = v if v is Dictionary else {"id": v}
				VEventSystem.schedule(gs, String(d3["id"]), ctx, int(d3.get("days", 0)))
			"change_budget":
				for slider in v:
					c["budget"][slider] = clampf(float(c["budget"].get(slider, 0.0)) + float(v[slider]), 0.0, 1.0)
			"activate_magic":
				VMagicSystem.activate(gs)
			"add_magic_deposit":
				if prov > 0:
					VMagicSystem.add_deposit(gs, prov, float(v))
			"discover_magic_deposit":
				VMagicSystem.discover_in_country(gs, tag, float(v))
			"convert_pops":
				VMagicSystem.convert_pops(gs, tag, prov, v)
			"log":
				gs.log_event(tag, String(v))


## Gasto del Estado por eventos/decisiones (subsidios, obras, programas): el dinero sale del tesoro y llega a
## los POPs de la nación como renta (proporcional al tamaño): se conserva la masa monetaria (no desaparece).
static func spend(gs: VGameState, tag: String, amount: float) -> void:
	var c: Dictionary = gs.countries.get(tag, {})
	if c.is_empty() or amount <= 0.0:
		return
	c["treasury"] = float(c["treasury"]) - amount
	var ps := gs.pops
	var total := 0.0
	for id in c["provinces"]:
		for s in gs.provinces[id]["pop_slots"]:
			total += float(ps.size[s])
	if total <= 0.0:
		return
	for id in c["provinces"]:
		for s in gs.provinces[id]["pop_slots"]:
			var share := amount * float(ps.size[s]) / total
			ps.cash[s] += share
			ps.income_acc[s] += share


## Militancia/conciencia de los POPs del ámbito (provincia o nación). v: número o {"value", "strata"}.
static func _change_pops(gs: VGameState, tag: String, prov: int, field: String, v) -> void:
	var amount := float(v.get("value", 0.0)) if v is Dictionary else float(v)
	var strata := -1
	if v is Dictionary and v.has("strata"):
		strata = VPopStore.STRATA.find(String(v["strata"]))
	var ps := gs.pops
	var arr: Array[float] = ps.militancy if field == "militancy" else ps.consciousness
	var provs: Array = [prov] if prov > 0 else gs.countries.get(tag, {}).get("provinces", [])
	for id in provs:
		for s in gs.provinces[id]["pop_slots"]:
			if strata >= 0 and ps.t_strata[ps.type_id[s]] != strata:
				continue
			arr[s] = clampf(arr[s] + amount, 0.0, 10.0)


static func _scale_population(gs: VGameState, tag: String, prov: int, factor: float) -> void:
	var ps := gs.pops
	var provs: Array = [prov] if prov > 0 else gs.countries.get(tag, {}).get("provinces", [])
	for id in provs:
		for s in gs.provinces[id]["pop_slots"]:
			ps.size[s] = maxi(1, int(round(float(ps.size[s]) * (1.0 + factor))))
		VPopulationSystem.recalc_province(gs, id)


static func _build_factory(gs: VGameState, tag: String, ftype: String) -> void:
	var instances := gs.country_state_instances(tag)
	for si in instances:
		if si["factories"].size() < 6:
			var err := VProductionSystem.government_build(gs, tag, si["key"], ftype)
			if err == "":
				return
			gs.log_event(tag, "No se pudo construir %s: %s" % [gs.factory_types.get(ftype, {}).get("name", ftype), err])
			return


static func _close_factory(gs: VGameState, tag: String, ftype: String) -> void:
	for si in gs.country_state_instances(tag):
		for f in si["factories"]:
			if f["open"] and (ftype == "any" or f["type"] == ftype):
				f["open"] = false
				gs.log_event(tag, "Cierra %s en %s" % [gs.factory_types.get(f["type"], {}).get("name", f["type"]), gs.states[si["state"]]["name"]])
				VEventSystem.notify(gs, "factory_closed", {"tag": tag})
				return


# ------------------------------------------------------------------ descripción (tooltips)
static func describe(gs: VGameState, eff: Dictionary) -> String:
	var lines := []
	for k in eff:
		var v = eff[k]
		if v is Array and k in LISTABLE:
			for item in v:
				var sub := describe(gs, {k: item})
				if sub != "Sin efectos inmediatos":
					lines.append(sub)
			continue
		match k:
			"target", "owner", "capital":
				lines.append({"target": "País objetivo", "owner": "Propietario", "capital": "Capital"}[k] + ": " + describe(gs, v).replace("\n", "; "))
			"every_owned_province", "random_owned_province":
				lines.append(("En cada provincia que cumpla: " if k == "every_owned_province" else "En una provincia: ") + describe(gs, v["effects"]).replace("\n", "; "))
			"add_treasury":
				lines.append("Tesoro %s" % _signed(float(v)))
			"add_treasury_ratio":
				lines.append("Tesoro %s%%" % _signed(float(v) * 100.0))
			"add_prestige":
				lines.append("Prestigio %s" % _signed(float(v)))
			"add_infamy":
				lines.append("Infamia %s" % _signed(float(v)))
			"change_relation":
				lines.append("Relaciones con el objetivo %s" % _signed(float(v)))
			"add_militancy", "add_consciousness":
				var amount := float(v.get("value", 0.0)) if v is Dictionary else float(v)
				lines.append("%s %s%s" % ["Militancia" if k == "add_militancy" else "Conciencia", _signed(amount),
					(" (" + String(v["strata"]) + ")") if v is Dictionary and v.has("strata") else ""])
			"change_reform":
				for rid in v:
					lines.append("Reforma %s %s" % [gs.reforms.get(rid, {}).get("name", rid), "↑" if int(v[rid]) > 0 else "↓"])
			"add_country_modifier", "add_province_modifier":
				var d: Dictionary = v if v is Dictionary else {"id": v}
				var eff2: Dictionary = d.get("effects", gs.event_modifiers.get(d["id"], {}).get("effects", {}))
				lines.append("%s «%s»%s: %s" % ["Modificador" if k == "add_country_modifier" else "Modificador provincial",
					VScopedState.modifier_name(gs, d["id"]), (" (%d meses)" % int(d["months"])) if int(d.get("months", 0)) > 0 else "", VModifiers.describe(eff2)])
			"set_country_flag", "set_flag", "set_province_flag":
				pass
			"add_technology":
				lines.append("Tecnología: %s" % gs.technologies.get(v, {}).get("name", v))
			"add_invention":
				lines.append("Invento: %s" % gs.inventions.get(v, {}).get("name", v))
			"add_research_points":
				lines.append("Investigación %s" % _signed(float(v)))
			"add_good_stockpile":
				for g in v:
					lines.append("Reserva de %s %s" % [gs.goods.get(g, {}).get("name", g), _signed(float(v[g]))])
			"build_factory":
				lines.append("Construir %s" % gs.factory_types.get(v.get("type", "") if v is Dictionary else v, {}).get("name", str(v)))
			"close_factory":
				lines.append("Cerrar una fábrica")
			"add_population", "kill_population":
				lines.append("Población %s%%" % _signed((float(v) if k == "add_population" else -absf(float(v))) * 100.0))
			"spawn_rebels":
				lines.append("¡Levantamiento rebelde!")
			"create_casus_belli":
				lines.append("Casus belli contra el objetivo")
			"start_war":
				lines.append("¡Guerra contra el objetivo!")
			"add_war_exhaustion":
				lines.append("Cansancio bélico %s" % _signed(float(v)))
			"add_influence":
				lines.append("Influencia %s" % _signed(float(v)))
			"add_to_sphere":
				lines.append("El objetivo entra en nuestra esfera")
			"change_budget":
				for slider in v:
					lines.append("Presupuesto %s %s" % [slider, _signed(float(v[slider]) * 100.0)])
			"activate_magic":
				lines.append("La magia regresa al mundo")
			"discover_magic_deposit", "add_magic_deposit":
				lines.append("Yacimiento arcano")
			"convert_pops":
				lines.append("Surgen nuevos %s" % gs.pop_type_name(String(v.get("to", ""))).to_lower())
			"trigger_event":
				pass
	return "\n".join(lines) if not lines.is_empty() else "Sin efectos inmediatos"


static func _signed(v: float) -> String:
	return ("+" if v >= 0.0 else "") + (("%.0f" % v) if absf(v) >= 10.0 else ("%.2f" % v))
