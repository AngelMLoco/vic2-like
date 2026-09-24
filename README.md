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
