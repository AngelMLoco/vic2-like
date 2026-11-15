class_name VBattleResolverVictoria
extends VBattleResolver
## Resolvedor provisional inspirado en Victoria II (sin cartas).
##
## Cada día, cada bando coloca en primera línea hasta 'anchura de frente' brigadas (las de apoyo,
## como la artillería, disparan desde la segunda línea al 60 %). Tirada diaria por bando 0–9
## (determinista según la batalla y el día) + ataque del líder propio − defensa del líder enemigo
## − defensa del terreno (solo contra el atacante) − atrincheramiento + ventaja de reconocimiento.
## El daño a organización y las bajas dependen del ataque de la brigada frente a la defensa de su
## objetivo, de su fuerza, su organización, el suministro, la moral y la tecnología.
## Termina cuando la organización media de la primera línea de un bando cae por debajo de 0,15
## o se queda sin hombres; o tras 45 días (gana el defensor).


func resolver_name() -> String:
	return "Victoria (provisional)"


func resolve_tick(battle: Dictionary, gs: VGameState) -> Dictionary:
	battle["day"] = int(battle.get("day", 0)) + 1
	var att := _side(gs, battle["attackers"])
	var dfn := _side(gs, battle["defenders"])
	if att["front"].is_empty():
		return {"done": true, "winner": "defender"}
	if dfn["front"].is_empty():
		return {"done": true, "winner": "attacker"}
	var p := gs.province(int(battle["province"]))
	var terrain_def := float(gs.terrain_types.get(p.get("terrain", "plains"), {}).get("defence", 0))
	var dig := 1.0 if int(dfn.get("dig_in", 0)) >= 5 else 0.0
	var river := 1.0 if battle.get("river", false) else 0.0
	var roll_a := _roll(battle, "a") + float(att["leader_attack"]) - float(dfn["leader_defence"]) - terrain_def - dig - river + (1.0 if float(att["recon"]) > float(dfn["recon"]) else 0.0)
	var roll_d := _roll(battle, "d") + float(dfn["leader_attack"]) - float(att["leader_defence"]) + (1.0 if float(dfn["recon"]) > float(att["recon"]) else 0.0)
	_fire(gs, battle, att, dfn, clampf(roll_a, 0.0, 12.0), "defender")
	_fire(gs, battle, dfn, att, clampf(roll_d, 0.0, 12.0), "attacker")
	var a_org := _avg_org(gs, battle["attackers"])
	var d_org := _avg_org(gs, battle["defenders"])
	if a_org < 0.15 or VCombatSystem.side_strength(gs, battle["attackers"]) < 300:
		return {"done": true, "winner": "defender"}
	if d_org < 0.15 or VCombatSystem.side_strength(gs, battle["defenders"]) < 300:
		return {"done": true, "winner": "attacker"}
	if int(battle["day"]) >= 45:
		return {"done": true, "winner": "defender"}
	return {"done": false, "winner": ""}


func _roll(battle: Dictionary, side: String) -> float:
	return float(absi(("%d|%d|%s" % [int(battle["id"]), int(battle["day"]), side]).hash()) % 10)


func _side(gs: VGameState, army_ids: Array) -> Dictionary:
	var front := []
	var back := []
	var leader_attack := 0.0
	var leader_defence := 0.0
	var recon := 0.0
	var dig := 0
	var width := gs.combat_width
	for aid in army_ids:
		var a: Dictionary = gs.armies.get(aid, {})
		if a.is_empty():
			continue
		leader_attack = maxf(leader_attack, VArmySystem.leader_stat(gs, a, "attack"))
		leader_defence = maxf(leader_defence, VArmySystem.leader_stat(gs, a, "defence"))
		recon += VArmySystem.leader_stat(gs, a, "recon")
		dig = maxi(dig, int(a.get("dig_in", 0)))
		for bid in a["brigades"]:
			var b: Dictionary = gs.brigades.get(bid, {})
			if b.is_empty() or int(b["strength"]) <= 0:
				continue
			var ut: Dictionary = gs.unit_types.get(b["type"], {})
			recon += float(ut.get("recon", 0.0)) * 0.1
			if ut.get("support", false):
				back.append([b, a])
			else:
				front.append([b, a])
	# si falta primera línea, el apoyo pasa al frente
	while front.size() < width and not back.is_empty():
		front.append(back.pop_back())
	return {"front": front.slice(0, width), "back": back.slice(0, width), "leader_attack": leader_attack,
		"leader_defence": leader_defence, "recon": recon, "dig_in": dig}


func _fire(gs: VGameState, battle: Dictionary, shooter: Dictionary, target: Dictionary, roll: float, target_side: String) -> void:
	var targets: Array = target["front"]
	if targets.is_empty():
		return
	var shooters: Array = []
	for e in shooter["front"]:
		shooters.append([e, 1.0])
	for e in shooter["back"]:
		shooters.append([e, 0.6])
	var i := 0
	for s in shooters:
		var b: Dictionary = s[0][0]
		var a: Dictionary = s[0][1]
		var ut: Dictionary = gs.unit_types.get(b["type"], {})
		var t_entry: Array = targets[i % targets.size()]
		i += 1
		var tb: Dictionary = t_entry[0]
		var tut: Dictionary = gs.unit_types.get(tb["type"], {})
		var tech := 1.0 + gs.mod(a["country"], "military_strength") if gs.countries.has(a["country"]) else 1.0
		var factor := float(ut.get("attack", 2.0)) * (1.0 + roll) / 5.0 * float(s[1]) * tech
		factor *= float(b["strength"]) / float(gs.unit_manpower) * (0.5 + 0.5 * float(b["organisation"]))
		factor *= (0.5 + 0.5 * float(a.get("supply", 1.0))) * clampf(float(a.get("morale", 1.0)), 0.3, 1.5) * (1.0 + float(b.get("experience", 0.0)) * 0.5)
		var defence := maxf(0.5, float(tut.get("defence", 2.0)) * float(tut.get("discipline", 1.0)))
		var org_dmg := 0.06 * factor / (defence / 3.0)
		var men := int(60.0 * factor / (defence / 3.0))
		VCombatSystem.damage_brigade(gs, battle, tb, t_entry[1], org_dmg, men, target_side)


func _avg_org(gs: VGameState, army_ids: Array) -> float:
	var t := 0.0
	var n := 0
	for aid in army_ids:
		var a: Dictionary = gs.armies.get(aid, {})
		if a.is_empty():
			continue
		for bid in a["brigades"]:
			var b: Dictionary = gs.brigades.get(bid, {})
			if not b.is_empty() and int(b["strength"]) > 0:
				t += float(b["organisation"])
				n += 1
	return t / float(n) if n > 0 else 0.0
