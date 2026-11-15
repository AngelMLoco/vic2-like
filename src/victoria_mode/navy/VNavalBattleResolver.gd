class_name VNavalBattleResolver
extends RefCounted
## Combate naval provisional: se resuelve en rondas dentro del mismo día hasta que un bando
## pierde la organización o se queda sin barcos. Considera ataque/defensa/casco de cada tipo,
## organización, almirante y tecnología naval. Produce daños, hundimientos y retirada.
## Sustituible igual que el resolver terrestre.


static func _power(gs: VGameState, f: Dictionary) -> float:
	var p := 0.0
	var adm: Dictionary = gs.leaders.get(int(f.get("admiral", 0)), {})
	var tech := 1.0 + gs.mod(f["country"], "naval_strength") if gs.countries.has(f["country"]) else 1.0
	for s in f["ships"]:
		var st: Dictionary = gs.ship_types.get(s["type"], {})
		p += float(st.get("attack", 0.0)) * float(s["hull"]) * (0.4 + 0.6 * float(s["organisation"]))
	return p * tech * (1.0 + float(adm.get("attack", 0.0)) * 0.1)


static func _org(f: Dictionary) -> float:
	var t := 0.0
	for s in f["ships"]:
		t += float(s["organisation"])
	return t / maxf(1.0, float(f["ships"].size()))


static func _hit(gs: VGameState, target: Dictionary, power: float, roll: float) -> int:
	var sunk := 0
	if target["ships"].is_empty():
		return 0
	var per := power * (0.5 + roll / 10.0) / float(target["ships"].size())
	for s in target["ships"].duplicate():
		var st: Dictionary = gs.ship_types.get(s["type"], {})
		var dfn := maxf(0.5, float(st.get("defence", 1.0)) * float(st.get("hull", 1.0)))
		s["hull"] = float(s["hull"]) - per * 0.08 / dfn
		s["organisation"] = maxf(0.0, float(s["organisation"]) - per * 0.1 / dfn)
		if float(s["hull"]) <= 0.0:
			target["ships"].erase(s)
			sunk += 1
			# los transportes hundidos se llevan parte de las tropas embarcadas
			if int(st.get("transport", 0)) > 0:
				for aid in target["transported_armies"]:
					var a: Dictionary = gs.armies.get(aid, {})
					for bid in a.get("brigades", []).slice(0, int(st["transport"])):
						var b: Dictionary = gs.brigades.get(bid, {})
						if not b.is_empty():
							VArmySystem.apply_casualties(gs, b, int(b["strength"]) / 2, a["country"])
	return sunk


## Resuelve un combate entre dos flotas enemigas en la misma zona. {"winner": "a"|"b", "sunk": n}
static func fight(gs: VGameState, a: Dictionary, b: Dictionary) -> Dictionary:
	var sunk := 0
	for r in 12:
		var roll_a := float(absi(("%d|%d|%d|a" % [int(a["id"]), int(b["id"]), r + gs.date.ordinal()]).hash()) % 10)
		var roll_b := float(absi(("%d|%d|%d|b" % [int(a["id"]), int(b["id"]), r + gs.date.ordinal()]).hash()) % 10)
		var pa := _power(gs, a)
		var pb := _power(gs, b)
		sunk += _hit(gs, b, pa, roll_a)
		sunk += _hit(gs, a, pb, roll_b)
		if b["ships"].is_empty() or _org(b) < 0.2:
			return {"winner": "a", "sunk": sunk}
		if a["ships"].is_empty() or _org(a) < 0.2:
			return {"winner": "b", "sunk": sunk}
	return {"winner": "a" if _power(gs, a) >= _power(gs, b) else "b", "sunk": sunk}
