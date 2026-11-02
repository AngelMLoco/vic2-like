# Chronicles of Aether — Victoria 2-like Fantasy Prototype

Early simulation prototype for a future fantasy grand-strategy game inspired by the systemic side of Victoria 2/GFM.

> This is deliberately **not** the final game architecture or balance. The goal is to answer one question: **can the world generate interesting history by itself?**

## What is in this prototype

- 8 fantasy countries
- 30 provinces on a deliberately abstract test map
- Population, culture, resources, wealth and unrest
- Country treasury, stability, military power and prestige
- Simple production/economic loop
- Minority and economic unrest
- Diplomacy and relations
- Claims and border wars
- Automatic war resolution with casualties and territorial changes
- Condition-driven historical/flavor events
- A generated world chronicle
- Province and country inspection
- Controls for +1 year, +5 years and +20 years

## Run

1. Install **Godot 4.x**.
2. Import this folder as a Godot project.
3. Run the project (F5).

No assets are required.

## Prototype philosophy

The map is intentionally ugly and schematic. The prototype focuses on:

1. world state,
2. interacting systems,
3. emergent consequences,
4. readable history.

If a 20-year hands-off simulation produces wars, reforms, crises, demographic changes and believable chains of consequences, the core idea is worth expanding.

## Next experiments

- POP groups instead of a single population value
- Proper goods market and prices
- Political movements and reforms
- Multi-country crises
- Technology / arcane industrialization
- Event files outside code for moddability
- Real province map and adjacency graph
- Player-controlled diplomacy
- Better war fronts and logistics


## v0.2 — POP Lab

The prototype now models population as POP groups rather than a single province population value.

Each POP has:
- class
- size
- culture
- religion
- literacy
- wealth
- needs satisfaction
- militancy
- ideology

Current classes:
- Campesinos
- Mineros
- Obreros
- Artesanos
- Comerciantes
- Soldados
- Burócratas
- Clérigos
- Aristócratas
- Magos

The yearly loop now connects POPs to:
- production
- tax income
- needs satisfaction
- wealth changes
- literacy growth
- militancy
- unrest
- reforms
- revolts
- war casualties

### Seeds

You can now:
- restart the exact same seed
- enter a custom integer seed
- generate a new random seed

This is important for comparing whether different worlds create meaningfully different histories.

### Simulation summary

The new **Resumen** tab tracks:
- starting and current world population
- needs satisfaction
- literacy
- militancy
- wars
- territorial changes
- revolts
- reforms
- major events
- current demographic/economic/military leaders by raw values

### Suggested test

Run several simulations for 100 years using different seeds.

For each one, look for:
1. different war histories,
2. different social unrest,
3. reforms triggering under different circumstances,
4. POP needs affecting militancy,
5. wars producing demographic damage,
6. conquered cultures becoming more militant.

The goal is not balance yet. The goal is to verify that interacting systems can create different historical trajectories.


## v0.3 alpha — Market Economy Lab

This version starts replacing the abstract POP `needs` value with a real goods market.

### Goods currently simulated

- grain
- wood
- iron
- coal
- clothes
- tools
- arcane crystal

Every year the simulation now calculates:

1. primary production from province resources,
2. manufactured clothes and tools,
3. global POP demand,
4. market supply and demand,
5. dynamic prices,
6. market availability,
7. whether each POP can afford its consumption basket,
8. resulting needs satisfaction,
9. wealth changes,
10. militancy and political pressure.

### Social rebalancing

Population growth is deliberately much slower than v0.2.

Poor needs satisfaction can now:
- reduce population growth,
- reduce wealth,
- increase militancy,
- cause disturbances,
- trigger labor reforms.

### War rebalancing

Countries no longer declare wars simply because relations are bad.

A war now needs a recognizable cause:
- territorial claim,
- historical rivalry,
- access to a strategic resource during a shortage.

Countries also consider:
- treasury,
- stability,
- war exhaustion,
- peace cooldown,
- relative military power.

War now damages production, lowers incomes, creates casualties and increases war exhaustion.

### Market tab

The new **Mercado** tab shows for every good:
- current price,
- price change from base,
- supply,
- demand,
- market coverage,
- shortage / tension / oversupply state.

### What to test

Run several seeds for 100 years.

Look for chains such as:

```
war
→ reduced production
→ commodity shortage
→ higher prices
→ lower POP needs satisfaction
→ higher militancy
→ unrest or reform
```

Also compare:
- population growth versus v0.2,
- wars per century,
- number of reforms/revolts,
- which goods repeatedly become scarce,
- whether strategic-resource shortages affect wars.

The values are not considered balanced yet. This phase is specifically about testing whether economic and social systems can create believable historical consequences.


## v0.3.1 — Social Balance

This patch focuses on making the simulation less extreme and more historically readable.

### Social conflict now has stages

Instead of every angry province jumping directly into revolt:

```
discontent
→ protest
→ strike / disturbances
→ rebellion
```

Each province now has social memory and a cooldown after a major social event, preventing the same province from firing unrest every year.

### Rebalanced economy and militancy

- primary production increased moderately
- clothes/tools production increased
- POP purchasing power increased
- militancy rises more slowly
- satisfied POPs calm down more noticeably
- cultural minorities still add pressure, but less explosively
- war exhaustion still affects social tension

### Reform pacing

Labor reform now:
- requires higher militancy,
- requires literacy,
- requires poor needs satisfaction,
- has a probability gate,
- has a long reform cooldown.

This should prevent every country from reforming immediately.

### War pacing

Wars still require an actual cause, but:
- historical rivalry can trigger sooner,
- declaration probability is higher,
- postwar cooldown is slightly shorter.

Goal: avoid both extremes — neither constant battle royale nor a century of peace.

### 100-year target zone

These are not final balance goals, only a useful test range:

- average needs satisfaction: roughly 65–85%
- average militancy: roughly 10–35
- protests: visible but not constant
- strikes/disturbances: occasional
- rebellions: rare
- reforms: a handful
- wars: several per century, with recognizable causes

If different seeds land in different parts of this range and produce different histories, the simulation is behaving more like a world and less like a scripted demo.


## v0.3.2 — Social Transmission & War Outcomes

This patch keeps the v0.3.1 economy mostly intact and focuses on two missing links:

### 1. Social shocks now target the classes that depend on the scarce good

Examples:
- grain shortages hit peasants, workers, miners and soldiers harder
- tool shortages hit miners, workers and artisans harder
- arcane crystal shortages hit mages especially hard

Shortage crises can now directly reduce wealth and raise militancy in the affected POPs.

### 2. Wars now produce outcomes that match their cause

- territorial-claim wars try to transfer the claimed province if the attacker wins
- strategic-resource wars try to transfer a province with that resource
- decisive historical-rivalry wars can sometimes force a territorial concession
- wars without border changes now transfer reparations instead of ending with no consequence

### Social tuning

The simulation now aims for visible but not constant conflict:
- protests should be common enough to appear in a century
- strikes should be less common
- rebellions should remain rare

### UI cleanup

Large BBCode bold/font-size tags were removed from dynamic RichText labels because they were rendering as visually duplicated headings on some Godot configurations.


## v0.4 — Grand Strategy Core

This milestone connects the major prototype systems that were still missing from the roadmap.

### Employment, unemployment and social mobility

POPs now have an employment rate. Employment depends on province resource, class and industrial capacity.

The simulation can now move population between classes:
- underemployed peasants/miners can become industrial workers,
- educated and wealthier workers can promote into bureaucracy,
- unemployment lowers income and raises political pressure.

### Industry

Provinces can own industry levels. AI countries can construct industry when they have:
- enough treasury,
- the required technology,
- a market incentive.

Current data-driven industries:
- textile mills,
- toolworks,
- arcane workshops.

Factories now consume strategic inputs and add to market demand.

### Migration

POPs can migrate internally from weak provinces toward provinces with better:
- employment,
- needs satisfaction,
- political conditions.

### Technology

Technology definitions live in `data/techs.json`.

Countries generate research points from literacy, mages and bureaucrats, automatically choose available technologies and unlock bonuses for:
- agriculture,
- mining,
- education,
- industry,
- logistics,
- political-pressure decay.

### Politics and laws

Countries now track basic laws:
- labor regulation,
- suffrage,
- citizenship,
- magic regulation.

Political pressure can create organized movements. Labor and suffrage movements can produce reforms, while reforms can calm some classes and anger others.

### Diplomacy and crises

Countries can form defensive alliances when relations are high.

Allies provide limited military support in war calculations.

International crises can emerge between highly hostile countries, with alliance networks making those crises more consequential.

### War goals and logistics

Wars now store their precise objective at declaration time:
- claimed province,
- strategic-resource province,
- historical rivalry.

If the attacker wins a claim/resource war, the peace system resolves the stored objective instead of trying to rediscover it later.

Technology can also improve logistics and therefore combat effectiveness.

### Data-driven events

Generic events now live in `data/events.json`.

The event engine currently supports triggers such as:
- year,
- technology,
- prestige,
- average literacy,
- average political pressure,
- market availability.

Effects can modify:
- prestige,
- treasury,
- stability,
- political pressure.

This is the foundation for future GFM-style content without hard-coding every event into the engine.

### Save / load

The prototype now has **Guardar** and **Cargar** buttons.

The save is written to Godot's `user://chronicles_save.json` and stores the simulation state.

### Development tab

A new **Desarrollo** tab shows each country's:
- researched technologies,
- active research,
- research points,
- industry count,
- allies,
- laws.

### Repository stability

`.gitattributes` normalizes Godot text files to LF and `.gitignore` excludes generated `.uid` files to avoid recurring Windows line-ending conflicts.

## Prototype boundary

v0.4 is intended to complete the **simulation-core prototype**, not final production content.

Still intentionally placeholder/prototype:
- abstract tile map instead of final geographic map,
- minimal UI/art,
- abstract war resolution rather than final battle presentation,
- small content catalogs,
- AI heuristics are simple,
- balance is experimental.

Those are production/content tasks built on top of the now-connected simulation core rather than missing foundational systems.


## v0.5 — Victoria-style visual layer

The laboratory grid UI has been replaced by a playable grand-strategy presentation.

### Main screen

- ornate dark/brass top resource bar
- treasury, literacy, military power and current research
- date and time-advance controls
- left-side state menu
- central political map
- right-side outliner
- selected-province panel along the bottom
- strategic minimap
- floating information window for population, market, development, chronicle and summary

### Political map

The map is generated in Godot and remains tied to simulation state rather than being a static image.

It currently contains:
- 30 clickable provinces
- fantasy-continent layout
- country political colors
- province borders
- country labels
- province names
- simple terrain/resource symbols
- hover and selected-province states
- automatic recoloring after territorial changes
- compact minimap using the same live ownership data

The final geographic map can later replace this schematic map without changing the underlying simulation model.
