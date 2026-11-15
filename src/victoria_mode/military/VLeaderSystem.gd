class_name VLeaderSystem
extends RefCounted
## Líderes: generales y almirantes.
## Los POPs de oficiales generan puntos de liderazgo (leadership) cada mes; contratar un líder los consume.
## Rasgos (personalidad + trasfondo) definidos en leader_traits.json, asignados de forma determinista.

const STATS := ["attack", "defence", "morale", "organisation", "speed", "recon"]


static func monthly(gs: VGameState) -> void:
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		if c["provinces"].is_empty():
			continue
		var officers := float(c.get("type_sizes", {}).get("officers", 0))
		var gain := officers / 1000.0 * (0.2 + float(c["budget"].get("military", 0.5))) * 0.1 * (1.0 + gs.mod(tag, "leadership"))
		c["leadership"] = minf(200.0, float(c.get("leadership", 0.0)) + gain)
		# IA: un general por cada ~10 brigadas, un almirante si hay flotas
		if tag != gs.player_tag:
			var generals := 0
			var admirals := 0
			for lid in gs.leaders:
				var l: Dictionary = gs.leaders[lid]
				if l["country"] == tag:
					if l["kind"] == "general":
						generals += 1
					else:
						admirals += 1
			var want := int(ceil(float(c["military"].get("brigades", 0)) / 10.0))
			if generals < want and float(c["leadership"]) >= cost(gs, "general"):
				var l2 := hire(gs, tag, "general")
				if not l2.is_empty():
					for a in VArmySystem.country_armies(gs, tag):
						if int(a["leader"]) == 0:
							VArmySystem.attach_leader(gs, a, int(l2["id"]))
							break
			elif admirals < mini(1, VNavySystem.country_fleets(gs, tag).size()) and float(c["leadership"]) >= cost(gs, "admiral"):
				var l3 := hire(gs, tag, "admiral")
				for f in VNavySystem.country_fleets(gs, tag):
					if int(f["admiral"]) == 0 and not l3.is_empty():
						f["admiral"] = int(l3["id"])
						l3["fleet"] = int(f["id"])
						break


static func cost(gs: VGameState, kind: String) -> float:
	return float(gs.leader_traits.get("leadership_cost_" + kind, 20))


static func hire(gs: VGameState, tag: String, kind: String) -> Dictionary:
	var c: Dictionary = gs.countries[tag]
	var price := cost(gs, kind)
	if float(c.get("leadership", 0.0)) < price:
		return {}
	c["leadership"] = float(c["leadership"]) - price
	var id := gs.new_id("leader")
	var h := absi(("%s|%d|%s" % [tag, id, kind]).hash())
	var pers: Array = gs.leader_traits.get("personalities", [])
	var backs: Array = gs.leader_traits.get("backgrounds", [])
	var names: Array = gs.leader_traits.get("names", ["Anónimo"])
	var surnames: Array = gs.leader_traits.get("surnames", [""])
	var p: Dictionary = pers[h % pers.size()] if not pers.is_empty() else {}
	var b: Dictionary = backs[(h / 7) % backs.size()] if not backs.is_empty() else {}
	var l := {"id": id, "country": tag, "kind": kind, "name": "%s %s" % [names[(h / 13) % names.size()], surnames[(h / 17) % surnames.size()]],
		"traits": [p.get("id", ""), b.get("id", "")], "army": 0, "fleet": 0}
	for s in STATS:
		l[s] = float(p.get(s, 0.0)) + float(b.get(s, 0.0))
	gs.leaders[id] = l
	gs.log_event(tag, "Nuevo %s: %s (%s, %s)" % ["general" if kind == "general" else "almirante", l["name"], p.get("name", ""), b.get("name", "")])
	return l


static func trait_names(gs: VGameState, l: Dictionary) -> String:
	var out := []
	for t in l.get("traits", []):
		for group in ["personalities", "backgrounds"]:
			for d in gs.leader_traits.get(group, []):
				if d["id"] == t:
					out.append(d["name"])
	return ", ".join(out)


static func describe(gs: VGameState, l: Dictionary) -> String:
	var parts := []
	for s in STATS:
		var v := float(l.get(s, 0.0))
		if v != 0.0:
			parts.append("%s %+g" % [{"attack": "ataque", "defence": "defensa", "morale": "moral", "organisation": "organización", "speed": "velocidad", "recon": "reconocimiento"}[s], v])
	return "%s — %s%s" % [l["name"], trait_names(gs, l), (" (" + ", ".join(parts) + ")") if not parts.is_empty() else ""]
