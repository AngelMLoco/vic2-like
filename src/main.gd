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

const GOODS := {
    "grano": {"base_price": 1.00},
    "madera": {"base_price": 0.90},
    "hierro": {"base_price": 1.35},
    "carbón": {"base_price": 1.15},
    "ropa": {"base_price": 1.60},
    "herramientas": {"base_price": 2.20},
    "cristal arcano": {"base_price": 3.20}
}

const CLASS_INCOME := {
    "Campesinos": 0.78,
    "Mineros": 0.92,
    "Obreros": 0.88,
    "Artesanos": 1.05,
    "Comerciantes": 1.40,
    "Soldados": 0.92,
    "Burócratas": 1.15,
    "Clérigos": 1.05,
    "Aristócratas": 2.10,
    "Magos": 1.75
}

# Cantidades deseadas por cada 1,000 personas al año.
# En esta fase son unidades abstractas; lo importante es la relación oferta/demanda.
const CLASS_NEEDS := {
    "Campesinos": {
        "grano": 1.00, "madera": 0.22, "ropa": 0.14, "herramientas": 0.035
    },
    "Mineros": {
        "grano": 0.96, "madera": 0.18, "ropa": 0.18, "herramientas": 0.11, "carbón": 0.025
    },
    "Obreros": {
        "grano": 0.94, "madera": 0.16, "ropa": 0.20, "herramientas": 0.085, "carbón": 0.03
    },
    "Artesanos": {
        "grano": 0.90, "madera": 0.17, "ropa": 0.22, "herramientas": 0.12, "hierro": 0.025
    },
    "Comerciantes": {
        "grano": 0.86, "madera": 0.16, "ropa": 0.32, "herramientas": 0.10, "cristal arcano": 0.018
    },
    "Soldados": {
        "grano": 1.08, "madera": 0.20, "ropa": 0.19, "herramientas": 0.12
    },
    "Burócratas": {
        "grano": 0.88, "madera": 0.17, "ropa": 0.30, "herramientas": 0.09
    },
    "Clérigos": {
        "grano": 0.88, "madera": 0.18, "ropa": 0.25, "herramientas": 0.07
    },
    "Aristócratas": {
        "grano": 0.82, "madera": 0.25, "ropa": 0.55, "herramientas": 0.14, "cristal arcano": 0.06
    },
    "Magos": {
        "grano": 0.88, "madera": 0.17, "ropa": 0.30, "herramientas": 0.16, "cristal arcano": 0.22
    }
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
var market := {}
var market_event_cooldowns := {}

var stats := {}
var initial_population: int = 0
var selected_province_index: int = 0

var year_label: Label
var status_label: Label
var seed_input: LineEdit
var map_grid: GridContainer
var detail_text: RichTextLabel
var pops_text: RichTextLabel
var market_text: RichTextLabel
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
    title.text = "CHRONICLES OF AETHER  —  v0.3.2 SOCIAL ECON LAB"
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
    right.custom_minimum_size.x = 530
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

    market_text = RichTextLabel.new()
    market_text.name = "Mercado"
    market_text.bbcode_enabled = true
    tabs.add_child(market_text)

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
    market_event_cooldowns.clear()

    stats = {
        "wars": 0,
        "territorial_changes": 0,
        "protests": 0,
        "strikes": 0,
        "revolts": 0,
        "reforms": 0,
        "major_events": 0,
        "shortage_crises": 0
    }

    _init_market()

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
        "grano", "madera", "hierro", "carbón", "cristal arcano"
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

            if rng.randf() < 0.24:
                local_culture = cultures[rng.randi_range(0, cultures.size() - 1)]

            var resource: String = resources[rng.randi_range(0, resources.size() - 1)]
            var total_population: int = rng.randi_range(30000, 95000)
            var local_wealth: float = rng.randf_range(0.78, 1.22)

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
                "social_cooldown": 0,
                "last_social_event": "",
                "pops": pops
            })

            idx += 1

    for i in range(provinces.size()):
        var province: Dictionary = provinces[i]

        if String(province["name"]) == "Erdan":
            province["owner"] = "Erdan"
            _shift_pop_culture(province, "Enana", 0.84)

        if String(province["name"]) == "Leth":
            province["owner"] = "Sylvar"
            _shift_pop_culture(province, "Silvana", 0.84)

        if String(province["name"]) == "Mord":
            province["owner"] = "Orkhan"
            _shift_pop_culture(province, "Orca", 0.84)

        province["culture"] = _dominant_culture(province["pops"])
        province["population"] = _sum_pop_sizes(province["pops"])
        provinces[i] = province

    for a in countries:
        relations[a] = {}

        for b in countries:
            if a != b:
                relations[a] = rng.randi_range(-10, 25)

    relations["Ardel"]["Varka"] = -58
    relations["Varka"]["Ardel"] = -58
    relations["Varka"]["Selia"] = -48
    relations["Selia"]["Varka"] = -48
    relations["Khaz-Dur"]["Erdan"] = 55
    relations["Erdan"]["Khaz-Dur"] = 55

    initial_population = _world_population()

    # Calcula un mercado inicial para que la UI no empiece vacía.
    _simulate_market_and_economy(false)
    _refresh_province_aggregates()

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
        "last_output": 0.0,
        "war_exhaustion": 0.0,
        "peace_until": START_YEAR,
        "industrial_bonus": 1.0,
        "reforms": [],
        "last_reform_year": START_YEAR - 25
    }


func _init_market() -> void:
    market.clear()

    for good_name in GOODS:
        var base_price: float = float(GOODS[good_name]["base_price"])
        market[good_name] = {
            "base_price": base_price,
            "price": base_price,
            "supply": 0.0,
            "demand": 0.0,
            "availability": 1.0
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

    if resource == "grano" or resource == "madera":
        shares["Campesinos"] = 0.49
        shares["Mineros"] = 0.025
        shares["Obreros"] = 0.105

    if resource == "hierro" or resource == "carbón":
        shares["Campesinos"] = 0.18
        shares["Mineros"] = 0.37
        shares["Obreros"] = 0.16

    if resource == "cristal arcano":
        shares["Campesinos"] = 0.15
        shares["Mineros"] = 0.25
        shares["Obreros"] = 0.15
        shares["Magos"] = 0.085

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

        if local_culture != state_culture and rng.randf() < 0.56:
            culture = local_culture
        elif rng.randf() < 0.06:
            culture = local_culture

        var literacy: float = _base_literacy(pop_class) + rng.randf_range(-0.07, 0.07)
        var wealth: float = _base_wealth(pop_class) + rng.randf_range(-7.0, 7.0)
        var initial_needs: float = rng.randf_range(0.58, 0.82)
        var militancy: float = clampf((0.78 - initial_needs) * 28.0 + rng.randf_range(0.0, 5.0), 0.0, 100.0)

        if culture != state_culture:
            militancy += rng.randf_range(2.0, 6.0)

        result.append({
            "class": pop_class,
            "size": size,
            "culture": culture,
            "religion": _religion_for_culture(culture),
            "literacy": clampf(literacy, 0.02, 0.95),
            "wealth": clampf(wealth, 2.0, 100.0),
            "militancy": clampf(militancy, 0.0, 100.0),
            "needs": initial_needs,
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
        _simulate_market_and_economy(true)
        _population_and_unrest()
        _generic_reforms()
        _diplomacy()
        _historical_events()
        _war_logic()
        _resolve_wars()
        _decay_war_exhaustion()
        _market_crisis_events()
        _refresh_province_aggregates()

    _refresh_all()


# -------------------------------------------------------------------
# ECONOMÍA Y MERCADO
# -------------------------------------------------------------------

func _simulate_market_and_economy(apply_state_finances: bool) -> void:
    var supply := {}
    var demand := {}
    var output_value_by_country := {}

    for good_name in GOODS:
        supply[good_name] = 0.0
        demand[good_name] = 0.0

    for country_name in countries:
        output_value_by_country[country_name] = 0.0

    # 1) Producción primaria y manufacturas.
    for p in provinces:
        var owner: String = String(p["owner"])
        var c: Dictionary = countries[owner]
        var war_factor: float = 0.72 if _at_war(owner) else 1.0
        var exhaustion_factor: float = clampf(1.0 - float(c["war_exhaustion"]) * 0.004, 0.62, 1.0)
        var industry_bonus: float = float(c["industrial_bonus"])
        var local_factor: float = float(p["wealth"]) * war_factor * exhaustion_factor * industry_bonus

        var resource: String = String(p["resource"])
        var resource_workers: int = _resource_worker_population(p["pops"], resource)
        var primary_output: float = (float(resource_workers) / 1000.0) * 3.20 * local_factor

        supply[resource] = float(supply[resource]) + primary_output
        output_value_by_country[owner] = float(output_value_by_country[owner]) + primary_output * float(GOODS[resource]["base_price"])

        var artisans: int = _pop_class_size(p["pops"], "Artesanos")
        var workers: int = _pop_class_size(p["pops"], "Obreros")

        var clothing_output: float = (
            float(artisans) * 0.00124
            + float(workers) * 0.00036
        ) * local_factor

        var tools_output: float = (
            float(artisans) * 0.00058
            + float(workers) * 0.00047
        ) * local_factor

        supply["ropa"] = float(supply["ropa"]) + clothing_output
        supply["herramientas"] = float(supply["herramientas"]) + tools_output

        output_value_by_country[owner] = (
            float(output_value_by_country[owner])
            + clothing_output * float(GOODS["ropa"]["base_price"])
            + tools_output * float(GOODS["herramientas"]["base_price"])
        )

    # 2) Demanda agregada de los POPs.
    for p in provinces:
        var pops: Array = p["pops"]

        for pop_data in pops:
            var pop: Dictionary = pop_data
            var pop_class: String = String(pop["class"])
            var basket: Dictionary = CLASS_NEEDS.get(pop_class, {})
            var scale: float = float(pop["size"]) / 1000.0

            for good_name in basket:
                demand[good_name] = float(demand[good_name]) + float(basket[good_name]) * scale

    # 3) Precios: escasez sube el precio, exceso de oferta lo baja.
    for good_name in GOODS:
        var good_market: Dictionary = market[good_name]
        var good_supply: float = float(supply[good_name])
        var good_demand: float = maxf(0.01, float(demand[good_name]))
        var scarcity_ratio: float = good_demand / maxf(0.01, good_supply)
        var target_multiplier: float = clampf(float(pow(scarcity_ratio, 0.62)), 0.55, 3.60)
        var target_price: float = float(good_market["base_price"]) * target_multiplier

        good_market["supply"] = good_supply
        good_market["demand"] = good_demand
        good_market["availability"] = clampf(good_supply / good_demand, 0.0, 1.0)
        good_market["price"] = lerpf(float(good_market["price"]), target_price, 0.42)

        market[good_name] = good_market

    # 4) Cada POP intenta pagar su cesta. Oferta y dinero importan por separado.
    for province_index in range(provinces.size()):
        var p: Dictionary = provinces[province_index]
        var owner: String = String(p["owner"])
        var c: Dictionary = countries[owner]
        var pops: Array = p["pops"]

        for pop_index in range(pops.size()):
            var pop: Dictionary = pops[pop_index]
            var pop_class: String = String(pop["class"])
            var basket: Dictionary = CLASS_NEEDS.get(pop_class, {})
            var scale: float = float(pop["size"]) / 1000.0
            var basket_cost: float = 0.0
            var weighted_availability: float = 0.0
            var weight_sum: float = 0.0

            for good_name in basket:
                var quantity: float = float(basket[good_name]) * scale
                var price: float = float(market[good_name]["price"])
                var weight: float = float(basket[good_name])

                basket_cost += quantity * price
                weighted_availability += float(market[good_name]["availability"]) * weight
                weight_sum += weight

            var availability_score: float = 1.0

            if weight_sum > 0.0:
                availability_score = weighted_availability / weight_sum

            var income_factor: float = float(CLASS_INCOME.get(pop_class, 1.0))
            var wage_income: float = scale * income_factor * (1.05 + float(p["wealth"]) * 0.55)
            var reserve_income: float = scale * float(pop["wealth"]) * 0.022
            var war_income_penalty: float = 0.82 if _at_war(owner) else 1.0
            var income: float = (wage_income + reserve_income) * war_income_penalty
            var affordability: float = clampf(income / maxf(0.01, basket_cost), 0.0, 1.0)
            var satisfaction: float = sqrt(maxf(0.0, availability_score * affordability))

            pop["needs"] = lerpf(float(pop["needs"]), satisfaction, 0.48)

            var budget_balance: float = income - basket_cost * availability_score
            var wealth_delta: float = clampf(budget_balance / maxf(1.0, scale) * 0.20, -2.4, 1.7)

            if float(pop["needs"]) < 0.50:
                wealth_delta -= 0.7

            pop["wealth"] = clampf(float(pop["wealth"]) + wealth_delta, 1.0, 100.0)
            pops[pop_index] = pop

        p["pops"] = pops
        provinces[province_index] = p

    # 5) Estado: impuestos sobre la producción, administración y guerra.
    if apply_state_finances:
        for country_name in countries:
            var c: Dictionary = countries[country_name]

            if not bool(c["alive"]):
                continue

            var output_value: float = float(output_value_by_country[country_name])
            var tax_income: float = output_value * 0.075
            var population_cost: float = float(_country_population(String(country_name))) / 1000.0 * 0.010
            var military_upkeep: float = float(c["military"]) * 0.085
            var war_cost: float = 7.0 if _at_war(String(country_name)) else 0.0

            c["last_output"] = output_value
            c["treasury"] = (
                float(c["treasury"])
                + tax_income
                - population_cost
                - military_upkeep
                - war_cost
            )

            if float(c["treasury"]) < 0.0:
                c["stability"] = float(c["stability"]) - 1.6
                c["military"] = maxf(10.0, float(c["military"]) * 0.992)
            else:
                c["stability"] = minf(100.0, float(c["stability"]) + 0.12)

            countries[country_name] = c


func _resource_worker_population(pops: Array, resource: String) -> int:
    if resource == "grano" or resource == "madera":
        return _pop_class_size(pops, "Campesinos")

    if resource == "hierro" or resource == "carbón" or resource == "cristal arcano":
        return _pop_class_size(pops, "Mineros")

    return 0


func _pop_class_size(pops: Array, pop_class: String) -> int:
    var total: int = 0

    for pop_data in pops:
        var pop: Dictionary = pop_data

        if String(pop["class"]) == pop_class:
            total += int(pop["size"])

    return total


func _market_crisis_events() -> void:
    for good_name in GOODS:
        var availability: float = float(market[good_name]["availability"])
        var price: float = float(market[good_name]["price"])
        var base_price: float = float(market[good_name]["base_price"])
        var next_allowed: int = int(market_event_cooldowns.get(good_name, START_YEAR))

        if (
            year >= next_allowed
            and availability < 0.72
            and price > base_price * 1.55
        ):
            market_event_cooldowns[good_name] = year + 10
            stats["shortage_crises"] = int(stats["shortage_crises"]) + 1
            _apply_shortage_pressure(String(good_name), availability, price / base_price)

            if good_name == "grano":
                _major_event("La escasez de grano dispara el precio de los alimentos. Campesinos, obreros y soldados sienten primero la crisis.")
            elif good_name == "cristal arcano":
                _major_event("El precio del cristal arcano se dispara. Magos, aristócratas y talleres arcanos compiten por reservas cada vez más escasas.")
            elif good_name == "herramientas":
                _log("La escasez de herramientas golpea especialmente a mineros, obreros y artesanos.")
            else:
                _log("Una escasez de %s eleva los precios y presiona a los grupos que más dependen de ese bien." % good_name)


func _apply_shortage_pressure(good_name: String, availability: float, price_ratio: float) -> void:
    var severity: float = clampf((0.72 - availability) * 5.0 + (price_ratio - 1.55) * 0.7, 0.35, 2.4)

    for province_index in range(provinces.size()):
        var p: Dictionary = provinces[province_index]
        var pops: Array = p["pops"]

        for pop_index in range(pops.size()):
            var pop: Dictionary = pops[pop_index]
            var pop_class: String = String(pop["class"])
            var basket: Dictionary = CLASS_NEEDS.get(pop_class, {})

            if not basket.has(good_name):
                continue

            var dependence: float = float(basket[good_name])
            var class_multiplier: float = 1.0

            if good_name == "grano" and (
                pop_class == "Campesinos"
                or pop_class == "Obreros"
                or pop_class == "Mineros"
                or pop_class == "Soldados"
            ):
                class_multiplier = 1.35

            if good_name == "cristal arcano" and pop_class == "Magos":
                class_multiplier = 1.80

            if good_name == "herramientas" and (
                pop_class == "Mineros"
                or pop_class == "Obreros"
                or pop_class == "Artesanos"
            ):
                class_multiplier = 1.50

            var shock: float = clampf(severity * (0.8 + dependence * 2.4) * class_multiplier, 0.25, 5.0)

            pop["militancy"] = clampf(float(pop["militancy"]) + shock, 0.0, 100.0)
            pop["wealth"] = maxf(1.0, float(pop["wealth"]) - shock * 0.35)
            pops[pop_index] = pop

        p["pops"] = pops
        p["unrest"] = _weighted_pop_value(pops, "militancy")
        provinces[province_index] = p


# -------------------------------------------------------------------
# SOCIEDAD
# -------------------------------------------------------------------

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

            # Mucho más lento que v0.2: aproximadamente 30-80% por siglo
            # en condiciones normales, en vez de triplicar la población.
            var growth_rate: float = 0.0012 + needs * 0.0037

            if _at_war(owner):
                growth_rate -= 0.0025

            if needs < 0.55:
                growth_rate -= 0.0018

            if militancy > 60.0:
                growth_rate -= 0.0012

            if pop_class == "Aristócratas" or pop_class == "Magos":
                growth_rate *= 0.72

            growth_rate = clampf(growth_rate, -0.008, 0.006)
            pop["size"] = maxi(1, int(round(float(pop["size"]) * (1.0 + growth_rate))))

            var militancy_delta: float = -0.08

            if needs < 0.64:
                militancy_delta += (0.64 - needs) * 7.2
            elif needs > 0.78:
                militancy_delta -= (needs - 0.78) * 2.4

            if needs < 0.48:
                militancy_delta += 0.58

            if String(pop["culture"]) != state_culture:
                militancy_delta += 0.12

            if float(c["stability"]) < 40.0:
                militancy_delta += (40.0 - float(c["stability"])) / 65.0

            militancy_delta += float(c["war_exhaustion"]) * 0.008

            pop["militancy"] = clampf(militancy + militancy_delta, 0.0, 100.0)

            var education_rate: float = 0.00125

            if pop_class == "Clérigos" or pop_class == "Burócratas" or pop_class == "Magos":
                education_rate += 0.0016

            if needs > 0.75:
                education_rate += 0.0007

            pop["literacy"] = clampf(literacy + education_rate, 0.0, 1.0)

            if float(pop["militancy"]) > 42.0 and float(pop["literacy"]) > 0.30:
                if pop_class == "Obreros" or pop_class == "Mineros":
                    pop["ideology"] = "Popular"
                elif rng.randf() < 0.12:
                    pop["ideology"] = "Reformista"

            pops[pop_index] = pop

        p["pops"] = pops
        p["population"] = _sum_pop_sizes(pops)
        p["culture"] = _dominant_culture(pops)
        p["unrest"] = _weighted_pop_value(pops, "militancy")

        var cooldown: int = maxi(0, int(p.get("social_cooldown", 0)) - 1)
        p["social_cooldown"] = cooldown

        if cooldown <= 0:
            var unrest: float = float(p["unrest"])

            if unrest >= 68.0 and rng.randf() < 0.035:
                stats["revolts"] = int(stats["revolts"]) + 1
                c["stability"] = float(c["stability"]) - 5.5
                p["social_cooldown"] = 10
                p["last_social_event"] = "rebelión"
                _log("Una rebelión estalla en %s contra el gobierno de %s." % [String(p["name"]), owner])
                _calm_after_social_event(pops, 10.0)

            elif unrest >= 43.0 and rng.randf() < 0.070:
                stats["strikes"] = int(stats["strikes"]) + 1
                c["stability"] = float(c["stability"]) - 1.6
                c["treasury"] = float(c["treasury"]) - 3.5
                p["social_cooldown"] = 6
                p["last_social_event"] = "huelga"
                _log("Huelgas y disturbios paralizan parte de %s." % String(p["name"]))
                _calm_after_social_event(pops, 4.5)

            elif unrest >= 25.0 and rng.randf() < 0.085:
                stats["protests"] = int(stats["protests"]) + 1
                c["stability"] = float(c["stability"]) - 0.5
                p["social_cooldown"] = 3
                p["last_social_event"] = "protesta"
                _log("Manifestaciones recorren %s; la población reclama reformas." % String(p["name"]))
                _calm_after_social_event(pops, 2.0)

        countries[owner] = c
        provinces[province_index] = p


func _generic_reforms() -> void:
    for country_name in countries:
        var c: Dictionary = countries[country_name]
        var reforms: Array = c["reforms"]

        if reforms.has("derechos_laborales"):
            continue

        var militancy: float = _country_avg_pop_value(String(country_name), "militancy")
        var literacy: float = _country_avg_pop_value(String(country_name), "literacy")
        var needs: float = _country_avg_pop_value(String(country_name), "needs")

        var reform_ready: bool = year - int(c["last_reform_year"]) >= 15

        if (
            reform_ready
            and militancy > 36.0
            and literacy > 0.33
            and needs < 0.66
            and rng.randf() < 0.085
        ):
            reforms.append("derechos_laborales")
            c["reforms"] = reforms
            c["last_reform_year"] = year
            c["stability"] = minf(100.0, float(c["stability"]) + 6.0)
            countries[country_name] = c

            _reduce_country_militancy(String(country_name), 7.0)
            stats["reforms"] = int(stats["reforms"]) + 1
            _major_event("%s aprueba sus primeras leyes laborales después de años de presión social." % String(country_name))


func _reduce_country_militancy(country_name: String, amount: float) -> void:
    for province_index in range(provinces.size()):
        var p: Dictionary = provinces[province_index]

        if String(p["owner"]) != country_name:
            continue

        var pops: Array = p["pops"]

        for pop_index in range(pops.size()):
            var pop: Dictionary = pops[pop_index]
            pop["militancy"] = maxf(0.0, float(pop["militancy"]) - amount)
            pops[pop_index] = pop

        p["pops"] = pops
        provinces[province_index] = p


func _calm_after_social_event(pops: Array, amount: float) -> void:
    for pop_index in range(pops.size()):
        var pop: Dictionary = pops[pop_index]
        pop["militancy"] = maxf(0.0, float(pop["militancy"]) - amount)
        pops[pop_index] = pop


# -------------------------------------------------------------------
# DIPLOMACIA Y GUERRA
# -------------------------------------------------------------------

func _diplomacy() -> void:
    var names: Array = countries.keys()

    for a in names:
        if not bool(countries[a]["alive"]):
            continue

        for b in names:
            if a == b or not bool(countries["alive"]):
                continue

            var drift: int = rng.randi_range(-2, 2)

            if countries[a]["rivals"].has(b):
                drift -= 1

            relations[a] = clampi(int(relations[a]) + drift, -100, 100)


func _war_logic() -> void:
    if wars.size() >= 2:
        return

    for attacker in countries:
        var attacker_name: String = String(attacker)
        var a: Dictionary = countries[attacker_name]

        if not bool(a["alive"]) or _at_war(attacker_name):
            continue

        if year < int(a["peace_until"]):
            continue

        if float(a["treasury"]) < 35.0 or float(a["stability"]) < 42.0:
            continue

        if float(a["war_exhaustion"]) > 28.0:
            continue

        for defender in countries:
            var defender_name: String = String(defender)

            if attacker_name == defender_name:
                continue

            var d: Dictionary = countries[defender_name]

            if not bool(d["alive"]) or _at_war(defender_name):
                continue

            if year < int(d["peace_until"]):
                continue

            var cause: String = _war_cause(attacker_name, defender_name)

            if cause == "":
                continue

            var hostility: float = -float(relations[attacker_name][defender_name])
            var power_ratio: float = float(a["military"]) / maxf(1.0, float(d["military"]))
            var confidence: float = maxf(0.0, (power_ratio - 1.0) * 22.0)
            var cause_strength: float = 28.0 if cause == "reclamación territorial" else 15.0
            var desire: float = hostility + confidence + cause_strength

            if desire > 74.0 and rng.randf() < 0.075:
                wars.append({
                    "attacker": attacker_name,
                    "defender": defender_name,
                    "years": 0,
                    "score": 0.0,
                    "cause": cause
                })

                stats["wars"] = int(stats["wars"]) + 1
                _log("%s declara la guerra a %s por %s." % [attacker_name, defender_name, cause])
                return


func _war_cause(attacker: String, defender: String) -> String:
    for p in provinces:
        if (
            String(p["owner"]) == defender
            and countries[attacker]["claims"].has(p["name"])
        ):
            return "reclamación territorial"

    var relation: int = int(relations[attacker][defender])

    if countries[attacker]["rivals"].has(defender) and relation <= -60:
        return "rivalidad histórica"

    var strategic_good: String = _country_strategic_shortage(attacker)

    if strategic_good != "" and relation <= -58 and _country_has_resource(defender, strategic_good):
        return "acceso a %s" % strategic_good

    return ""


func _country_strategic_shortage(country_name: String) -> String:
    var important_goods: Array[String] = ["hierro", "carbón", "cristal arcano"]

    for good_name in important_goods:
        if (
            float(market[good_name]["availability"]) < 0.66
            and not _country_has_resource(country_name, good_name)
        ):
            return good_name

    return ""


func _country_has_resource(country_name: String, resource: String) -> bool:
    for p in provinces:
        if String(p["owner"]) == country_name and String(p["resource"]) == resource:
            return true

    return false


func _resolve_wars() -> void:
    for idx in range(wars.size() - 1, -1, -1):
        var w: Dictionary = wars[idx]
        var attacker_name: String = String(w["attacker"])
        var defender_name: String = String(w["defender"])
        var a: Dictionary = countries[attacker_name]
        var d: Dictionary = countries[defender_name]

        w["years"] = int(w["years"]) + 1

        var a_roll: float = (
            float(a["military"]) * rng.randf_range(0.72, 1.28)
            + float(a["stability"]) * 0.22
            - float(a["war_exhaustion"]) * 0.18
        )

        var d_roll: float = (
            float(d["military"]) * rng.randf_range(0.72, 1.28)
            + float(d["stability"]) * 0.22
            - float(d["war_exhaustion"]) * 0.18
        )

        w["score"] = float(w["score"]) + (a_roll - d_roll) / 20.0

        a["treasury"] = float(a["treasury"]) - 8.0
        d["treasury"] = float(d["treasury"]) - 8.0
        a["stability"] = float(a["stability"]) - rng.randf_range(0.35, 1.0)
        d["stability"] = float(d["stability"]) - rng.randf_range(0.35, 1.0)
        a["military"] = maxf(10.0, float(a["military"]) - rng.randf_range(0.45, 1.6))
        d["military"] = maxf(10.0, float(d["military"]) - rng.randf_range(0.45, 1.6))
        a["war_exhaustion"] = clampf(float(a["war_exhaustion"]) + 7.0, 0.0, 100.0)
        d["war_exhaustion"] = clampf(float(d["war_exhaustion"]) + 7.0, 0.0, 100.0)

        countries[attacker_name] = a
        countries[defender_name] = d

        _apply_war_casualties(attacker_name, rng.randf_range(0.0011, 0.0034))
        _apply_war_casualties(defender_name, rng.randf_range(0.0011, 0.0034))

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

            pop["size"] = maxi(
                1,
                int(round(float(pop["size"]) * (1.0 - casualty_rate)))
            )

            pops[pop_index] = pop

        p["pops"] = pops
        p["population"] = _sum_pop_sizes(pops)
        provinces[province_index] = p


func _peace(winner: String, loser: String, w: Dictionary) -> void:
    var winner_country: Dictionary = countries[winner]
    var loser_country: Dictionary = countries[loser]
    var candidates: Array[int] = []

    for i in range(provinces.size()):
        if String(provinces[i]["owner"]) == loser:
            candidates.append(i)

    var taken := ""
    var cause: String = String(w.get("cause", ""))

    if candidates.size() > 1:
        var target: int = -1
        var attacker_won: bool = winner == String(w.get("attacker", ""))

        # El objetivo de guerra solo se impone si vence quien lo declaró.
        if attacker_won and cause == "reclamación territorial":
            for i in candidates:
                if winner_country["claims"].has(provinces[i]["name"]):
                    target = i
                    break

        if attacker_won and target < 0 and cause.begins_with("acceso a "):
            var desired_resource: String = cause.trim_prefix("acceso a ")

            for i in candidates:
                if String(provinces[i]["resource"]) == desired_resource:
                    target = i
                    break

        # Una victoria muy decisiva en una rivalidad puede producir una cesión,
        # preferentemente donde exista población culturalmente afín.
        if (
            attacker_won
            and target < 0
            and cause == "rivalidad histórica"
            and float(w.get("score", 0.0)) >= 6.0
            and rng.randf() < 0.38
        ):
            var winner_culture: String = String(winner_country["culture"])

            for i in candidates:
                if String(provinces[i]["culture"]) == winner_culture:
                    target = i
                    break

            if target < 0 and rng.randf() < 0.30:
                var smallest_population: int = 2147483647

                for i in candidates:
                    var candidate_population: int = int(provinces[i]["population"])
                    if candidate_population < smallest_population:
                        smallest_population = candidate_population
                        target = i

        if target >= 0:
            taken = String(provinces[target]["name"])
            provinces[target]["owner"] = winner

            var conquered_pops: Array = provinces[target]["pops"]

            for pop_index in range(conquered_pops.size()):
                var pop: Dictionary = conquered_pops[pop_index]
                pop["militancy"] = clampf(float(pop["militancy"]) + 11.0, 0.0, 100.0)
                conquered_pops[pop_index] = pop

            provinces[target]["pops"] = conquered_pops
            provinces[target]["unrest"] = _weighted_pop_value(conquered_pops, "militancy")
            stats["territorial_changes"] = int(stats["territorial_changes"]) + 1

    winner_country["prestige"] = float(winner_country["prestige"]) + 7.0
    loser_country["prestige"] = float(loser_country["prestige"]) - 5.0
    loser_country["stability"] = float(loser_country["stability"]) - 5.5

    winner_country["peace_until"] = year + 7
    loser_country["peace_until"] = year + 7
    winner_country["war_exhaustion"] = clampf(float(winner_country["war_exhaustion"]) + 7.0, 0.0, 100.0)
    loser_country["war_exhaustion"] = clampf(float(loser_country["war_exhaustion"]) + 10.0, 0.0, 100.0)

    countries[winner] = winner_country
    countries[loser] = loser_country

    relations[winner][loser] = -78
    relations[loser][winner] = -78

    if taken != "":
        _log("La guerra termina con victoria de %s. %s cede %s." % [winner, loser, taken])
    else:
        var reparations: float = minf(18.0, maxf(4.0, float(countries[loser]["treasury"]) * 0.08))
        countries[loser]["treasury"] = float(countries[loser]["treasury"]) - reparations
        countries[winner]["treasury"] = float(countries[winner]["treasury"]) + reparations
        _log("La guerra termina con victoria de %s. No cambian las fronteras, pero %s paga reparaciones." % [winner, loser])


func _decay_war_exhaustion() -> void:
    for country_name in countries:
        if _at_war(String(country_name)):
            continue

        var c: Dictionary = countries[country_name]
        c["war_exhaustion"] = maxf(0.0, float(c["war_exhaustion"]) - 3.2)
        countries[country_name] = c


func _at_war(country_name: String) -> bool:
    for w in wars:
        if String(w["attacker"]) == country_name or String(w["defender"]) == country_name:
            return true

    return false


# -------------------------------------------------------------------
# EVENTOS / HISTORIA
# -------------------------------------------------------------------

func _historical_events() -> void:
    if year >= 184 and not fired_events.has("arcane_engine"):
        fired_events["arcane_engine"] = true
        countries["Lunaris"]["prestige"] = float(countries["Lunaris"]["prestige"]) + 14.0
        countries["Lunaris"]["industrial_bonus"] = 1.13
        _major_event("Lunaris demuestra el primer motor de cristal arcano. La nueva tecnología aumenta su capacidad industrial.")

    if (
        year >= 187
        and not fired_events.has("ardel_reform")
        and _country_avg_pop_value("Ardel", "militancy") > 22.0
        and _country_avg_pop_value("Ardel", "literacy") > 0.22
    ):
        fired_events["ardel_reform"] = true
        countries["Ardel"]["government"] = "Monarquía parlamentaria"
        countries["Ardel"]["stability"] = minf(100.0, float(countries["Ardel"]["stability"]) + 10.0)
        stats["reforms"] = int(stats["reforms"]) + 1
        _major_event("La Crisis de Valem obliga a la corona de Ardel a aceptar un parlamento con poderes reales.")

    if (
        year >= 190
        and not fired_events.has("orc_reform")
        and _country_avg_pop_value("Orkhan", "militancy") > 24.0
    ):
        fired_events["orc_reform"] = true
        countries["Orkhan"]["government"] = "Kanato reformista"
        countries["Orkhan"]["military"] = float(countries["Orkhan"]["military"]) + 7.0
        countries["Orkhan"]["stability"] = minf(100.0, float(countries["Orkhan"]["stability"]) + 8.0)
        stats["reforms"] = int(stats["reforms"]) + 1
        _major_event("Los clanes de Orkhan pactan la Reforma de las Nueve Banderas y profesionalizan el ejército.")

    if year >= 194 and not fired_events.has("arcane_accident"):
        fired_events["arcane_accident"] = true
        countries["Lunaris"]["stability"] = float(countries["Lunaris"]["stability"]) - 8.0

        for province_index in range(provinces.size()):
            var p: Dictionary = provinces[province_index]

            if String(p["owner"]) == "Lunaris" and String(p["resource"]) == "cristal arcano":
                var pops: Array = p["pops"]

                for pop_index in range(pops.size()):
                    var pop: Dictionary = pops[pop_index]
                    pop["militancy"] = clampf(float(pop["militancy"]) + 7.0, 0.0, 100.0)
                    pops[pop_index] = pop

                p["pops"] = pops
                provinces[province_index] = p

        _major_event("Una explosión en una refinería arcana de Lunaris inicia el primer debate sobre regulación mágica industrial.")


# -------------------------------------------------------------------
# UI
# -------------------------------------------------------------------

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
    _refresh_market()
    _refresh_history()
    _refresh_summary()

    if not provinces.is_empty():
        selected_province_index = clampi(selected_province_index, 0, provinces.size() - 1)
        _show_province(selected_province_index)


func _refresh_province_aggregates() -> void:
    for i in range(provinces.size()):
        var p: Dictionary = provinces[i]
        var pops: Array = p["pops"]

        p["population"] = _sum_pop_sizes(pops)
        p["culture"] = _dominant_culture(pops)
        p["unrest"] = _weighted_pop_value(pops, "militancy")

        provinces[i] = p


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

    detail_text.text = "%s\n[color=#aaaaaa]%s[/color]\n\nProvincia\nCultura dominante: %s\nRecurso principal: %s\nPoblación: %s\nRiqueza local: %.2f\nNecesidades satisfechas: %.1f%%\nAlfabetización: %.1f%%\nMilitancia: %.1f / 100\n\n%s\nGobierno: %s\nCultura estatal: %s\nTesoro: %.1f\nProducción anual: %.1f\nEstabilidad: %.1f\nPoder militar: %.1f\nAgotamiento de guerra: %.1f / 100\nPrestigio: %.1f\n\nSituación\n%s" % [
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
        float(c["war_exhaustion"]),
        float(c["prestige"]),
        "EN GUERRA" if _at_war(owner) else "En paz"
    ]

    if int(p.get("social_cooldown", 0)) > 0:
        detail_text.text += "\n\n[color=#aaaaaa]Memoria social: %s (%d años de enfriamiento)[/color]" % [
            String(p.get("last_social_event", "conflicto")),
            int(p.get("social_cooldown", 0))
        ]

    _refresh_pops(p)


func _refresh_pops(p: Dictionary) -> void:
    var lines: Array[String] = []

    lines.append("POPs de %s" % String(p["name"]))
    lines.append("[color=#aaaaaa]Sus necesidades ahora dependen de precios, oferta y poder adquisitivo.[/color]\n")

    var pops: Array = p["pops"]

    for pop_data in pops:
        var pop: Dictionary = pop_data
        var pop_class: String = String(pop["class"])
        var goods_list: Array[String] = []

        var basket: Dictionary = CLASS_NEEDS.get(pop_class, {})

        for good_name in basket:
            goods_list.append(String(good_name))

        lines.append(
            "%s — %s\nCultura: %s | Religión: %s\nNecesidades: %.0f%% | Alfabetización: %.0f%%\nRiqueza: %.1f | Militancia: %.1f | Ideología: %s\nCesta: %s\n" % [
                pop_class,
                _fmt_pop(int(pop["size"])),
                String(pop["culture"]),
                String(pop["religion"]),
                float(pop["needs"]) * 100.0,
                float(pop["literacy"]) * 100.0,
                float(pop["wealth"]),
                float(pop["militancy"]),
                String(pop["ideology"]),
                ", ".join(goods_list)
            ]
        )

    pops_text.text = "\n".join(lines)


func _refresh_market() -> void:
    var lines: Array[String] = []

    lines.append("=== MERCADO MUNDIAL ===")
    lines.append("[color=#aaaaaa]Los precios reaccionan a la oferta y demanda de cada año.[/color]\n")

    for good_name in GOODS:
        var g: Dictionary = market[good_name]
        var base_price: float = float(g["base_price"])
        var price: float = float(g["price"])
        var price_change: float = (price / base_price - 1.0) * 100.0
        var availability: float = float(g["availability"]) * 100.0
        var condition := "normal"

        if availability < 70.0:
            condition = "ESCASEZ"
        elif availability < 90.0:
            condition = "tensión"
        elif float(g["supply"]) > float(g["demand"]) * 1.25:
            condition = "exceso de oferta"

        lines.append(
            "%s — %.2f (%+.0f%%)\nOferta %.1f | Demanda %.1f | Cobertura %.0f%% | %s\n" % [
                String(good_name).capitalize(),
                price,
                price_change,
                float(g["supply"]),
                float(g["demand"]),
                availability,
                condition
            ]
        )

    market_text.text = "\n".join(lines)


func _refresh_history() -> void:
    var lines: Array[String] = ["=== CRÓNICA DEL MUNDO ===\n"]
    var start: int = maxi(0, history.size() - 50)

    for i in range(start, history.size()):
        lines.append(history[i])

    history_text.text = "\n".join(lines)
    history_text.scroll_to_line(history.size())


func _refresh_summary() -> void:
    var world_population: int = _world_population()
    var growth_percent: float = 0.0

    if initial_population > 0:
        growth_percent = (
            float(world_population - initial_population)
            / float(initial_population)
        ) * 100.0

    var biggest_country: String = _country_with_max("population")
    var richest_country: String = _country_with_max("treasury")
    var productive_country: String = _country_with_max("output")
    var strongest_country: String = _country_with_max("military")
    var unstable_country: String = _country_with_max("militancy")

    var global_needs: float = _world_pop_average("needs")
    var global_literacy: float = _world_pop_average("literacy")
    var global_militancy: float = _world_pop_average("militancy")

    var lines: Array[String] = []

    lines.append("=== RESUMEN DE LA SIMULACIÓN ===")
    lines.append("[color=#aaaaaa]Seed %d — %d años simulados[/color]" % [current_seed, year - START_YEAR])
    lines.append("")
    lines.append("— Demografía y sociedad —")
    lines.append("Población inicial: %s" % _fmt_pop(initial_population))
    lines.append("Población actual: %s (%+.1f%%)" % [_fmt_pop(world_population), growth_percent])
    lines.append("Necesidades medias satisfechas: %.1f%%" % (global_needs * 100.0))
    lines.append("Alfabetización media: %.1f%%" % (global_literacy * 100.0))
    lines.append("Militancia media: %.1f / 100\n" % global_militancy)

    lines.append("")
    lines.append("— Historia generada —")
    lines.append("Guerras iniciadas: %d" % int(stats["wars"]))
    lines.append("Cambios territoriales: %d" % int(stats["territorial_changes"]))
    lines.append("Protestas: %d" % int(stats["protests"]))
    lines.append("Huelgas/disturbios: %d" % int(stats["strikes"]))
    lines.append("Rebeliones: %d" % int(stats["revolts"]))
    lines.append("Reformas: %d" % int(stats["reforms"]))
    lines.append("Crisis de escasez: %d" % int(stats["shortage_crises"]))
    lines.append("Grandes eventos: %d\n" % int(stats["major_events"]))

    lines.append("")
    lines.append("— Estados destacados —")
    lines.append("Mayor población: %s (%s)" % [biggest_country, _fmt_pop(_country_population(biggest_country))])
    lines.append("Mayor tesoro: %s (%.1f)" % [richest_country, float(countries[richest_country]["treasury"])])
    lines.append("Mayor producción: %s (%.1f)" % [productive_country, float(countries[productive_country]["last_output"])])
    lines.append("Mayor poder militar: %s (%.1f)" % [strongest_country, float(countries[strongest_country]["military"])])
    lines.append("Mayor militancia: %s (%.1f)" % [unstable_country, _country_avg_pop_value(unstable_country, "militancy")])

    summary_text.text = "\n".join(lines)


# -------------------------------------------------------------------
# HELPERS
# -------------------------------------------------------------------

func _country_with_max(metric: String) -> String:
    var best_name := ""
    var best_value: float = -1000000000.0

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
            "militancy":
                value = _country_avg_pop_value(String(country_name), "militancy")
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

        for pop_data in pops:
            var pop: Dictionary = pop_data
            var size: int = int(pop["size"])
            weighted_sum += float(pop[field]) * float(size)
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

        for pop_data in pops:
            var pop: Dictionary = pop_data
            var size: int = int(pop["size"])
            weighted_sum += float(pop[field]) * float(size)
            population_sum += size

    if population_sum <= 0:
        return 0.0

    return weighted_sum / float(population_sum)


func _sum_pop_sizes(pops: Array) -> int:
    var total: int = 0

    for pop_data in pops:
        var pop: Dictionary = pop_data
        total += int(pop["size"])

    return total


func _weighted_pop_value(pops: Array, field: String) -> float:
    var weighted_sum: float = 0.0
    var population_sum: int = 0

    for pop_data in pops:
        var pop: Dictionary = pop_data
        var size: int = int(pop["size"])
        weighted_sum += float(pop[field]) * float(size)
        population_sum += size

    if population_sum <= 0:
        return 0.0

    return weighted_sum / float(population_sum)


func _dominant_culture(pops: Array) -> String:
    var totals := {}

    for pop_data in pops:
        var pop: Dictionary = pop_data
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
