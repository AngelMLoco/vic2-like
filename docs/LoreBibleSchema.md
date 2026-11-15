# Biblia de lore — esquema (Chronicles of Aether)

Este documento describe **cómo introducir el lore definitivo** en el juego. No contiene lore: el mundo, sus
naciones, religiones y la historia de la magia los aporta el autor.

## Dónde va cada cosa

El motor separa tres capas de contenido (`data/victoria_mode/content/`):

| Paquete | Contenido | Estado |
|---|---|---|
| `core/` | Eventos sistémicos reutilizables (`core.*`, `magic.*`), decisiones, modificadores, plantillas de crónica y manifiesto de arte. Sin naciones concretas. | Activo |
| `prototype/` | Contenido **temporal** de la geografía de pruebas (Tierra, año 136): cadenas `country.<tag>.*` y perfiles de ramas mágicas. | Activo solo en el escenario de prototipo |
| `fantasy/` | Chronicles of Aether: biblia de lore, eventos nacionales y regionales definitivos. | Vacío |

Un escenario elige sus paquetes (`data/victoria_mode/scenarios/scenarios.json` → `content_packs`). El escenario
definitivo cargará `["core", "fantasy"]` y no cargará `prototype`.

Hay dos tipos de datos de lore:

1. **Datos jugables.** Países, culturas, religiones, mapa, historia inicial, eventos y decisiones. Viven en sus
   JSON propios y en el archivo de historia del escenario, y son los que simula el juego.
2. **Biblia de lore** (`content/fantasy/lore/*.json`). Es la referencia narrativa (origen de un país, doctrina
   de una religión, reglas de la magia, conflictos pasados, guion de cadenas). Se valida al cargar y queda en
   `gs.lore`, pero **no simula nada**. Sirve para que las cadenas, la crónica y las herramientas tengan una
   fuente única de verdad.

## Formato de la biblia

Cada archivo es `{"lore_type": "<tipo>", "entries": [ … ]}`. Las plantillas vacías están en
`content/fantasy/lore/_templates/`: se copian a `content/fantasy/lore/` y se rellenan. El cargador ignora
`_templates/`.

| `lore_type` | Campos obligatorios | Campos recomendados |
|---|---|---|
| `world` | id, name | premise, tone, themes |
| `era` | id, name, start_year | end_year, summary, scenario (bookmark asociado) |
| `calendar` | id, name, months | era_suffix |
| `continent` | id, name | climate, summary |
| `region` | id, name, continent | states (ids del mapa definitivo), summary |
| `country` | id, name, origin | tag, government, cultures, religions, rivals, allies, historical_claims, magic_branches |
| `magic` | id, name, rules | origin, social_perception, military_implications |
| `magic_institution` | id, name, kind | country, founded, summary (kind: academy, order, guild, church, state) |
| `religion` | id, name, magic_attitude | doctrine, holy_sites |
| `culture` | id, name, group | magic_tradition, relations, history |
| `conflict` | id, name, sides | start_year, end_year, outcome, legacy |
| `event_chain` | id, name, stages | endings |
| `character` | id, name | country, role, born, traits, dynasty (FUTURO: aún no se simulan personajes) |
| `dynasty` | id, name | country, founded, members (FUTURO) |

Valores cerrados:

* `magic_attitude`: `sacred`, `accepted`, `regulated`, `suspicious` o `heretical`.
* `magic_tradition`: `strong`, `common`, `rare` o `none`.

Un campo obligatorio ausente, una actitud no válida o un id repetido producen un error de datos con el archivo
y la entrada.

## Del lore a los datos jugables

| Concepto de lore | Dato jugable |
|---|---|
| Actitud de una religión ante la magia | `religions.json` → `magic_attitude`. Modula la formación de magos y la tensión religiosa. |
| Tradición mágica de una cultura | `cultures.json` → `groups[].magic_tradition` o `cultures[].magic_tradition` |
| Capacidad mágica de un país | `country.magic_branches` (nivel por rama) |
| Escuelas o sendas de magia | `magic_branches.<rama> = {"level": n, "paths": ["<escuela>"]}` y `magic/magic_schools.json`. El nivel mide capacidad; la escuela es la senda concreta. |
| Estado inicial | Archivo de historia del escenario (ver *Historia inicial*) |
| Cadenas narrativas | `content/fantasy/events/*.json` con espacio de nombres `country.<tag>.*` o `region.<id>.*` |
| Ilustraciones | `art` de cada evento → categoría del manifiesto de arte |

## Espacios de nombres de eventos

| Espacio de nombres | Uso |
|---|---|
| `core.economy.*`, `core.politics.*`, `core.society.*`, `core.religion.*`, `core.war.*`, `core.diplomacy.*`, `core.migration.*`, `core.technology.*` | Eventos sistémicos de cualquier mundo |
| `magic.world.*`, `magic.social.*`, `magic.economy.*`, `magic.politics.*`, `magic.military.*` | La magia como fenómeno sistémico |
| `country.<tag>.*` | Cadenas nacionales (en el paquete del mundo correspondiente) |
| `region.<id>.*` | Cadenas regionales |

## Historia inicial (escenario)

El archivo `history` del escenario declara el estado de partida. Todo es opcional:

```json
{
 "start_date": {"year": 1, "month": 1, "day": 1},
 "flags": ["FLAG_GLOBAL"],
 "provinces": {"123": {"owner": "AAA", "controller": "AAA", "cores": ["AAA", "BBB"]}},
 "relations": [["AAA", "BBB", -80]],
 "alliances": [["AAA", "CCC"]],
 "rivals": [["AAA", "BBB"]],
 "wars": [{"name": "…", "attackers": ["AAA"], "defenders": ["BBB"], "start": {"year": 0, "month": 9, "day": 1}}],
 "countries": {
  "AAA": {"government": "…", "capital": 123, "literacy": 0.3, "prestige": 20, "treasury": 5000,
          "brigades": 18, "ships": 10, "factory_levels": 6,
          "technologies": ["…"], "inventions": ["…"], "reforms": {"voting": 1},
          "flags": ["…"], "variables": {"…": 1}, "modifiers": [{"id": "…", "months": 0}],
          "magic_branches": {"military": {"level": 2, "paths": ["…"]}}}
 }
}
```

Pendiente de futuros milestones: la composición de población por país, las fábricas concretas por estado y
los personajes.

## Eras y marcadores

`scenarios.json` lista los escenarios (id, nombre, era, historia y paquetes). Las eras se describen en la
biblia (`era`). Para añadir la Era II basta con crear otro archivo de historia y otra entrada de escenario: el
motor ya no asume el año 136.
