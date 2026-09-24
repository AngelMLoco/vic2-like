extends Control

const START_YEAR := 180

const COUNTRY_COLORS := {
    "Ardel": Color("5b8def"),
    "Varka": Color("c75050"),
    "Selia": Color("d8a941"),
    "Khaz-Dur": Color("8d7652"),
    "Sylvar": Color("4f9d69"),
    "Orkhan": Color("8f5fbf"),
    "Lunaris": Color("6dc7d9"),
    "Erdan": Color("ce8455")
}

const RESOURCE_VALUES := {
    "grano": 1.00,
    "hierro": 1.35,
    "madera": 1.10,
    "carbón": 1.40,
    "cristal arcano": 2.20,
    "caballos": 1.25,
    "azufre": 1.50,
    "plata": 1.80
}

const CLASS_PRODUCTIVITY := {
    "Campesinos": 0.85,
    "Mineros": 1.15,
    "Obreros": 1.20,
    "Artesanos": 1.10,
    "Comerciantes": 0.70,
    "Soldados": 0.25,
    "Burócratas": 0.35,
    "Clérigos": 0.25,
    "Aristócratas": 0.15,
    "Magos": 0.80
}

const CLASS_INCOME := {
    "Campesinos": 0.55,
    "Mineros": 0.72,
    "Obreros": 0.68,
    "Artesanos": 0.85,
    "Comerciantes": 1.15,
    "Soldados": 0.72,
    "Burócratas": 0.95,
    "Clérigos": 0.82,
    "Aristócratas": 1.65,
    "Magos": 1.35
}

const CLASS_NEED_COST := {
    "Campesinos": 0.72,
    "Mineros": 0.78,
    "Obreros": 0.80,
    "Artesanos": 0.92,
    "Comerciantes": 1.15,
    "Soldados": 0.82,
    "Burócratas": 1.00,
    "Clérigos": 0.90,
    "Aristócratas": 1.55,
    "Magos": 1.30
}

var rng := RandomNumberGenerator.new()
var current_seed: int = 7
var year: int = START_YEAR

var countries := {}
var provinces: Array[Dictionary] = []
var relations := {}
var wars: Array[Dictionary] = []
var history: Array[String] = []
var fired_events := {}

var stats := {}
var initial_population: int = 0
var selected_province_index: int = 0

var year_label: Label
var status_label: Label
var seed_input: LineEdit
var map_grid: GridContainer
var detail_text: RichTextLabel
var pops_text: RichTextLabel
var history_text: RichTextLabel
var summary_text: RichTextLabel


func _ready() -> void:
    rng.seed = current_seed
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
    title.text = "CHRONICLES OF AETHER  —  v0.2 POP LAB"
    title.add_theme_font_size_override("font_size", 24)
    top.add_child(title)
    top.add_spacer(false)

    year_label = Label.new()
    year_label.add_theme_font_size_override("font_size", 22)
    top.add_child(year_label)

    var controls := HBoxContainer.new()
    controls.add_theme_constant_override("separation", 6)
    root.add_child(controls)

    for item in [["+1 año", 1], ["+5 años", 5], ["+20 años", 20], ["+100 años", 100]]:
        var b := Button.new()
        b.text = String(item[0])
        var amount: int = int(item[1])
        b.pressed.connect(func(): _advance_years(amount))
        controls.add_child(b)

    var reset := Button.new()
    reset.text = "Reiniciar misma seed"
    reset.pressed.connect(_reset_world)
    controls.add_child(reset)

    var seed_label := Label.new()
    seed_label.text = "  Seed:"
    controls.add_child(seed_label)

    seed_input = LineEdit.new()
    seed_input.custom_minimum_size.x = 120
    seed_input.text = str(current_seed)
    seed_input.placeholder_text = "Ej. 481920"
    seed_input.text_submitted.connect(func(_value: String): _use_seed())
    controls.add_child(seed_input)

    var use_seed := Button.new()
    use_seed.text = "Usar seed"
    use_seed.pressed.connect(_use_seed)
    controls.add_child(use_seed)

    var random_seed := Button.new()
    random_seed.text = "Nueva aleatoria"
    random_seed.pressed.connect(_random_world)
    controls.add_child(random_seed)

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
    map_title.text = "Mapa abstracto — haz clic en una provincia"
    left.add_child(map_title)

    map_grid = GridContainer.new()
    map_grid.columns = 6
    map_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
    left.add_child(map_grid)

    var right := VBoxContainer.new()
    right.custom_minimum_size.x = 500
    body.add_child(right)

    var tabs := TabContainer.new()
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    right.add_child(tabs)

    detail_text = RichTextLabel.new()
    detail_text.name = "Inspector"
    detail_text.bbcode_enabled = true
    tabs.add_child(detail_text)

    pops_text = RichTextLabel.new()
    pops_text.name = "POPs"
    pops_text.bbcode_enabled = true
    tabs.add_child(pops_text)

    history_text = RichTextLabel.new()
    history_text.name = "Crónica"
    history_text.bbcode_enabled = true
    tabs.add_child(history_text)

    summary_text = RichTextLabel.new()
    summary_text.name = "Resumen"
    summary_text.bbcode_enabled = true
    tabs.add_child(summary_text)


func _create_world() -> void:
    rng.seed = current_seed
    year = START_YEAR
    selected_province_index = 0

    countries = {
        "Ardel": _country("Asteriana", "Monarquía constitucional", 120.0, 72.0, 68.0, 50.0, ["Erdan"], ["Varka"]),
        "Varka": _country("Varkesa", "Imperio autocrático", 150.0, 66.0, 82.0, 45.0, ["Selia"], ["Ardel"]),
        "Selia": _country("Seliana", "República mercantil", 135.0, 78.0, 50.0, 62.0, [], ["Varka"]),
        "Khaz-Dur": _country("Enana", "Confederación de clanes", 110.0, 82.0, 64.0, 42.0, ["Erdan"], []),
        "Sylvar": _country("Silvana", "Consejo druídico", 90.0, 76.0, 48.0, 58.0, ["Leth"], []),
        "Orkhan": _country("Orca", "Kanato electivo", 95.0, 58.0, 77.0, 35.0, ["Mord"], ["Varka"]),
        "Lunaris": _country("Lunar", "Teocracia arcana", 105.0, 70.0, 58.0, 70.0, [], []),
        "Erdan": _country("Enana", "Principado", 55.0, 63.0, 35.0, 38.0, [], [])
    }

    provinces.clear()
    wars.clear()
    relations.clear()
    history.clear()
    fired_events.clear()

    stats = {
        "wars": 0,
        "territorial_changes": 0,
        "revolts": 0,
        "reforms": 0,
        "major_events": 0
    }

    var names: Array[String] = [
        "Valem", "Roth", "Eldor", "Meren", "Aster",
        "Dorn", "Kareth", "Voln", "Saren", "Mira",
        "Cindor", "Harun", "Eran", "Talem", "Bron",
        "Duran", "Khel", "Nor", "Leth", "Virel",
        "Mord", "Krag", "Ur", "Selun", "Asha",
        "Neral", "Erdan", "Thol", "Garen", "Yrd"
    ]

    var plan: Array = [
        ["Ardel", 5],
        ["Varka", 5],
        ["Selia", 4],
        ["Khaz-Dur", 4],
        ["Sylvar", 3],
        ["Orkhan", 3],
        ["Lunaris", 3],
        ["Erdan", 3]
    ]

    var resources: Array[String] = [
        "grano", "hierro", "madera", "carbón",
        "cristal arcano", "caballos", "azufre", "plata"
    ]

    var cultures: Array[String] = [
        "Asteriana", "Varkesa", "Seliana", "Enana", "Silvana", "Orca", "Lunar"
    ]

    var idx: int = 0
    for row in plan:
        var owner: String = String(row[0])
        var count: int = int(row[1])

        for _j in range(count):
            var state_culture: String = String(countries[owner]["culture"])
            var local_culture: String = state_culture

            if rng.randf() < 0.22:
                local_culture = cultures[rng.randi_range(0, cultures.size() - 1)]

            var resource: String = resources[rng.randi_range(0, resources.size() - 1)]
            var total_population: int = rng.randi_range(30000, 95000)
            var local_wealth: float = rng.randf_range(0.75, 1.30)

            var pops: Array[Dictionary] = _generate_pops(
                total_population,
                state_culture,
                local_culture,
                resource
            )

            provinces.append({
                "name": names[idx],
                "owner": owner,
                "culture": _dominant_culture(pops),
                "resource": resource,
                "population": _sum_pop_sizes(pops),
                "wealth": local_wealth,
                "unrest": _weighted_pop_value(pops, "militancy"),
                "pops": pops
            })
            idx += 1

    for i in range(provinces.size()):
        var province: Dictionary = provinces[i]

        if String(province["name"]) == "Erdan":
            province["owner"] = "Erdan"
            _shift_pop_culture(province, "Enana", 0.82)

        if String(province["name"]) == "Leth":
            province["owner"] = "Sylvar"
            _shift_pop_culture(province, "Silvana", 0.82)

        if String(province["name"]) == "Mord":
            province["owner"] = "Orkhan"
            _shift_pop_culture(province, "Orca", 0.82)

        province["culture"] = _dominant_culture(province["pops"])
        province["population"] = _sum_pop_sizes(province["pops"])
        provinces[i] = province

    for a in countries:
        relations[a] = {}
        for b in countries:
            if a != b:
                relations[a][b] = rng.randi_range(-15, 25)

    relations["Ardel"]["Varka"] = -65
    relations["Varka"]["Ardel"] = -65
    relations["Varka"]["Selia"] = -55
    relations["Selia"]["Varka"] = -55
    relations["Khaz-Dur"]["Erdan"] = 55
    relations["Erdan"]["Khaz-Dur"] = 55

    initial_population = _world_population()
    _log("Comienza la Era de los Reinos Modernos. Seed %d." % current_seed)


func _country(
    culture: String,
    government: String,
    treasury: float,
    stability: float,
    military: float,
    prestige: float,
    claims: Array,
    rivals: Array
) -> Dictionary:
    return {
        "culture": culture,
        "government": government,
        "treasury": treasury,
        "stability": stability,
        "military": military,
        "prestige": prestige,
        "claims": claims,
        "rivals": rivals,
        "alive": true,
        "last_output": 0.0
    }


func _generate_pops(
    total: int,
    state_culture: String,
    local_culture: String,
    resource: String
) -> Array[Dictionary]:
    var shares := {
        "Campesinos": 0.30,
        "Mineros": 0.10,
        "Obreros": 0.17,
        "Artesanos": 0.10,
        "Comerciantes": 0.055,
        "Soldados": 0.065,
        "Burócratas": 0.035,
        "Clérigos": 0.035,
        "Aristócratas": 0.018,
        "Magos": 0.012
    }

    if resource == "grano" or resource == "caballos" or resource == "madera":
        shares["Campesinos"] = 0.46
        shares["Mineros"] = 0.035
        shares["Obreros"] = 0.115

    if resource == "hierro" or resource == "carbón" or resource == "azufre" or resource == "plata":
        shares["Campesinos"] = 0.19
        shares["Mineros"] = 0.34
        shares["Obreros"] = 0.16

    if resource == "cristal arcano":
        shares["Campesinos"] = 0.16
        shares["Mineros"] = 0.24
        shares["Obreros"] = 0.15
        shares["Magos"] = 0.075

    var total_share: float = 0.0
    for value in shares.values():
        total_share += float(value)

    var result: Array[Dictionary] = []
    var assigned: int = 0
    var classes: Array = shares.keys()

    for class_index in range(classes.size()):
        var pop_class: String = String(classes[class_index])
        var size: int

        if class_index == classes.size() - 1:
            size = maxi(1, total - assigned)
        else:
            size = maxi(1, int(round(float(total) * float(shares[pop_class]) / total_share)))
            assigned += size

        var culture: String = state_culture
        if local_culture != state_culture and rng.randf() < 0.55:
            culture = local_culture
        elif rng.randf() < 0.08:
            culture = local_culture

        var literacy: float = _base_literacy(pop_class) + rng.randf_range(-0.08, 0.08)
        var wealth: float = _base_wealth(pop_class) + rng.randf_range(-8.0, 8.0)
        var needs: float = clampf(rng.randf_range(0.52, 0.88) + wealth / 420.0, 0.25, 1.0)
        var militancy: float = clampf((1.0 - needs) * 30.0 + rng.randf_range(0.0, 6.0), 0.0, 100.0)

        if culture != state_culture:
            militancy += rng.randf_range(2.0, 7.0)

        result.append({
            "class": pop_class,
            "size": size,
            "culture": culture,
            "religion": _religion_for_culture(culture),
            "literacy": clampf(literacy, 0.02, 0.95),
            "wealth": clampf(wealth, 2.0, 100.0),
            "militancy": clampf(militancy, 0.0, 100.0),
            "needs": needs,
            "ideology": _initial_ideology(pop_class)
        })

    return result


func _base_literacy(pop_class: String) -> float:
    match pop_class:
        "Aristócratas", "Magos", "Burócratas":
            return 0.58
        "Comerciantes", "Clérigos", "Artesanos":
            return 0.42
        "Soldados", "Obreros":
            return 0.26
        "Mineros":
            return 0.20
        _:
            return 0.16


func _base_wealth(pop_class: String) -> float:
    match pop_class:
        "Aristócratas":
            return 82.0
        "Magos":
            return 64.0
        "Comerciantes":
            return 58.0
        "Burócratas", "Clérigos":
            return 45.0
        "Artesanos":
            return 38.0
        "Soldados":
            return 31.0
        "Obreros", "Mineros":
            return 25.0
        _:
            return 22.0


func _initial_ideology(pop_class: String) -> String:
    var roll: float = rng.randf()

    if pop_class == "Aristócratas" or pop_class == "Clérigos":
        return "Tradicionalista" if roll < 0.72 else "Conservadora"

    if pop_class == "Obreros" or pop_class == "Mineros":
        if roll < 0.28:
            return "Reformista"
        if roll < 0.55:
            return "Popular"
        return "Conservadora"

    if pop_class == "Magos" or pop_class == "Burócratas":
        return "Reformista" if roll < 0.58 else "Conservadora"

    return "Conservadora" if roll < 0.58 else "Reformista"


func _religion_for_culture(culture: String) -> String:
    match culture:
        "Enana":
            return "Culto de la Forja"
        "Silvana":
            return "Antigua Fe"
        "Orca":
            return "Culto de los Ancestros"
        "Lunar":
            return "Iglesia Lunar"
        "Varkesa":
            return "Iglesia Imperial"
        _:
            return "Iglesia Solar"


func _advance_years(amount: int) -> void:
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
    var output_by_country := {}

    for country_name in countries:
        output_by_country[country_name] = 0.0

    for province_index in range(provinces.size()):
        var p: Dictionary = provinces[province_index]
        var owner: String = String(p["owner"])
        var c: Dictionary = countries[owner]
        var resource: String = String(p["resource"])
        var resource_value: float = float(RESOURCE_VALUES.get(resource, 1.0))
        var province_output: float = 0.0
        var pops: Array = p["pops"]

        for pop_index in range(pops.size()):
            var pop: Dictionary = pops[pop_index]
            var pop_class: String = String(pop["class"])
            var size: int = int(pop["size"])
            var productivity: float = float(CLASS_PRODUCTIVITY.get(pop_class, 0.5))
            var literacy_bonus: float = 0.80 + float(pop["literacy"]) * 0.55
            var work_output: float = (float(size) / 1000.0) * productivity * resource_value * literacy_bonus

            province_output += work_output

            var income_factor: float = float(CLASS_INCOME.get(pop_class, 0.7))
            var need_cost: float = float(CLASS_NEED_COST.get(pop_class, 1.0))
            var economic_health: float = clampf(float(c["treasury"]) / 180.0, -0.25, 0.55)
            var war_penalty: float = -0.16 if _at_war(owner) else 0.0
            var wage_effect: float = income_factor * float(p["wealth"]) * 0.22
            var affordability: float = 0.46 + wage_effect / (22.0 * need_cost) + economic_health + war_penalty
            var needs: float = clampf(affordability, 0.12, 1.0)

            pop["needs"] = lerpf(float(pop["needs"]), needs, 0.35)

            var wealth_delta: float = (float(pop["needs"]) - 0.62) * 4.0
            if _at_war(owner):
                wealth_delta -= 0.7
            pop["wealth"] = clampf(float(pop["wealth"]) + wealth_delta, 1.0, 100.0)

            pops[pop_index] = pop

        p["pops"] = pops
        p["wealth"] = clampf(float(p["wealth"]) + (province_output / 450.0) - 0.08, 0.55, 2.0)
        provinces[province_index] = p
        output_by_country[owner] = float(output_by_country[owner]) + province_output

    for country_name in countries:
        var c: Dictionary = countries[country_name]
        if not bool(c["alive"]):
            continue

        var gross_output: float = float(output_by_country[country_name])
        var tax_income: float = gross_output * 0.12
        var military_upkeep: float = float(c["military"]) * 0.10
        var war_cost: float = 7.5 if _at_war(String(country_name)) else 0.0

        c["last_output"] = gross_output
        c["treasury"] = float(c["treasury"]) + tax_income - military_upkeep - war_cost

        if float(c["treasury"]) < 0.0:
            c["stability"] = float(c["stability"]) - 2.5
            c["military"] = float(c["military"]) * 0.985
        else:
            c["stability"] = minf(100.0, float(c["stability"]) + 0.30)

        countries[country_name] = c


func _population_and_unrest() -> void:
    for province_index in range(provinces.size()):
        var p: Dictionary = provinces[province_index]
        var owner: String = String(p["owner"])
        var c: Dictionary = countries[owner]
        var state_culture: String = String(c["culture"])
        var pops: Array = p["pops"]

        for pop_index in range(pops.size()):
            var pop: Dictionary = pops[pop_index]
            var pop_class: String = String(pop["class"])
            var needs: float = float(pop["needs"])
            var militancy: float = float(pop["militancy"])
            var literacy: float = float(pop["literacy"])

            var growth_rate: float = 0.004 + needs * 0.010
            if _at_war(owner):
                growth_rate -= 0.004
            if militancy > 60.0:
                growth_rate -= 0.003
            if pop_class == "Aristócratas" or pop_class == "Magos":
                growth_rate *= 0.70

            pop["size"] = maxi(1, int(round(float(pop["size"]) * (1.0 + growth_rate))))

            var militancy_delta: float = (0.67 - needs) * 7.5

            if String(pop["culture"]) != state_culture:
                militancy_delta += 0.65

            if float(c["stability"]) < 45.0:
                militancy_delta += (45.0 - float(c["stability"])) / 30.0

            if _at_war(owner):
                militancy_delta += 0.45

            if needs > 0.83:
                militancy_delta -= 0.75

            pop["militancy"] = clampf(militancy + militancy_delta, 0.0, 100.0)

            var education_rate: float = 0.0015
            if pop_class == "Clérigos" or pop_class == "Burócratas" or pop_class == "Magos":
                education_rate += 0.0020
            if needs > 0.75:
                education_rate += 0.0010

            pop["literacy"] = clampf(literacy + education_rate, 0.0, 1.0)

            if float(pop["militancy"]) > 48.0 and literacy > 0.28:
                if pop_class == "Obreros" or pop_class == "Mineros":
                    pop["ideology"] = "Popular"
                elif rng.randf() < 0.15:
                    pop["ideology"] = "Reformista"

            pops[pop_index] = pop

        p["pops"] = pops
        p["population"] = _sum_pop_sizes(pops)
        p["culture"] = _dominant_culture(pops)
        p["unrest"] = _weighted_pop_value(pops, "militancy")

        if float(p["unrest"]) > 58.0 and rng.randf() < 0.11:
            stats["revolts"] = int(stats["revolts"]) + 1
            c["stability"] = float(c["stability"]) - 5.0
            _log("Estallan disturbios en %s. Las clases populares exigen cambios al gobierno de %s." % [String(p["name"]), owner])
            _calm_after_revolt(pops)

        countries[owner] = c
        provinces[province_index] = p


func _calm_after_revolt(pops: Array) -> void:
    for pop_index in range(pops.size()):
        var pop: Dictionary = pops[pop_index]
        pop["militancy"] = maxf(0.0, float(pop["militancy"]) - rng.randf_range(6.0, 14.0))
        pops[pop_index] = pop


func _diplomacy() -> void:
    var names: Array = countries.keys()

    for a in names:
        if not bool(countries[a]["alive"]):
            continue

        for b in names:
            if a == b or not bool(countries[b]["alive"]):
                continue

            var drift: int = rng.randi_range(-3, 3)

            if countries[a]["rivals"].has(b):
                drift -= 2

            relations[a][b] = clampi(int(relations[a][b]) + drift, -100, 100)


func _historical_events() -> void:
    if year >= 184 and not fired_events.has("arcane_engine"):
        fired_events["arcane_engine"] = true
        countries["Lunaris"]["prestige"] = float(countries["Lunaris"]["prestige"]) + 14.0
        countries["Lunaris"]["treasury"] = float(countries["Lunaris"]["treasury"]) + 20.0
        _major_event("Lunaris demuestra el primer motor de cristal arcano. Comerciantes y monarcas hablan de una nueva era industrial.")

    if (
        year >= 187
        and not fired_events.has("ardel_reform")
        and _country_avg_pop_value("Ardel", "militancy") > 18.0
        and _country_avg_pop_value("Ardel", "literacy") > 0.20
    ):
        fired_events["ardel_reform"] = true
        countries["Ardel"]["government"] = "Monarquía parlamentaria"
        countries["Ardel"]["stability"] = minf(100.0, float(countries["Ardel"]["stability"]) + 13.0)
        stats["reforms"] = int(stats["reforms"]) + 1
        _major_event("La Crisis de Valem obliga a la corona de Ardel a aceptar un parlamento con poderes reales.")

    if (
        year >= 190
        and not fired_events.has("orc_reform")
        and _country_avg_pop_value("Orkhan", "militancy") > 16.0
    ):
        fired_events["orc_reform"] = true
        countries["Orkhan"]["government"] = "Kanato reformista"
        countries["Orkhan"]["military"] = float(countries["Orkhan"]["military"]) + 8.0
        countries["Orkhan"]["stability"] = minf(100.0, float(countries["Orkhan"]["stability"]) + 10.0)
        stats["reforms"] = int(stats["reforms"]) + 1
        _major_event("Los clanes de Orkhan pactan la Reforma de las Nueve Banderas y profesionalizan el ejército.")

    if year >= 194 and not fired_events.has("arcane_accident"):
        fired_events["arcane_accident"] = true
        countries["Lunaris"]["stability"] = float(countries["Lunaris"]["stability"]) - 10.0

        for province_index in range(provinces.size()):
            var p: Dictionary = provinces[province_index]

            if String(p["owner"]) == "Lunaris" and String(p["resource"]) == "cristal arcano":
                var pops: Array = p["pops"]
                for pop_index in range(pops.size()):
                    var pop: Dictionary = pops[pop_index]
                    pop["militancy"] = clampf(float(pop["militancy"]) + 8.0, 0.0, 100.0)
                    pops[pop_index] = pop
                p["pops"] = pops
                p["unrest"] = _weighted_pop_value(pops, "militancy")
                provinces[province_index] = p

        _major_event("Una explosión en una refinería arcana de Lunaris inicia el primer debate sobre regulación mágica industrial.")

    if year >= 198 and not fired_events.has("miners_movement"):
        var miner_population: int = _world_class_population("Mineros")
        var miner_militancy: float = _world_class_average("Mineros", "militancy")

        if miner_population > 180000 and miner_militancy > 26.0:
            fired_events["miners_movement"] = true
            stats["reforms"] = int(stats["reforms"]) + 1
            _major_event("La Liga de Mineros atraviesa fronteras y exige límites de jornada y mayor seguridad en minas y refinerías.")


func _war_logic() -> void:
    if wars.size() >= 2:
        return

    for attacker in countries:
        if not bool(countries[attacker]["alive"]) or _at_war(String(attacker)):
            continue

        for defender in countries:
            if attacker == defender or not bool(countries[defender]["alive"]) or _at_war(String(defender)):
                continue

            var hostility: float = -float(relations[attacker][defender])
            var attacker_power: float = float(countries[attacker]["military"])
            var defender_power: float = float(countries[defender]["military"])
            var power_ratio: float = attacker_power / maxf(1.0, defender_power)
            var claim_bonus: float = 0.0

            for p in provinces:
                if String(p["owner"]) == String(defender) and countries[attacker]["claims"].has(p["name"]):
                    claim_bonus = 35.0

            var desire: float = hostility + claim_bonus + maxf(0.0, (power_ratio - 1.0) * 35.0)

            if desire > 86.0 and rng.randf() < 0.11:
                wars.append({
                    "attacker": String(attacker),
                    "defender": String(defender),
                    "years": 0,
                    "score": 0.0
                })
                stats["wars"] = int(stats["wars"]) + 1
                _log("%s declara la guerra a %s." % [String(attacker), String(defender)])
                return


func _resolve_wars() -> void:
    for idx in range(wars.size() - 1, -1, -1):
        var w: Dictionary = wars[idx]
        var attacker_name: String = String(w["attacker"])
        var defender_name: String = String(w["defender"])
        var a: Dictionary = countries[attacker_name]
        var d: Dictionary = countries[defender_name]

        w["years"] = int(w["years"]) + 1

        var a_roll: float = float(a["military"]) * rng.randf_range(0.70, 1.30) + float(a["stability"]) * 0.25
        var d_roll: float = float(d["military"]) * rng.randf_range(0.70, 1.30) + float(d["stability"]) * 0.25

        w["score"] = float(w["score"]) + (a_roll - d_roll) / 18.0

        a["treasury"] = float(a["treasury"]) - 9.0
        d["treasury"] = float(d["treasury"]) - 9.0
        a["stability"] = float(a["stability"]) - rng.randf_range(0.4, 1.4)
        d["stability"] = float(d["stability"]) - rng.randf_range(0.4, 1.4)
        a["military"] = maxf(8.0, float(a["military"]) - rng.randf_range(0.5, 2.0))
        d["military"] = maxf(8.0, float(d["military"]) - rng.randf_range(0.5, 2.0))

        countries[attacker_name] = a
        countries[defender_name] = d

        _apply_war_casualties(attacker_name, rng.randf_range(0.0015, 0.0045))
        _apply_war_casualties(defender_name, rng.randf_range(0.0015, 0.0045))

        wars[idx] = w

        if absf(float(w["score"])) > 8.0 or int(w["years"]) >= 5:
            var winner: String = attacker_name if float(w["score"]) >= 0.0 else defender_name
            var loser: String = defender_name if winner == attacker_name else attacker_name
            _peace(winner, loser, w)
            wars.remove_at(idx)


func _apply_war_casualties(country_name: String, rate: float) -> void:
    for province_index in range(provinces.size()):
        var p: Dictionary = provinces[province_index]

        if String(p["owner"]) != country_name:
            continue

        var pops: Array = p["pops"]

        for pop_index in range(pops.size()):
            var pop: Dictionary = pops[pop_index]
            var casualty_rate: float = rate

            if String(pop["class"]) == "Soldados":
                casualty_rate *= 4.0

            pop["size"] = maxi(1, int(round(float(pop["size"]) * (1.0 - casualty_rate))))
            pops[pop_index] = pop

        p["pops"] = pops
        p["population"] = _sum_pop_sizes(pops)
        provinces[province_index] = p


func _peace(winner: String, loser: String, _w: Dictionary) -> void:
    var candidates: Array[int] = []

    for i in range(provinces.size()):
        if String(provinces[i]["owner"]) == loser:
            candidates.append(i)

    var taken := ""

    if candidates.size() > 1:
        var preferred: int = -1

        for i in candidates:
            if countries[winner]["claims"].has(provinces[i]["name"]):
                preferred = i
                break

        var target: int = preferred if preferred >= 0 else candidates[rng.randi_range(0, candidates.size() - 1)]
        taken = String(provinces[target]["name"])
        provinces[target]["owner"] = winner

        var conquered_pops: Array = provinces[target]["pops"]
        for pop_index in range(conquered_pops.size()):
            var pop: Dictionary = conquered_pops[pop_index]
            pop["militancy"] = clampf(float(pop["militancy"]) + 12.0, 0.0, 100.0)
            conquered_pops[pop_index] = pop

        provinces[target]["pops"] = conquered_pops
        provinces[target]["unrest"] = _weighted_pop_value(conquered_pops, "militancy")
        stats["territorial_changes"] = int(stats["territorial_changes"]) + 1

    countries[winner]["prestige"] = float(countries[winner]["prestige"]) + 8.0
    countries[loser]["prestige"] = float(countries[loser]["prestige"]) - 6.0
    countries[loser]["stability"] = float(countries[loser]["stability"]) - 7.0
    relations[winner][loser] = -85
    relations[loser][winner] = -85

    if taken != "":
        _log("La guerra termina con victoria de %s. %s cede %s." % [winner, loser, taken])
    else:
        _log("La guerra termina con victoria de %s, pero sin cambios territoriales." % winner)


func _at_war(country_name: String) -> bool:
    for w in wars:
        if String(w["attacker"]) == country_name or String(w["defender"]) == country_name:
            return true
    return false


func _major_event(text: String) -> void:
    stats["major_events"] = int(stats["major_events"]) + 1
    _log(text)


func _log(text: String) -> void:
    history.append("%d — %s" % [year, text])


func _reset_world() -> void:
    _create_world()
    _refresh_all()


func _use_seed() -> void:
    var candidate: String = seed_input.text.strip_edges()

    if not candidate.is_valid_int():
        status_label.text = "Seed inválida: usa un número entero."
        return

    current_seed = int(candidate)
    _create_world()
    _refresh_all()


func _random_world() -> void:
    current_seed = int(Time.get_unix_time_from_system()) + int(Time.get_ticks_msec())
    seed_input.text = str(current_seed)
    _create_world()
    _refresh_all()


func _refresh_all() -> void:
    seed_input.text = str(current_seed)
    year_label.text = "Año %d" % year
    status_label.text = "Seed %d  |  %d guerras activas  |  %s" % [
        current_seed,
        wars.size(),
        "mundo estable" if wars.is_empty() else "conflicto en curso"
    ]

    _rebuild_map()
    _refresh_history()
    _refresh_summary()

    if not provinces.is_empty():
        selected_province_index = clampi(selected_province_index, 0, provinces.size() - 1)
        _show_province(selected_province_index)


func _rebuild_map() -> void:
    for child in map_grid.get_children():
        child.queue_free()

    for i in range(provinces.size()):
        var p: Dictionary = provinces[i]
        var b := Button.new()
        b.custom_minimum_size = Vector2(125, 105)
        b.text = "%s\n%s\n%s\n%.0fK hab." % [
            String(p["name"]),
            String(p["owner"]),
            String(p["resource"]),
            float(p["population"]) / 1000.0
        ]

        var style := StyleBoxFlat.new()
        style.bg_color = COUNTRY_COLORS.get(String(p["owner"]), Color.GRAY)
        style.corner_radius_top_left = 5
        style.corner_radius_top_right = 5
        style.corner_radius_bottom_left = 5
        style.corner_radius_bottom_right = 5
        b.add_theme_stylebox_override("normal", style)

        var province_index: int = i
        b.pressed.connect(func(): _show_province(province_index))
        map_grid.add_child(b)


func _show_province(index: int) -> void:
    selected_province_index = index
    var p: Dictionary = provinces[index]
    var owner: String = String(p["owner"])
    var c: Dictionary = countries[owner]
    var avg_needs: float = _weighted_pop_value(p["pops"], "needs")
    var avg_literacy: float = _weighted_pop_value(p["pops"], "literacy")

    detail_text.text = "[font_size=24][b]%s[/b][/font_size]\n[color=#aaaaaa]%s[/color]\n\n[b]Provincia[/b]\nCultura dominante: %s\nRecurso: %s\nPoblación: %s\nRiqueza local: %.2f\nNecesidades satisfechas: %.1f%%\nAlfabetización: %.1f%%\nMilitancia: %.1f / 100\n\n[b]%s[/b]\nGobierno: %s\nCultura estatal: %s\nTesoro: %.1f\nProducción anual: %.1f\nEstabilidad: %.1f\nPoder militar: %.1f\nPrestigio: %.1f\n\n[b]Situación[/b]\n%s" % [
        String(p["name"]),
        owner,
        String(p["culture"]),
        String(p["resource"]),
        _fmt_pop(int(p["population"])),
        float(p["wealth"]),
        avg_needs * 100.0,
        avg_literacy * 100.0,
        float(p["unrest"]),
        owner,
        String(c["government"]),
        String(c["culture"]),
        float(c["treasury"]),
        float(c["last_output"]),
        float(c["stability"]),
        float(c["military"]),
        float(c["prestige"]),
        "EN GUERRA" if _at_war(owner) else "En paz"
    ]

    _refresh_pops(p)


func _refresh_pops(p: Dictionary) -> void:
    var lines: Array[String] = []
    lines.append("[font_size=22][b]POPs de %s[/b][/font_size]" % String(p["name"]))
    lines.append("[color=#aaaaaa]La población provincial es la suma de estos grupos.[/color]\n")

    var pops: Array = p["pops"]

    for pop in pops:
        var pop_data: Dictionary = pop
        lines.append(
            "[b]%s[/b] — %s\nCultura: %s | Religión: %s\nNecesidades: %.0f%% | Alfabetización: %.0f%%\nRiqueza: %.1f | Militancia: %.1f | Ideología: %s\n" % [
                String(pop_data["class"]),
                _fmt_pop(int(pop_data["size"])),
                String(pop_data["culture"]),
                String(pop_data["religion"]),
                float(pop_data["needs"]) * 100.0,
                float(pop_data["literacy"]) * 100.0,
                float(pop_data["wealth"]),
                float(pop_data["militancy"]),
                String(pop_data["ideology"])
            ]
        )

    pops_text.text = "\n".join(lines)


func _refresh_history() -> void:
    var lines: Array[String] = ["[font_size=22][b]Crónica del mundo[/b][/font_size]\n"]
    var start: int = maxi(0, history.size() - 45)

    for i in range(start, history.size()):
        lines.append(history[i])

    history_text.text = "\n".join(lines)
    history_text.scroll_to_line(history.size())


func _refresh_summary() -> void:
    var world_population: int = _world_population()
    var growth_percent: float = 0.0

    if initial_population > 0:
        growth_percent = (float(world_population - initial_population) / float(initial_population)) * 100.0

    var biggest_country: String = _country_with_max("population")
    var richest_country: String = _country_with_max("treasury")
    var productive_country: String = _country_with_max("output")
    var strongest_country: String = _country_with_max("military")
    var stable_country: String = _country_with_max("stability")

    var global_needs: float = _world_pop_average("needs")
    var global_literacy: float = _world_pop_average("literacy")
    var global_militancy: float = _world_pop_average("militancy")

    var lines: Array[String] = []
    lines.append("[font_size=24][b]Resumen de la simulación[/b][/font_size]")
    lines.append("[color=#aaaaaa]Seed %d — %d años simulados[/color]\n" % [current_seed, year - START_YEAR])
    lines.append("[b]Demografía[/b]")
    lines.append("Población inicial: %s" % _fmt_pop(initial_population))
    lines.append("Población actual: %s (%+.1f%%)" % [_fmt_pop(world_population), growth_percent])
    lines.append("Necesidades medias satisfechas: %.1f%%" % (global_needs * 100.0))
    lines.append("Alfabetización media: %.1f%%" % (global_literacy * 100.0))
    lines.append("Militancia media: %.1f / 100\n" % global_militancy)
    lines.append("[b]Historia generada[/b]")
    lines.append("Guerras iniciadas: %d" % int(stats["wars"]))
    lines.append("Cambios territoriales: %d" % int(stats["territorial_changes"]))
    lines.append("Disturbios/revueltas: %d" % int(stats["revolts"]))
    lines.append("Reformas: %d" % int(stats["reforms"]))
    lines.append("Grandes eventos: %d\n" % int(stats["major_events"]))
    lines.append("[b]Estados destacados por dato actual[/b]")
    lines.append("Mayor población: %s (%s)" % [biggest_country, _fmt_pop(_country_population(biggest_country))])
    lines.append("Mayor tesoro: %s (%.1f)" % [richest_country, float(countries[richest_country]["treasury"])])
    lines.append("Mayor producción: %s (%.1f)" % [productive_country, float(countries[productive_country]["last_output"])])
    lines.append("Mayor poder militar: %s (%.1f)" % [strongest_country, float(countries[strongest_country]["military"])])
    lines.append("Mayor estabilidad: %s (%.1f)" % [stable_country, float(countries[stable_country]["stability"])])

    summary_text.text = "\n".join(lines)


func _country_with_max(metric: String) -> String:
    var best_name := ""
    var best_value: float = -INF

    for country_name in countries:
        var value: float = 0.0

        match metric:
            "population":
                value = float(_country_population(String(country_name)))
            "treasury":
                value = float(countries[country_name]["treasury"])
            "output":
                value = float(countries[country_name]["last_output"])
            "military":
                value = float(countries[country_name]["military"])
            "stability":
                value = float(countries[country_name]["stability"])
            _:
                value = 0.0

        if value > best_value:
            best_value = value
            best_name = String(country_name)

    return best_name


func _world_population() -> int:
    var total: int = 0
    for p in provinces:
        total += int(p["population"])
    return total


func _country_population(country_name: String) -> int:
    var total: int = 0

    for p in provinces:
        if String(p["owner"]) == country_name:
            total += int(p["population"])

    return total


func _world_pop_average(field: String) -> float:
    var weighted_sum: float = 0.0
    var population_sum: int = 0

    for p in provinces:
        var pops: Array = p["pops"]
        for pop in pops:
            var pop_data: Dictionary = pop
            var size: int = int(pop_data["size"])
            weighted_sum += float(pop_data[field]) * float(size)
            population_sum += size

    if population_sum <= 0:
        return 0.0

    return weighted_sum / float(population_sum)


func _country_avg_pop_value(country_name: String, field: String) -> float:
    var weighted_sum: float = 0.0
    var population_sum: int = 0

    for p in provinces:
        if String(p["owner"]) != country_name:
            continue

        var pops: Array = p["pops"]
        for pop in pops:
            var pop_data: Dictionary = pop
            var size: int = int(pop_data["size"])
            weighted_sum += float(pop_data[field]) * float(size)
            population_sum += size

    if population_sum <= 0:
        return 0.0

    return weighted_sum / float(population_sum)


func _world_class_population(pop_class: String) -> int:
    var total: int = 0

    for p in provinces:
        var pops: Array = p["pops"]
        for pop in pops:
            var pop_data: Dictionary = pop
            if String(pop_data["class"]) == pop_class:
                total += int(pop_data["size"])

    return total


func _world_class_average(pop_class: String, field: String) -> float:
    var weighted_sum: float = 0.0
    var population_sum: int = 0

    for p in provinces:
        var pops: Array = p["pops"]
        for pop in pops:
            var pop_data: Dictionary = pop

            if String(pop_data["class"]) != pop_class:
                continue

            var size: int = int(pop_data["size"])
            weighted_sum += float(pop_data[field]) * float(size)
            population_sum += size

    if population_sum <= 0:
        return 0.0

    return weighted_sum / float(population_sum)


func _sum_pop_sizes(pops: Array) -> int:
    var total: int = 0

    for pop in pops:
        total += int(pop["size"])

    return total


func _weighted_pop_value(pops: Array, field: String) -> float:
    var weighted_sum: float = 0.0
    var population_sum: int = 0

    for pop in pops:
        var size: int = int(pop["size"])
        weighted_sum += float(pop[field]) * float(size)
        population_sum += size

    if population_sum <= 0:
        return 0.0

    return weighted_sum / float(population_sum)


func _dominant_culture(pops: Array) -> String:
    var totals := {}

    for pop in pops:
        var culture: String = String(pop["culture"])
        totals[culture] = int(totals.get(culture, 0)) + int(pop["size"])

    var best_culture := ""
    var best_population: int = -1

    for culture in totals:
        var culture_population: int = int(totals[culture])

        if culture_population > best_population:
            best_population = culture_population
            best_culture = String(culture)

    return best_culture


func _shift_pop_culture(province: Dictionary, target_culture: String, share: float) -> void:
    var pops: Array = province["pops"]

    for pop_index in range(pops.size()):
        var pop: Dictionary = pops[pop_index]

        if rng.randf() < share:
            pop["culture"] = target_culture
            pop["religion"] = _religion_for_culture(target_culture)

        pops[pop_index] = pop

    province["pops"] = pops


func _fmt_pop(n: int) -> String:
    if n >= 1000000:
        return "%.2f M" % (float(n) / 1000000.0)

    return "%.1f mil" % (float(n) / 1000.0)
