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
| 13 | Eventos/decisiones GFM-like (scripted + condicionales, cadenas, flags) | ✅ (M4: motor + vertical slice) |
| 14 | Pulido: tooltips, ledger, rendimiento (M3.1 ✅ parcial), saves | ⏳ |

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

## M3.1 — Pasada de arquitectura de rendimiento — completada

Índices persistentes de unidades, versión de acceso, caché de relaciones bélicas, caché de rutas, regiones de
acceso, presupuesto diario de A*, IA estratégica/táctica, warscore/bloqueo/asedios orientados a eventos,
suministro y refuerzo con cachés, y menos operaciones por POP en población, producción, movilidad y política.
Benchmark fijo (`tests/VictoriaPerformanceBenchmark`): de 18,6 s a 10,5 s por año headless (−43 %); el pico
diario baja de 367 ms a 87 ms. El objetivo de < 8 s/año **no se ha alcanzado**: el coste restante es el modelo
de POPs como diccionarios en GDScript (ver Testing → M3.1).

## M3.2 — Almacén de POPs y estabilidad política — completada (rendimiento al 97 % del objetivo)

POPs en estructura de arrays (`VPopStore`, ids numéricos, lista libre, fusión, alias de ids, enlaces de
Soldier POP en O(1)), guardado v4 columnar, sistemas calientes sin diccionarios por POP, diagnóstico de
militancia por componentes, relajación proporcional de militancia y conciencia, reforma de subsidio de paro con
efecto sobre la militancia por paro y movimientos que se enfrían si no crecen. De 10,5 a 8,2 s por año.
El objetivo de < 8 s **no se ha alcanzado**; el informe sobre C# está en Testing → M3.2 y queda pendiente
de decisión.

## Milestone 4 — Eventos, decisiones y despertar mágico — completado (vertical slice)

* **Motor de eventos data-driven:**
  * condiciones compiladas y efectos validados;
  * ámbitos global, nación, estado y provincia;
  * cadencias y ganchos on_action;
  * MTTH determinista, `once`, cooldown y presupuesto anti-spam;
  * cola de ventanas del jugador e IA de opciones;
  * follow-ups y crónica.
* **Decisiones** con visibilidad, disponibilidad con motivo, coste, cooldown e IA, integradas en Política.
* **Estado con ámbito:** banderas de nación, provincia y estado, variables y modificadores temporales de nación
  y de provincia (en VModifiers).
* **Contenido:** 53 eventos, entre ellos cadenas política, económica, diplomática y militar, 5 líneas
  nacionales, eventos emergentes y sistémicos, y 10 eventos mágicos. 11 decisiones.
* **Despertar mágico** definido en datos (GLOBAL_MAGIC_ACTIVATED), con ramas por nación sobre `magic_branches`
  (perfiles PROTOTYPE).
* **Capa mágica:**
  * 8 tecnologías y 4 inventos;
  * cadena de 4 bienes y 3 fábricas;
  * yacimientos (capa secundaria, no sustituye el RGO);
  * magos como POP real;
  * hooks militares y la unidad `arcane_support`;
  * debate político de regulación.

Pendiente (no es de este milestone): lore final del despertar, escuelas de magia definitivas, combate con
cartas, arte de eventos (el motor ya resuelve `art_key`), crisis diplomáticas profundas, personajes y dinastías.

## Milestone 5 — Equilibrio fantástico, marco de lore y contenido — completado

* **Decisión de rendimiento:** no se migra a C# ni a GDExtension. El objetivo práctico pasa a ser < 10 s/año
  en el benchmark de 10 años.
* **Magos con curva estable** (`VMageModel`). Crecen hacia la capacidad que la sociedad sostiene, no hay un
  tope global. Hay empleo real (fábricas mágicas, academias, administración, ejército y práctica privada),
  paro y crisis de magos, degradación del exceso, fuga de cerebros entre naciones y emigración forzada por
  eventos.
* **Política mágica real:** la reforma `magic_regulation` (Prohibida, Tolerada, Licenciada, Promovida, Control
  estatal), con postura por ideología en los datos, apoyo en la cámara según esa postura e IA trimestral.
  Las religiones tienen actitud mágica y las culturas, tradición mágica (valores PROTOTYPE).
* **Academias sistémicas:** capacidad, promoción, plazas de docencia e investigación pagadas con el
  presupuesto de educación, e investigación arcana.
* **Diagnóstico** de militancia y conciencia por componentes (incluidos eventos, magia y modificadores
  temporales), con promedios acumulados.
* **Marco de lore:**
  * paquetes de contenido `core` / `prototype` / `fantasy`;
  * espacios de nombres de eventos;
  * escenarios / bookmarks;
  * historia inicial ampliada (provincias, rivales, tecnologías, reformas, banderas, variables, modificadores,
    ramas mágicas);
  * biblia de lore con esquema y plantillas (`docs/LoreBibleSchema.md`);
  * ramas mágicas con nivel y sendas, y esquema de escuelas.
* **Contenido:** 109 eventos (56 nuevos) en cadenas de varias etapas: guerra, economía, sociedad,
  migración, religión y sociedad mágica. Reaccionan al estado real y recuerdan las decisiones con banderas.
  Hay 14 decisiones.
* **Crónica:** historia nacional por categorías, historia emergente desde on_action y filtros en la interfaz.
* **Arte:** manifiesto de 24 categorías visuales con dirección de óleo del XIX (sin generar imágenes).
* **Guardado v6.**

Pendiente (no es de este milestone):

* lore definitivo de Chronicles of Aether (lo aporta el autor);
* mapa de fantasía;
* escuelas de magia finales;
* personajes y dinastías;
* combate con cartas;
* crisis internacionales completas;
* colonización profunda;
* ilustraciones (el manifiesto ya describe los encargos).

## M5.5 — Economía de largo plazo y transición industrial — completada

* **Diagnóstico económico** (`VEconomyDiagnostics`, solo pruebas) y motivos de no inversión.
* **Desarrollo rural (RGO):** separa tamaño y eficiencia, lo financian aristócratas o el Estado y tiene límite
  por provincia.
* **Inversión por capacidad:** proyectos privados en paralelo según tamaño, capitalistas y capital;
  capacidad estatal propia con programa contra el paro; duplicados por estado y tipo; plazas de fábrica
  por estado definidas en datos; puntuación con escasez, tendencia, paro y urbanización; saturación mundial;
  subvenciones temporales; crecimiento gradual.
* **Economía mágica con consumidores reales:** academias que consumen reactivos e industrias corrientes que
  usan componentes y reactivos. Hay fábricas mágicas sin forzarlas (18 en el año 100).
* **Transición demográfica**, salarios sin dinero impreso y consumo de la riqueza.
* **Resultado a 100 años:** paro del 31 % al 10,8 %, necesidades vitales de 0,57 a 0,81 y riesgo rebelde de
  50/85 a 31/86.
* **Pendiente:** deflación nominal tardía (precios hacia el suelo tras unos 70 años) y riesgo rebelde aún en
  un tercio de las naciones a 100 años, ligado a la conciencia y no a la economía.

## M5.6 — Demanda, precios y madurez política — completada

* **Liquidación de compras:** lo pagado por bienes que no llegaron vuelve a los POPs compradores. Era la
  causa raíz de la deflación tardía: el dinero se destruía.
* **Demanda por renta (Engel)** con elasticidad por nivel y saturación.
* **Utilización del RGO** según el precio relativo y el exceso de oferta mundial.
* Las fábricas en pérdidas con salarios recortados ya cierran.
* **Conciencia ≠ revuelta:** niveles presión, agitación y riesgo. El riesgo exige partidarios militantes;
  el cauce político frena la radicalización.
* **Empleo estatal funcional:** clero, burócratas, soldados y oficiales según educación, administración y
  ejército real.
* **Resultado a 100 años (normal):**

  | Métrica | Antes | Después |
  |---|---|---|
  | Mediana de precios | 0,34 | 1,04 |
  | Bienes en el suelo | 15/43 | 3/43 |
  | Naciones con riesgo de revuelta | 31 | 2 |
  | Facciones | 65 | 20 |
  | Empleo estatal | 108 M | 68 M |

* **Pendiente:**
  * paro del 14 % (artesanos con un 40 % de paro);
  * excedentes de bienes militares y mágicos;
  * topes de reforma por tipo de gobierno, que bloquean el cauce político en los Estados absolutistas.

## Siguiente paso (milestone 6)

* Introducir el lore definitivo en el paquete `fantasy`: mundo, eras, naciones, religiones con su actitud
  mágica y culturas con su tradición.
* Mapa de fantasía y escenario de la Era I.
* Primeras cadenas nacionales `country.<tag>.*` y regionales.
* Generar las 24 ilustraciones del manifiesto.
* Escuelas de magia sobre `magic_schools.json` y `paths`.

## (histórico) Siguiente paso previsto tras M4 (milestone 5)

* Contenido: más cadenas GFM-like, arte de eventos y el lore definitivo del despertar.
* Mapa: el mapa de fantasía definitivo.
* Combate con cartas sobre `VBattleResolver`.
* Equilibrar la economía mágica.

## (histórico) Siguiente paso previsto tras M3 (milestone 4)

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
