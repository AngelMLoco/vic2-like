class_name VEventDebug
extends RefCounted
## Consola de depuración de contenido (pruebas y desarrollo; sin esperar años de partida):
##   VEventDebug.run(gs, "fire_event magic.world.awakening")
##   VEventDebug.run(gs, "fire_event core.economy.food_crisis FRK")
##   VEventDebug.run(gs, "fire_event magic.world.ley_discovery PRS 1234")      (provincia)
##   VEventDebug.run(gs, "take_decision found_arcane_academy PRS")
##   VEventDebug.run(gs, "activate_magic")
##   VEventDebug.run(gs, "list_available_decisions FRK")
##   VEventDebug.run(gs, "list_events")
## Devuelve un texto con el resultado.


static func run(gs: VGameState, command: String) -> String:
	var a := command.strip_edges().split(" ", false)
	if a.is_empty():
		return "comandos: fire_event <id> [TAG] [provincia], take_decision <id> <TAG>, activate_magic, list_available_decisions <TAG>, list_events"
	var tag := a[2] if a.size() > 2 else gs.player_tag
	match a[0]:
		"fire_event":
			if a.size() < 2:
				return "uso: fire_event <id> [TAG] [provincia]"
			var prov := int(a[3]) if a.size() > 3 else 0
			return ("disparado %s" % a[1]) if VEventSystem.debug_fire(gs, a[1], tag if a.size() > 2 else (tag if gs.event_defs.get(a[1], {}).get("scope", "") != "global" else ""), prov) else "evento desconocido"
		"take_decision":
			if a.size() < 2:
				return "uso: take_decision <id> <TAG>"
			var err := VDecisionSystem.debug_take(gs, tag, a[1])
			return "tomada" if err == "" else err
		"activate_magic":
			VMagicSystem.debug_activate(gs)
			return "magia activada"
		"list_available_decisions":
			var t2 := a[1] if a.size() > 1 else gs.player_tag
			return ", ".join(VDecisionSystem.list_available(gs, t2))
		"list_events":
			var ids := gs.event_defs.keys()
			ids.sort()
			return ", ".join(ids)
	return "comando desconocido: " + a[0]
