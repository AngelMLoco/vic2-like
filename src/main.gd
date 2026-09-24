extends Control

const YEARS_PER_RUN := 20
const COUNTRY_COLORS := {
    "Ardel": Color("5b8def"), "Varka": Color("c75050"), "Selia": Color("d8a941"),
    "Khaz-Dur": Color("8d7652"), "Sylvar": Color("4f9d69"), "Orkhan": Color("8f5fbf"),
    "Lunaris": Color("6dc7d9"), "Erdan": Color("ce8455")
}

var rng := RandomNumberGenerator.new()
var year := 180
var countries := {}
var provinces: Array[Dictionary] = []
var relations := {}
var wars: Array[Dictionary] = []
var history: Array[String] = []
var fired_events := {}

var year_label: Label
var status_label: Label
var map_grid: GridContainer
var detail_text: RichTextLabel
var history_text: RichTextLabel

func _ready() -> void:
    rng.seed = 7
    _build_ui()
    _create_world()
    _refresh_all()

func _build_ui() -> void:
    var bg := ColorRect.new()
    bg.color = Color("101319")
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(bg)

    var root := VBoxContainer.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_theme_constant_override("separation", 8)
    root.offset_left = 12
    root.offset_top = 12
    root.offset_right = -12
    root.offset_bottom = -12
    add_child(root)

    var top := HBoxContainer.new()
    root.add_child(top)
    var title := Label.new()
    title.text = "CHRONICLES OF AETHER  —  prototipo de simulación"
    title.add_theme_font_size_override("font_size", 24)
    top.add_child(title)
    top.add_spacer(false)
    year_label = Label.new()
    year_label.add_theme_font_size_override("font_size", 22)
    top.add_child(year_label)

    var controls := HBoxContainer.new()
    root.add_child(controls)
    for item in [["+1 año",1],["+5 años",5],["+20 años",20]]:
        var b := Button.new()
        b.text = item[0]
        var amount: int = item[1]
        b.pressed.connect(func(): _advance_years(amount))
        controls.add_child(b)
    var reset := Button.new()
    reset.text = "Reiniciar mundo"
    reset.pressed.connect(_reset_world)
    controls.add_child(reset)
    status_label = Label.new()
    status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    controls.add_child(status_label)

    var body := HSplitContainer.new()
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(body)

    var left := VBoxContainer.new()
    left.custom_minimum_size.x = 850
    body.add_child(left)
    var map_title := Label.new()
    map_title.text = "Mapa abstracto (30 provincias)"
    left.add_child(map_title)
    map_grid = GridContainer.new()
    map_grid.columns = 6
    map_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
    left.add_child(map_grid)

    var right := VBoxContainer.new()
    right.custom_minimum_size.x = 430
    body.add_child(right)
    var tabs := TabContainer.new()
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    right.add_child(tabs)
    detail_text = RichTextLabel.new()
    detail_text.name = "Inspector"
    detail_text.bbcode_enabled = true
    tabs.add_child(detail_text)
    history_text = RichTextLabel.new()
    history_text.name = "Crónica"
    history_text.bbcode_enabled = true
    tabs.add_child(history_text)

func _create_world() -> void:
    countries = {
        "Ardel": _country("Asteriana","Monarquía constitucional",120.0,72.0,68.0,50.0,["Erdan"],["Varka"]),
        "Varka": _country("Varkesa","Imperio autocrático",150.0,66.0,82.0,45.0,["Selia"],["Ardel"]),
        "Selia": _country("Seliana","República mercantil",135.0,78.0,50.0,62.0,[],["Varka"]),
        "Khaz-Dur": _country("Enana","Confederación de clanes",110.0,82.0,64.0,42.0,["Erdan"],[]),
        "Sylvar": _country("Silvana","Consejo druídico",90.0,76.0,48.0,58.0,["Leth"],[]),
        "Orkhan": _country("Orca","Kanato electivo",95.0,58.0,77.0,35.0,["Mord"],["Varka"]),
        "Lunaris": _country("Lunar","Teocracia arcana",105.0,70.0,58.0,70.0,[],[]),
        "Erdan": _country("Enana","Principado",55.0,63.0,35.0,38.0,[],[])
    }
    provinces.clear()
    wars.clear()
    relations.clear()
    history.clear()
    fired_events.clear()
    year = 180

    var names := ["Valem","Roth","Eldor","Meren","Aster","Dorn","Kareth","Voln","Saren","Mira","Cindor","Harun","Eran","Talem","Bron","Duran","Khel","Nor","Leth","Virel","Mord","Krag","Ur","Selun","Asha","Neral","Erdan","Thol","Garen","Yrd"]
    var plan := [["Ardel",5],["Varka",5],["Selia",4],["Khaz-Dur",4],["Sylvar",3],["Orkhan",3],["Lunaris",3],["Erdan",3]]
    var resources := ["grano","hierro","madera","carbón","cristal arcano","caballos","azufre","plata"]
    var cultures := ["Asteriana","Varkesa","Seliana","Enana","Silvana","Orca","Lunar"]

    var idx := 0
    for row in plan:
        var owner: String = row[0]
        var count: int = row[1]
        for _j in range(count):
            var culture: String = countries[owner].culture
            if rng.randf() < 0.22:
                culture = cultures[rng.randi_range(0,cultures.size()-1)]
            provinces.append({
                "name": names[idx],
                "owner": owner,
                "culture": culture,
                "resource": resources[rng.randi_range(0,resources.size()-1)],
                "population": rng.randi_range(22000,85000),
                "wealth": rng.randf_range(0.7,1.35),
                "unrest": rng.randf_range(0.0,8.0)
            })
            idx += 1

    for p in provinces:
        if p.name == "Erdan":
            p.owner = "Erdan"
            p.culture = "Enana"
        if p.name == "Leth":
            p.owner = "Sylvar"
            p.culture = "Silvana"
        if p.name == "Mord":
            p.owner = "Orkhan"
            p.culture = "Orca"

    for a in countries:
        relations[a] = {}
        for b in countries:
            if a != b:
                relations[a][b] = rng.randi_range(-15,25)

    relations["Ardel"]["Varka"] = -65
    relations["Varka"]["Ardel"] = -65
    relations["Varka"]["Selia"] = -55
    relations["Selia"]["Varka"] = -55
    relations["Khaz-Dur"]["Erdan"] = 55
    relations["Erdan"]["Khaz-Dur"] = 55

    _log("Comienza la Era de los Reinos Modernos.")

func _country(culture:String, government:String, treasury:float, stability:float, military:float, prestige:float, claims:Array, rivals:Array) -> Dictionary:
    return {
        "culture": culture,
        "government": government,
        "treasury": treasury,
        "stability": stability,
        "military": military,
        "prestige": prestige,
        "claims": claims,
        "rivals": rivals,
        "alive": true
    }

func _advance_years(amount:int) -> void:
    for _i in range(amount):
        year += 1
        _economy()
        _population_and_unrest()
        _diplomacy()
        _historical_events()
        _war_logic()
        _resolve_wars()
    _refresh_all()

func _economy() -> void:
    var values := {
        "grano":1.0, "hierro":1.35, "madera":1.1, "carbón":1.4,
        "cristal arcano":2.2, "caballos":1.25, "azufre":1.5, "plata":1.8
    }
    for name in countries:
        var c: Dictionary = countries[name]
        if not c.alive:
            continue
        var production := 0.0
        for p in provinces:
            if p.owner == name:
                production += (p.population / 25000.0) * p.wealth * values[p.resource]
        var war_penalty := 0.80 if _at_war(name) else 1.0
        c.treasury += production * 1.8 * war_penalty - c.military * 0.10
        if c.treasury < 0:
            c.stability -= 3.0
            c.military *= 0.98
        else:
            c.stability = minf(100.0, float(c.stability) + 0.35)
        countries[name] = c

func _population_and_unrest() -> void:
    for i in range(provinces.size()):
        var p: Dictionary = provinces[i]
        var c: Dictionary = countries[p.owner]
        var growth := 1.0 + rng.randf_range(0.004,0.016)
        if _at_war(p.owner):
            growth -= rng.randf_range(0.002,0.010)
        p.population = maxi(1000, int(p.population * growth))
        var pressure := 0.0
        if p.culture != c.culture:
            pressure += 1.8
        if c.stability < 50:
            pressure += (50.0-c.stability)/18.0
        if c.treasury < 20:
            pressure += 1.0
        p.unrest = clampf(float(p.unrest) + pressure - rng.randf_range(0.4,1.6), 0.0, 100.0)
        if p.unrest > 72 and rng.randf() < 0.18:
            c.stability -= 4.0
            _log("Disturbios en %s sacuden a %s; la población %s exige cambios." % [p.name,p.owner,p.culture])
            p.unrest *= 0.65
        countries[p.owner] = c
        provinces[i] = p

func _diplomacy() -> void:
    var names := countries.keys()
    for a in names:
        if not countries[a].alive:
            continue
        for b in names:
            if a == b or not countries[b].alive:
                continue
            var drift := rng.randi_range(-3,3)
            if countries[a].rivals.has(b):
                drift -= 2
            relations[a][b] = clampi(int(relations[a][b]) + drift, -100, 100)

func _historical_events() -> void:
    if year >= 184 and not fired_events.has("arcane_engine"):
        fired_events["arcane_engine"] = true
        countries["Lunaris"].prestige += 14
        countries["Lunaris"].treasury += 20
        _log("Lunaris demuestra el primer motor de cristal arcano. Comerciantes y monarcas hablan de una nueva era industrial.")

    if year >= 187 and countries["Ardel"].stability < 69 and not fired_events.has("ardel_reform"):
        fired_events["ardel_reform"] = true
        countries["Ardel"].government = "Monarquía parlamentaria"
        countries["Ardel"].stability += 13
        _log("La Crisis de Valem obliga a la corona de Ardel a aceptar un parlamento con poderes reales.")

    if year >= 190 and not fired_events.has("orc_reform") and countries["Orkhan"].stability < 55:
        fired_events["orc_reform"] = true
        countries["Orkhan"].government = "Kanato reformista"
        countries["Orkhan"].military += 8
        countries["Orkhan"].stability += 10
        _log("Los clanes de Orkhan pactan la Reforma de las Nueve Banderas y profesionalizan el ejército.")

    if year >= 194 and not fired_events.has("arcane_accident"):
        fired_events["arcane_accident"] = true
        countries["Lunaris"].stability -= 10
        for i in range(provinces.size()):
            if provinces[i].owner == "Lunaris" and provinces[i].resource == "cristal arcano":
                provinces[i].unrest += 15
        _log("Una explosión en una refinería arcana de Lunaris inicia el primer debate sobre regulación mágica industrial.")

func _war_logic() -> void:
    if wars.size() >= 2:
        return
    for attacker in countries:
        if not countries[attacker].alive or _at_war(attacker):
            continue
        for defender in countries:
            if attacker == defender or not countries[defender].alive or _at_war(defender):
                continue
            var hostility: float = -float(relations[attacker][defender])
            var power_ratio: float = float(countries[attacker].military) / maxf(1.0, float(countries[defender].military))
            var claim_bonus: float = 0.0
            for p in provinces:
                if p.owner == defender and countries[attacker].claims.has(p.name):
                    claim_bonus = 35.0
            var desire: float = hostility + claim_bonus + maxf(0.0, (power_ratio - 1.0) * 35.0)
            if desire > 86 and rng.randf() < 0.11:
                wars.append({"attacker":attacker,"defender":defender,"years":0,"score":0.0})
                _log("%s declara la guerra a %s." % [attacker,defender])
                return

func _resolve_wars() -> void:
    for idx in range(wars.size()-1,-1,-1):
        var w: Dictionary = wars[idx]
        var a: Dictionary = countries[w.attacker]
        var d: Dictionary = countries[w.defender]
        w.years += 1
        var a_roll: float = float(a.military) * rng.randf_range(0.70, 1.30) + float(a.stability) * 0.25
        var d_roll: float = float(d.military) * rng.randf_range(0.70, 1.30) + float(d.stability) * 0.25
        w.score += (a_roll-d_roll)/18.0
        a.treasury -= 9
        d.treasury -= 9
        a.stability -= rng.randf_range(0.4,1.4)
        d.stability -= rng.randf_range(0.4,1.4)
        a.military = maxf(8.0, float(a.military) - rng.randf_range(0.5, 2.0))
        d.military = maxf(8.0, float(d.military) - rng.randf_range(0.5, 2.0))
        countries[w.attacker]=a
        countries[w.defender]=d
        wars[idx]=w
        if abs(w.score) > 8 or w.years >= 5:
            var winner: String = w.attacker if w.score >= 0 else w.defender
            var loser: String = w.defender if winner == w.attacker else w.attacker
            _peace(winner, loser, w)
            wars.remove_at(idx)

func _peace(winner:String, loser:String, _w:Dictionary) -> void:
    var candidates := []
    for i in range(provinces.size()):
        if provinces[i].owner == loser:
            candidates.append(i)

    var taken := ""
    if candidates.size() > 1:
        var preferred := -1
        for i in candidates:
            if countries[winner].claims.has(provinces[i].name):
                preferred = i
                break
        var target: int = preferred if preferred >= 0 else int(candidates[rng.randi_range(0, candidates.size() - 1)])
        taken = provinces[target].name
        provinces[target].owner = winner
        provinces[target].unrest += 25

    countries[winner].prestige += 8
    countries[loser].prestige -= 6
    countries[loser].stability -= 7
    relations[winner][loser] = -85
    relations[loser][winner] = -85

    if taken != "":
        _log("La guerra termina con victoria de %s. %s cede %s." % [winner,loser,taken])
    else:
        _log("La guerra termina con victoria de %s, pero sin cambios territoriales." % winner)

func _at_war(name:String) -> bool:
    for w in wars:
        if w.attacker == name or w.defender == name:
            return true
    return false

func _log(text:String) -> void:
    history.append("%d — %s" % [year,text])

func _reset_world() -> void:
    rng.seed = 7
    _create_world()
    _refresh_all()

func _refresh_all() -> void:
    year_label.text = "Año %d" % year
    status_label.text = "%d guerras activas  |  %s" % [wars.size(), "mundo estable" if wars.is_empty() else "conflicto en curso"]
    _rebuild_map()
    _refresh_history()
    if provinces.size() > 0:
        _show_province(provinces[0])

func _rebuild_map() -> void:
    for child in map_grid.get_children():
        child.queue_free()
    for p in provinces:
        var b := Button.new()
        b.custom_minimum_size = Vector2(125,105)
        b.text = "%s\n%s\n%s\n%.0fK hab." % [p.name,p.owner,p.resource,p.population/1000.0]
        var style := StyleBoxFlat.new()
        style.bg_color = COUNTRY_COLORS.get(p.owner,Color.GRAY)
        style.corner_radius_top_left=5
        style.corner_radius_top_right=5
        style.corner_radius_bottom_left=5
        style.corner_radius_bottom_right=5
        b.add_theme_stylebox_override("normal",style)
        var hp := p.duplicate(true)
        b.pressed.connect(func(): _show_province(hp))
        map_grid.add_child(b)

func _show_province(p:Dictionary) -> void:
    var c: Dictionary = countries[p.owner]
    detail_text.text = "[font_size=24][b]%s[/b][/font_size]\n[color=#aaaaaa]%s[/color]\n\n[b]Provincia[/b]\nCultura: %s\nRecurso: %s\nPoblación: %s\nRiqueza local: %.2f\nDescontento: %.1f / 100\n\n[b]%s[/b]\nGobierno: %s\nCultura estatal: %s\nTesoro: %.1f\nEstabilidad: %.1f\nPoder militar: %.1f\nPrestigio: %.1f\n\n[b]Situación[/b]\n%s" % [p.name,p.owner,p.culture,p.resource,_fmt_pop(p.population),p.wealth,p.unrest,p.owner,c.government,c.culture,c.treasury,c.stability,c.military,c.prestige,"EN GUERRA" if _at_war(p.owner) else "En paz"]

func _refresh_history() -> void:
    var lines := ["[font_size=22][b]Crónica del mundo[/b][/font_size]\n"]
    var start: int = maxi(0, history.size() - 35)
    for i in range(start,history.size()):
        lines.append(history[i])
    history_text.text = "\n".join(lines)
    history_text.scroll_to_line(history.size())

func _fmt_pop(n:int) -> String:
    if n >= 1000000:
        return "%.2f M" % (n/1000000.0)
    return "%.1f mil" % (n/1000.0)
