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
- Kaelen: moverse, cámara orbital, fijar objetivo (lock-on), ataque ligero (combo de 2-3 golpes), rodar con invulnerabilidad, estamina, frasco de curación (10 usos por nivel), recibir daño, morir.
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
| Frasco de curación | 10 usos por nivel; cura el 38 % de la vida máxima (38 / 27 / 15 HP en las arenas 1 / 2 / 3); 0,9 s de uso |
| Daño de Kaelen | 20 / 20 / 36 (golpes 1, 2 y 3 del combo; duplicado el 2026-10-14, el valor original era 10 / 10 / 18) |
| Vida esbirro | 30 |
| Vida jefe | 400 / 500 / 600 |
| Fase 2 del jefe | al 50% de vida: +25% velocidad de ataque, más presupuesto al Orquestador |

Impactos: hitbox `Area3D` activada en ventanas de la animación; hurtbox en cada personaje. Feedback: pausa de impacto (~60 ms), parpadeo de material, partículas simples, sonido.

**Feedback de combate (implementado 2026-10-15):**
- *Pausa de impacto* (`scripts/combat/hit_stop.gd`): al acertar Kaelen baja `Engine.time_scale` a 0,05 durante 60 ms de reloj real (40 ms cuando ella recibe daño). Las peticiones no se apilan (mientras hay una activa se ignoran) y el tiempo se restaura siempre: al terminar, al pausar el juego, al morir (la pantalla de muerte pausa el árbol), al cambiar de escena y al salir el nodo del árbol; si otro sistema cambió la escala durante el impacto no se pisa. Los `Tween` de la interfaz que ignoran la escala de tiempo no se ven afectados.
- *Parpadeo de material* (`scripts/combat/hit_flash.gd`): al recibir un golpe (cualquier `Hurtbox` con daño) el modelo de jefes, esbirros, élites y Kaelen se tiñe 0,1 s: blanco en enemigos, rojo en Kaelen. Es un uniform `hit_flash` / `hit_flash_color` del shader `psx_lit` (sin pases extra ni overlays), animado con un `Tween` atado al modelo.
- *Cámara*: Kaelen sacude la cámara (0,07 m, 0,22 s, `CameraRig.shake`) cuando un golpe le quita el 15 % o más de su vida máxima. Con un jefe fijado a más de 8 m el brazo se alarga 0,4 m por metro de más (máximo +3 m) para encuadrar a los jefes enormes.

**Frasco de curación (implementado 2026-10-15, para que el juego sea más justo):**
- *Cargas:* 10 en cada nivel (exterior y las tres arenas). Se rellenan al entrar a cada nivel y al reintentar tras morir (Kaelen se reconstruye y `level_gameplay._refill_player` llama a `refill_heals`).
- *Cantidad:* `round(vida máxima × 0,38)`: 38 / 27 / 15 HP con vida máxima 100 / 70 / 40. En la arena 3 sigue siendo un tercio de la barra, aunque en HP absolutos cura menos que en la arena 1.
- *Uso:* subestado de MOVE (`Player.try_heal`). Dura 0,9 s: Kaelen camina al 35 % de su velocidad, el modelo brilla en verde y suena el trago; la vida llega al final y solo entonces se gasta la carga. Un golpe recibido, rodar, atacar, morir o una escena dirigida lo cancelan **sin gastar la carga** (el castigo de que te golpeen es el tiempo perdido, no el frasco). No se puede empezar durante ataque, rodada, HURT, muerte, pausa ni escenas dirigidas, ni con la vida llena ni sin cargas.
- *Animación y sonido:* el modelo de Kaelen no tiene clip de beber: se reutiliza la locomoción (andar lento) con un brillo verde progresivo (`HitFlash.glow`, uniform `hit_flash` de `psx_lit`), una bocanada verde con chispas doradas al curar (`ImpactFx.heal`) y el sonido `Firebuff 1` del pack Free Fantasy SFX (TomMusic, ya usado).
- *Orquestador:* la intensidad solo sube con `player_damaged` y con la vida baja (`hp_ratio` por debajo de `LOW_HP_RATIO` / `FORCE_RELAX_HP`). Curarse no emite ningún evento de daño, así que no cuenta como "va bien"; solo saca antes a Kaelen del respiro forzado por vida baja, que es lo correcto.

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
- **Actualización 2026-10-15:** el templo es un edificio escalonado generado por `level_builder._temple` (torre de cuatro pisos, frontón y columnas sobre la puerta, alas con tejado, ruinas); los tres huecos de la isla (ojos y nariz) llevan estanques con shader de agua; el vacío se cubre con un mar de niebla en capas y tres anillos de árboles lejanos (modelos del pack PS1 de árboles, oscurecidos y fundidos con la bruma por distancia); los estanques usan una textura de agua del pack SBS (CC0); las escaleras de las arenas tienen una rampa de colisión bajo los peldaños visuales. Detalle en `docs/problemas-mapa.md`.

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

**Iluminación por arena (implementado 2026-10-15):** cada `arena_N_gameplay.tscn` lleva un nodo `Mood` (`scripts/game/arena_mood.gd`) que copia el `Environment` del nivel generado y le pone luz ambiente, niebla, ajustes de color y el color y la energía del `Sun`; `arena_N.tscn` no se toca.

| | Arena 1 — Catacumba | Arena 2 — Claustro | Arena 3 — Ruinas |
|---|---|---|---|
| Ambiente (color / energía) | marrón cálido, 0,6 | azul pálido, 0,6 | gris neutro, 0,65 |
| Niebla (color, inicio–fin) | pardo oscuro, 4–46 m | blanco azulado, 8–34 m | gris, 12–80 m |
| Sol (color / energía) | ámbar, 0,3 | blanco frío, 0,5 | arena pálida, 0,95 |
| Tono (brillo / contraste / saturación) | 0,95 / 1,12 / 1,10 | 1,06 / 1,00 / 0,75 | 1,00 / 1,05 / 0,80 |
| Tinte al derrotar al jefe | ámbar (1, 0,84, 0,7) | azul (0,8, 0,88, 1) | oro pálido (1, 0,94, 0,72) |

Al derrotar al jefe aparece, con un fundido de 2,5 s, un tinte multiplicativo sutil sobre el mundo (por debajo del HUD) que dura hasta cambiar de escena.

**Rejas y triggers (nombres fijos en todas las arenas):** `GateEntry` (sur, se cierra al entrar), `GateExit` (norte, se abre con `Events.boss_defeated`), `ExitTrigger` (`Area3D` tras `GateExit`, lleva al piso siguiente), `PlayerStart`, `BossStart`, 6 `Marker3D` en el grupo `spawn_point`.

**Final dentro de `arena_3`:** detrás de `GateExit` (la "puerta bloqueada") sale un pasillo de 6 m de ancho (el de la reja) y ~20 m de largo hacia la **sala de Elysia** (12 × 12 m, techo 6 m) con el altar, Elysia estática mirando hacia el pasillo y un `EndingTrigger` (`Area3D`) delante de ella. La lógica (texto, cámara, créditos) la conecta A con `ending_director.gd`; las cámaras fijas son `EndingCam1` y `EndingCam2` dentro de la sala.

**Sala de Elysia rota (la isla cae):** la sala está dentro de la isla y la isla está cayendo. El muro norte tiene un hueco irregular (cortes sustractivos `BreakWall*` y `BreakCeil*` que añade `_break_room()` en `level_builder.gd`, solo en la sección de `arena_3`) que sube hasta el techo, así que desde el altar se ve el cielo. `scenes/props/ending_room.tscn` (`scripts/game/ending_room.gd`, instanciada en `arena_3_gameplay.tscn` con su origen en el centro del muro norte, z = −57,5) pone lo demás: fondo de cielo con degradado, escombros y bloques del kit (`wall_ruin`, `pillar_collapsed`) y primitivas con la textura de concreto, grietas oscuras en suelo y muros, luz fría del cielo y una `SafetyBarrier` invisible que tapa el hueco (Kaelen no puede salir ni caer; los bloques grandes también tienen colisión y nada estorba el camino entre la puerta y el `EndingTrigger`).
- **Ilusión de caída:** la sala no se mueve; hacia arriba se desplazan nubes (`CPUParticles3D`), rachas de viento, los islotes del exterior (`islet_*`) y fragmentos de la propia isla, con parallax (lo lejano sube más despacio). Todo lo exterior solo se dibuja y se mueve con la cámara cerca de la sala.
- **Activación:** durante el combate y al entrar a la sala el hueco muestra una deriva lenta (10 % de velocidad). `EndingDirector.play()` llama `start_fall()` (grupo `ending_room`): en 2,5 s la velocidad sube al 100 %, empieza a caer polvo y guijarros del techo y la cámara activa tiembla levemente. Los planos `EndingCam1` y `EndingCam2` miran hacia el norte con el hueco y la caída detrás de Elysia.
- **Viento (VFX):** las rachas son un `StormFX` "gust" de aire (Storm & Wind 3D Free) que sopla hacia arriba, apagado hasta `start_fall()` y formándose durante los mismos 2,5 s de la aceleración. Por indicación de diseño el viento no se ve dentro de la sala: el efecto está a 34 m por detrás del muro norte (toda su extensión queda más allá de `GUST_MAX_Z`, tras la barrera) y solo se percibe a través del hueco; el sonido del viento (`wind_fall.mp3`) se mantiene. Dentro de la sala solo cae un polvo escaso cerca del hueco (14 partículas, gris apagado) y los guijarros del techo.
- **Materiales y tono (final melancólico):** el muro norte y el altar de la sala dejaron la textura dorada y usan la misma piedra de la mazmorra que el resto de muros de `arena_3`; los bloques caídos usan el concreto del kit y las piezas `wall_ruin` / `pillar_collapsed`. El cielo visible por el hueco pasó de un atardecer cálido a uno frío y apagado (horizonte malva grisáceo, medios azul acero, resplandor tenue, nubes grisáceas) y la luz de cielo de la sala baja de 1,4 a 1,15 con tono más frío, sin ocultar a Kaelen ni a Elysia (la luz cálida del altar no cambia). FPS en el final, medidos sin vsync: sin diferencia apreciable (≈300 antes y después).
- **Audio:** `assets/audio/sfx/ambient/wind_fall.mp3` (WIND-FALL, aportado por la autora del proyecto) suena en bucle desde `start_fall()` con su propio `AudioStreamPlayer` en el bus SFX a -9 dB (por debajo de los diálogos y la música): entra con un fundido de 2,5 s sincronizado con la aceleración y `EndingDirector._finish()` lo baja en 1,2 s (`stop_wind`) justo antes de pasar a créditos.

**Diálogo del final (la isla cae y Kaelen no se arrepiente):** Kaelen derrotó a los tres guardianes (Bone Dragon, Blackhorn y Mecha King Ghidorah) para llegar a Elysia, y esos tres guardianes eran lo que mantenía la isla en el aire: al caer, condenó a todos sus habitantes. Elysia lo comprende en cuanto nota el temblor; el tono es melancólico y triste, sin reproche duro, y Kaelen no se arrepiente: solo quería verla otra vez. Terminan aceptando caer juntos. Son 19 líneas (`ENDING_01`..`ENDING_19` en `localization/translations.csv`, una línea por clave y por hablante; el prefijo "Kaelen:" / "Elysia:" se mantiene en ambos idiomas solo para detectar quién habla y no se muestra):

1. (narrador) Tres pisos de acero y sangre. Y en lo alto del templo, una luz que seguía encendida.
2. Kaelen: Elysia... por fin te encuentro.
3. Elysia: Kaelen. Sabía que vendrías. Siempre lo supe.
4. (narrador) El suelo tiembla. Del techo roto cae polvo, y el cielo se abre sobre el altar.
5. Elysia: ¿Lo sientes? La isla ya no flota.
6. Elysia: Los tres guardianes la mantenían en el aire. Y tú los has vencido.
7. Kaelen: No había otro camino hasta ti.
8. Elysia: Aquí vive gente, Kaelen. Familias. Niños. Todos caerán con nosotras.
9. Elysia: Esa es la parte que más duele.
10. Kaelen: Lo sé. Y aun así lo volvería a hacer.
11. Kaelen: No vine a salvar a nadie. Vine a verte otra vez. Solo eso.
12. (narrador) Elysia baja la mirada. Más allá del hueco, una torre se desprende y se pierde entre las nubes.
13. Elysia: Debería odiarte por esto. Pero no puedo. Ni siquiera ahora.
14. Elysia: Esperé tanto tu luz... y llega justo cuando todo se apaga.
15. Kaelen: Entonces no la soltemos. Que la caída nos encuentre juntas.
16. Elysia: Juntas, entonces. Aunque no quede cielo al que volver.
17. (narrador) Se abrazan mientras el suelo se desprende del cielo.
18. Elysia: Cierra los ojos, Kaelen. Caer también es una forma de volar.
19. (narrador) Y el templo, con sus muertos y sus velas, se hundió despacio en las nubes.

- **Avance:** el diálogo ya no pasa solo. Cada línea se revela con el `Typewriter` (30 car/s, pausas en la puntuación); una pulsación durante el revelado completa la línea y, con la línea completa, la siguiente pulsación pasa a la siguiente. Aceptan ataque (clic izquierdo, RB), `ui_accept` (Enter, Espacio, A del mando). Tras empezar o completar una línea se ignora (y se consume) la entrada durante 0,15 s y cada pulsación emite `advanced` una sola vez, así que una ráfaga no salta varias líneas. Con la línea completa parpadea un triángulo ▼ en la esquina de la caja.
- **Caja (`DialogueBox`, `scripts/ui/dialogue_box.gd`):** banda negra semitransparente abajo (112 px, el mismo degradado vertical que la banda de "HAS MUERTO", opacidad 0,88) sobre la escena a 640x360; arriba el nombre del hablante en DungeonFont (`TitleLabel` de `menu_theme.tres`, 26 px; Kaelen rojo apagado, Elysia azul pálido) y debajo su texto (14 px, hasta 2 líneas). Se muestra una línea de un solo hablante cada vez; la narración no lleva nombre y va centrada en gris. Funciona igual en español e inglés.
- **Cámara:** `ENDING_LINES` de `EndingDirector` asocia cada línea a un plano (1 = `EndingCam1` lejana, 2 = `EndingCam2` cercana): líneas 1-4 lejos (encuentro), 5-9 cerca (la verdad), 10-12 lejos (la isla se desprende), 13-18 cerca (despedida) y la última, lejos. La cámara cambia justo cuando empieza la primera línea del plano. `total_duration()` pasó a ser solo la duración mínima (revelado de las líneas + entrada + abrazo), porque el resto depende del jugador. La música del final baja 7 dB (ducking, `AudioManager.duck_music`) mientras dura el diálogo para que se oigan los blips y se recupera antes del fundido.
- **Blips (causa de que no sonaran):** los archivos de dmochas llegan con pico de -17 a -25 dBFS y RMS de -30 a -36 dBFS; con el volumen que se les daba (-12 / -15 dB) y el cambio de tono 0,85 de Kaelen (fundamental ~200 Hz) el pico medido en el bus UI era de -33 dB (Kaelen) y -32 dB (Elysia), frente a -10 dB de un sonido de interfaz: ~22 dB más bajos, inaudibles bajo la música. El bus UI existía, no estaba silenciado ni atenuado (0 dB), y el árbol no se pausa en el final. Ahora los blips se normalizan a -3 dBFS de pico (`scripts/tools/make_dialogue_blips.py`): Kaelen usa tres sonidos graves (~280-410 Hz, tono 0,9, -4 dB) y Elysia tres agudos (~680-790 Hz, tono 1,12, -7 dB). Pico medido en el bus UI con la ventana abierta: -5,8 dB (Kaelen) y -8,8 dB (Elysia). Se alternan dos reproductores para que un blip no corte al anterior en seco. Las pruebas miden pico y RMS de cada archivo y que el bus UI exista y no esté silenciado. Los blips siguen en el bus UI, de modo que el volumen de Interfaz de Opciones también regula las voces.

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
- **Retirada y órdenes de posición:** un esbirro normal con la vida por debajo del 30 % se aleja unos segundos antes de volver; durante la pinza del jefe (§8.4) recibe del Orquestador un punto de cerco al que ir y en el que quedarse en `Rodear`.

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

**Repulsión (anti ráfagas de daño).** Para que el jugador no encadene golpes sin parar ni se quede pegado al jefe, cada jefe reacciona cuando se cumple **cualquiera** de estas tres condiciones (y el enfriamiento terminó):

1. Recibe al menos el **10 % de su vida máxima** en una ventana deslizante de **4 s** (50 de 500 en Bone Dragon, 63 de 625 en Blackhorn, 75 de 750 en Ghidorah; dos golpes del combo ya bastan en Bone Dragon). Antes era el 15 %.
2. Recibe **3 golpes en 3 s**, aunque hagan poco daño.
3. Kaelen permanece a **3,2 m o menos** del jefe durante **7 s** (el contador baja al doble de velocidad si se aleja). Evita esconderse bajo el cuerpo de Ghidorah.

La reacción:

- Interrumpe lo que esté haciendo, **también la recuperación** (antes esperaba al final de la ventana de castigo y llegaba tarde): el objetivo es cortar el encadenado. Solo se pospone durante el rugido de transición de fase o tras la muerte; si el golpe que supera el umbral también activa la fase 2, gana la transición de fase.
- Reproduce la misma animación de rugido y el mismo sonido que la fase 2, sin cambiar de fase. El rugido se corta a un máximo de **1,6 s** para que no sea un descanso. Mientras ruge es **invulnerable**.
- **0,35 s después** de empezar a rugir (el aviso) sale una **onda de choque**: un anillo naranja que crece desde el suelo del jefe hasta el radio de **7 m** (antes 6 m) y una sacudida de cámara de 0,18 m durante 0,45 s.
- Si Kaelen está dentro del radio, sale empujada hacia fuera a **18 m/s** con un pequeño salto de **3 m/s**; la velocidad decae a 0 en **0,5 s**, es decir, recorre unos **4,5 m** (antes 11 m/s y 0,4 s: 2,2 m, menos que el alcance de su espada, por eso no se notaba). No recibe daño pero pierde el control mientras dura (estado de aturdimiento).
- La **rodada solo lo esquiva en el momento justo**: sus i-frames (0,05-0,40 s de la rodada) deben cubrir el instante de la onda. Con la onda 0,35 s después del rugido, hay que rodar entre 0,40 s y 0,05 s antes de ese instante; si se rueda demasiado pronto o tarde, la onda empuja igual. También lo ignoran la muerte, las cinemáticas y la victoria.
- **Enfriamiento de 7 s** (antes 9 s); el daño recibido en ese tiempo no cuenta.

Todos los valores (`repel_threshold`, `repel_window`, `repel_burst_hits`, `repel_burst_window`, `repel_glue_time`, `repel_glue_radius`, `repel_cooldown`, `repel_radius`, `repel_force`, `repel_push_time`, `repel_lift`, `repel_push_delay`, `repel_roar_max`, `repel_enabled`) se exportan por jefe.

**Medición** (`scripts/tools/boss_pressure_sim.gd`: usa el `Boss` real, avanzado a 60 Hz, con una Kaelen simulada que encadena el combo 20/20/36 con 85 % de acierto, limitada por aguante y que rueda el 70 % de los ataques; 12 ejecuciones por celda). "Constante" golpea sin parar; "oportunista" solo golpea durante la recuperación del jefe (2 golpes por ventana).

| Jefe / perfil | Repulsiones en 30 s (antes → ahora) | Ataques del jefe en 30 s | Tiempo para matarlo (antes → ahora) |
|---|---|---|---|
| Bone Dragon / constante | 2,00 → 2,83 | 7,7 → 10,3 | 31,5 s → 31,9 s* |
| Bone Dragon / oportunista | 2,00 → 3,00 | 7,0 → 9,7 | 38,5 s → 42,1 s |
| Blackhorn / constante | 2,25 → 3,00 | 9,5 → 11,2 | 35,9 s → 46,0 s |
| Blackhorn / oportunista | 1,92 → 2,25 | 8,1 → 10,0 | 45,3 s → 50,4 s |
| Ghidorah / constante | 1,75 → 3,00 | 8,6 → 10,8 | 43,3 s → 55,7 s |
| Ghidorah / oportunista | 0,83 → 2,50 | 8,2 → 9,8 | 48,5 s → 60,7 s |

\* El Bone Dragon es el primer jefe y se mantiene como el más fácil; la vida extra se compensa con un rugido más corto. La Kaelen simulada es mucho más eficiente que una persona, así que los tiempos reales serán mayores. Aun así, ahora la repulsión se activa cada ~9-10 s de presión (siete de enfriamiento más el rugido), y su efecto se nota: el empuje es de 4,5 m y la rodada ya no la esquiva sin cuidado.

**Dificultad general (cifras).** Vida: Bone Dragon 400 → **500**, Blackhorn 500 → **625**, Ghidorah 600 → **750** (+25 %). Tiempo muerto entre ataques (`attack_cooldown`): 0,4 → **0,25 s** (Bone Dragon), 0,5 → **0,3 s** (Blackhorn), 0,6 → **0,35 s** (Ghidorah). Avisos y recuperaciones (s) y daño por ataque:

| Ataque | Aviso | Recuperación | Daño |
|---|---|---|---|
| Bone Dragon: mordida | 1,10 → 0,95 | 1,00 → 0,80 | 25 → 28 |
| Bone Dragon: pisotón | 1,45 → 1,20 | 1,20 → 0,95 | 30 → 34 |
| Bone Dragon: barrido de cola | 1,20 → 1,00 | 1,00 → 0,80 | 20 → 23 |
| Blackhorn: golpe al suelo | 1,35 → 1,15 | 0,90 → 0,75 | 20 → 23 |
| Blackhorn: zarpazo | 1,90 → 1,50 | 1,10 → 0,90 | 18 → 21 |
| Blackhorn: embestida | 1,00 → 0,90 | 1,40 → 1,10 | 25 → 28 |
| Ghidorah: mordida | 1,10 → 0,95 | 1,00 → 0,80 | 12 → 14 |
| Ghidorah: barrido de cola | 1,20 → 1,00 | 1,20 → 0,95 | 10 → 12 |
| Ghidorah: rayo | 1,10 → 1,00 | 1,30 → 1,00 | 14 → 16 |

**Hitboxes de ataque.** Las zonas de daño deben cubrir lo que muestra la animación y no dejar zonas seguras pegado al jefe. `scripts/tools/boss_hitbox_map.gd` reproduce cada ataque, recorre su ventana activa y dibuja qué puntos del suelo alcanzaría Kaelen; mide el porcentaje de zona libre dentro del rango del ataque (cono de unos 30° delante del jefe). Cambios (antes → ahora):

- Bone Dragon: mordida, esfera r 1,2 → **1,7** (la zona libre en su cono bajó del 50 % al 19 %); pisotón r 2,5 → **2,9** y desplazada a z −1,2; barrido de cola, caja de 1,6 × 2 × 4,5 que empezaba a 0,75 m del cuerpo → **2,2 × 2,2 × 5,5** que empieza en el cuerpo.
- Blackhorn: golpe al suelo, r 3,0 → **3,8** (llega a su `max_range` de 4 m; zona libre 18 % → 2 %); zarpazo 2 × 2 × 4 → **3,2 × 2,4 × 5** y adelantado hasta el cuerpo (zona libre 49 % → 30 %); embestida 1,5 × 2,5 × 3 → **2,4 × 2,5 × 4** (arranca pegada al jefe).
- Ghidorah: la caja del barrido de cola (2,5 × 3 × 6, a 3,5-9,5 m) dejaba un hueco de 3,5 m alrededor del cuerpo aunque el aviso lo pintaba de rojo → **2,8 × 3 × 9,6** desde el cuerpo hasta el borde del aviso (zona libre 29 % → 0 %). La mordida ya no tenía huecos (0 %).
- Los avisos del suelo se ajustaron al mismo tamaño que cada nueva zona de daño.

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

**Balance (2026-10-15, `scripts/tools/orchestrator_sim.gd`):** simulación del modelo real a 10 Hz (30 ejecuciones de 180 s por arena y por perfil de Kaelen). Con la regla de grupos de 2-3 esbirros con 1 élite la intensidad oscila en las tres arenas (mínimo 0, máximo 100, oscilaciones medias de 45-69 puntos, 0,2-2 entradas al PICO por minuto, respiros de ~20 s). Como la vida máxima baja a 70 y 40, el mismo golpe pesaba más en la arena 3 y la intensidad no pasaba de 85; ahora el daño que recibe el modelo se escala a medias hacia una vida de 100 (`OrchestratorModel.hp_damage_scale`: x1,0 / x1,2 / x1,8).

**Vista de depuración (F3):** muestra en pantalla intensidad, fase, tamaño del último grupo, esbirros vivos, fichas de ataque asignadas, la **meta táctica actual del jefe** y el **comportamiento detectado de Kaelen** (huyendo, con esbirros, pegada, pasiva, y si está distraída). Sirve para la presentación y para ajustar valores.

### 8.4 Tácticas del jefe y coordinación de escuadra
Hasta aquí el jefe decidía **qué ataque** usar, pero entre ataques siempre hacía lo mismo: perseguir a Kaelen por detrás hasta `engage_range`. Siguiendo la idea de *Three States and a Plan: The A.I. of F.E.A.R.* (Orkin, GDC 2006) —comportamiento complejo que sale de **órdenes simples**, una **memoria compartida** y una coordinación **legible** para el jugador— se añade una capa de decisión por encima de la selección de ataques. No es un planificador (ni GOAP ni A* sobre acciones): son **metas puntuadas por utilidad**, una memoria de combate y un coordinador de escuadra.

**Memoria de combate** (`scripts/ai/combat_memory.gd`, lógica pura). El jefe la actualiza a **10 Hz**. Guarda la posición y velocidad **suavizadas** de Kaelen, la variación de su distancia al jefe y una **posición prevista a ~1 s** (velocidad limitada a 7 m/s para que una rodada no dispare la predicción; el jefe la limita además al navmesh). Con eso detecta:

| Comportamiento | Cuándo |
|---|---|
| HUYENDO | la distancia al jefe crece > 1 m/s con Kaelen a > 2,2 m/s durante 0,8 s (a > 4,5 m; se olvida tras 1,2 s de calma) |
| CON ESBIRROS | su objetivo fijado es un esbirro, golpea a uno a < 3 m, el esbirro más cercano está a menos de la mitad de distancia que el jefe, o va decidida hacia uno |
| PEGADA | permanece a ≤ 3,8 m durante 2 s |
| PASIVA | lejos (≥ 7 m) durante 3 s sin atacar, huir ni ir a por esbirros |

Marcas independientes: *distraída* (con esbirros, o de espaldas al jefe) y *rodeando* (> 2,2 m/s tangenciales a < 7 m). El lado preferido de rodada sigue siendo `BossBrain.dodge_bias`.

**Metas del jefe** (`scripts/ai/boss_tactics.gd`, lógica pura). Cuando no está en mitad de un ataque se reevalúa cada **0,5 s** (y al acabar una recuperación o un rugido, que es cuando de verdad decide). Cada meta tiene una puntuación; la meta actual puntúa ×1,3 (histéresis) y debe durar ≥ 1 s. Las que no son ATACAR caducan y quedan en enfriamiento.

| Meta | Se activa cuando | Qué hace | Tope / enfriamiento |
|---|---|---|---|
| ATACAR | por defecto (1,0; ×1,25 en fase 2) | acercarse y atacar, como siempre | — |
| CORTAR PASO | Kaelen huye a > 6 m (1,5-2,1), o está pasiva a > 10 m (0,9) | va al **punto previsto** a 1,5 s en vez de seguirla por detrás; solo puede lanzar ataques de apertura (embestida, salto, rayo) | 4 s / 2,5 s |
| ESPERAR | combo largo (≥ 16 % de su vida en 4 s: 1,4), recién repelida (< 3 s: 1,5), vida < 30 % (0,5), Kaelen pasiva (1,1) | **no ataca**: se retira y la rodea a ~8 m a velocidad ×0,6; Blackhorn hace además su burla (`taunt`). Un respiro legible. En fase 2 vale ×0,6 | 2,4 s / 7 s |
| PINZA | hay esbirros y Kaelen va con ellos, entre 4 y 18 m (1,5; 1,8 con 2 o más; ×1,2 en fase 2) | el jefe se planta en su lado a 6 m (sin lanzar ataques de apertura) y **ruge brevemente (≤ 1,1 s)** para anunciarlo; el Orquestador manda a los esbirros a los puntos de cerco | 4 s / 9 s |

**Emboscada.** Si Kaelen está distraída (con esbirros o de espaldas) y el jefe aún no la alcanza, se acerca a velocidad ×0,6 y el ataque que lance tiene un **aviso ×1,3 más largo** (la animación se frena en proporción para seguir sincronizada): más peligroso por pillarla distraída, pero más legible.

**Especialización.**
- **Blackhorn**: la embestida y el salto (`intercept_attacks`) se apuntan al **punto previsto** de Kaelen a 1 s si ella se mueve a > 1,8 m/s (intercepción); burla en ESPERAR.
- **Bone Dragon**: si Kaelen intenta rodearlo, el **coletazo** puntúa ×2,2 (`circling_attack`).
- **Ghidorah** (demasiado grande para moverse en pinza): usa el **rayo para cortar la huida**. `GhidorahBeamAim` pide al jefe el punto previsto (delante de la dirección de huida) para la franja, que sigue fijándose al 70 % del aviso; como el impacto tarda `active_time` en recorrerla desde Ghidorah, sigue siendo esquivable moviéndose en ángulo o rodando.

**Pinza y escuadra** (`scripts/ai/squad_tactics.gd`). Cuando la meta es PINZA, el Orquestador (cada 0,35 s) calcula `pincer_points`: tantos puntos como esbirros libres, a **3,6 m de Kaelen y en el lado opuesto al jefe** (abanico de 55° entre vecinos centrado a 180° del jefe), los reparte con `assign_points` (asignación voraz por cercanía) y envía `order_to` a cada esbirro: va al punto y se queda en `Rodear` allí hasta que la orden caduca (0,9 s, se renueva mientras dure la pinza). La orden es la única interfaz nueva de los esbirros (los papeles completos de escuadra quedan para otra fase).

**Amenazas compartidas.** Mientras el jefe está en AVISO o ACTIVO, `AttackTokens` no reparte fichas nuevas si Kaelen está a ≤ 10 m (`SquadTactics.token_slots`: 0 fichas con el jefe cerca; 1 con una amenaza lejana como el rayo; 2 sin amenaza). Un esbirro que ya tenía ficha pero aún no atacaba la devuelve. Así nunca se acumulan el ataque del jefe y los de los esbirros de cerca.

**Retirada de esbirros.** Un esbirro **normal** (no élite) con vida < 30 % deja de atacar: se aleja durante 3,5 s hasta ~9 m de Kaelen (sin pedir ficha) y vuelve. Una vez por vida.

**Medición** (`scripts/tools/boss_tactics_sim.gd`: `Boss` real avanzado a 60 Hz y el código real del Orquestador para la pinza; esbirros simples en oleadas de 3; 8 ejecuciones de 120 s por celda; "antes" = `tactics_enabled = false`, es decir, el comportamiento anterior). "Agresiva" va pegada al jefe y rueda ~50 % de los avisos; "huidiza" kitea a 9-13 m, mata esbirros y solo entra a castigar cuando el jefe se recupera. El daño usa un modelo geométrico simple de los volúmenes de ataque (sirve para comparar, no como cifra absoluta):

| Jefe / perfil | Daño recibido por Kaelen por min (antes → después) | % del tiempo: ATACAR / CORTAR / ESPERAR / PINZA | Cortes · pinzas · esperas por min | Tiempo para matar al jefe (antes → después) |
|---|---|---|---|---|
| Bone Dragon / agresiva | 370 → 312 | 77,5 / 8,8 / 6,4 / 7,2 | 3,7 · 1,8 · 3,7 | 29 s → 30 s |
| Bone Dragon / huidiza | 222 → 212 | 62,4 / 27,0 / 2,1 / 8,5 | 5,1 · 2,3 · 1,0 | 85 s → 107 s |
| Blackhorn / agresiva | 333 → 303 | 78,3 / 5,8 / 6,3 / 9,5 | 1,6 · 2,4 · 1,8 | 39 s → 38 s |
| Blackhorn / huidiza | 295 → 249 | 66,3 / 22,5 / 1,5 / 9,7 | 4,3 · 2,4 · 0,7 | 75 s → 90 s |
| Ghidorah / agresiva | 327 → 285 | 80,7 / 7,5 / 5,0 / 6,7 | 2,9 · 1,8 · 2,9 | 47 s → 46 s |
| Ghidorah / huidiza | 179 → 176 | 63,8 / 28,5 / 0,2 / 7,6 | 4,7 · 1,9 · 0,1 | no muere en 120 s (ni antes ni después) |

Lectura: contra una Kaelen pegada al jefe, los respiros (ESPERAR, el rugido de la pinza y el aviso largo de la emboscada) **reducen** el daño un 8-16 % sin cambiar el tiempo para matarlo. Contra una Kaelen que huye, el daño se mantiene o baja (el jefe la persigue con intención, pero también pierde tiempo reposicionándose) y el tiempo para matarlo sube un 20-25 %, porque el jefe ya no se queda parado a su alcance al recuperarse. Como el daño por minuto no sube, **no se tocó el daño de los ataques** (`resources/attacks/*.tres`); la compensación de equilibrio son las ventanas de respiro y los avisos legibles descritos arriba.

## 9. HUD
- Barras de vida y estamina (esquina superior izquierda).
- Contador del frasco de curación bajo las barras: icono de frasco y "x10"; se atenúa al llegar a 0.
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

### 10.3 Menú de opciones (implementado)
Se abre desde el menú principal y desde la pausa (overlay `scenes/ui/options_menu.tscn`). Cuatro pestañas
(LB / RB con el mando):
- **Controles:** lista de acciones con su tecla/ratón y su botón de mando; se elige una fila, se pulsa
  Enter / A / clic y luego la nueva tecla o botón (Esc o Back cancelan). Si la entrada ya la usaba otra
  acción, intercambian. Los sticks (mover y cámara) son fijos. Sensibilidad de cámara (ratón y stick
  derecho) y "Restaurar por defecto".
- **Volumen:** General (Master), Música, Efectos y Interfaz, en vivo sobre los buses de audio.
- **Pantalla:** modo de ventana (Ventana / Pantalla completa sin bordes, una ventana sin marco del tamaño del monitor, con cambio de ventana rápido / Pantalla completa exclusiva, que toma el control de la pantalla), resolución de ventana (solo en modo ventana: 1280x720, 1920x1080 y 2560x1440, múltiplos enteros de 640x360 que quepan en el monitor; la ventana se centra), sincronización vertical y límite de FPS (sin límite / 30 / 60 / 120). Se aplican en vivo, al iniciar el juego, y los valores no válidos del archivo vuelven a los de por defecto (ventana, 1280x720, VSync activado, sin límite). Alt+Enter alterna entre ventana y pantalla completa en cualquier momento.
- **Idioma:** español / inglés (`localization/translations.csv`, claves `tr()`).
Todo se guarda en `user://settings.cfg` (`ConfigFile`, autoload `UserSettings`) y se carga al iniciar.

**Controles por defecto**

| Acción | Teclado y ratón | Mando Xbox |
|---|---|---|
| Mover | W A S D | Stick izquierdo (LS) |
| Cámara | Ratón | Stick derecho (RS), zona muerta 0,2, curva cuadrática |
| Atacar | Clic izquierdo | RB y X |
| Rodar | Espacio | B |
| Curarse (frasco) | R | Y |
| Fijar objetivo | Clic central / Q | R3 (clic del stick derecho) |
| Pausa | Esc | Start |
| Menús: moverse / aceptar / volver | Flechas / Enter / Esc | D-pad o stick izquierdo / A / B |
| Opciones: cambiar de pestaña | — | LB / RB |
| Alternar pantalla completa | Alt + Enter | — |
| Depuración | F3 / F5 / F6 | — |

Atacar (o Enter / Espacio / A del mando / clic) avanza los diálogos del final: no pasan solos. Distribución tipo Dark Souls: RB ataque, B rodar,
Y curarse, R3 fijar, sin botón de guardia (el juego no la tiene); LB, LT, RT y A quedan libres.

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

### 12.1 Rendimiento: precalentamiento de efectos de los jefes
En gl_compatibility cada shader se compila la primera vez que se dibuja. En el nivel 3 eso producía tirones al lanzar ataques de Ghidorah. Se midió con `scripts/tools/ghidorah_profile.gd` (nivel `arena_3_gameplay` con ventana, sin vsync; fuerza dos rondas de mordida, barrido de cola y rayo y registra el tiempo de cada fotograma; GTX 1050, 1280 × 720):

| Medida | Antes | Después |
|---|---|---|
| Fotograma más lento en el primer rayo | **71-125 ms** (según la caché de shaders del controlador) | **≤ 20 ms** |
| Fotograma más lento de toda la sesión | 71-125 ms | 20 ms |
| Primera mordida / primer barrido de cola | 20-47 ms | ≤ 17 ms |
| Media / mediana / p99 durante los ataques | 3,6 / 3,3 / 6,2 ms | 3,6 / 3,3 / 6,2 ms |

Causa: el rayo (5 shaders y 2 sistemas de partículas GPU) y los avisos rojos del suelo se compilaban en el primer disparo; el resto del coste de un ataque es despreciable (los fotogramas con ataque activo cuestan lo mismo que sin él). Corrección: `ShaderWarmup` dibuja una vez, en la carga y fuera de pantalla (un `SubViewport` de 64 × 64 con su propio mundo 3D), una copia de cada efecto y de cada aviso de los ataques del jefe, y se libera a los 3 fotogramas; además cada animación de ataque se reproduce una vez al cargar para que el `AnimationPlayer` resuelva sus pistas. No se ejecuta sin ventana (pruebas).

### 12.2 Efectos de impacto y sellos (Storm & Wind 3D Free y Magic Circles 3D Free)
Los dos paquetes se copian como recursos sueltos (`addons/storm_wind`, `addons/magic_circles`, con su `LICENSE.txt`, CC BY 4.0) y no se activa ningún plugin: sus clases (`StormFX`, `MagicArea`) y shaders funcionan por ruta. Los paquetes 2D del bundle (VFX 2D, Sprite FX, Weather FX, Scene Transitions, Retro Screen FX) usan shaders `canvas_item`, y PSX Look / Retro Screen duplican el post-proceso propio (`shaders/psx/`), así que no se integraron.

`ImpactFx` (`scripts/vfx/impact_fx.gd`) es un único nodo colgado de la raíz con reservas fijas de `CPUParticles3D` de un disparo (6 de chispas y 4 de polvo) que se reutilizan, así que golpear no crea nodos ni mallas. Todos dibujan con `spark.gdshader` de Storm & Wind en modo tramado (`dither`, como el aspecto PSX).

| Efecto | Dónde |
|---|---|
| Chispas en el punto de golpe (metal: más; hueso: chispas y polvo; carne: pocas, rojizas) | `Events.hit_landed`, que ya emite `Hitbox`; no se tocó `hitbox.gd` |
| Polvo al rodar | `PlayerController.try_roll` |
| Polvo en golpes al suelo (`slam`, `stomp`, `pounce`) | `Boss._begin_active` |
| Humo oscuro con brasas | muerte de un esbirro (`Minion._die`) |
| Sello de fuego que se cierra justo antes de la onda (aviso) | `Boss.start_repel` (radio = `repel_radius`, forma durante `repel_push_delay`) |
| Sello de sangre de 5 m | rugido de la fase 2 (`Boss._physics_process`) |
| Onda de brasas en el suelo y esfera de impacto más pequeña y cálida | rayo de Ghidorah (`BeamVfx`, escena `beam_vfx.tscn`) |
| Racha de aire que sube por el hueco | final (`EndingRoom`) |

Rendimiento: `ShaderWarmup` añade al `SubViewport` de precalentamiento una muestra de cada efecto nuevo (chispas, polvo, sello, onda y racha), así que no vuelven los tirones del primer uso. Medido con `ghidorah_profile.gd` en `arena_3_gameplay` antes y después (GTX 1050, 1280 × 720, sin vsync, dos rondas): fotograma más lento 27,7 → 20,9 ms, media 5,4 → 4,0 ms (los números absolutos varían con la carga de la máquina; sin tirón nuevo en el primer rayo ni en las primeras mordidas).

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
