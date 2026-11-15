class_name VBattleResolver
extends RefCounted
## Interfaz del resolvedor de combate terrestre.
##
## VCombatSystem crea las batallas, une a los ejércitos que llegan, termina la batalla, ordena
## retiradas y comunica el resultado a VWarSystem (warscore). El resolver SOLO decide qué pasa en
## cada día de combate: daños de organización y bajas.
##
## Implementaciones:
##   VBattleResolverVictoria — provisional (dados, ataque/defensa, terreno, líder, anchura de frente).
##   VBattleResolverCards    — futura (mazos de cartas de los comandantes). Se enchufa con
##                             VCombatSystem.set_resolver(...) sin tocar ejército, movimiento,
##                             ocupación ni warscore.
##
## Contrato de resolve_tick(battle, gs) -> {"done": bool, "winner": "attacker" | "defender" | ""}
##   · debe aplicar las bajas SOLO mediante VCombatSystem.damage_brigade() (que resta hombres a los
##     POPs de soldados y registra las pérdidas de la batalla);
##   · puede leer cualquier dato de gs y guardar su propio estado en battle["resolver_state"].


func resolve_tick(_battle: Dictionary, _gs: VGameState) -> Dictionary:
	push_error("VBattleResolver.resolve_tick no implementado")
	return {"done": true, "winner": "defender"}


func resolver_name() -> String:
	return "abstracto"
