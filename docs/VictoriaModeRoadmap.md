# Segunda versión — Hoja de ruta

Filosofía: **Victoria II como esqueleto → Chronicles of Aether como juego final.**
Mecánicas y organización funcional inspiradas en Victoria II / HoD (y la filosofía de contenido
de GFM), con código, datos, gráficos y geografía propios (Natural Earth, dominio público).

## Estado por fase

| Fase | Contenido | Estado |
|---|---|---|
| 0 | Auditoría, checkpoint git (`backup/pre-victoria-mode`, tag `checkpoint-pre-victoria-mode`), legacy aislado en `src/legacy` + `data/legacy` | ✅ |
| 1 | Menú principal (Nuevo / Cargar / Opciones / Salir) y selector de modo | ✅ |
| 2 | Mapamundi: 2.922 provincias, 1.060 estados, 389 zonas marítimas, 146 lagos; fronteras de país/estado/provincia/costa; cámara; minimapa; 12 mapmodes activos + 6 previstos | ✅ |
| 3 | Selección de nación estilo Victoria, ranking GP/secundarias, JUGAR | ✅ |
| 4 | Datos base: 89 naciones, 107 culturas, 18 religiones, cores, RGOs, terrenos | ✅ (base) |
| 5 | POPs: modelo completo, necesidades vida/diario/lujo, empleo y paro, promoción/democión (reglas en datos), migración interna e internacional, crecimiento, alfabetización, conciencia, militancia, ideología, issues | ✅ (M2) |
| 6 | Economía: RGO, 49 bienes, fábricas por partición de estado, artesanos, capitalistas, mercado interno→esfera(API)→mundial, presupuesto completo, deuda, banco, aranceles, stockpile | ✅ (M2) |
| 7 | Política: partidos por plantilla, restricciones de gobierno, elecciones con POPs, cámara alta, 12 reformas por niveles, movimientos (organización/radicalismo) | ✅ (M2) · rebeldes armados ⏳ M3 |
| 8 | Tecnología: 26 tecnologías en 5 ramas, investigación, 16 inventos, `magic_unlocked` | ✅ (M2) · magia ⏳ M4 |
| 9 | Diplomacia: relaciones, alianzas, garantías, acceso militar, treguas, influencia, esferas (conectadas al mercado) | ✅ (M3) · crisis ⏳ |
| 10 | Ejército físico: brigadas ← Soldier POP, movimiento por adyacencia, supply real, attrition, generales | ✅ (M3) |
| 11 | Guerra: CB data-driven sobre estados, justificación, ocupación, warscore con desglose, wargoals, paz | ✅ (M3) |
| 12 | Armada: flotas en zonas marítimas, transporte real, bloqueos (mercado), combate naval | ✅ (M3) |
| — | Rebeldes armados a partir de movimientos políticos | ✅ (M3) |
| 13 | Eventos/decisiones GFM-like (scripted + condicionales, cadenas, flags) | ⏳ |
| 14 | Pulido: tooltips, ledger, rendimiento, saves | ⏳ |

## Milestone 1 (actual) — "esto es la base correcta"

Hecho: menú, selector de modo, mapamundi real con países/estados/provincias, fronteras, colores
nacionales, zoom, paneo, minimapa, mapmodes, selección de país desde el mapa, ranking, pantalla
de inicio, botón JUGAR, barra superior con 8 pestañas, panel de provincia, fecha año 136,
pausa y velocidades 1–5, guardado/carga con `save_version`.

Placeholders conscientes del milestone 1:
* Presupuesto simplificado (impuestos por estrato desde POPs reales; aranceles/deuda/banco a 0).
* Ejército y flota son recuentos (brigadas/barcos por país), aún no unidades en el mapa.
* Las pestañas Tecnología, Comercio, Diplomacia muestran datos reales disponibles y botones
  deshabilitados con la fase en la que se activan.
* Ideología de POPs inicial por estrato; militancia/conciencia constantes.
* Nombres de provincias: ciudades reales de Natural Earth (temporal, el mapa se sustituirá).

## Milestone 2 — completado

Población, economía, política y tecnología funcionan de forma sistémica (ver Architecture → «Milestone 2»).
Placeholders que quedan: esferas sin miembros (la API de mercado de esfera existe), rebeldes armados
(los movimientos marcan `rebel_risk`), mantenimiento militar real (solo salarios y reserva de bienes),
bancarrota, IA política/económica mínima, contenido y nombres de partidos genéricos.

## M2.11 y Milestone 3 — completados

* M2.11: rendimiento (agregados por cubos, escalonado), control de la industrialización, auditoría monetaria,
  apoyo conservador a reformas según militancia.
* M3: diplomacia, influencia y esferas, ejércitos y brigadas vinculadas a Soldier POPs, suministro y desgaste,
  líderes, combate con resolver sustituible, guerra/CB/justificación/ocupación/warscore/paz, armada con
  transporte y bloqueo, rebeldes armados, IA diplomática/militar/naval, UI de Diplomacia y Militar, ventana de
  guerra y paz, contadores en el mapa, mapmodes militar/esferas/rebelión/suministro, guardado v3.

Placeholders conscientes: sin cartas (solo la interfaz VBattleResolver), sin crisis diplomáticas profundas,
sin sistema colonial, IA sencilla (sin frentes), selección rectangular de ejércitos no implementada (Mayús+clic
añade a la selección), ríos sin datos (el resolver ya admite battle.river), naciones liberables solo si existe
una nación latente sin provincias.

## Siguiente paso (milestone 4)

Eventos y decisiones GFM-like (scripted + condicionales, cadenas, flags), contenido de fantasía en capas y el
despertar mágico (GLOBAL_MAGIC_ACTIVATED con ramas por nación).

## (histórico) Previsto para el milestone 3

Diplomacia (relaciones, alianzas, Grandes Potencias, influencia, esferas reales que usen la capa de mercado),
ejércitos físicos con Soldier POPs, movimiento, supply/attrition, generales, guerra (CB, justificación,
ocupación, warscore, wargoals, paz), armada (flotas, transporte, bloqueos, combate naval) y facciones rebeldes.

## (histórico) Siguiente paso previsto tras el milestone 1

1. `economy/`: VMarketSystem (precios, oferta/demanda, interno→esfera→mundial),
   VProductionSystem (RGO por provincia, fábricas por instancia de estado, artesanos).
2. `population/`: necesidades life/everyday/luxury con compra real, empleo, promoción/democión, migración.
3. Presupuesto completo (ingresos/gastos reales, deuda, stockpile).
4. `politics/`: partidos por país, elecciones, cámara alta, reformas por niveles (datos en `reforms/`).
5. `technology/`: árbol data-driven + inventos.
