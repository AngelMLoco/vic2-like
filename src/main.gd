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
    "cristal arcano": {"base_price": 3.20},
    "componentes arcanos": {"base_price": 4.80}
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
        "grano": 0.82, "madera": 0.25, "ropa": 0.55, "herramientas": 0.14,
        "cristal arcano": 0.06, "componentes arcanos": 0.025
    },
    "Magos": {
        "grano": 0.88, "madera": 0.17, "ropa": 0.30, "herramientas": 0.16,
        "cristal arcano": 0.22, "componentes arcanos": 0.085
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
var tech_defs: Array = []
var industry_defs: Array = []
var event_defs: Array = []
var cb_defs: Array = []
var event_last_fired := {}

var armies: Array[Dictionary] = []
var fleets: Array[Dictionary] = []
var casus_bellis: Array[Dictionary] = []
var next_army_id: int = 1
var next_fleet_id: int = 1
var selected_army_id: int = -1
var player_country: String = ""
var game_started: bool = false

var stats := {}
var initial_population: int = 0
var selected_province_index: int = 0

var year_label: Label
var status_label: Label
var seed_input: LineEdit
var treasury_label: Label
var literacy_label: Label
var military_label: Label
var research_label: Label
var political_map
var minimap
var province_panel_text: RichTextLabel
var outliner_text: RichTextLabel
var info_modal: PanelContainer
var info_tabs: TabContainer
var detail_text: RichTextLabel
var pops_text: RichTextLabel
var market_text: RichTextLabel
var development_text: RichTextLabel
var history_text: RichTextLabel
var summary_text: RichTextLabel
var country_select_overlay: PanelContainer
var action_modal: PanelContainer
var action_modal_content: VBoxContainer


func _ready() -> void:
    rng.seed = current_seed
    _load_external_data()
    _build_ui()
    _create_world()
    _initialize_military_layer()
    _show_country_select()
    _refresh_all()


func _build_ui() -> void:
    var bg := ColorRect.new()
    bg.color = Color("111519")
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(bg)

    var root := VBoxContainer.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_theme_constant_override("separation", 0)
    add_child(root)

    # ---------- Barra superior ----------
    var top_panel := PanelContainer.new()
    top_panel.custom_minimum_size.y = 78
    top_panel.add_theme_stylebox_override("panel", _panel_style(Color("241f1a"), Color("8b6a38"), 2))
    root.add_child(top_panel)

    var top := HBoxContainer.new()
    top.add_theme_constant_override("separation", 0)
    top_panel.add_child(top)

    var brand := Label.new()
    brand.text = "  CHRONICLES OF AETHER  "
    brand.custom_minimum_size.x = 330
    brand.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    brand.add_theme_font_size_override("font_size", 26)
    brand.add_theme_color_override("font_color", Color("f0d39a"))
    top.add_child(brand)

    treasury_label = _top_stat("Tesoro", "¤ 0")
    literacy_label = _top_stat("Alfabetización", "0%")
    military_label = _top_stat("Poder militar", "0")
    research_label = _top_stat("Investigación", "—")
    top.add_child(treasury_label)
    top.add_child(literacy_label)
    top.add_child(military_label)
    top.add_child(research_label)

    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(spacer)

    var date_box := VBoxContainer.new()
    date_box.custom_minimum_size.x = 270
    date_box.alignment = BoxContainer.ALIGNMENT_CENTER
    top.add_child(date_box)

    year_label = Label.new()
    year_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    year_label.add_theme_font_size_override("font_size", 20)
    year_label.add_theme_color_override("font_color", Color("f3dfb2"))
    date_box.add_child(year_label)

    var speed := HBoxContainer.new()
    speed.alignment = BoxContainer.ALIGNMENT_CENTER
    date_box.add_child(speed)
    for item in [["▶",1],["▶▶",5],["▶▶▶",20],["⏩",100]]:
        var b := Button.new()
        b.text = String(item[0])
        b.custom_minimum_size = Vector2(48,30)
        _style_small_button(b)
        var amount: int = int(item[1])
        b.pressed.connect(func(): _advance_years(amount))
        speed.add_child(b)

    # ---------- Cuerpo ----------
    var body := HBoxContainer.new()
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 0)
    root.add_child(body)

    # Menú izquierdo
    var left_panel := PanelContainer.new()
    left_panel.custom_minimum_size.x = 178
    left_panel.add_theme_stylebox_override("panel", _panel_style(Color("201c18"), Color("795d34"), 2))
    body.add_child(left_panel)

    var left := VBoxContainer.new()
    left.add_theme_constant_override("separation", 4)
    left_panel.add_child(left)

    var menu_title := Label.new()
    menu_title.text = "  REINO"
    menu_title.custom_minimum_size.y = 40
    menu_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    menu_title.add_theme_font_size_override("font_size", 18)
    menu_title.add_theme_color_override("font_color", Color("d9b97d"))
    left.add_child(menu_title)

    var diplomacy_button := Button.new()
    diplomacy_button.text = "🤝  Diplomacia"
    diplomacy_button.custom_minimum_size = Vector2(0,48)
    diplomacy_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    _style_menu_button(diplomacy_button)
    diplomacy_button.pressed.connect(_open_diplomacy_panel)
    left.add_child(diplomacy_button)

    var economy_button := Button.new()
    economy_button.text = "¤  Economía"
    economy_button.custom_minimum_size = Vector2(0,48)
    economy_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    _style_menu_button(economy_button)
    economy_button.pressed.connect(func(): _open_info_tab(2))
    left.add_child(economy_button)

    var technology_button := Button.new()
    technology_button.text = "⚗  Tecnología"
    technology_button.custom_minimum_size = Vector2(0,48)
    technology_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    _style_menu_button(technology_button)
    technology_button.pressed.connect(func(): _open_info_tab(3))
    left.add_child(technology_button)

    var military_button := Button.new()
    military_button.text = "⚔  Militar"
    military_button.custom_minimum_size = Vector2(0,48)
    military_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    _style_menu_button(military_button)
    military_button.pressed.connect(_open_military_panel)
    left.add_child(military_button)

    var politics_button := Button.new()
    politics_button.text = "🏛  Política"
    politics_button.custom_minimum_size = Vector2(0,48)
    politics_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    _style_menu_button(politics_button)
    politics_button.pressed.connect(func(): _open_info_tab(3))
    left.add_child(politics_button)

    var population_button := Button.new()
    population_button.text = "♟  Población"
    population_button.custom_minimum_size = Vector2(0,48)
    population_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    _style_menu_button(population_button)
    population_button.pressed.connect(func(): _open_info_tab(1))
    left.add_child(population_button)

    var trade_button := Button.new()
    trade_button.text = "⚓  Comercio"
    trade_button.custom_minimum_size = Vector2(0,48)
    trade_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    _style_menu_button(trade_button)
    trade_button.pressed.connect(func(): _open_info_tab(2))
    left.add_child(trade_button)

    var chronicle_button := Button.new()
    chronicle_button.text = "📜  Crónica"
    chronicle_button.custom_minimum_size = Vector2(0,48)
    chronicle_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    _style_menu_button(chronicle_button)
    chronicle_button.pressed.connect(func(): _open_info_tab(4))
    left.add_child(chronicle_button)

    var summary_button := Button.new()
    summary_button.text = "▦  Resumen"
    summary_button.custom_minimum_size = Vector2(0,48)
    summary_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    _style_menu_button(summary_button)
    summary_button.pressed.connect(func(): _open_info_tab(5))
    left.add_child(summary_button)

    var left_spacer := Control.new()
    left_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    left.add_child(left_spacer)

    var seed_box := VBoxContainer.new()
    seed_box.add_theme_constant_override("separation", 4)
    left.add_child(seed_box)

    var seed_caption := Label.new()
    seed_caption.text = "  Seed del mundo"
    seed_caption.add_theme_color_override("font_color", Color("a99a7f"))
    seed_box.add_child(seed_caption)

    seed_input = LineEdit.new()
    seed_input.text = str(current_seed)
    seed_input.placeholder_text = "Seed"
    seed_input.text_submitted.connect(func(_value: String): _use_seed())
    seed_box.add_child(seed_input)

    var seed_actions := HBoxContainer.new()
    seed_box.add_child(seed_actions)
    var use_seed := Button.new()
    use_seed.text = "Usar"
    use_seed.pressed.connect(_use_seed)
    _style_small_button(use_seed)
    seed_actions.add_child(use_seed)
    var random_seed := Button.new()
    random_seed.text = "Nueva"
    random_seed.pressed.connect(_random_world)
    _style_small_button(random_seed)
    seed_actions.add_child(random_seed)

    var save_load := HBoxContainer.new()
    seed_box.add_child(save_load)
    var save_button := Button.new()
    save_button.text = "Guardar"
    save_button.pressed.connect(_save_game)
    _style_small_button(save_button)
    save_load.add_child(save_button)
    var load_button := Button.new()
    load_button.text = "Cargar"
    load_button.pressed.connect(_load_game)
    _style_small_button(load_button)
    save_load.add_child(load_button)

    status_label = Label.new()
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    status_label.add_theme_font_size_override("font_size", 11)
    status_label.add_theme_color_override("font_color", Color("a99776"))
    left.add_child(status_label)

    # Centro: avisos + mapa + panel inferior
    var center := VBoxContainer.new()
    center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    center.size_flags_vertical = Control.SIZE_EXPAND_FILL
    center.add_theme_constant_override("separation", 0)
    body.add_child(center)

    var alerts := HBoxContainer.new()
    alerts.custom_minimum_size.y = 40
    alerts.add_theme_constant_override("separation", 4)
    center.add_child(alerts)
    for text_value in ["⚠ Movimiento político", "🤝 Diplomacia activa", "✦ Mercado arcano"]:
        var alert := Label.new()
        alert.text = "  " + text_value + "  "
        alert.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        alert.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        alert.add_theme_color_override("font_color", Color("ead9b7"))
        alert.add_theme_stylebox_override("normal", _panel_style(Color("3a2420"), Color("74513d"), 1))
        alerts.add_child(alert)

    var map_frame := PanelContainer.new()
    map_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
    map_frame.add_theme_stylebox_override("panel", _panel_style(Color("405f69"), Color("94713e"), 2))
    center.add_child(map_frame)

    var map_script = load("res://src/ui/PoliticalMap.gd")
    political_map = map_script.new()
    political_map.name = "PoliticalMap"
    political_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    political_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
    political_map.custom_minimum_size = Vector2(760,460)
    political_map.connect("province_selected", Callable(self, "_on_map_province_clicked"))
    political_map.connect("army_selected", Callable(self, "_on_map_army_selected"))
    map_frame.add_child(political_map)

    var bottom_panel := PanelContainer.new()
    bottom_panel.custom_minimum_size.y = 185
    bottom_panel.add_theme_stylebox_override("panel", _panel_style(Color("211c18"), Color("9a743b"), 2))
    center.add_child(bottom_panel)

    var bottom := HBoxContainer.new()
    bottom.add_theme_constant_override("separation", 12)
    bottom_panel.add_child(bottom)

    var province_badge := VBoxContainer.new()
    province_badge.custom_minimum_size.x = 220
    bottom.add_child(province_badge)

    var selected_title := Label.new()
    selected_title.name = "SelectedProvinceTitle"
    selected_title.text = "VALem"
    selected_title.add_theme_font_size_override("font_size", 26)
    selected_title.add_theme_color_override("font_color", Color("efd29a"))
    province_badge.add_child(selected_title)

    var selected_sub := Label.new()
    selected_sub.name = "SelectedProvinceOwner"
    selected_sub.text = "Provincia"
    selected_sub.add_theme_color_override("font_color", Color("af9e80"))
    province_badge.add_child(selected_sub)

    var vignette := ColorRect.new()
    vignette.custom_minimum_size = Vector2(200,105)
    vignette.color = Color("4b4130")
    province_badge.add_child(vignette)

    province_panel_text = RichTextLabel.new()
    province_panel_text.bbcode_enabled = true
    province_panel_text.fit_content = false
    province_panel_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    province_panel_text.add_theme_font_size_override("normal_font_size", 15)
    bottom.add_child(province_panel_text)

    # Outliner derecho
    var right_panel := PanelContainer.new()
    right_panel.custom_minimum_size.x = 330
    right_panel.add_theme_stylebox_override("panel", _panel_style(Color("1d1a17"), Color("806238"), 2))
    body.add_child(right_panel)

    var right := VBoxContainer.new()
    right.add_theme_constant_override("separation", 8)
    right_panel.add_child(right)

    var outliner_title := Label.new()
    outliner_title.text = "  OUTLINER"
    outliner_title.custom_minimum_size.y = 42
    outliner_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    outliner_title.add_theme_font_size_override("font_size", 20)
    outliner_title.add_theme_color_override("font_color", Color("ead4a5"))
    right.add_child(outliner_title)

    outliner_text = RichTextLabel.new()
    outliner_text.bbcode_enabled = true
    outliner_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
    right.add_child(outliner_text)

    var mini_label := Label.new()
    mini_label.text = "  MAPA GENERAL"
    mini_label.add_theme_color_override("font_color", Color("c8ae7b"))
    right.add_child(mini_label)

    var mini_frame := PanelContainer.new()
    mini_frame.custom_minimum_size.y = 185
    mini_frame.add_theme_stylebox_override("panel", _panel_style(Color("3d5153"), Color("725b37"), 1))
    right.add_child(mini_frame)

    minimap = map_script.new()
    minimap.compact_mode = true
    minimap.interactive = false
    minimap.show_country_labels = false
    minimap.show_province_names = false
    minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
    minimap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    minimap.size_flags_vertical = Control.SIZE_EXPAND_FILL
    mini_frame.add_child(minimap)

    # ---------- Ventana de información ----------
    info_modal = PanelContainer.new()
    info_modal.visible = false
    info_modal.set_anchors_preset(Control.PRESET_CENTER)
    info_modal.position = Vector2(230,120)
    info_modal.size = Vector2(1040,650)
    info_modal.add_theme_stylebox_override("panel", _panel_style(Color("171819"), Color("a17a42"), 3))
    add_child(info_modal)

    var modal_root := VBoxContainer.new()
    info_modal.add_child(modal_root)

    var modal_header := HBoxContainer.new()
    modal_root.add_child(modal_header)
    var modal_title := Label.new()
    modal_title.text = "  ARCHIVOS DEL ESTADO"
    modal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    modal_title.add_theme_font_size_override("font_size", 20)
    modal_title.add_theme_color_override("font_color", Color("e6cd98"))
    modal_header.add_child(modal_title)
    var close := Button.new()
    close.text = "✕"
    close.custom_minimum_size = Vector2(44,36)
    close.pressed.connect(func(): info_modal.visible = false)
    _style_small_button(close)
    modal_header.add_child(close)

    info_tabs = TabContainer.new()
    info_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    modal_root.add_child(info_tabs)

    detail_text = _new_info_page("Inspector")
    pops_text = _new_info_page("POPs")
    market_text = _new_info_page("Mercado")
    development_text = _new_info_page("Desarrollo")
    history_text = _new_info_page("Crónica")
    summary_text = _new_info_page("Resumen")

    info_tabs.add_child(detail_text)
    info_tabs.add_child(pops_text)
    info_tabs.add_child(market_text)
    info_tabs.add_child(development_text)
    info_tabs.add_child(history_text)
    info_tabs.add_child(summary_text)


func _new_info_page(page_name: String) -> RichTextLabel:
    var page := RichTextLabel.new()
    page.name = page_name
    page.bbcode_enabled = true
    page.size_flags_vertical = Control.SIZE_EXPAND_FILL
    page.add_theme_font_size_override("normal_font_size", 15)
    return page


func _top_stat(title_text: String, value_text: String) -> Label:
    var label := Label.new()
    label.text = title_text + "\n" + value_text
    label.custom_minimum_size = Vector2(205,72)
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.add_theme_font_size_override("font_size", 15)
    label.add_theme_color_override("font_color", Color("e8d9ba"))
    label.add_theme_stylebox_override("normal", _panel_style(Color("1b1a18"), Color("5e4a31"), 1))
    return label


func _panel_style(bg_color: Color, border_color: Color, border_width: int = 1) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = bg_color
    style.border_color = border_color
    style.set_border_width_all(border_width)
    style.corner_radius_top_left = 2
    style.corner_radius_top_right = 2
    style.corner_radius_bottom_left = 2
    style.corner_radius_bottom_right = 2
    style.content_margin_left = 8
    style.content_margin_right = 8
    style.content_margin_top = 6
    style.content_margin_bottom = 6
    return style


func _style_menu_button(button: Button) -> void:
    button.add_theme_font_size_override("font_size", 16)
    button.add_theme_color_override("font_color", Color("e6d6b4"))
    button.add_theme_stylebox_override("normal", _panel_style(Color("29231d"), Color("5c4931"), 1))
    button.add_theme_stylebox_override("hover", _panel_style(Color("3c3023"), Color("a47b3f"), 1))
    button.add_theme_stylebox_override("pressed", _panel_style(Color("4a3524"), Color("c5964e"), 1))


func _style_small_button(button: Button) -> void:
    button.add_theme_font_size_override("font_size", 13)
    button.add_theme_color_override("font_color", Color("e8d7b0"))
    button.add_theme_stylebox_override("normal", _panel_style(Color("29241f"), Color("675238"), 1))
    button.add_theme_stylebox_override("hover", _panel_style(Color("403328"), Color("a07942"), 1))


func _open_info_tab(tab_index: int) -> void:
    info_modal.visible = true
    info_tabs.current_tab = clampi(tab_index, 0, info_tabs.get_tab_count() - 1)

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
    event_last_fired.clear()
    armies.clear()
    fleets.clear()
    casus_bellis.clear()
    next_army_id = 1
    next_fleet_id = 1
    selected_army_id = -1

    stats = {
        "wars": 0,
        "territorial_changes": 0,
        "protests": 0,
        "strikes": 0,
        "revolts": 0,
        "reforms": 0,
        "major_events": 0,
        "shortage_crises": 0,
        "migrations": 0,
        "industries_built": 0,
        "technologies_researched": 0,
        "alliances_formed": 0,
        "political_movements": 0,
        "diplomatic_crises": 0
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
                "pressure": _weighted_pop_value(pops, "political_pressure"),
                "social_cooldown": 0,
                "last_social_event": "",
                "industries": {},
                "landmass": _province_landmass(idx),
                "occupation": 0.0,
                "occupied_by": "",
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

    _seed_initial_industries()

    for a in countries:
        relations[a] = {}

        for b in countries:
            if a != b:
                relations[a][b] = rng.randi_range(-10, 25)

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
        "last_reform_year": START_YEAR - 25,
        "technologies": [],
        "research_points": 0.0,
        "active_research": "",
        "allies": [],
        "logistics": 1.0,
        "last_industry_year": START_YEAR - 10,
        "laws": {
            "labor": "sin regulación",
            "suffrage": "censitario",
            "citizenship": "cultura estatal",
            "magic_regulation": "sin regulación"
        },
        "movement_cooldown": START_YEAR
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
        var political_pressure: float = clampf(
            (0.72 - initial_needs) * 52.0
            + literacy * 8.0
            + rng.randf_range(0.0, 4.0),
            0.0,
            60.0
        )
        var militancy: float = clampf(
            maxf(0.0, political_pressure - 30.0) * 0.18
            + rng.randf_range(0.0, 2.5),
            0.0,
            22.0
        )

        if culture != state_culture:
            political_pressure += rng.randf_range(4.0, 8.0)
            militancy += rng.randf_range(0.5, 1.8)

        result.append({
            "class": pop_class,
            "size": size,
            "culture": culture,
            "religion": _religion_for_culture(culture),
            "literacy": clampf(literacy, 0.02, 0.95),
            "wealth": clampf(wealth, 2.0, 100.0),
            "political_pressure": clampf(political_pressure, 0.0, 100.0),
            "militancy": clampf(militancy, 0.0, 100.0),
            "employment": 0.92,
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
        _research_and_technology()
        _employment_mobility_and_industry()
        _simulate_market_and_economy(true)
        _migration()
        _population_and_unrest()
        _political_movements()
        _generic_reforms()
        _diplomacy()
        _diplomatic_actions()
        _diplomatic_crises()
        _historical_events()
        _data_driven_events()
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
        var sector_bonus: float = _tech_modifier(owner, "agriculture_productivity") if (resource == "grano" or resource == "madera") else _tech_modifier(owner, "mining_productivity")
        var primary_output: float = (float(resource_workers) / 1000.0) * 3.20 * local_factor * (1.0 + sector_bonus)

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

        var industries: Dictionary = p.get("industries", {})
        for industry_id in industries:
            var level: int = int(industries[industry_id])
            if level <= 0:
                continue
            var industry: Dictionary = _industry_def(String(industry_id))
            if industry.is_empty():
                continue
            var input_factor: float = 1.0
            var inputs: Dictionary = industry.get("inputs", {})
            for input_good in inputs:
                if market.has(input_good):
                    input_factor = minf(input_factor, float(market[input_good]["availability"]))
                    demand[input_good] = float(demand[input_good]) + float(inputs[input_good]) * float(level) * 12.0
            var employed_workers: int = int(float(_pop_class_size(p["pops"], "Obreros")) * _pop_class_employment(p["pops"], "Obreros"))
            var capacity: float = float(industry.get("worker_capacity", 10000)) * float(level)
            var labor_factor: float = clampf(float(employed_workers) / maxf(1.0, capacity), 0.15, 1.0)
            var tech_factor: float = 1.0 + _tech_modifier(owner, "industry_productivity")
            var industry_output: float = float(industry.get("output_per_level", 0.0)) * float(level) * labor_factor * input_factor * tech_factor * war_factor
            var output_good: String = String(industry.get("output_good", ""))
            if market.has(output_good):
                supply[output_good] = float(supply[output_good]) + industry_output
                output_value_by_country[owner] = float(output_value_by_country[owner]) + industry_output * float(GOODS[output_good]["base_price"])

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
            var employment: float = float(pop.get("employment", 1.0))
            var income: float = (wage_income * employment + reserve_income) * war_income_penalty
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

            pop["political_pressure"] = clampf(
                float(pop["political_pressure"]) + shock * 2.2,
                0.0,
                100.0
            )
            pop["militancy"] = clampf(
                float(pop["militancy"]) + shock * 0.16,
                0.0,
                100.0
            )
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
            var pressure: float = float(pop["political_pressure"])
            var literacy: float = float(pop["literacy"])

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

            # Presión política: responde rápido a problemas económicos y puede bajar rápido.
            var pressure_delta: float = -0.62 - _tech_modifier(owner, "pressure_decay")

            if needs < 0.72:
                pressure_delta += (0.72 - needs) * 10.5
            elif needs > 0.80:
                pressure_delta -= (needs - 0.80) * 4.0

            if needs < 0.50:
                pressure_delta += 0.45

            var employment: float = float(pop.get("employment", 1.0))
            if employment < 0.82:
                pressure_delta += (0.82 - employment) * 4.2

            if String(pop["culture"]) != state_culture:
                pressure_delta += 0.14

            if float(c["stability"]) < 40.0:
                pressure_delta += (40.0 - float(c["stability"])) / 80.0

            pressure_delta += float(c["war_exhaustion"]) * 0.012

            if needs < 0.66:
                pressure_delta += literacy * 0.24

            pressure = clampf(pressure + pressure_delta, 0.0, 100.0)
            pop["political_pressure"] = pressure

            # Militancia: radicalización lenta. Una sociedad puede estar muy presionada
            # sin que toda la población quiera tomar las armas.
            var militancy_delta: float = -0.30

            if pressure > 55.0:
                militancy_delta += (pressure - 55.0) * 0.012

            if pressure > 75.0:
                militancy_delta += (pressure - 75.0) * 0.015

            if pressure < 35.0:
                militancy_delta -= 0.18

            if needs > 0.78:
                militancy_delta -= 0.12

            if String(pop["culture"]) != state_culture:
                militancy_delta += 0.03

            militancy_delta += float(c["war_exhaustion"]) * 0.003

            pop["militancy"] = clampf(militancy + militancy_delta, 0.0, 100.0)

            var education_rate: float = 0.00125 + _tech_modifier(owner, "education_rate")

            if pop_class == "Clérigos" or pop_class == "Burócratas" or pop_class == "Magos":
                education_rate += 0.0016

            if needs > 0.75:
                education_rate += 0.0007

            pop["literacy"] = clampf(literacy + education_rate, 0.0, 1.0)

            if pressure > 58.0 and float(pop["literacy"]) > 0.30:
                if pop_class == "Obreros" or pop_class == "Mineros":
                    pop["ideology"] = "Popular"
                elif rng.randf() < 0.08:
                    pop["ideology"] = "Reformista"

            pops[pop_index] = pop

        p["pops"] = pops
        p["population"] = _sum_pop_sizes(pops)
        p["culture"] = _dominant_culture(pops)
        p["unrest"] = _weighted_pop_value(pops, "militancy")
        p["pressure"] = _weighted_pop_value(pops, "political_pressure")

        var cooldown: int = maxi(0, int(p.get("social_cooldown", 0)) - 1)
        p["social_cooldown"] = cooldown

        if cooldown <= 0:
            var province_pressure: float = float(p["pressure"])
            var province_militancy: float = float(p["unrest"])

            if (
                province_pressure >= 80.0
                and province_militancy >= 45.0
                and rng.randf() < 0.018
            ):
                stats["revolts"] = int(stats["revolts"]) + 1
                c["stability"] = float(c["stability"]) - 5.0
                p["social_cooldown"] = 12
                p["last_social_event"] = "rebelión"
                _log("Una rebelión estalla en %s contra el gobierno de %s." % [String(p["name"]), owner])
                _calm_after_social_event(pops, 22.0, 7.0)

            elif (
                province_pressure >= 62.0
                and province_militancy >= 18.0
                and rng.randf() < 0.050
            ):
                stats["strikes"] = int(stats["strikes"]) + 1
                c["stability"] = float(c["stability"]) - 1.4
                c["treasury"] = float(c["treasury"]) - 3.0
                p["social_cooldown"] = 7
                p["last_social_event"] = "huelga"
                _log("Huelgas y disturbios paralizan parte de %s." % String(p["name"]))
                _calm_after_social_event(pops, 14.0, 2.0)

            elif province_pressure >= 45.0 and rng.randf() < 0.065:
                stats["protests"] = int(stats["protests"]) + 1
                c["stability"] = float(c["stability"]) - 0.35
                p["social_cooldown"] = 4
                p["last_social_event"] = "protesta"
                _log("Manifestaciones recorren %s; la población reclama reformas." % String(p["name"]))
                _calm_after_social_event(pops, 8.0, 0.5)

        countries[owner] = c
        provinces[province_index] = p


func _generic_reforms() -> void:
    for country_name in countries:
        var c: Dictionary = countries[country_name]
        var reforms: Array = c["reforms"]

        if reforms.has("derechos_laborales"):
            continue

        var pressure: float = _country_avg_pop_value(String(country_name), "political_pressure")
        var militancy: float = _country_avg_pop_value(String(country_name), "militancy")
        var literacy: float = _country_avg_pop_value(String(country_name), "literacy")
        var needs: float = _country_avg_pop_value(String(country_name), "needs")
        var reform_ready: bool = year - int(c["last_reform_year"]) >= 18

        if (
            reform_ready
            and pressure > 58.0
            and militancy > 10.0
            and literacy > 0.30
            and needs < 0.70
            and rng.randf() < 0.055
        ):
            reforms.append("derechos_laborales")
            c["reforms"] = reforms
            c["laws"]["labor"] = "protección básica"
            c["last_reform_year"] = year
            c["stability"] = minf(100.0, float(c["stability"]) + 5.0)
            countries[country_name] = c

            _apply_reform_social_effects(String(country_name))
            stats["reforms"] = int(stats["reforms"]) + 1
            _major_event("%s aprueba leyes laborales para responder a años de presión social; las élites reaccionan con inquietud." % String(country_name))


func _apply_reform_social_effects(country_name: String) -> void:
    for province_index in range(provinces.size()):
        var p: Dictionary = provinces[province_index]

        if String(p["owner"]) != country_name:
            continue

        var pops: Array = p["pops"]

        for pop_index in range(pops.size()):
            var pop: Dictionary = pops[pop_index]
            var pop_class: String = String(pop["class"])
            var pressure_change: float = 0.0
            var militancy_change: float = 0.0

            if pop_class == "Obreros" or pop_class == "Mineros" or pop_class == "Artesanos":
                pressure_change = -20.0
                militancy_change = -5.0
            elif pop_class == "Campesinos" or pop_class == "Soldados":
                pressure_change = -10.0
                militancy_change = -2.0
            elif pop_class == "Aristócratas":
                pressure_change = 12.0
                militancy_change = 2.0
            elif pop_class == "Clérigos":
                pressure_change = 6.0
                militancy_change = 1.0

            pop["political_pressure"] = clampf(
                float(pop["political_pressure"]) + pressure_change,
                0.0,
                100.0
            )
            pop["militancy"] = clampf(
                float(pop["militancy"]) + militancy_change,
                0.0,
                100.0
            )
            pops[pop_index] = pop

        p["pops"] = pops
        p["pressure"] = _weighted_pop_value(pops, "political_pressure")
        p["unrest"] = _weighted_pop_value(pops, "militancy")
        provinces[province_index] = p


func _calm_after_social_event(
    pops: Array,
    pressure_amount: float,
    militancy_amount: float
) -> void:
    for pop_index in range(pops.size()):
        var pop: Dictionary = pops[pop_index]
        pop["political_pressure"] = maxf(
            0.0,
            float(pop["political_pressure"]) - pressure_amount
        )
        pop["militancy"] = maxf(
            0.0,
            float(pop["militancy"]) - militancy_amount
        )
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
            if a == b or not bool(countries[b]["alive"]):
                continue

            var drift: int = rng.randi_range(-2, 2)

            if countries[a]["rivals"].has(b):
                drift -= 1

            relations[a][b] = clampi(int(relations[a][b]) + drift, -100, 100)


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

            var goal: Dictionary = _build_war_goal(attacker_name, defender_name)

            if goal.is_empty():
                continue

            var cause: String = String(goal["cause"])
            var hostility: float = -float(relations[attacker_name][defender_name])
            var power_ratio: float = float(a["military"]) / maxf(1.0, float(d["military"]))
            var confidence: float = maxf(0.0, (power_ratio - 1.0) * 22.0)
            var cause_strength: float = 15.0

            if cause == "reclamación territorial":
                cause_strength = 28.0
            elif cause == "acceso estratégico":
                cause_strength = 22.0

            var desire: float = hostility + confidence + cause_strength

            if desire > 74.0 and rng.randf() < 0.075:
                wars.append({
                    "attacker": attacker_name,
                    "defender": defender_name,
                    "years": 0,
                    "score": 0.0,
                    "cause": cause,
                    "goal_province": String(goal.get("goal_province", "")),
                    "goal_resource": String(goal.get("goal_resource", ""))
                })

                stats["wars"] = int(stats["wars"]) + 1

                var goal_province: String = String(goal.get("goal_province", ""))
                var goal_resource: String = String(goal.get("goal_resource", ""))

                if cause == "reclamación territorial":
                    _log("%s declara la guerra a %s por su reclamación sobre %s." % [attacker_name, defender_name, goal_province])
                elif cause == "acceso estratégico":
                    _log("%s declara la guerra a %s para asegurar %s en %s." % [attacker_name, defender_name, goal_resource, goal_province])
                else:
                    _log("%s declara la guerra a %s por rivalidad histórica." % [attacker_name, defender_name])

                return


func _build_war_goal(attacker: String, defender: String) -> Dictionary:
    for p in provinces:
        if (
            String(p["owner"]) == defender
            and countries[attacker]["claims"].has(p["name"])
        ):
            return {
                "cause": "reclamación territorial",
                "goal_province": String(p["name"]),
                "goal_resource": String(p["resource"])
            }

    var relation: int = int(relations[attacker][defender])
    var strategic_good: String = _country_strategic_shortage(attacker)

    if strategic_good != "" and relation <= -58:
        for p in provinces:
            if (
                String(p["owner"]) == defender
                and String(p["resource"]) == strategic_good
            ):
                return {
                    "cause": "acceso estratégico",
                    "goal_province": String(p["name"]),
                    "goal_resource": strategic_good
                }

    if countries[attacker]["rivals"].has(defender) and relation <= -60:
        return {
            "cause": "rivalidad histórica",
            "goal_province": "",
            "goal_resource": ""
        }

    return {}


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

        var a_logistics: float = 1.0 + _tech_modifier(attacker_name, "logistics")
        var d_logistics: float = 1.0 + _tech_modifier(defender_name, "logistics")
        var a_support: float = _allied_support(attacker_name, defender_name)
        var d_support: float = _allied_support(defender_name, attacker_name)

        var a_roll: float = (
            float(a["military"]) * a_logistics * rng.randf_range(0.72, 1.28)
            + float(a["stability"]) * 0.22
            + a_support
            - float(a["war_exhaustion"]) * 0.18
        )

        var d_roll: float = (
            float(d["military"]) * d_logistics * rng.randf_range(0.72, 1.28)
            + float(d["stability"]) * 0.22
            + d_support
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
    var goal_province: String = String(w.get("goal_province", ""))
    var attacker_won: bool = winner == String(w.get("attacker", ""))

    if candidates.size() > 1 and attacker_won:
        var target: int = -1

        if (
            (cause == "reclamación territorial" or cause == "acceso estratégico")
            and goal_province != ""
        ):
            for i in candidates:
                if String(provinces[i]["name"]) == goal_province:
                    target = i
                    break

        if (
            target < 0
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
                pop["political_pressure"] = clampf(
                    float(pop["political_pressure"]) + 18.0,
                    0.0,
                    100.0
                )
                pop["militancy"] = clampf(
                    float(pop["militancy"]) + 4.0,
                    0.0,
                    100.0
                )
                conquered_pops[pop_index] = pop

            provinces[target]["pops"] = conquered_pops
            provinces[target]["pressure"] = _weighted_pop_value(conquered_pops, "political_pressure")
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
        _log("La guerra termina con victoria de %s. %s cede %s, el objetivo de guerra." % [winner, loser, taken])
    else:
        var loser_treasury: float = float(countries[loser]["treasury"])
        var reparations: float = minf(18.0, maxf(4.0, loser_treasury * 0.08))
        countries[loser]["treasury"] = loser_treasury - reparations
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
        and _country_avg_pop_value("Ardel", "political_pressure") > 48.0
        and _country_avg_pop_value("Ardel", "militancy") > 10.0
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
        and _country_avg_pop_value("Orkhan", "political_pressure") > 52.0
        and _country_avg_pop_value("Orkhan", "militancy") > 12.0
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
                    pop["political_pressure"] = clampf(
                        float(pop["political_pressure"]) + 14.0,
                        0.0,
                        100.0
                    )
                    pop["militancy"] = clampf(
                        float(pop["militancy"]) + 2.0,
                        0.0,
                        100.0
                    )
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
    year_label.text = "1 Enero  %d" % year
    status_label.text = "Seed %d\n%d guerras activas" % [current_seed, wars.size()]

    _rebuild_map()
    _refresh_market()
    _refresh_development()
    _refresh_history()
    _refresh_summary()

    if not provinces.is_empty():
        selected_province_index = clampi(selected_province_index, 0, provinces.size() - 1)
        _show_province(selected_province_index)

    _refresh_topbar()
    _refresh_outliner()


func _refresh_topbar() -> void:
    if provinces.is_empty():
        return

    var owner := String(provinces[selected_province_index]["owner"])
    var c: Dictionary = countries[owner]
    var literacy := _country_avg_pop_value(owner, "literacy") * 100.0
    var active := String(c.get("active_research", ""))
    var active_name := "Sin proyecto"
    if active != "":
        active_name = String(_tech_def(active).get("name", active))

    treasury_label.text = "TESORO\n¤ %.1f" % float(c["treasury"])
    literacy_label.text = "ALFABETIZACIÓN\n%.1f%%" % literacy
    military_label.text = "PODER MILITAR\n%.1f" % float(c["military"])
    research_label.text = "INVESTIGACIÓN\n%s" % active_name


func _refresh_outliner() -> void:
    if provinces.is_empty():
        return

    var owner := String(provinces[selected_province_index]["owner"])
    var c: Dictionary = countries[owner]
    var lines: Array[String] = []

    lines.append("[font_size=20][b]%s[/b][/font_size]" % owner)
    lines.append("[color=#b4a587]%s[/color]\n" % String(c["government"]))

    lines.append("[color=#d9b96d][b]ALERTAS[/b][/color]")
    var pressure := _country_avg_pop_value(owner, "political_pressure")
    if pressure > 45.0:
        lines.append("⚠ Presión política elevada: %.1f" % pressure)
    if float(market["grano"]["availability"]) < 0.75:
        lines.append("⚠ Tensión en el mercado de grano")
    if c.get("allies", []).is_empty():
        lines.append("• Sin alianzas defensivas")
    else:
        lines.append("🤝 Aliados: %s" % ", ".join(c.get("allies", [])))

    lines.append("\n[color=#d9b96d][b]GUERRAS[/b][/color]")
    var has_war := false
    for w in wars:
        if String(w["attacker"]) == owner or String(w["defender"]) == owner:
            has_war = true
            lines.append("⚔ %s — %s" % [String(w["attacker"]), String(w["defender"])])
            lines.append("   Objetivo: %s" % String(w.get("goal_province", "sin objetivo territorial")))
    if not has_war:
        lines.append("En paz")

    lines.append("\n[color=#d9b96d][b]INVESTIGACIÓN[/b][/color]")
    var active := String(c.get("active_research", ""))
    if active == "":
        lines.append("Sin investigación activa")
    else:
        var tech := _tech_def(active)
        lines.append(String(tech.get("name", active)))
        lines.append("Puntos: %.1f / %.1f" % [float(c.get("research_points", 0.0)), float(tech.get("cost", 0.0))])

    lines.append("\n[color=#d9b96d][b]ESTADO[/b][/color]")
    lines.append("Población: %s" % _fmt_pop(_country_population(owner)))
    lines.append("Estabilidad: %.1f" % float(c["stability"]))
    lines.append("Prestigio: %.1f" % float(c["prestige"]))
    lines.append("Producción: %.1f" % float(c["last_output"]))
    lines.append("Militancia: %.1f" % _country_avg_pop_value(owner, "militancy"))

    outliner_text.text = "\n".join(lines)


func _refresh_province_aggregates() -> void:
    for i in range(provinces.size()):
        var p: Dictionary = provinces[i]
        var pops: Array = p["pops"]

        p["population"] = _sum_pop_sizes(pops)
        p["culture"] = _dominant_culture(pops)
        p["unrest"] = _weighted_pop_value(pops, "militancy")
        p["pressure"] = _weighted_pop_value(pops, "political_pressure")

        provinces[i] = p


func _rebuild_map() -> void:
    if political_map != null:
        political_map.set_world(provinces, COUNTRY_COLORS)
        political_map.set_selected(selected_province_index)

    if minimap != null:
        minimap.set_world(provinces, COUNTRY_COLORS)
        minimap.set_selected(selected_province_index)

func _show_province(index: int) -> void:
    if index < 0 or index >= provinces.size():
        return

    selected_province_index = index

    var p: Dictionary = provinces[index]
    var owner: String = String(p["owner"])
    var c: Dictionary = countries[owner]
    var avg_needs: float = _weighted_pop_value(p["pops"], "needs")
    var avg_literacy: float = _weighted_pop_value(p["pops"], "literacy")
    var avg_pressure: float = _weighted_pop_value(p["pops"], "political_pressure")
    var avg_employment: float = _weighted_pop_value(p["pops"], "employment")

    if political_map != null:
        political_map.set_selected(index)
    if minimap != null:
        minimap.set_selected(index)

    var industries: Dictionary = p.get("industries", {})
    var industry_names: Array[String] = []
    for industry_id in industries:
        var def: Dictionary = _industry_def(String(industry_id))
        industry_names.append("%s x%d" % [String(def.get("name", industry_id)), int(industries[industry_id])])

    var industry_text := "Sin industria"
    if not industry_names.is_empty():
        industry_text = ", ".join(industry_names)

    province_panel_text.text = "[font_size=22][b]%s[/b][/font_size]   [color=#b9aa8c]Propietario: %s[/color]\n\n[b]Población[/b]  %s     [b]Cultura[/b]  %s     [b]Recurso[/b]  %s\n[b]Presión[/b]  %.1f     [b]Militancia[/b]  %.1f     [b]Empleo[/b]  %.0f%%\n[b]Necesidades[/b]  %.0f%%     [b]Alfabetización[/b]  %.0f%%\n\n[b]Industria local[/b]\n%s" % [
        String(p["name"]),
        owner,
        _fmt_pop(int(p["population"])),
        String(p["culture"]),
        String(p["resource"]).capitalize(),
        avg_pressure,
        float(p["unrest"]),
        avg_employment * 100.0,
        avg_needs * 100.0,
        avg_literacy * 100.0,
        industry_text
    ]

    var title_node := find_child("SelectedProvinceTitle", true, false)
    if title_node is Label:
        title_node.text = String(p["name"]).to_upper()
    var owner_node := find_child("SelectedProvinceOwner", true, false)
    if owner_node is Label:
        owner_node.text = "%s · %s" % [owner, String(c["government"])]

    detail_text.text = "[font_size=24][b]%s[/b][/font_size]\n[color=#aaaaaa]%s[/color]\n\n[b]Provincia[/b]\nCultura dominante: %s\nRecurso principal: %s\nPoblación: %s\nRiqueza local: %.2f\nNecesidades satisfechas: %.1f%%\nAlfabetización: %.1f%%\nPresión política: %.1f / 100\nMilitancia: %.1f / 100\nEmpleo: %.1f%%\n\n[b]%s[/b]\nGobierno: %s\nTesoro: %.1f\nProducción anual: %.1f\nEstabilidad: %.1f\nPoder militar: %.1f\nPrestigio: %.1f\n\n[b]Situación[/b]\n%s" % [
        String(p["name"]), owner, String(p["culture"]), String(p["resource"]),
        _fmt_pop(int(p["population"])), float(p["wealth"]), avg_needs * 100.0,
        avg_literacy * 100.0, avg_pressure, float(p["unrest"]), avg_employment * 100.0,
        owner, String(c["government"]), float(c["treasury"]), float(c["last_output"]),
        float(c["stability"]), float(c["military"]), float(c["prestige"]),
        "EN GUERRA" if _at_war(owner) else "En paz"
    ]

    _refresh_pops(p)
    _refresh_topbar()
    _refresh_outliner()

func _refresh_pops(p: Dictionary) -> void:
    var lines: Array[String] = []

    lines.append("[font_size=22][b]POPs de %s[/b][/font_size]" % String(p["name"]))
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
            "[b]%s[/b] — %s\nCultura: %s | Religión: %s\nEmpleo: %.0f%% | Necesidades: %.0f%% | Alfabetización: %.0f%%\nRiqueza: %.1f | Presión: %.1f | Militancia: %.1f\nIdeología: %s\nCesta: %s\n" % [
                pop_class,
                _fmt_pop(int(pop["size"])),
                String(pop["culture"]),
                String(pop["religion"]),
                float(pop.get("employment", 1.0)) * 100.0,
                float(pop["needs"]) * 100.0,
                float(pop["literacy"]) * 100.0,
                float(pop["wealth"]),
                float(pop["political_pressure"]),
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
            "[b]%s[/b] — %.2f (%+.0f%%)\nOferta %.1f | Demanda %.1f | Cobertura %.0f%% | %s\n" % [
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
    var pressured_country: String = _country_with_max("political_pressure")
    var unstable_country: String = _country_with_max("militancy")

    var global_needs: float = _world_pop_average("needs")
    var global_literacy: float = _world_pop_average("literacy")
    var global_pressure: float = _world_pop_average("political_pressure")
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
    lines.append("Presión política media: %.1f / 100" % global_pressure)
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
    lines.append("Migraciones internas: %d" % int(stats["migrations"]))
    lines.append("Industrias construidas: %d" % int(stats["industries_built"]))
    lines.append("Tecnologías investigadas: %d" % int(stats["technologies_researched"]))
    lines.append("Alianzas formadas: %d" % int(stats["alliances_formed"]))
    lines.append("Movimientos políticos: %d" % int(stats["political_movements"]))
    lines.append("Crisis diplomáticas: %d" % int(stats["diplomatic_crises"]))
    lines.append("Grandes eventos: %d\n" % int(stats["major_events"]))

    lines.append("")
    lines.append("— Estados destacados —")
    lines.append("Mayor población: %s (%s)" % [biggest_country, _fmt_pop(_country_population(biggest_country))])
    lines.append("Mayor tesoro: %s (%.1f)" % [richest_country, float(countries[richest_country]["treasury"])])
    lines.append("Mayor producción: %s (%.1f)" % [productive_country, float(countries[productive_country]["last_output"])])
    lines.append("Mayor poder militar: %s (%.1f)" % [strongest_country, float(countries[strongest_country]["military"])])
    lines.append("Mayor presión política: %s (%.1f)" % [pressured_country, _country_avg_pop_value(pressured_country, "political_pressure")])
    lines.append("Mayor militancia: %s (%.1f)" % [unstable_country, _country_avg_pop_value(unstable_country, "militancy")])

    summary_text.text = "\n".join(lines)



# -------------------------------------------------------------------
# DESARROLLO, EMPLEO, MIGRACIÓN, DIPLOMACIA Y DATOS
# -------------------------------------------------------------------

func _load_external_data() -> void:
    tech_defs = _load_json_array("res://data/techs.json")
    industry_defs = _load_json_array("res://data/industries.json")
    event_defs = _load_json_array("res://data/events.json")


func _load_json_array(path: String) -> Array:
    if not FileAccess.file_exists(path):
        push_warning("No se encontró " + path)
        return []

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_warning("No se pudo abrir " + path)
        return []

    var parsed = JSON.parse_string(file.get_as_text())
    if parsed is Array:
        return parsed

    push_warning("Formato JSON inválido en " + path)
    return []


func _seed_initial_industries() -> void:
    for i in range(provinces.size()):
        var p: Dictionary = provinces[i]
        var industries: Dictionary = p.get("industries", {})

        if rng.randf() < 0.22:
            industries["textile_mill"] = 1

        p["industries"] = industries
        provinces[i] = p


func _tech_def(tech_id: String) -> Dictionary:
    for item in tech_defs:
        var d: Dictionary = item
        if String(d.get("id", "")) == tech_id:
            return d
    return {}


func _industry_def(industry_id: String) -> Dictionary:
    for item in industry_defs:
        var d: Dictionary = item
        if String(d.get("id", "")) == industry_id:
            return d
    return {}


func _has_tech(country_name: String, tech_id: String) -> bool:
    if tech_id == "":
        return true
    return countries[country_name]["technologies"].has(tech_id)


func _tech_modifier(country_name: String, effect_key: String) -> float:
    var total := 0.0
    var techs: Array = countries[country_name].get("technologies", [])

    for tech_id in techs:
        var d: Dictionary = _tech_def(String(tech_id))
        var effects: Dictionary = d.get("effects", {})
        if effects.has(effect_key):
            total += float(effects[effect_key])

    return total


func _available_techs(country_name: String) -> Array[String]:
    var result: Array[String] = []
    var known: Array = countries[country_name].get("technologies", [])

    for item in tech_defs:
        var tech: Dictionary = item
        var tech_id: String = String(tech.get("id", ""))

        if known.has(tech_id) or year < int(tech.get("year", START_YEAR)):
            continue

        var prereqs: Array = tech.get("prerequisites", [])
        var ready := true
        for prereq in prereqs:
            if not known.has(String(prereq)):
                ready = false
                break

        if ready:
            result.append(tech_id)

    return result


func _research_and_technology() -> void:
    for country_name in countries:
        var name := String(country_name)
        var c: Dictionary = countries[name]

        if not bool(c["alive"]):
            continue

        var literacy: float = _country_avg_pop_value(name, "literacy")
        var magi: int = _country_class_population(name, "Magos")
        var bureaucrats: int = _country_class_population(name, "Burócratas")
        var yearly_points: float = 2.0 + literacy * 7.0 + float(magi + bureaucrats) / 30000.0

        c["research_points"] = float(c.get("research_points", 0.0)) + yearly_points

        var active: String = String(c.get("active_research", ""))
        if active == "" or _has_tech(name, active):
            var available := _available_techs(name)
            if not available.is_empty():
                active = available[0]
                c["active_research"] = active

        if active != "":
            var tech: Dictionary = _tech_def(active)
            var cost: float = float(tech.get("cost", 99999.0))

            if float(c["research_points"]) >= cost:
                c["research_points"] = float(c["research_points"]) - cost
                var known: Array = c["technologies"]
                known.append(active)
                c["technologies"] = known
                c["active_research"] = ""
                c["prestige"] = float(c["prestige"]) + 2.0
                stats["technologies_researched"] = int(stats["technologies_researched"]) + 1
                _log("%s completa la investigación: %s." % [name, String(tech.get("name", active))])

        countries[name] = c


func _employment_mobility_and_industry() -> void:
    for province_index in range(provinces.size()):
        var p: Dictionary = provinces[province_index]
        var owner: String = String(p["owner"])
        var pops: Array = p["pops"]
        var industries: Dictionary = p.get("industries", {})

        var industrial_capacity := 0
        for industry_id in industries:
            var industry: Dictionary = _industry_def(String(industry_id))
            industrial_capacity += int(industry.get("worker_capacity", 0)) * int(industries[industry_id])

        var worker_size := _pop_class_size(pops, "Obreros")
        var industrial_employment: float = 0.65
        if worker_size > 0:
            industrial_employment = clampf(float(industrial_capacity) / float(worker_size), 0.35, 1.0)

        for pop_index in range(pops.size()):
            var pop: Dictionary = pops[pop_index]
            var pop_class: String = String(pop["class"])
            var employment := 0.94

            if pop_class == "Obreros":
                employment = industrial_employment
            elif pop_class == "Mineros":
                employment = 0.96 if ["hierro", "carbón", "cristal arcano"].has(String(p["resource"])) else 0.68
            elif pop_class == "Campesinos":
                employment = 0.96 if ["grano", "madera"].has(String(p["resource"])) else 0.76
            elif pop_class == "Artesanos":
                employment = clampf(0.72 + float(market["ropa"]["price"]) / 10.0 + float(market["herramientas"]["price"]) / 16.0, 0.62, 0.98)

            pop["employment"] = employment
            pops[pop_index] = pop

        p["pops"] = pops

        # Movilidad: campesinos/mineros desempleados pasan a obreros cuando hay plazas.
        var worker_index := _find_pop_index(pops, "Obreros")
        if worker_index >= 0 and industrial_employment > 0.80:
            var source_class := "Campesinos"
            if ["hierro", "carbón", "cristal arcano"].has(String(p["resource"])):
                source_class = "Mineros"

            var source_index := _find_pop_index(pops, source_class)
            if source_index >= 0:
                var source: Dictionary = pops[source_index]
                var target: Dictionary = pops[worker_index]
                var move: int = mini(int(source["size"] * 0.009), 900)

                if move > 0 and float(source.get("employment", 1.0)) < 0.90:
                    source["size"] = maxi(1, int(source["size"]) - move)
                    target["size"] = int(target["size"]) + move
                    target["literacy"] = maxf(float(target["literacy"]), float(source["literacy"]) * 0.92)
                    pops[source_index] = source
                    pops[worker_index] = target

        # Ascenso de obreros alfabetizados hacia clases medias.
        worker_index = _find_pop_index(pops, "Obreros")
        var bureaucrat_index := _find_pop_index(pops, "Burócratas")
        if worker_index >= 0 and bureaucrat_index >= 0:
            var worker: Dictionary = pops[worker_index]
            if float(worker["literacy"]) > 0.48 and float(worker["wealth"]) > 34.0:
                var promote: int = mini(int(worker["size"] * 0.0025), 250)
                if promote > 0:
                    var bureaucrat: Dictionary = pops[bureaucrat_index]
                    worker["size"] = maxi(1, int(worker["size"]) - promote)
                    bureaucrat["size"] = int(bureaucrat["size"]) + promote
                    pops[worker_index] = worker
                    pops[bureaucrat_index] = bureaucrat

        p["pops"] = pops
        provinces[province_index] = p

    _ai_build_industries()


func _ai_build_industries() -> void:
    for country_name in countries:
        var name := String(country_name)
        var c: Dictionary = countries[name]

        if year - int(c.get("last_industry_year", START_YEAR - 10)) < 5:
            continue
        if float(c["treasury"]) < 130.0:
            continue

        var best_industry := ""
        var best_score := -1.0

        for item in industry_defs:
            var industry: Dictionary = item
            var required: String = String(industry.get("required_tech", ""))
            if not _has_tech(name, required):
                continue

            var output_good: String = String(industry.get("output_good", ""))
            if not market.has(output_good):
                continue

            var score: float = float(market[output_good]["price"]) / float(market[output_good]["base_price"])
            if score > best_score:
                best_score = score
                best_industry = String(industry["id"])

        if best_industry == "":
            continue

        var definition := _industry_def(best_industry)
        var cost: float = float(definition.get("construction_cost", 100.0))
        if float(c["treasury"]) < cost + 45.0:
            continue

        var candidate := -1
        var best_workers := -1
        for i in range(provinces.size()):
            if String(provinces[i]["owner"]) != name:
                continue
            var workers: int = _pop_class_size(provinces[i]["pops"], "Obreros")
            if workers > best_workers:
                best_workers = workers
                candidate = i

        if candidate >= 0:
            var p: Dictionary = provinces[candidate]
            var industries: Dictionary = p.get("industries", {})
            industries[best_industry] = int(industries.get(best_industry, 0)) + 1
            p["industries"] = industries
            provinces[candidate] = p
            c["treasury"] = float(c["treasury"]) - cost
            c["last_industry_year"] = year
            countries[name] = c
            stats["industries_built"] = int(stats["industries_built"]) + 1
            _log("%s amplía %s en %s." % [name, String(definition.get("name", best_industry)), String(p["name"])])


func _migration() -> void:
    for country_name in countries:
        var name := String(country_name)
        var worst := -1
        var best := -1
        var worst_score := 999.0
        var best_score := -999.0

        for i in range(provinces.size()):
            var p: Dictionary = provinces[i]
            if String(p["owner"]) != name:
                continue

            var needs: float = _weighted_pop_value(p["pops"], "needs")
            var employment: float = _weighted_pop_value(p["pops"], "employment")
            var pressure: float = _weighted_pop_value(p["pops"], "political_pressure") / 100.0
            var score: float = needs * 0.55 + employment * 0.45 - pressure * 0.20

            if score < worst_score:
                worst_score = score
                worst = i
            if score > best_score:
                best_score = score
                best = i

        if worst < 0 or best < 0 or worst == best or best_score - worst_score < 0.12:
            continue

        if rng.randf() > 0.22:
            continue

        var source: Dictionary = provinces[worst]
        var destination: Dictionary = provinces[best]
        var source_pops: Array = source["pops"]
        var destination_pops: Array = destination["pops"]

        var source_index := _find_pop_index(source_pops, "Obreros")
        if source_index < 0:
            source_index = _find_pop_index(source_pops, "Campesinos")
        if source_index < 0:
            continue

        var pop_class: String = String(source_pops[source_index]["class"])
        var destination_index := _find_pop_index(destination_pops, pop_class)
        if destination_index < 0:
            continue

        var movers: int = mini(int(source_pops[source_index]["size"] * 0.006), 500)
        if movers <= 0:
            continue

        source_pops[source_index]["size"] = maxi(1, int(source_pops[source_index]["size"]) - movers)
        destination_pops[destination_index]["size"] = int(destination_pops[destination_index]["size"]) + movers
        source["pops"] = source_pops
        destination["pops"] = destination_pops
        provinces[worst] = source
        provinces[best] = destination
        stats["migrations"] = int(stats["migrations"]) + 1


func _diplomatic_actions() -> void:
    var names: Array = countries.keys()
    for i in range(names.size()):
        var a := String(names[i])
        for j in range(i + 1, names.size()):
            var b := String(names[j])

            if countries[a]["rivals"].has(b) or countries[b]["rivals"].has(a):
                continue

            var allies_a: Array = countries[a].get("allies", [])
            var allies_b: Array = countries[b].get("allies", [])

            if allies_a.has(b):
                continue

            if int(relations[a][b]) >= 72 and int(relations[b][a]) >= 72 and allies_a.size() < 2 and allies_b.size() < 2:
                if rng.randf() < 0.035:
                    allies_a.append(b)
                    allies_b.append(a)
                    countries[a]["allies"] = allies_a
                    countries[b]["allies"] = allies_b
                    stats["alliances_formed"] = int(stats["alliances_formed"]) + 1
                    _log("%s y %s firman una alianza defensiva." % [a, b])


func _allied_support(country_name: String, enemy: String) -> float:
    var support := 0.0
    var allies: Array = countries[country_name].get("allies", [])

    for ally_value in allies:
        var ally := String(ally_value)
        if ally == enemy or not countries.has(ally):
            continue
        if countries[ally]["allies"].has(enemy):
            continue
        support += float(countries[ally]["military"]) * 0.08

    return minf(support, 18.0)



func _political_movements() -> void:
    for country_name in countries:
        var name := String(country_name)
        var c: Dictionary = countries[name]

        if year < int(c.get("movement_cooldown", START_YEAR)):
            continue

        var pressure: float = _country_avg_pop_value(name, "political_pressure")
        var literacy: float = _country_avg_pop_value(name, "literacy")
        var militancy: float = _country_avg_pop_value(name, "militancy")
        var laws: Dictionary = c.get("laws", {})

        if pressure < 46.0 or literacy < 0.26:
            continue

        if String(laws.get("labor", "sin regulación")) == "sin regulación":
            if rng.randf() < 0.055:
                c["movement_cooldown"] = year + 10
                countries[name] = c
                stats["political_movements"] = int(stats["political_movements"]) + 1
                _log("Un movimiento laboral organizado aparece en %s y exige protección para trabajadores." % name)
                _change_country_pressure(name, 3.0, ["Obreros", "Mineros", "Artesanos"])
                continue

        if String(laws.get("suffrage", "censitario")) == "censitario" and literacy > 0.45:
            if rng.randf() < 0.035:
                c["movement_cooldown"] = year + 12
                countries[name] = c
                stats["political_movements"] = int(stats["political_movements"]) + 1
                _log("Una campaña por ampliar el sufragio gana fuerza en %s." % name)
                if pressure > 60.0 and militancy < 30.0 and rng.randf() < 0.30:
                    c = countries[name]
                    c["laws"]["suffrage"] = "ampliado"
                    c["stability"] = minf(100.0, float(c["stability"]) + 3.0)
                    countries[name] = c
                    _change_country_pressure(name, -8.0, ["Burócratas", "Comerciantes", "Obreros"])
                    stats["reforms"] = int(stats["reforms"]) + 1
                    _major_event("%s amplía el derecho al voto ante la presión de una sociedad cada vez más alfabetizada." % name)


func _change_country_pressure(country_name: String, amount: float, classes: Array = []) -> void:
    for province_index in range(provinces.size()):
        if String(provinces[province_index]["owner"]) != country_name:
            continue

        var pops: Array = provinces[province_index]["pops"]
        for pop_index in range(pops.size()):
            var pop: Dictionary = pops[pop_index]
            if not classes.is_empty() and not classes.has(String(pop["class"])):
                continue
            pop["political_pressure"] = clampf(float(pop["political_pressure"]) + amount, 0.0, 100.0)
            pops[pop_index] = pop
        provinces[province_index]["pops"] = pops


func _diplomatic_crises() -> void:
    if _active_crisis_pressure() or rng.randf() > 0.035:
        return

    var names: Array = countries.keys()
    var best_a := ""
    var best_b := ""
    var worst_relation := 0

    for a_value in names:
        var a := String(a_value)
        for b_value in names:
            var b := String(b_value)
            if a == b:
                continue
            var relation := int(relations[a][b])
            if relation < worst_relation and relation <= -72 and not _at_war(a) and not _at_war(b):
                worst_relation = relation
                best_a = a
                best_b = b

    if best_a == "" or best_b == "":
        return

    stats["diplomatic_crises"] = int(stats["diplomatic_crises"]) + 1
    var backing_a: Array = countries[best_a].get("allies", [])
    var backing_b: Array = countries[best_b].get("allies", [])

    if not backing_a.is_empty() or not backing_b.is_empty():
        _major_event("Una crisis internacional enfrenta a %s y %s; sus aliados movilizan diplomáticos y tropas." % [best_a, best_b])
    else:
        _log("Una crisis diplomática enfrenta a %s y %s, pero ninguna potencia decide intervenir." % [best_a, best_b])

    relations[best_a][best_b] = clampi(int(relations[best_a][best_b]) - 4, -100, 100)
    relations[best_b][best_a] = clampi(int(relations[best_b][best_a]) - 4, -100, 100)


func _active_crisis_pressure() -> bool:
    # Evita crisis internacionales todos los años; usa la fecha del último evento como memoria simple.
    var last := int(event_last_fired.get("__diplomatic_crisis__", -9999))
    if year - last < 8:
        return true
    event_last_fired["__diplomatic_crisis__"] = year
    return false


func _data_driven_events() -> void:
    for item in event_defs:
        var event: Dictionary = item
        var event_id: String = String(event.get("id", ""))

        for country_name in countries:
            var name := String(country_name)
            var key := event_id + "::" + name
            var once: bool = bool(event.get("once", false))

            if once and fired_events.has(key):
                continue

            var cooldown: int = int(event.get("cooldown", 0))
            if year - int(event_last_fired.get(key, -9999)) < cooldown:
                continue

            if not _event_trigger_met(event.get("trigger", {}), name):
                continue

            fired_events[key] = true
            event_last_fired[key] = year
            _apply_event_effects(event.get("effects", {}), name)

            var text_value: String = String(event.get("text", "Evento en {country}.")).replace("{country}", name)
            _major_event(text_value)


func _event_trigger_met(trigger: Dictionary, country_name: String) -> bool:
    if year < int(trigger.get("year_gte", START_YEAR)):
        return false
    if trigger.has("has_tech") and not _has_tech(country_name, String(trigger["has_tech"])):
        return false
    if trigger.has("country_prestige_gte") and float(countries[country_name]["prestige"]) < float(trigger["country_prestige_gte"]):
        return false
    if trigger.has("avg_pressure_gte") and _country_avg_pop_value(country_name, "political_pressure") < float(trigger["avg_pressure_gte"]):
        return false
    if trigger.has("avg_literacy_gte") and _country_avg_pop_value(country_name, "literacy") < float(trigger["avg_literacy_gte"]):
        return false

    if trigger.has("market_good"):
        var good_name := String(trigger["market_good"])
        if not market.has(good_name):
            return false
        if trigger.has("market_availability_lte") and float(market[good_name]["availability"]) > float(trigger["market_availability_lte"]):
            return false

    return true


func _apply_event_effects(effects: Dictionary, country_name: String) -> void:
    var c: Dictionary = countries[country_name]

    if effects.has("prestige"):
        c["prestige"] = float(c["prestige"]) + float(effects["prestige"])
    if effects.has("treasury"):
        c["treasury"] = float(c["treasury"]) + float(effects["treasury"])
    if effects.has("stability"):
        c["stability"] = clampf(float(c["stability"]) + float(effects["stability"]), 0.0, 100.0)

    countries[country_name] = c

    if effects.has("pressure_change"):
        var amount: float = float(effects["pressure_change"])
        for province_index in range(provinces.size()):
            if String(provinces[province_index]["owner"]) != country_name:
                continue
            var pops: Array = provinces[province_index]["pops"]
            for pop_index in range(pops.size()):
                pops[pop_index]["political_pressure"] = clampf(float(pops[pop_index]["political_pressure"]) + amount, 0.0, 100.0)
            provinces[province_index]["pops"] = pops


func _refresh_development() -> void:
    var lines: Array[String] = ["=== DESARROLLO ===", ""]

    for country_name in countries:
        var name := String(country_name)
        var c: Dictionary = countries[name]
        var tech_names: Array[String] = []

        for tech_id in c.get("technologies", []):
            var d: Dictionary = _tech_def(String(tech_id))
            tech_names.append(String(d.get("name", tech_id)))

        var active: String = String(c.get("active_research", ""))
        var active_name := "ninguna"
        if active != "":
            active_name = String(_tech_def(active).get("name", active))

        var industry_count := 0
        for p in provinces:
            if String(p["owner"]) == name:
                var industries: Dictionary = p.get("industries", {})
                for industry_id in industries:
                    industry_count += int(industries[industry_id])

        lines.append("%s" % name)
        lines.append("Tecnologías: %d | Investigación: %s (%.1f pts)" % [tech_names.size(), active_name, float(c.get("research_points", 0.0))])
        lines.append("Industrias: %d | Aliados: %s" % [industry_count, ", ".join(c.get("allies", [])) if not c.get("allies", []).is_empty() else "ninguno"])
        var laws: Dictionary = c.get("laws", {})
        lines.append("Leyes: trabajo %s | sufragio %s | ciudadanía %s" % [
            String(laws.get("labor", "—")),
            String(laws.get("suffrage", "—")),
            String(laws.get("citizenship", "—"))
        ])
        lines.append("")

    development_text.text = "\n".join(lines)


func _save_game() -> void:
    var payload := {
        "version": 1,
        "year": year,
        "seed": current_seed,
        "countries": countries,
        "provinces": provinces,
        "relations": relations,
        "wars": wars,
        "history": history,
        "fired_events": fired_events,
        "event_last_fired": event_last_fired,
        "market": market,
        "market_event_cooldowns": market_event_cooldowns,
        "stats": stats,
        "initial_population": initial_population
    }

    var file := FileAccess.open("user://chronicles_save.json", FileAccess.WRITE)
    if file == null:
        status_label.text = "No se pudo guardar."
        return

    file.store_string(JSON.stringify(payload))
    status_label.text = "Partida guardada."


func _load_game() -> void:
    if not FileAccess.file_exists("user://chronicles_save.json"):
        status_label.text = "No hay partida guardada."
        return

    var file := FileAccess.open("user://chronicles_save.json", FileAccess.READ)
    if file == null:
        status_label.text = "No se pudo cargar."
        return

    var parsed = JSON.parse_string(file.get_as_text())
    if not parsed is Dictionary:
        status_label.text = "Guardado inválido."
        return

    var data: Dictionary = parsed
    year = int(data.get("year", START_YEAR))
    current_seed = int(data.get("seed", 7))
    countries = data.get("countries", {})
    relations = data.get("relations", {})
    fired_events = data.get("fired_events", {})
    event_last_fired = data.get("event_last_fired", {})
    market = data.get("market", {})
    market_event_cooldowns = data.get("market_event_cooldowns", {})
    stats = data.get("stats", {})
    initial_population = int(data.get("initial_population", 0))

    provinces.clear()
    for p in data.get("provinces", []):
        if p is Dictionary:
            provinces.append(p)

    wars.clear()
    for w in data.get("wars", []):
        if w is Dictionary:
            wars.append(w)

    history.clear()
    for entry in data.get("history", []):
        history.append(String(entry))

    rng.seed = current_seed
    status_label.text = "Partida cargada."
    _refresh_province_aggregates()
    _refresh_all()


func _find_pop_index(pops: Array, pop_class: String) -> int:
    for i in range(pops.size()):
        if String(pops[i]["class"]) == pop_class:
            return i
    return -1


func _pop_class_employment(pops: Array, pop_class: String) -> float:
    var index := _find_pop_index(pops, pop_class)
    if index < 0:
        return 0.0
    return float(pops[index].get("employment", 1.0))


func _country_class_population(country_name: String, pop_class: String) -> int:
    var total := 0
    for p in provinces:
        if String(p["owner"]) != country_name:
            continue
        total += _pop_class_size(p["pops"], pop_class)
    return total


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
            "political_pressure":
                value = _country_avg_pop_value(String(country_name), "political_pressure")
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
