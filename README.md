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
