extends Node
## Experiencia del jugador (M5): ventanas y notificaciones que recibe un país jugador simulado en tres
## situaciones de 5 años: paz, guerra y crisis mágica. El «jugador» elige como la IA (sin interfaz).
##   godot --headless --path . res://tests/VictoriaPlayerExperienceTest.tscn -- [años por escenario]
## Objetivo: contenido frecuente pero sin interrupciones constantes (≈ 2–12 ventanas al año).

const PLAYER := "FRK"

var failures := 0
var years := 5


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		years = int(args[0])
	await get_tree().process_frame
	var res := {}
	for scenario in ["paz", "guerra", "crisis mágica"]:
		res[scenario] = run(scenario)
	print("\n== resumen (por año) ==")
	for k in res:
		var r: Dictionary = res[k]
		print("  %-14s ventanas %.1f (mayores %.1f, normales %.1f) · notificaciones %.1f · ocultos %.1f · crónica del jugador %d" % [k, r["popups"], r["major"], r["normal"], r["notif"], r["hidden"], int(r["chronicle"])])
		check(float(r["popups"]) >= 1.0, "%s: el jugador recibe contenido (%.1f ventanas/año)" % [k, r["popups"]])
		check(float(r["popups"]) <= 14.0, "%s: sin interrupciones constantes (%.1f ventanas/año)" % [k, r["popups"]])
		check(float(r["major"]) <= 3.0, "%s: los acontecimientos mayores son raros (%.1f/año)" % [k, r["major"]])
	check(float(res["guerra"]["popups"]) >= float(res["paz"]["popups"]) * 0.8, "la guerra produce al menos tanto contenido como la paz")
	print("== %d fallos ==" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func run(scenario: String) -> Dictionary:
	print("-- %s (%d años)" % [scenario, years])
	var gs := VDataLoader.new_game()
	gs.player_tag = PLAYER
	gs.flags["events_no_pause"] = true
	var sim := VWorldSimulation.new(gs)
	var note := ""
	if scenario == "guerra":
		var enemy := ""
		for n in VDiplomacySystem.neighbor_countries(gs, PLAYER):
			if not gs.countries[n]["provinces"].is_empty() and not (n in gs.countries[PLAYER]["allies"]) and float(gs.countries[n].get("military_score", 0.0)) > 5.0:
				enemy = n
				break
		VEventEffects.apply(gs, {"start_war": {"cb": "humiliate"}}, {"tag": PLAYER, "target": enemy})
		note = "contra %s" % enemy
	elif scenario == "crisis mágica":
		VMagicSystem.activate(gs)
		VMagicPolicy.set_level(gs, PLAYER, "magic_promoted")
		VMagicSystem.convert_pops(gs, PLAYER, 0, {"from": ["clerks", "clergy"], "to": "magi", "share": 0.25, "max": 60000})
		note = "magia activa, fomento y magos sin plazas suficientes"
	var st: Dictionary = VScopedState.es(gs)["stats"]
	var k0 := {"player_major": int(st.get("player_major", 0)), "player_normal": int(st.get("player_normal", 0)),
		"player_notification": int(st.get("player_notification", 0)), "player_hidden": int(st.get("player_hidden", 0))}
	var popups := 0
	for d in years * 365:
		sim.run_days(1)
		# el jugador simulado responde a todas las ventanas pendientes (elige como la IA)
		var q: Array = VEventSystem.pending(gs)
		while not q.is_empty():
			var item: Dictionary = q[0]
			var e: Dictionary = gs.event_defs.get(item["id"], {})
			var opt := VEventAI.choose(gs, e, item["ctx"]) if not e.is_empty() else 0
			VEventSystem.choose(gs, 0, opt)
			popups += 1
	var y := float(years)
	var out := {
		"major": float(int(st.get("player_major", 0)) - k0["player_major"]) / y,
		"normal": float(int(st.get("player_normal", 0)) - k0["player_normal"]) / y,
		"notif": float(int(st.get("player_notification", 0)) - k0["player_notification"]) / y,
		"hidden": float(int(st.get("player_hidden", 0)) - k0["player_hidden"]) / y,
		"chronicle": VChronicle.entries_for(gs, PLAYER, "", 1000).size()}
	out["popups"] = float(out["major"]) + float(out["normal"])
	print("   %s · ventanas respondidas %d · guerras activas del jugador %d" % [note, popups, gs.countries[PLAYER]["wars"].size()])
	for e in VChronicle.entries_for(gs, PLAYER, "", 6):
		print("     ", VChronicle.line(e))
	return out
