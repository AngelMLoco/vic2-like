class_name VMagicPolicy
extends RefCounted
## Política mágica (M5): la reforma «magic_regulation» (politics/reforms.json) con niveles provisionales
## Prohibida · Tolerada · Licenciada · Promovida · Control estatal. Sus efectos son modificadores nacionales
## (capacidad y promoción de magos, atracción, investigación arcana, eficiencia de fábricas mágicas, militancia
## de los magos, tensión religiosa, plazas estatales).
##
## No todas las ideologías piensan igual: la postura de cada ideología es issues.magic_policy en
## ideologies.json (data-driven). En la cámara, cada ideología apoya los cambios que acercan la ley a su postura
## y se opone a los que la alejan (VPoliticsSystem.can_change_reform, tipo «magic»).
## IA (trimestral): el gobierno empuja hacia la postura de su partido, corregida por la situación (tensión
## religiosa, paro de magos, guerra, academias). Los eventos pueden decretar un nivel (set_magic_regulation).

const REFORM := "magic_regulation"


static func levels(gs: VGameState) -> Array:
	return gs.reforms.get(REFORM, {}).get("levels", [])


static func level_index(gs: VGameState, level_id: String) -> int:
	var lv := levels(gs)
	for i in lv.size():
		if lv[i]["id"] == level_id:
			return i
	return -1


static func level_id(gs: VGameState, tag: String) -> String:
	var lv := levels(gs)
	var i := gs.reform_level(tag, REFORM)
	return String(lv[i]["id"]) if i >= 0 and i < lv.size() else ""


## Índice de la postura de una ideología (issues.magic_policy); -1 si no tiene.
static func stance(gs: VGameState, ideology: String) -> int:
	return level_index(gs, String(gs.ideologies.get(ideology, {}).get("issues", {}).get("magic_policy", "")))


## Apoyo de una ideología a pasar de 'old' a 'new': +1 si acerca la ley a su postura, −1 si la aleja.
static func ideology_support(gs: VGameState, ideology: String, old: int, new: int) -> float:
	var st := stance(gs, ideology)
	if st < 0:
		return 0.0
	return signf(float(absi(old - st) - absi(new - st)))


## Decreto (eventos): fija el nivel sin pasar por la cámara.
static func set_level(gs: VGameState, tag: String, lid: String) -> void:
	var i := level_index(gs, lid)
	if i < 0 or not gs.countries.has(tag):
		return
	var c: Dictionary = gs.countries[tag]
	var old := gs.reform_level(tag, REFORM)
	if old == i:
		return
	c["reforms"][REFORM] = i
	VModifiers.recompute(gs, tag)
	gs.log_event(tag, "Regulación de la magia: %s" % levels(gs)[i]["name"])
	VEventSystem.notify(gs, "reform_passed", {"tag": tag, "reform": REFORM, "direction": signi(i - old)})


## IA trimestral (escalonada por nación desde VMageModel/VMagicSystem).
static func ai_country(gs: VGameState, tag: String, idx: int) -> void:
	if tag == gs.player_tag or not VMagicSystem.is_active(gs) or (gs.month_index + idx) % 3 != 2 or gs.flags.get("ai_disabled", false):
		return
	var c: Dictionary = gs.countries[tag]
	if int(c.get("reform_cooldown", 0)) > 0:
		return
	var cur := gs.reform_level(tag, REFORM)
	var want := desired_level(gs, tag)
	if want < 0 or want == cur:
		return
	# no todos los trimestres: un debate tarda (tirada determinista)
	if VEventSystem.roll01("magpol|%s|%d" % [tag, gs.month_index]) > 0.35:
		return
	VPoliticsSystem.change_reform(gs, tag, REFORM, 1 if want > cur else -1)


## Nivel que quiere el gobierno: postura del partido gobernante, corregida por la situación.
static func desired_level(gs: VGameState, tag: String) -> int:
	var rp := VPoliticsSystem.ruling_party(gs, tag)
	var want := stance(gs, String(rp.get("ideology", "")))
	if want < 0:
		return -1
	var c: Dictionary = gs.countries[tag]
	var info: Dictionary = c.get("_magi_info", {})
	var att := VMageModel.religion_attitude(gs, String(c.get("religion", "")))
	var ip := level_index(gs, "magic_promoted")
	var il := level_index(gs, "magic_licensed")
	var isc := level_index(gs, "magic_state_control")
	# clero hostil y muchos magos: el gobierno se vuelve más restrictivo
	if att in ["suspicious", "heretical"] and float(info.get("share", 0.0)) > 0.0006 and want > 0:
		want = mini(want, il)
	# crisis de magos sin empleo: se deja de fomentar
	if float(info.get("unemployment", 0.0)) > 0.3 and want == ip:
		want = il
	# en guerra, con rama militar, el Estado quiere controlar a los magos
	if not c.get("wars", []).is_empty() and VMagicSystem.branch_level(gs, tag, "military") >= 2 and want != 0:
		want = isc
	# con academias propias, la prohibición total se vuelve impracticable
	if VMageModel.academies(gs, tag) > 0 and want == 0:
		want = il
	return want
