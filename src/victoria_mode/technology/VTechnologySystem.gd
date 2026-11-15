class_name VTechnologySystem
extends RefCounted
## Tecnología e inventos.
##
## Puntos de investigación (mensuales) = clero alfabetizado + oficinistas alfabetizados + base por
## alfabetización nacional, × gasto en educación, × (1 + prestigio/200), × modificadores 'research'.
## Una tecnología necesita sus prerrequisitos; al completarse aplica sus efectos, desbloquea fábricas
## y añade sus inventos al bote. Cada mes cada invento del bote puede activarse según su probabilidad
## y sus condiciones (separado de la tecnología, como en Victoria II).
## Magia: magic_unlocked = false hasta GLOBAL_MAGIC_ACTIVATED (VMagicSystem.activate lo pone a true). Las
## tecnologías mágicas (data/victoria_mode/magic/technologies.json) exigen la bandera y el nivel de la rama de
## country.magic_branches que declaran (VMagicSystem.tech_allowed).


static func setup_new_game(gs: VGameState) -> void:
	gs.flags["magic_unlocked"] = false
	for tag in gs.countries:
		var c: Dictionary = gs.countries[tag]
		c["technologies"] = c.get("technologies", [])
		c["inventions"] = []
		c["research"] = ""
		c["research_progress"] = 0.0
		c["research_points"] = 0.0
		c["research_points_monthly"] = 0.0
		# naciones civilizadas empiezan con la primera tecnología de comercio y cultura
		if c.get("civilized", true) and float(c.get("prestige", 0)) >= 15.0:
			for t in ["double_entry_bookkeeping", "scholasticism"]:
				if not (t in c["technologies"]) and gs.technologies.has(t):
					c["technologies"].append(t)


static func research_points(gs: VGameState, tag: String) -> float:
	var c: Dictionary = gs.countries[tag]
	var clergy := float(c.get("_clergy_literacy", 0.0))
	var clerks := float(c.get("_clerks_literacy", 0.0))
	var base := clergy / 10000.0 * 3.0 + clerks / 10000.0 * 6.0 + float(c.get("literacy", 0.0)) * 20.0
	# M5: magos de las academias (investigación arcana; VMageModel._state_posts)
	base += float(c.get("_magi_research", 0.0)) / 10000.0 * 6.0
	var edu := 0.5 + float(c["budget"].get("education", 0.0))
	return base * edu * (1.0 + float(c.get("prestige", 0.0)) / 200.0) * (1.0 + gs.mod(tag, "research"))


static func can_research(gs: VGameState, tag: String, tech_id: String) -> bool:
	var c: Dictionary = gs.countries[tag]
	var t: Dictionary = gs.technologies.get(tech_id, {})
	if t.is_empty() or tech_id in c["technologies"]:
		return false
	if not VMagicSystem.tech_allowed(gs, tag, t):
		return false
	for pre in t.get("prerequisites", []):
		if not (pre in c["technologies"]):
			return false
	return true


static func available(gs: VGameState, tag: String) -> Array:
	var out := []
	for t in gs.technologies:
		if can_research(gs, tag, t):
			out.append(t)
	out.sort_custom(func(a, b): return float(gs.technologies[a]["cost"]) < float(gs.technologies[b]["cost"]))
	return out


static func set_research(gs: VGameState, tag: String, tech_id: String) -> bool:
	if not can_research(gs, tag, tech_id):
		return false
	var c: Dictionary = gs.countries[tag]
	if c["research"] != tech_id:
		c["research"] = tech_id
	return true


static func monthly(gs: VGameState, tag: String, is_player: bool) -> void:
	var c: Dictionary = gs.countries[tag]
	if c["provinces"].is_empty():
		return
	var rp := research_points(gs, tag)
	c["research_points_monthly"] = rp
	c["research_points_daily"] = rp / 30.0
	c["research_points"] = float(c.get("research_points", 0.0)) + rp
	if c["research"] == "" and not is_player:
		var av := available(gs, tag)
		if not av.is_empty():
			c["research"] = av[(gs.month_index + tag.hash()) % mini(3, av.size())]
	if c["research"] != "":
		# M5: la regulación mágica acelera o frena la investigación de tecnologías mágicas
		if String(gs.technologies[c["research"]].get("category", "")) == "magic":
			rp *= maxf(0.1, 1.0 + gs.mod(tag, "magic_research"))
		c["research_progress"] = float(c["research_progress"]) + rp
		var cost := float(gs.technologies[c["research"]]["cost"])
		if float(c["research_progress"]) >= cost:
			complete(gs, tag, c["research"])
			c["research_progress"] = float(c["research_progress"]) - cost
	_roll_inventions(gs, tag)


static func complete(gs: VGameState, tag: String, tech_id: String) -> void:
	var c: Dictionary = gs.countries[tag]
	if tech_id in c["technologies"]:
		return
	c["technologies"].append(tech_id)
	if c["research"] == tech_id:
		c["research"] = ""
	VModifiers.recompute(gs, tag)
	gs.log_event(tag, "Tecnología investigada: %s" % gs.technologies[tech_id]["name"])
	VEventSystem.notify(gs, "technology_researched", {"tag": tag, "tech": tech_id})


static func invention_pool(gs: VGameState, tag: String) -> Array:
	var c: Dictionary = gs.countries[tag]
	var out := []
	for i in gs.inventions:
		var inv: Dictionary = gs.inventions[i]
		if inv["technology"] in c["technologies"] and not (i in c["inventions"]):
			out.append(i)
	return out


static func _roll_inventions(gs: VGameState, tag: String) -> void:
	var c: Dictionary = gs.countries[tag]
	for i in invention_pool(gs, tag):
		var inv: Dictionary = gs.inventions[i]
		if not VConditions.country_ok(gs, tag, inv.get("conditions", {})):
			continue
		var chance := float(inv.get("chance", 0.05)) * (1.0 + float(c.get("literacy", 0.0)))
		# determinista por nación, invento y mes (reproducible en pruebas)
		var roll := float(absi(("%s|%s|%d" % [tag, i, gs.month_index]).hash()) % 10000) / 10000.0
		if roll < chance:
			activate_invention(gs, tag, i)


static func activate_invention(gs: VGameState, tag: String, inv_id: String) -> void:
	var c: Dictionary = gs.countries[tag]
	if inv_id in c["inventions"]:
		return
	c["inventions"].append(inv_id)
	VModifiers.recompute(gs, tag)
	gs.log_event(tag, "Invento: %s" % gs.inventions[inv_id]["name"])
	VEventSystem.notify(gs, "invention_discovered", {"tag": tag, "invention": inv_id})
