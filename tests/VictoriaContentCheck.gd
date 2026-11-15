## Comprobación rápida de carga de contenido (errores de datos y recuento), sin simular:
##   godot --headless --path . -s tests/VictoriaContentCheck.gd
extends SceneTree

func _process(_d: float) -> bool:
	var gs := VDataLoader.new_game()
	print("eventos %d · decisiones %d · modificadores %d · categorías de arte %d · paquetes %s · escenario %s" % [
		gs.event_defs.size(), gs.decision_defs.size(), gs.event_modifiers.size(), gs.art_manifest.size(),
		str(gs.content_packs), gs.scenario_id])
	var by_ns := {}
	for id in gs.event_defs:
		var ns: String = String(id).get_slice(".", 0) + "." + String(id).get_slice(".", 1)
		by_ns[ns] = int(by_ns.get(ns, 0)) + 1
	print("por espacio de nombres: ", by_ns)
	for e in gs.data_errors:
		print("ERROR DE DATOS: ", e)
	print("errores de datos: %d" % gs.data_errors.size())
	quit(1 if not gs.data_errors.is_empty() else 0)
	return true
