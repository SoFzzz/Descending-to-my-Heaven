# Descending to my Heaven — Documento de Diseño

- **Fecha:** 2026-10-10
- **Equipo:** 3 personas, dedicación completa durante 7 días: Paula Sofia Gonzalez Zambrano, David Alejandro Aza Jojoa y Stehven Alexander Obando Cordoba
- **Motor:** Godot 4.7.2 (GDScript, renderizador Compatibility)
- **Objetivo de éxito:** un juego 3D lowpoly estilo PSX, jugable de principio a fin, donde se puede **derrotar a los 3 jefes** y ver el final. La inteligencia artificial de los enemigos debe ser demostrable y explicable.

---

## 1. Visión

*Boss rush* de acción en tercera persona con combate tipo soulslike. Kaelen, con armadura robada y un mandoble, asciende un templo de 3 pisos sobre una isla flotante. Cada piso es un enfrentamiento contra un jefe acompañado de esbirros. Al vencer al tercer jefe encuentra a Elysia, su amada.

Estética: fantasía oscura PSX (baja resolución interna, texturas con filtro *nearest*, niebla de distancia, paleta apagada).

## 2. Alcance

### Dentro (obligatorio)
- Kaelen: moverse, cámara orbital, fijar objetivo (lock-on), ataque ligero (combo de 2-3 golpes), rodar con invulnerabilidad, estamina, recibir daño, morir.
- 3 enfrentamientos de jefe + esbirros.
- Sistema de jefe único reutilizable (vida, 3-4 ataques con aviso, fase 2 al 50%).
- IA de esbirros, IA de selección de ataques del jefe y Orquestador (sección 8).
- Vida máxima decreciente por nivel: 100% → 70% → 40%.
- Muerte → reaparece al inicio del enfrentamiento actual; el jefe se reinicia.
- Escena final con Elysia → créditos.
- Menú principal y menú de pausa (sección 10).
- Efectos de sonido y música (sección 11).
- HUD: vida, estamina, barra del jefe.
- Pantalla de créditos con todas las licencias.

### Opcional (solo si sobra tiempo)
- Menú de opciones (volumen, sensibilidad de cámara, pantalla completa).
- Parry.
- Efecto visual por jefe derrotado (filtro de color sobre el mundo).

### Fuera
- Escalada, puntos débiles, mecánicas de ruptura.
- Inventario, objetos, niveles de personaje, guardado entre sesiones.
- Diálogos ramificados; voces.

## 3. Reparto de personajes y assets

| Rol | Modelo (D:\ASSETS-PRUEBA) | Rig / animación |
|---|---|---|
| Kaelen | `low-poly-woman-knight` (modelo final, sin modelado propio por tiempo) | Sin rig → Mixamo (auto-rig + animaciones) |
| Elysia | `ancient-elf-lady-psx` (744 triángulos, modelo final) | Sin rig ni animaciones (decisión 2026-10-12): Mixamo deforma su vestido de una pieza y el pelo largo. Modelo estático en pose de reposo; en Godot un `Tween` de respiración (sube/baja ~2 cm en bucle) y giro hacia Kaelen; el abrazo se resuelve con fundido de cámara |
| Arma de Kaelen | `demonic weapons pack/greatsword` (ya tiene .glb) | Adjunta al hueso de la mano (`BoneAttachment3D`) |
| Jefe 1 | `bonedragon` | Ya trae rig con skin (~70 huesos), sin animaciones; animaciones creadas en Blender + movimiento procedural |
| Esbirros 1 | `Skeleton` | Sin rig → Mixamo |
| Élite 1 | `knight__ps1_psx` | Trae rig propio (26 huesos) solo con `Idle` → re-rig en Mixamo |
| Jefe 2 | `blackhorn` (Blackhorn of the Shattered Peaks; reemplaza a Dead Oath Hunter desde 2026-10-14) | Rig Mixamo con 8 animaciones propias (idle, burla, rugido, caminar, correr, embestida, zarpazo con salto, golpe al suelo) + `hurt`/`death` tomadas de otro personaje Mixamo; exportado a 3.20 m con `_source/tools/export_multi_action.py -- blackhorn` |
| Élite 3 | `straw_reaper` (The Straw Reaper, imaginais) | Rig Mixamo; 8 clips nombrados (`idle`, `walk`, `lurch`, `attack`, `attack_2`, `combo`, `hurt`, `death`). Sustituye al Aura Battler como élite de la arena 3 (2026-10-15) |
| Esbirros 2 | `Plague Arcanist` | Rig Mixamo + 10 animaciones (nombres genéricos, hay que identificarlas y renombrarlas) |
| Jefe 3 | `mecha-king-ghidorah` (reducir de 26k a ~8k triángulos) | Ya trae rig con skin (3 cuellos, 2 colas, alas), sin animaciones; decimar conservando pesos; animaciones creadas en Blender + movimiento procedural |
| Esbirros 3 | `TheWrapper V2` | Rig propio + 6 animaciones (embestida, idle, correr, grito, caminar, golpe) |
| Reserva (élite 3) | `aura_battler_dunbine` | Sin uso desde 2026-10-15 (el élite 3 es el Straw Reaper). Sin rig: mecha flotante animado por piezas rígidas (flotar, embestida, giro) |
| Escenarios | `floating_island`, `float-islands`, `PSX_Dungeon`, `Modular Dungeon Free Edition`, `modulardungeontextures` (detalle en sección 6) | Estáticos |
| Reserva | `psx_insectoid_demon` (jefe 3 si Ghidorah falla), `DoriOri` | Sustitutos si algo falla al importar |

Estado real de cada modelo (rig y animaciones verificados): ver [`asset-status.md`](asset-status.md).

**Regla de sustitución:** si el día 1 un modelo no importa bien o no se puede animar, se reemplaza por uno de reserva ese mismo día. No se gastan más de 2 horas peleando con un asset.

**Animaciones mínimas:**
- Kaelen: idle, caminar, correr, rodar, ataque 1-2-3, recibir golpe, morir.
- Esbirro: idle, caminar, atacar, recibir golpe, morir.
- Jefe: idle, moverse, 3 ataques, morir. Lo que falte se simula con tweens (inclinar, embestir, sacudir).
- Dragones (jefes 1 y 3): las animaciones base se crean por script con poses clave sobre su propio rig (`_source/tools/animate_bonedragon.py`, `animate_ghidorah.py`, utilidades en `dragon_anim.py`); en Godot se puede sumar movimiento procedural (ondulación de cuellos y colas) para que no se vean rígidos.


## 4. Combate (valores iniciales, se ajustan en el día 6)

| Parámetro | Valor |
|---|---|
| Vida base Kaelen | 100 (nivel 1), 70 (nivel 2), 40 (nivel 3) |
| Daño de golpe de esbirro / jefe | 20 / 20-35 |
| Estamina | 100; regenera 30/s tras 0.6 s sin gastar |
| Costo rodar / atacar | 25 / 20 |
| Invulnerabilidad al rodar | 0.35 s de 0.6 s |
| Daño de Kaelen | 20 / 20 / 36 (golpes 1, 2 y 3 del combo; duplicado el 2026-10-14, el valor original era 10 / 10 / 18) |
| Vida esbirro | 30 |
| Vida jefe | 400 / 500 / 600 |
| Fase 2 del jefe | al 50% de vida: +25% velocidad de ataque, más presupuesto al Orquestador |

Impactos: hitbox `Area3D` activada en ventanas de la animación; hurtbox en cada personaje. Feedback: pausa de impacto (~60 ms), parpadeo de material, partículas simples, sonido.

## 5. Flujo del juego

```
Menú principal → Exterior (isla, sendero, fachada del templo) → entra al templo
  → Piso 1: arena del Bone Dragon → reja de salida + escalera (fundido)
  → Piso 2: arena de Blackhorn → reja de salida + escalera (fundido)
  → Piso 3: arena de Mecha King Ghidorah → la puerta bloqueada se abre al morir Ghidorah
      → pasillo (~20 m) → sala de Elysia (altar) → zona de activación → texto → Créditos → Menú principal
```

Al ser un *boss rush*, no hay exploración ni salas de relleno entre jefes: los esbirros aparecen dentro de cada arena. Cada transición entre pisos es una escalera + fundido a negro, que oculta la carga de escena. Al morir se reinicia solo el piso actual.

## 6. Escenarios y diseño de niveles

### 6.1 Estructura del mundo

El juego ocurre en un solo lugar: **un templo de 3 pisos construido sobre una isla flotante**. Kaelen empieza fuera, entra al templo y sube piso por piso. **Cada piso es una escena de Godot**; entre pisos hay escalera + fundido a negro. El pasillo final y la sala de Elysia están **dentro de la escena del piso 3** (no hay escena `ending` aparte ni cúspide abierta).

```
                    ┌────────────────────────────┐  puerta     ┌─────────┐   ┌─────────────┐
   Piso 3           │ Arena 3 — Ruinas (Ghidorah) │─bloqueada─►│ Pasillo │──►│ Sala Elysia │ → créditos
                    └────────────▲───────────────┘             └─────────┘   └─────────────┘
                                 │ escalera / fundido
                    ┌────────────┴───────────────┐
   Piso 2           │ Arena 2 — Claustro          │
                    └────────────▲───────────────┘
                                 │ escalera / fundido
                    ┌────────────┴───────────────┐
   Piso 1           │ Arena 1 — Catacumba         │
                    └────────────▲───────────────┘
                                 │ puerta del templo
                    ┌────────────┴───────────────┐
   Exterior         │ Isla flotante (sendero)     │
                    └────────────────────────────┘
```

| Escena | Contenido | Duración aproximada |
|---|---|---|
| `exterior` | Kaelen aparece en la isla y camina por un sendero corto hasta la puerta del templo. | 1-2 min |
| `arena_1` | Catacumba — Bone Dragon + esqueletos (+ knight élite) | 3-6 min |
| `arena_2` | Claustro — Blackhorn + Plague Arcanists | 3-6 min |
| `arena_3` | Ruinas — Mecha King Ghidorah + TheWrapper (+ Straw Reaper élite); al morir el jefe se abre la puerta norte → pasillo → sala de Elysia (`EndingTrigger`) | 5-10 min |

**Generación:** las 4 escenas se generan con un script paramétrico y determinista (`scripts/tools/level_builder.gd`, ver 6.4). No hay generación procedural ni addons: el plano está en una tabla y para cambiarlo se edita un número y se vuelve a ejecutar.

### 6.2 Exterior (`float-islands`)

Se descartó `floating_island` (61 MB, texturas fotográficas). El exterior usa:
- `float-islands/FloatingIsland.fbx` como isla principal (escalada para que el sendero quepa holgado) y copias pequeñas como islotes decorativos.
- Un sendero con **colisión invisible** (caja) y paredes invisibles a los lados.
- La fachada del templo armada con piezas de `PSX_Dungeon` (muros, arco, puerta) y la `ExitTrigger` en la puerta.
- `base_env.tres` (cielo + niebla de distancia) para ocultar el vacío.

### 6.3 Diseño de las arenas

**Reglas comunes a las 3 arenas:**
- **Entrada al sur, salida al norte.** Al entrar, una reja (`IronGate` de `Modular Dungeon`) se cierra detrás de Kaelen. Al morir el jefe, se abre la reja de salida.
- **Inicio del jugador** a 4 m de la entrada, mirando al centro. **Inicio del jefe** en el tercio norte.
- **Pilares como cobertura:** 4 a 6 pilares repartidos. Sirven para cortar la línea de visión de los esbirros, esconder los puntos de aparición del Orquestador y darle al jugador un respiro.
- **Puntos de aparición de esbirros:** 6 `Marker3D` en el perímetro, detrás de pilares o en nichos, siempre sobre la malla de navegación.
- **Margen de cámara:** 3 m libres entre el área de combate y las paredes (ver 7.5).
- **Iluminación:** 1 luz direccional tenue + 4 a 6 antorchas (`OmniLight3D`) como máximo, para mantener rendimiento y el look PSX.
- **Límites:** paredes invisibles que encierran el área jugable, aunque la decoración siga más allá.

| | Arena 1 — Catacumba | Arena 2 — Claustro | Arena 3 — Ruinas |
|---|---|---|---|
| Jefe | Bone Dragon | Blackhorn | Mecha King Ghidorah |
| Forma | Rectangular | Octogonal | Circular / irregular |
| Área de combate | 32 × 32 m | 24 m de diámetro | 40 × 40 m |
| Altura | Techo a 8 m | Techo a 8 m (bóveda) | Sin techo (muros de 12 m, cielo con niebla) |
| Por qué ese tamaño | Dragón largo (≈ 8 m) que necesita espacio para barrer con la cola | Jefe humanoide rápido; arena chica = más presión | Jefe enorme (≈ 10 m); proyectiles de largo alcance |
| Pilares | 4 pilares gruesos + cadenas colgando | 6 columnas finas en anillo | Pilares rotos (`Pillar_Collapsed`) y escombros |
| Identidad visual | Oscura, cálida (antorchas), calaveras en muros, piso de piedra sucia | Fría y blanca, velas, candelabro central, telas | Abierta, viento, luz de cielo gris, metal y oro oxidado |
| Piezas clave | `Skull_Wall`, `Chain`, `Candle_*`, `Debris` | `Hexagon`, `Chandelier`, `Arch`, `Candle_*` | `Pillar_Collapsed_*`, `Wall_Ruin`; `Altar` en la sala de Elysia |
| Texturas | `concrete_512_indexed_dark`, `Floor512_indexed` | `concrete_512_indexed`, `512_fabric`, `gold512` | `metal_512`, `gold512`, `TerraCotta_512` |
| Ambiente sonoro | `Cave` | `Interior Night` | Viento |

**Rejas y triggers (nombres fijos en todas las arenas):** `GateEntry` (sur, se cierra al entrar), `GateExit` (norte, se abre con `Events.boss_defeated`), `ExitTrigger` (`Area3D` tras `GateExit`, lleva al piso siguiente), `PlayerStart`, `BossStart`, 6 `Marker3D` en el grupo `spawn_point`.

**Final dentro de `arena_3`:** detrás de `GateExit` (la "puerta bloqueada") sale un pasillo de 6 m de ancho (el de la reja) y ~20 m de largo hacia la **sala de Elysia** (12 × 12 m, techo 6 m) con el altar, Elysia estática mirando hacia el pasillo y un `EndingTrigger` (`Area3D`) delante de ella. La lógica (texto, cámara, créditos) la conecta A con `ending_director.gd`; las cámaras fijas son `EndingCam1` y `EndingCam2` dentro de la sala.

### 6.4 Uso de los kits de dungeon y texturas en Godot

| Pack | Rol | Uso |
|---|---|---|
| `PSX_Dungeon` | **Kit principal** | Muros, pisos, arcos, pilares, escaleras, puertas, velas, cadenas. Ya tiene estética PSX. |
| `Modular Dungeon Free Edition` | Complemento | `IronGate` (rejas de entrada/salida), `Altar` (final), `Lever`, `Grille`. |
| `modulardungeontextures` | Texturas de superficie | Texturas de 512 px repetibles para pisos y muros; se reducen a 256 px. |
| `Retro PSX Style Mansion Assets` | Decoración opcional | Solo props que encajen: candelabros, alfombras, libros, velas. Se ignora la carpeta `UE4 Ready`. |
| `Low Poly Fantasy RPG Items` | Decoración opcional | Cofres, frascos y objetos sueltos. |
| `Fantasy Weapon Starter Pack` | Armas de esbirros y decoración | Lanza/hacha para los esqueletos; armeros decorativos. |
| `demonic weapons pack` | Arma de Kaelen | Mandoble. |

**Flujo de trabajo (en este orden):**
1. **Bloqueo (día 2):** cada arena se genera primero con `scripts/tools/level_builder.gd` (`CSGBox3D`/`CSGCylinder3D` y un material liso, a partir de una tabla con el plano). Se hornea la navegación y se prueba el combate. Nadie decora antes de que la arena se juegue bien.
2. **Importación del kit (día 2-3):**
   - Importar cada pieza FBX con la escala corregida para que un módulo de muro mida exactamente 4 m (ver 7.3).
   - Colisión automática en el import: `Static Body` con forma simple (caja/convexa) para muros y pilares; *trimesh* solo para pisos y escaleras.
   - Guardar cada pieza como escena (`assets/environment/kit/<pieza>.tscn`).
3. **Construcción con `GridMap` (día 3-4):**
   - Crear una `MeshLibrary` con las piezas de muro, piso y esquina del kit.
   - Construir pisos y muros con `GridMap` (celda de 4 × 4 × 4 m), pintado por el mismo `level_builder.gd` a partir del plano (otra salida, mismas medidas).
   - Pilares, escombros, velas, cadenas y decoración se colocan a mano encima.
4. **Texturas:**
   - Ajuste global del proyecto: `rendering/textures/canvas_textures/default_texture_filter = Nearest`.
   - Import de cada textura: sin mipmaps, `Size Limit` 256, compresión *Lossless*.
   - Pisos y muros reutilizan `modulardungeontextures` con repetición (`uv1_scale`).
   - Las piezas bloqueadas con CSG pueden usar *triplanar* temporalmente.
5. **Material único PSX:** se usan los shaders de **Godot-PSX-Starter-kit** (MIT, portados a Godot 4 en `shaders/psx/`): `psx_lit.gdshader` para casi todo (vértices que tiemblan, iluminación por vértice, textura *nearest*), con variantes `alpha_scissor` (rejas, cadenas, follaje), `transparent` y `metal`; parámetros `albedoTex`, `modulate_color` (tinte), `uv_scale` y `precision_multiplier`. Cambiar `modulate_color` en la plantilla ajusta la paleta. Postproceso en `shaders/psx/postprocess/`: `pp_band_dither` (reducción de color con *dithering*, lo más importante para el look PS1) y opcionales (`vhs`, `ntsc`, `grain`, `lcd`…). Original sin portar en `_source/godot-psx-starter-kit/`.
6. **Decoración (día 6):** solo después de que el flujo completo funcione.

**Generador de niveles (`scripts/tools/level_builder.gd`):**
- **Regla:** las escenas generadas se sobrescriben al ejecutar el generador; **nunca se editan a mano ni se les agregan nodos**. Todo el gameplay va en `scenes/levels/<nivel>_gameplay.tscn`, que instancia el nivel (hijo `Level`) + Kaelen + enemigos, y busca los puntos del mapa por nombre (`scripts/game/level_gameplay.gd` coloca a Kaelen en `PlayerStart`).
- Ejecutar: `godot --headless --path . -s res://scripts/tools/level_builder.gd` (todas) o `... -- arena_2` (una). Sobrescribe `scenes/levels/{exterior,arena_1,arena_2,arena_3}.tscn`, así que **no se editan a mano**: los cambios van en las tablas `LEVELS` y `EXTERIOR` del script. Lo que se agregue va en escenas aparte: `arena_N_gameplay.tscn` instancia el nivel como hijo `Level`.
- Arenas 1 y 3: muros, suelo y techo en `GridMap` con `assets/environment/kit/dungeon_kit.meshlib` (piezas de `PSX_Dungeon` normalizadas por `_source/tools/export_dungeon_kit.py`). Arena 2 (octogonal): suelo y techo en `GridMap` en las celdas que tocan el octágono, muros con piezas del kit giradas 45° y colisión por cajas. Escalones, pasillos, jambas y dintel de las rejas son CSG.
- Navegación: se hornea al generar (`NavigationSmall` capa 1, r 0.5; `NavigationLarge` capa 2, r 2.5).
- Rejas: `GateEntry` y `GateExit` son `AnimatableBody3D` de 6 × 6 m, ambas cerradas; la meta `open_offset` (0, −6.1, 0) indica cuánto bajarlas para abrirlas.
- Exterior: `island_main` (pieza `IslandSkull` de `float-islands`, ≈ 104 m, exportada por `_source/tools/export_float_island.py`) con colisión trimesh, sendero de 67 m con paredes invisibles, templo escalonado con arco y pilares del kit, islotes y `ExitTrigger` en la puerta.

### 6.5 Reglas para que todo se vea como un conjunto
1. **Un solo shader PSX** para todos los modelos (vértices "temblorosos", filtro *nearest*, iluminación por vértice).
2. **Paleta común:** piedra gris fría, bronce oxidado, negro, acentos blancos/cuarzo. Las texturas que no encajen se re-tiñen con el parámetro `tint` o se reemplazan por `modulardungeontextures`.
3. **Resolución de texturas uniforme:** 128 px o 256 px.
4. **Escalas según la sección 7** — nada entra a una arena sin pasar por `scale_reference`.
5. **Iluminación y niebla compartidas:** un `WorldEnvironment` base (`assets/environment/base_env.tres`) reutilizado en todas las escenas, con variaciones pequeñas por arena.
6. **Un kit principal** (`PSX_Dungeon`); los demás solo aportan piezas puntuales.

### 6.6 Entregables por escena
| Escena | Contenido mínimo |
|---|---|
| `scale_reference` | Kaelen, Elysia, un esbirro de cada tipo, los 3 jefes, módulo de muro, puerta y pilar, alineados sobre una grilla de 1 m |
| `exterior` | Isla `float-islands`, sendero con colisión, fachada del templo, islotes, cielo y niebla |
| `arena_1`, `arena_2`, `arena_3` | Arena cerrada, navegación horneada (2 capas, ver 7.6), 6 spawns, rejas, inicio de jugador y jefe, iluminación |
| `arena_3` (además) | Puerta bloqueada `GateExit`, pasillo ~20 m, sala de Elysia con altar, Elysia, `EndingTrigger` y cámaras fijas |

## 7. Escala y dimensiones

### 7.1 Por qué hace falta
Los modelos vienen de autores distintos y sus escalas originales no tienen relación entre sí. Medidas de los archivos originales:

| Modelo | Tamaño en el archivo original |
|---|---|
| `knight__ps1_psx` | ≈ 0.02 unidades (diminuto) |
| `kaden-base-model` | ≈ 1.73 unidades (correcto) |
| `mecha-king-ghidorah` | ≈ 6.6 unidades |
| `PSX_Dungeon` muro | ≈ 20 unidades |
| `floating_island` | ≈ 61 000 unidades |

Además, varios FBX traen escalas internas de 100× o 0.01× en sus nodos. **Nunca se confía en la escala original:** cada modelo se normaliza a las medidas de esta sección. **1 unidad de Godot = 1 metro.**

### 7.2 Las cinco medidas de cada personaje

Cada personaje tiene cinco "tamaños" distintos que **no** deben confundirse:

| | Qué es | Nodo en Godot | Para qué sirve |
|---|---|---|---|
| **a) Tamaño visual** | Lo que se ve: el modelo 3D | `MeshInstance3D` / `Skeleton3D` | Presencia, legibilidad, escala dramática |
| **b) Collider (cápsula)** | El cuerpo físico que choca con el mundo y con otros | `CollisionShape3D` del `CharacterBody3D` | Que no atraviese paredes ni otros personajes |
| **c) Hurtbox / Hitbox** | Zonas que **reciben** daño (hurtbox) y que **hacen** daño (hitbox) | `Area3D` + forma | Combate: qué golpe conecta |
| **d) Espacio de cámara** | Distancia y altura de la cámara, y espacio libre que necesita | `SpringArm3D` + `Camera3D` | Que siempre se vea a Kaelen y al enemigo |
| **e) Espacio de navegación** | Radio y altura con que la IA calcula caminos | `NavigationAgent3D` + `NavigationMesh` | Que los enemigos no se atasquen ni atraviesen pilares |

**Reglas generales:**
- **El collider es más chico que el modelo** (no se nota que choca "en el aire").
- **La hurtbox del jugador es un poco más chica que su modelo** → los golpes que "rozan" no cuentan; se siente justo.
- **Las hurtbox de los enemigos son un poco más grandes que su modelo** → los golpes del jugador que se ven conectar, conectan.
- **Las hitbox solo están activas en la ventana de daño de la animación**, nunca todo el tiempo.
- **El radio de navegación es igual o mayor que el radio del collider**, para que el camino calculado sea transitable de verdad.
- **El aviso visual de un ataque (decal en el piso) tiene el mismo tamaño que su hitbox.**

### 7.3 Medidas de referencia del escenario
| Elemento | Medida |
|---|---|
| Celda de `GridMap` / módulo de muro | 4 m ancho × 4 m alto |
| Puerta normal | 3 m alto × 2 m ancho |
| Reja de arena (entrada/salida) | 6 m alto × 6 m ancho (pasa un jefe) |
| Escalón | 0.25 m |
| Pilar | 1.2 m de diámetro × 8 m |
| Techo arenas 1 y 2 | 8 m (2 módulos apilados) |
| Isla `floating_island` | ≈ 150 m de ancho |
| Islotes `float-islands` | 20-60 m (decorativos) |

### 7.4 Tabla de personajes

**Personajes humanos y esbirros**

| Personaje | a) Visual (alto) | b) Collider (cápsula) | c) Hurtbox | c) Hitbox de ataque | e) Navegación |
|---|---|---|---|---|---|
| **Kaelen** | 1.70 m (1.75 con capucha) | r 0.35 · alto 1.70 | Cápsula r 0.30 · alto 1.50 | Caja a lo largo del mandoble: 0.25 × 0.25 × 2.15 m, en el hueso de la mano (hoja de ≈ 2.3 m; alcance efectivo ≈ 2.6 m desde Kaelen, 3.0 m hasta el centro de un esbirro y 3.5 m hasta el de Blackhorn) | — (jugador) |
| **Elysia** | 1.60 m | r 0.30 · alto 1.60 (solo bloquea) | — | — | — |
| **Skeleton** | 1.75 m | r 0.35 · alto 1.75 | Cápsula r 0.40 · alto 1.80 | Esfera r 0.5 a 1.2 m al frente | Capa chica |
| **Knight (élite 1)** | 2.10 m (escalado ×1.15) | r 0.40 · alto 2.10 | Cápsula r 0.45 · alto 2.10 | Caja de espada 0.2 × 0.2 × 1.2 m | Capa chica |
| **Plague Arcanist** | 1.80 m | r 0.35 · alto 1.80 | Cápsula r 0.40 · alto 1.85 | Esfera r 0.5 a 1.3 m al frente | Capa chica |
| **TheWrapper** | 2.00 m | r 0.45 · alto 2.00 | Cápsula r 0.50 · alto 2.05 | Embestida: caja 1 × 1.5 × 2.5 m al frente | Capa chica |
| **Straw Reaper (élite 3)** | 1.90 m (con la hoz) | r 0.40 · alto 1.90 | Cápsula r 0.45 · alto 1.95 | Hoz: caja 1.4 × 1.2 × 1.8 m al frente | Capa chica |
| **Aura Battler (reserva, sin uso)** | 3.00 m (flota a 0.5 m) | r 0.80 · alto 2.50 | Cápsula r 0.90 · alto 2.80 | Giro: esfera r 2.5 alrededor | Capa grande |

**Jefes** — un solo collider no alcanza; usan varias formas unidas a huesos (`BoneAttachment3D`).

| Jefe | a) Visual | b) Collider físico | c) Hurtboxes | c) Hitboxes por ataque | e) Navegación |
|---|---|---|---|---|---|
| **Bone Dragon** | 8 m de largo · 3.5 m de alto · 10 m de envergadura | Cápsula horizontal r 1.2 × 4 m en el torso; la cola **sin** collider físico | Torso (caja), cabeza (esfera r 0.8, daño ×1.25), 4 patas (cápsulas) | Mordida: esfera r 1.2 en la cabeza · Barrido de cola: caja curva 5 m · Pisotón: esfera r 2.5 bajo la pata | Capa grande |
| **Blackhorn** | 3.20 m (ya exportado a esa altura; casi el doble que Kaelen) | r 0.70 · alto 3.20 | Cápsula r 1.0 · alto 3.2 | Garras: esferas r 0.6 en ambas manos · Zarpazo con salto: caja 2 × 2 × 4 m al frente · Golpe al suelo: esfera r 3 alrededor · Embestida: caja 1.5 × 2.5 × 3 m al frente | Capa grande |
| **Mecha King Ghidorah** | 10 m de alto · 14 m de largo · 14 m de envergadura | Cápsula r 2.5 · alto 6 en el torso + cápsulas en patas; cuellos y cabezas **sin** collider físico | Torso y patas (siempre alcanzables); 3 cabezas (esferas r 1.0) solo alcanzables cuando bajan para morder | Mordida: zona fija en el suelo de 4.6 × 2.4 × 7 m delante del jefe (de pegado al cuerpo a 5 m; no sigue la altura de la mandíbula, así que quedarse debajo o pegado no es seguro) · Barrido de cola: caja 6 m · Rayo: el aviso es una franja roja en el piso desde Ghidorah hasta Kaelen (fijada al 70 % del aviso) y al disparar el impacto la recorre en 0.9 s (de 2.5 m del jefe hasta 2 m más allá de Kaelen) con una zona de daño corta (1.5 × 2.4 × 2 m) que viaja con él | Capa grande |

**Por qué los cuellos, cabezas y colas no tienen collider físico:** se mueven mucho y empujarían a Kaelen o a la cámara de forma errática. Solo tienen hurtbox/hitbox (`Area3D`), que detectan sin empujar.

**Diseño que sale de las medidas:** las cabezas de Ghidorah están a 7-9 m de altura, fuera del alcance del mandoble. Solo se pueden golpear justo después de una mordida, cuando la cabeza baja al suelo. Esto da un momento claro de castigo sin necesidad de escalar.

### 7.5 Espacio de cámara (d)

| Parámetro | Valor normal | Con lock-on a jefe grande |
|---|---|---|
| Pivote (altura sobre los pies de Kaelen) | 1.5 m | 2.5 m |
| Distancia (`SpringArm3D.spring_length`) | 4 m | 6-7 m (según tamaño del jefe) |
| Campo de visión (FOV) | 70° | 75° |
| Margen de colisión del brazo | 0.2 m | 0.2 m |
| Distancia máxima de lock-on | 15 m | 25 m |

- **Punto de lock-on:** cada enemigo tiene un `Marker3D` llamado `LockOnPoint` en el pecho (no en los pies ni en el origen). En los jefes grandes va en el torso, a media altura.
- **El brazo de la cámara solo choca con el escenario** (capa `world`), nunca con personajes. Si chocara con un dragón, la cámara se metería dentro de Kaelen.
- **Espacio libre:** dentro del área de combate debe haber al menos 3 m entre el jugador y cualquier pared en la dirección de la cámara. Por eso las arenas tienen 3 m de margen entre el área jugable y los muros.
- **Techo:** con pivote de 2.5 m y distancia de 7 m, la cámara puede subir a ≈ 5 m; los techos de 8 m de las arenas 1 y 2 dejan margen.
- **Pilares que tapan la vista:** el brazo los esquiva acercándose. Si molesta en las pruebas, se vuelven semitransparentes cuando se interponen (opcional, día 6).

### 7.6 Espacio de navegación (e)

Dos capas de navegación por arena, horneadas con parámetros distintos (`NavigationRegion3D` en capas de navegación 1 y 2):

| Capa | Quién la usa | Radio del agente | Alto del agente | Escalón máx. | Pendiente máx. |
|---|---|---|---|---|---|
| **Chica** (capa 1) | Esqueletos, Knight, Plague Arcanist, TheWrapper, Straw Reaper | 0.5 m | 2.0 m | 0.3 m | 35° |
| **Grande** (capa 2) | Bone Dragon, Blackhorn, Ghidorah, Aura Battler | 2.5 m | 4.0 m | 0.5 m | 25° |

Parámetros comunes del horneado: celda 0.25 m, alto de celda 0.25 m.

**Reglas de diseño de arena que salen de esto:**
- Entre pilares debe haber al menos **1.5 m** libres (pasan los esbirros) y en el espacio central al menos **6 m** (pasan los jefes).
- Los jefes grandes no necesitan pasar entre pilares: se mueven por el centro de la arena.
- Los `Marker3D` de aparición deben estar sobre la capa chica; la posición inicial del jefe, sobre la capa grande.
- `NavigationAgent3D` con evitación (`avoidance_enabled`) en los esbirros, con radio de evitación igual al de su collider.

### 7.7 Capas de colisión
| Capa | Nombre | Quién está en ella |
|---|---|---|
| 1 | `world` | Muros, pisos, pilares, paredes invisibles |
| 2 | `player` | Collider de Kaelen |
| 3 | `enemy` | Colliders de esbirros |
| 4 | `boss` | Colliders de jefes |
| 5 | `player_hitbox` | Hitbox del mandoble |
| 6 | `enemy_hitbox` | Hitboxes de esbirros y jefes |
| 7 | `player_hurtbox` | Hurtbox de Kaelen |
| 8 | `enemy_hurtbox` | Hurtboxes de esbirros y jefes |

- `player_hitbox` solo detecta `enemy_hurtbox`; `enemy_hitbox` solo detecta `player_hurtbox`. Así los enemigos no se dañan entre sí y Kaelen no se daña a sí misma.
- El `SpringArm3D` de la cámara solo detecta `world`.

### 7.8 Procedimiento de normalización (día 1)
1. Importar el modelo. Si viene en FBX con escalas internas raras, abrirlo en Blender, aplicar escala (`Ctrl+A → All Transforms`) y exportar GLB.
2. Colocarlo en `scale_reference` junto a una cápsula de 1.70 m y la grilla de 1 m.
3. Ajustar la escala en el import de Godot (*Advanced Import → Root Scale*) hasta que su altura coincida con la columna **a) Visual** de la tabla 7.4.
4. Anotar el factor final en la tabla de abajo, para que nadie lo vuelva a adivinar.
5. Crear la escena del personaje (`.tscn`) con collider, hurtbox, punto de lock-on y agente de navegación según las tablas 7.4-7.6.

| Modelo | Factor de escala de import | Medido por |
|---|---|---|
| Se completa el día 1 con la medición real de cada modelo | | |

## 8. Inteligencia Artificial dentro del juego

Tres capas, cada una con una técnica reconocida de IA para videojuegos.

### 8.1 Esbirros — Máquina de estados finitos + navegación
- **Percepción:** detección por radio (12 m) + cono de visión (110°) + raycast de línea de visión.
- **Estados:** `Idle/Patrulla → Persecución → Rodear → Ataque → Recuperación → Muerte`; `Aturdido` al recibir golpe.
- **Navegación:** `NavigationRegion3D` + `NavigationAgent3D` (búsqueda de rutas A* sobre la malla de navegación) con evitación entre agentes.
- **Coordinación por fichas de ataque:** un gestor central reparte como máximo 2 fichas. Solo un esbirro con ficha puede pasar a `Ataque`; los demás pasan a `Rodear` (orbitan a Kaelen a 3-4 m). Esto evita que todos ataquen a la vez y produce el ritmo de un soulslike.

### 8.2 Jefes — Selección de ataques por utilidad
Cada ataque es un recurso (`BossAttack`) con: rango mínimo/máximo, tiempo de aviso (telegraph), recuperación y peso base. Cada vez que el jefe decide qué hacer, calcula un puntaje para cada ataque:

```
puntaje = peso_base
        × ajuste_distancia(distancia a Kaelen)
        × penalización_repetición (0.3 si fue el último ataque)
        × bonus_anticipación (si el jugador esquiva repetidamente hacia un lado)
        × multiplicador_fase
```

Elige por sorteo ponderado entre los 2 mejores (para que no sea completamente predecible). El jefe guarda un historial corto de cómo esquiva el jugador para el bonus de anticipación.

### 8.3 Orquestador
Un nodo autoload `Orchestrator` que ajusta la presión del combate según cómo juega el jugador.

**Intensidad (0-100):**
- Sube: recibir daño (+daño × 1.5), vida baja (< 30%: +5/s), enemigos a < 5 m (+2/s cada uno).
- Baja: −8/s de forma natural; −15/s si no hay enemigos cerca.

**Fases (máquina de estados):**
| Fase | Comportamiento | Transición |
|---|---|---|
| Crecimiento | Genera grupos de 2 o 3 esbirros | intensidad ≥ 80 → Pico |
| Pico | No genera nada; deja que los enemigos actuales presionen | 5 s → Respiro |
| Respiro | No genera nada durante 10-20 s | tiempo cumplido e intensidad < 30 → Crecimiento |

**Tamaño del grupo:**
```
presión = base_nivel
        × factor_desempeño   (0.6 a 1.4, según vida actual y tiempo sin recibir daño)
        × multiplicador_fase_jefe (1.0; 1.5 en fase 2)
grupo = 3 esbirros si presión ≥ base_nivel, 2 si no
```
Límite de esbirros vivos: 3. Cada grupo lleva exactamente 1 élite (más vida/daño) en lugar de uno de sus esbirros: 1 élite + 1 o 2 normales. Si el élite muere no se repone dentro del grupo; el siguiente grupo, tras la ventana del jefe, trae otro élite.

**Puntos de aparición:** `Marker3D` en cada arena; el Orquestador elige los que están fuera del cono de la cámara y a más de 8 m de Kaelen.

**Reglas de seguridad:** si la vida de Kaelen es < 25%, se fuerza Respiro. Si el jefe está en un ataque especial, no se genera nada.

**Comunicación:** señales globales (`player_damaged`, `enemy_died`, `boss_phase_changed`, `arena_entered`, `arena_cleared`).

**Vista de depuración (F3):** muestra en pantalla intensidad, fase, tamaño del último grupo, esbirros vivos y fichas de ataque asignadas. Sirve para la presentación y para ajustar valores.

## 9. HUD
- Barras de vida y estamina (esquina superior izquierda).
- Barra del jefe con su nombre (parte inferior), visible solo durante el enfrentamiento.
- Mensajes grandes centrados: "HAS MUERTO" / nombre del jefe derrotado.
- Indicador de lock-on sobre el objetivo.

## 10. Menús

### 10.1 Menú principal (obligatorio)
- Fondo: la isla flotante con cámara girando lentamente (reutiliza `exterior`).
- Título del juego.
- Botones: **Iniciar**, **Opciones** (oculto si no se implementa), **Créditos**, **Salir**.
- Navegable con ratón y teclado/mando (foco inicial en "Iniciar").

### 10.2 Menú de pausa (obligatorio)
Complejidad baja (≈ medio día). Se abre con `Esc` / `Start`:
- Pausa el juego con `get_tree().paused = true`; el menú usa `process_mode = PROCESS_MODE_ALWAYS` para seguir respondiendo.
- Botones: **Continuar**, **Opciones** (si existe), **Volver al menú principal**, **Salir del juego**.
- Libera el cursor del ratón al abrir y lo vuelve a capturar al cerrar.

### 10.3 Menú de opciones (opcional)
- Volumen: General, Música, Efectos (sliders conectados a los buses de audio).
- Sensibilidad de cámara.
- Pantalla completa / ventana.
- Persistencia simple en `user://settings.cfg` (`ConfigFile`).

### 10.4 Pantalla de muerte y créditos
- Muerte: "HAS MUERTO" + fundido + reaparición automática (sin menú).
- Créditos: equipo + lista de assets, autores y licencias (requisito de CC-BY), botón para volver al menú.

## 11. Sonido (SFX y música)

### 11.1 Buses de audio
`Master` → `Music`, `SFX`, `UI`. Permite el control de volumen del menú de opciones y bajar la música en la pausa.

### 11.2 Lista de efectos de sonido

| Categoría | Sonidos |
|---|---|
| Kaelen | pasos (piedra), swing del mandoble ×2-3 variantes, impacto en carne, impacto en metal/hueso, rodar, recibir golpe, muerte, respiración agotada (sin estamina) |
| Esbirros | pasos, ataque, recibir golpe, muerte (por tipo: esqueleto/hueso, arcanista, caballero/metal) |
| Jefes | rugido de entrada, aviso de ataque, golpe al suelo/impacto pesado, cambio a fase 2, muerte |
| UI | mover selección, confirmar, volver, abrir/cerrar pausa |
| Ambiente | viento en la isla, eco/goteo en el templo, cadenas o fuego por arena |

### 11.3 Música (BGM) — asignación propuesta

Pistas reunidas en `_source/bgm/` (original: `D:\BGM`):

| Momento | Pista |
|---|---|
| Menú principal | `celtic melancholy.mp3` |
| Isla / entrada al templo | `LVS04_10_Battlefield_bpm180_loop.ogg` (o silencio + ambiente) |
| Jefe 1 — Bone Dragon | `skull dragon battle.mp3` |
| Jefe 2 — Blackhorn | `Blazing Honor.mp3` |
| Jefe 3 — Mecha King Ghidorah | `black dragon battle.mp3` |
| Fase 2 de jefe / alternativas | `ancient creature battle.mp3`, `hellhound battle.mp3`, `wyvern battle.mp3` |
| Encuentro con Elysia y créditos | `sadness piano4.mp3` |

- Transición: fundido de la música de ambiente a la de jefe al iniciar el enfrentamiento; bajar volumen de la música en pausa.
- Si una pista no hace bucle limpio, marcar el punto de loop en el import de Godot.

### 11.4 Efectos de sonido (SFX) — packs disponibles

Packs reunidos en `_source/sfx/` (original: `D:\SFX`):

| Pack | Contenido | Uso en el juego |
|---|---|---|
| `40 Free PSX Footsteps` | Pasos en piedra, concreto, metal, escaleras, tierra, grava, pasto, madera | Pasos de Kaelen (piedra/metal) y esbirros |
| `Free Fantasy SFX Pack By TomMusic` | Ataques, hechizos, puertas/rejas/cofres, antorchas, agua; loops de ambiente (cueva, interior, bosque, mar) | Swings e impactos, puertas entre arenas, ambiente de templo (`Cave`, `Interior Night`) |
| `Monsters SFX Vol.1` | Rugidos, gruñidos, chillidos, aliento de fuego | Rugidos de dragones, sonidos de esbirros y jefes |
| `Be Not Afraid UI` | Sonidos de interfaz de estilo oscuro | Menús: mover, confirmar, volver, pausa |

Faltantes a conseguir si no están en los packs: golpe recibido/grito de Kaelen, sonido de rodar, crujido de huesos para el esqueleto, golpe metálico para el knight.

### 11.5 Licencias de audio
| Origen | Licencia | Crédito |
|---|---|---|
| EpicOrderSounds (`Blazing Honor`) | Uso libre, crédito opcional | "Music by EpicOrderSounds" |
| TomMusic | Ver `ReadMe.txt` del pack | TomMusic |
| Ririsaurus (`Monsters SFX Vol.1`) | Uso libre, **no redistribuir** | Riria / Ririsaurus |
| Atelier Magicae (`Be Not Afraid UI`) | Uso libre, **no redistribuir**, crédito obligatorio | "Atelier Magicae" |
| Resto de pistas BGM y pasos PSX | Registrar autor y licencia antes del día 7 | — |

### 11.6 Implementación
- `AudioStreamPlayer3D` en personajes para sonidos espaciales; `AudioStreamPlayer` para música y UI.
- Variación de tono aleatoria (±10%) en sonidos repetidos (pasos, swings) para que no suenen iguales.
- Sonidos de impacto disparados desde el sistema de hitbox, no desde cada script.
- Formato: `.ogg` para música, `.wav` para efectos cortos.

## 12. Arquitectura en Godot

```
res://
  assets/        # modelos, texturas, audio (Git LFS), cada uno con su licencia
  scenes/
    player/      kaelen.tscn
    enemies/     minion_base.tscn + variantes por nivel
    bosses/      boss_base.tscn + boss_dragon / boss_blackhorn / boss_ghidorah
    levels/      exterior, arena_1, arena_2, arena_3 (incluye pasillo y sala de Elysia), scale_reference
    ui/          main_menu, pause_menu, options_menu, hud, credits, debug_overlay
  scripts/
    player/      player_controller.gd, player_combat.gd, lock_on.gd, camera_rig.gd
    combat/      health.gd, hitbox.gd, hurtbox.gd, stamina.gd
    ai/          minion_fsm.gd, attack_token_manager.gd, boss_brain.gd, boss_attack.gd (Resource), orchestrator.gd
    game/        game_state.gd (autoload: nivel actual, vida máxima), events.gd (autoload: señales)
    audio/       audio_manager.gd (autoload: música y sonidos globales)
  shaders/       psx/ (psx_lit*.gdshader, psx_unlit*.gdshader) + psx/postprocess/ (pp_band_dither y efectos de pantalla)
```

Principios: componentes pequeños (`Health`, `Hitbox`, `Hurtbox`, `Stamina`) que se reutilizan en Kaelen, esbirros y jefes. Los jefes comparten `boss_base` y solo cambian modelo y recursos `BossAttack`. Las arenas son escenas independientes cargadas por `game_state`.

## 13. Repositorio y assets
### 13.1 Estructura

```
Descending-to-my-Heaven/          (raíz del repo = raíz del proyecto Godot)
  docs/                           documentación
  _source/                        material original, NO lo importa Godot (contiene .gdignore)
    models/                       copia de D:\ASSETS-PRUEBA
    bgm/                          copia de D:\BGM
    sfx/                          copia de D:\SFX
  assets/                         solo lo que el juego usa, ya procesado (GLB reducidos, OGG)
  scenes/ scripts/ shaders/ ...
```

- `_source/` es el respaldo compartido del equipo: todos tienen los mismos archivos originales. El archivo vacío `_source/.gdignore` hace que Godot lo ignore (si no, importaría cientos de archivos y el editor se volvería lento).
- `assets/` contiene solo lo que realmente usa el juego, ya procesado; cada carpeta lleva su `license.txt`.
- **Git LFS** para modelos, texturas, audio y `.blend`.
- Al copiar a `_source/` se omite lo duplicado o basura: carpetas `WAV Files` de TomMusic (mismos sonidos que `OGG Files`), versiones `.wav`/`.m4a` duplicadas de pistas que ya tienen `.ogg`/`.mp3`, `__MACOSX/` y `.DS_Store`.
- Conversión FBX → GLB en Blender cuando el import directo de Godot falle.

### 13.2 Visibilidad del repositorio
El repositorio debe ser **privado**. Varios packs prohíben redistribuir los archivos originales (Ririsaurus, Atelier Magicae, licencia estándar de Sketchfab) y Ghidorah es fan-art de una propiedad con copyright. Lo que se publica es el juego exportado, no los archivos originales.
- **Regla de trabajo (histórica, desde 2026-10-14 no aplica):** una sola persona editaba cada escena `.tscn` a la vez (dueño por escena) para evitar conflictos de merge.

## 14. Roles

> Desde 2026-10-14 no hay roles A/B/C ni dueños de archivos. La tabla queda como referencia histórica (ver "Estado actual" del plan de trabajo).

| Persona | Responsabilidad principal |
|---|---|
| A — Jugador e interfaz | Controlador, cámara, lock-on, combate de Kaelen, HUD, menús |
| B — IA y enemigos | FSM de esbirros, fichas de ataque, `boss_base` + utilidad, Orquestador, overlay de depuración |
| C — Arte, escenarios y sonido | Mixamo, Blender, importación, construcción de arenas e isla, cohesión visual, shader PSX, SFX y música, créditos |

## 15. Cronograma

| Día | Meta | Criterio de "hecho" |
|---|---|---|
| 1 | Proyecto + repo + LFS; importar assets; **normalizar escalas (7.8)**; preparar la isla (6.2); Kaelen con placeholder | Cada modelo visible en Godot con sus animaciones listadas; `scale_reference` armada; cápsula que se mueve con cámara |
| 2 | Combate de Kaelen; esbirro con FSM y navegación; arena 1 en bruto | Se puede matar a un esbirro y morir ante él |
| 3 | `boss_base` + jefe 1; menú principal y pausa | **Hito crítico: jefe 1 se puede ganar y perder**, entrando desde el menú |
| 4 | Orquestador; jefes 2 y 3; arenas 2 y 3; isla | Las 3 arenas jugables por separado; Orquestador generando oleadas |
| 5 | Flujo completo: transiciones, reaparición, vida decreciente, final, créditos; SFX principales | Partida completa de principio a fin |
| 6 | Pulido: cohesión visual, música, resto de SFX, balance, overlay F3; opciones si da tiempo | 2 personas externas lo terminan (o casi) |
| 7 | Congelación de funciones; bugs; exportar Windows (+ Web si funciona) | Ejecutable final probado en otra PC |

**Si el día 3 falla el hito:** se recorta a 2 animaciones por jefe, se elimina el recorrido por la isla (queda solo como fondo del menú) y el Orquestador se reduce a dos estados (generar / no generar).

## 16. Pruebas
- **Escena de pruebas** (`test_arena.tscn`) con Kaelen, un esbirro y un jefe intercambiable.
- **Atajos de depuración:** F3 overlay de IA, F5 saltar al siguiente jefe, F6 invulnerabilidad.
- **Checklist de partida completa** al final de los días 5, 6 y 7: menú → isla → 3 jefes → final → créditos → menú, muriendo al menos una vez por jefe y usando la pausa.
- Ajuste de dificultad mirando el overlay del Orquestador (la intensidad debe oscilar, no quedarse en 0 ni en 100).

## 17. Riesgos

| Riesgo | Mitigación |
|---|---|
| Modelos con rigs incompatibles o FBX que no importan | Validar todo el día 1; reservas listadas; límite de 2 h por asset |
| Jefes sin animaciones | Movimiento por tweens y código (embestidas, saltos, rotaciones) |
| Assets que no combinan visualmente | Reglas de cohesión (6.5) aplicadas desde el día 1 |
| Construir escenarios consume el tiempo de combate | Arenas definidas en 6.3; bloqueo con CSG primero (6.4), decoración solo el día 6 |
| Escalas inconsistentes entre modelos | Normalización obligatoria en `scale_reference` (7.8) antes de usar cualquier modelo |
| `floating_island` demasiado pesada o no encaja | Texturas a 256 px y tinte; alternativa con `float-islands` (6.2) |
| Conflictos de merge en `.tscn` | Dueño por escena; commits pequeños y frecuentes |
| Ghidorah demasiado pesado | Reducir polígonos en Blender antes de importar |
| Exportación Web falla | Windows es el entregable obligatorio; Web es opcional |
