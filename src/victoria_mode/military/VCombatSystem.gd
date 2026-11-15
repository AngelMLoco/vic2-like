class_name VCombatSystem
extends RefCounted
## Batallas terrestres: creación, incorporación de refuerzos, tick diario, fin y retirada.
## La resolución de cada día se delega en un VBattleResolver intercambiable.

static var _resolver: VBattleResolver = null


static func resolver() -> VBattleResolver:
	if _resolver == null:
		_resolver = VBattleResolverVictoria.new()
	return _resolver


## Sustituye el resolvedor (p. ej. el futuro sistema de cartas) sin tocar el resto de sistemas.
static func set_resolver(r: VBattleResolver) -> void:
	_resolver = r


## ¿Son enemigos estos dos ejércitos? (guerra entre sus naciones o rebeldes contra su país)
static func hostile(gs: VGameState, a: Dictionary, b: Dictionary) -> bool:
	var ra := int(a.get("rebel_faction", 0))
	var rb := int(b.get("rebel_faction", 0))
	if ra > 0 and rb > 0:
		return false
	if ra > 0:
		return b["country"] == gs.rebel_factions.get(ra, {}).get("country", "?")
	if rb > 0:
		return a["country"] == gs.rebel_factions.get(rb, {}).get("country", "?")
	return VWarSystem.at_war_with(gs, a["country"], b["country"])


static func hostile_present(gs: VGameState, army: Dictionary, province_id: int) -> bool:
	for o in VArmySystem.armies_in(gs, province_id):
		if int(o["id"]) != int(army["id"]) and hostile(gs, army, o):
			return true
	return false


## Un ejército llega a una provincia: si hay enemigos, empieza (o se une a) una batalla.
static func on_army_arrived(gs: VGameState, army: Dictionary) -> void:
	var prov := int(army["province"])
	for bid in gs.battles:
		var bt: Dictionary = gs.battles[bid]
		if bt.get("kind", "land") != "land" or int(bt["province"]) != prov:
			continue
		for side in ["attackers", "defenders"]:
			for oid in bt[side]:
				var o: Dictionary = gs.armies.get(oid, {})
				if not o.is_empty() and hostile(gs, army, o):
					var mine := "defenders" if side == "attackers" else "attackers"
					if not (int(army["id"]) in bt[mine]):
						bt[mine].append(int(army["id"]))
					army["battle"] = int(bt["id"])
					army["path"] = []
					return
				if not o.is_empty() and not hostile(gs, army, o) and o["country"] == army["country"]:
					if not (int(army["id"]) in bt[side]):
						bt[side].append(int(army["id"]))
					army["battle"] = int(bt["id"])
					army["path"] = []
					return
	var enemies := []
	for o in VArmySystem.armies_in(gs, prov):
		if int(o["id"]) != int(army["id"]) and hostile(gs, army, o) and not o.get("retreating", false):
			enemies.append(o)
	if enemies.is_empty():
		return
	start_battle(gs, prov, [army], enemies)


static func start_battle(gs: VGameState, prov: int, attackers: Array, defenders: Array) -> Dictionary:
	var id := gs.new_id("battle")
	var war_id := VWarSystem.war_between(gs, attackers[0]["country"], defenders[0]["country"])
	var bt := {"id": id, "kind": "land", "province": prov, "attackers": [], "defenders": [], "day": 0,
		"att_tag": attackers[0]["country"], "def_tag": defenders[0]["country"], "war": war_id,
		"att_rebel": int(attackers[0].get("rebel_faction", 0)), "def_rebel": int(defenders[0].get("rebel_faction", 0)),
		"losses": {"attacker": 0, "defender": 0}, "start_strength": {"attacker": 0, "defender": 0}}
	for a in attackers:
		bt["attackers"].append(int(a["id"]))
		a["battle"] = id
		a["path"] = []
	for d in defenders:
		bt["defenders"].append(int(d["id"]))
		d["battle"] = id
		d["path"] = []
	bt["start_strength"]["attacker"] = side_strength(gs, bt["attackers"])
	bt["start_strength"]["defender"] = side_strength(gs, bt["defenders"])
	gs.battles[id] = bt
	return bt


static func side_strength(gs: VGameState, army_ids: Array) -> int:
	var t := 0
	for aid in army_ids:
		var a: Dictionary = gs.armies.get(aid, {})
		if not a.is_empty():
			t += VArmySystem.army_strength(gs, a)
	return t


## Único punto por el que un resolver aplica daño: organización + bajas reales (POPs de soldados).
static func damage_brigade(gs: VGameState, battle: Dictionary, b: Dictionary, army: Dictionary, org_dmg: float, men: int, side: String) -> void:
	b["organisation"] = maxf(0.0, float(b["organisation"]) - org_dmg)
	var tag: String = army["country"] if int(army.get("rebel_faction", 0)) == 0 else ""
	var lost := VArmySystem.apply_casualties(gs, b, men, tag)
	battle["losses"][side] = int(battle["losses"].get(side, 0)) + lost


static func daily(gs: VGameState) -> void:
	for bid in gs.battles.keys():
		var bt: Dictionary = gs.battles.get(bid, {})
		if bt.is_empty() or bt.get("kind", "land") != "land":
			continue
		for side in ["attackers", "defenders"]:
			var alive := []
			for aid in bt[side]:
				if gs.armies.has(aid) and int(gs.armies[aid]["province"]) == int(bt["province"]):
					alive.append(aid)
			bt[side] = alive
		var res: Dictionary
		if bt["attackers"].is_empty():
			res = {"done": true, "winner": "defender"}
		elif bt["defenders"].is_empty():
			res = {"done": true, "winner": "attacker"}
		else:
			res = resolver().resolve_tick(bt, gs)
		if res.get("done", false):
			end_battle(gs, bt, res.get("winner", "defender"))


static func end_battle(gs: VGameState, bt: Dictionary, winner: String) -> void:
	gs.battles.erase(int(bt["id"]))
	var losers: Array = bt["defenders"] if winner == "attacker" else bt["attackers"]
	var winners: Array = bt["attackers"] if winner == "attacker" else bt["defenders"]
	for aid in winners:
		if gs.armies.has(aid):
			var a: Dictionary = gs.armies[aid]
			a["battle"] = 0
			for b in a["brigades"]:
				gs.brigades[b]["experience"] = minf(1.0, float(gs.brigades[b].get("experience", 0.0)) + 0.03)
	for aid in losers:
		if gs.armies.has(aid):
			var a2: Dictionary = gs.armies[aid]
			a2["battle"] = 0
			a2["morale"] = maxf(0.2, float(a2.get("morale", 1.0)) - 0.15)
			VArmySystem.start_retreat(gs, a2)
	var p := gs.province(int(bt["province"]))
	var wtag: String = bt["att_tag"] if winner == "attacker" else bt["def_tag"]
	var ltag: String = bt["def_tag"] if winner == "attacker" else bt["att_tag"]
	var text := "Batalla de %s: vence %s (bajas %s / %s)" % [p.get("name", "?"), gs.country_name(wtag) if int(bt["att_rebel" if winner == "attacker" else "def_rebel"]) == 0 else "Rebeldes",
		UiTheme.fmt_int(bt["losses"]["attacker"]), UiTheme.fmt_int(bt["losses"]["defender"])]
	gs.log_event(wtag, text)
	gs.log_event(ltag, text)
	VWarSystem.on_battle_end(gs, bt, winner)
	VArmySystem.update_counts(gs)
