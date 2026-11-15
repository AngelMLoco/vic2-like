class_name VEventAI
extends RefCounted
## Elección de opción de la IA: peso base × factores de los modificadores cuyas condiciones se cumplen; las
## opciones con trigger falso pesan 0. Tirada ponderada determinista (evento, nación, mes): no siempre la A.


static func weights(gs: VGameState, e: Dictionary, ctx: Dictionary) -> Array:
	var out := []
	for o in e["options"]:
		if not VEventConditions.check(gs, o["trigger"], ctx):
			out.append(0.0)
			continue
		var w := float(o["ai_base"])
		for m in o["ai_mods"]:
			if VEventConditions.check(gs, m[1], ctx):
				w *= float(m[0])
		out.append(maxf(0.0, w))
	return out


static func choose(gs: VGameState, e: Dictionary, ctx: Dictionary) -> int:
	var w := weights(gs, e, ctx)
	var total := 0.0
	for x in w:
		total += float(x)
	if total <= 0.0:
		return 0
	var roll := VEventSystem.roll01("%s|%s|%d|ai" % [e["id"], ctx.get("tag", ""), gs.month_index]) * total
	for i in w.size():
		roll -= float(w[i])
		if roll < 0.0:
			return i
	return w.size() - 1
