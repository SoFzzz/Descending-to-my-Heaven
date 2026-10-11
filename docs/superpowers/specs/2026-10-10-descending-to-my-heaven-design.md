# Descending to my Heaven — Documento de Diseño

- **Fecha:** 2026-10-10
- **Equipo:** 3 personas, dedicación completa durante 7 días
- **Motor:** Godot 4.3+ (GDScript)
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
- IA de esbirros, IA de selección de ataques del jefe y Orquestador (sección 7).
- Vida máxima decreciente por nivel: 100% → 70% → 40%.
- Muerte → reaparece al inicio del enfrentamiento actual; el jefe se reinicia.
- Escena final con Elysia → créditos.
- Menú principal y menú de pausa (sección 9).
- Efectos de sonido y música (sección 10).
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
| Kaelen | Malla generada a partir del concept art (capucha, capa, armadura borgoña) reducida a ~5k triángulos; referencia de armadura: `low-poly-woman-knight` | Rig + animaciones Mixamo; capa separada (rígida al pecho o con huesos de resorte) |
| Elysia | `elisya.fbx` (vestido, 497k triángulos) reducida a ~5k triángulos | Rig Mixamo; idle, levantarse, abrazo |
| Arma de Kaelen | `demonic weapons pack/greatsword` (ya tiene .glb) | Adjunta al hueso de la mano (`BoneAttachment3D`) |
| Jefe 1 | `bonedragon` | Rig propio de dragón (cola, cuello, mandíbula, alas, patas con IK); animaciones creadas en Blender + movimiento procedural |
| Esbirros 1 | `Skeleton` | Sin rig → Mixamo |
| Élite 1 | `knight__ps1_psx` | Rig → Mixamo |
| Jefe 2 | `MaleniaPsx` | Rig propio + idle; ataques Mixamo reasignados (retarget en Godot) |
| Esbirros 2 | `Plague Arcanist` | Rig Mixamo + 10 animaciones |
| Jefe 3 | `mecha-king-ghidorah` (reducir de 26k a ~8k triángulos) | Rig propio (3 cuellos, 2 colas, alas); animaciones creadas en Blender + movimiento procedural |
| Esbirros 3 | `TheWrapper V2` | Rig propio + 6 animaciones (embestida, idle, correr, grito, caminar, golpe) |
| Élite 3 (opcional) | `aura_battler_dunbine` | Sin rig: mecha flotante animado por piezas rígidas (flotar, embestida, giro) |
| Escenarios | `float-islands`, `PSX_Dungeon`, `Modular Dungeon Free Edition`, `modulardungeontextures` | Estáticos |
| Reserva | `psx_insectoid_demon` (jefe 3 si Ghidorah falla), `DoriOri` | Sustitutos si algo falla al importar |

**Regla de sustitución:** si el día 1 un modelo no importa bien o no se puede animar, se reemplaza por uno de reserva ese mismo día. No se gastan más de 2 horas peleando con un asset.

**Animaciones mínimas:**
- Kaelen: idle, caminar, correr, rodar, ataque 1-2-3, recibir golpe, morir.
- Esbirro: idle, caminar, atacar, recibir golpe, morir.
- Jefe: idle, moverse, 3 ataques, morir. Lo que falte se simula con tweens (inclinar, embestir, sacudir).
- Dragones (jefes 1 y 3): las animaciones base (idle, rugido, mordida, barrido de cola, pisotón, muerte) se crean con keyframes en Blender sobre su rig; en Godot se suma movimiento procedural (ondulación de cuellos y colas, respiración) para que no se vean rígidos.


## 4. Combate (valores iniciales, se ajustan en el día 6)

| Parámetro | Valor |
|---|---|
| Vida base Kaelen | 100 (nivel 1), 70 (nivel 2), 40 (nivel 3) |
| Daño de golpe de esbirro / jefe | 20 / 20-35 |
| Estamina | 100; regenera 30/s tras 0.6 s sin gastar |
| Costo rodar / atacar | 25 / 20 |
| Invulnerabilidad al rodar | 0.35 s de 0.6 s |
| Daño de Kaelen | 10 / 10 / 18 (golpe 3 del combo) |
| Vida esbirro | 30 |
| Vida jefe | 400 / 500 / 600 |
| Fase 2 del jefe | al 50% de vida: +25% velocidad de ataque, más presupuesto al Orquestador |

Impactos: hitbox `Area3D` activada en ventanas de la animación; hurtbox en cada personaje. Feedback: pausa de impacto (~60 ms), parpadeo de material, partículas simples, sonido.

## 5. Flujo del juego

```
Menú principal → Llegada a la isla / entrada al templo
  → Jefe 1 (Bone Dragon)
  → Jefe 2 (Malenia)
  → Jefe 3 (Mecha King Ghidorah)
  → Encuentro con Elysia (cámara fija + texto) → Créditos → Menú principal
```

Al ser un *boss rush*, no hay exploración entre jefes: cada transición es corta (escalera, puerta o fundido a negro) y sirve para ocultar la carga de escena.

## 6. Escenarios

> **Estado: por definir.** Todavía no se decidió el diseño de cada nivel. Esta sección fija las reglas y las decisiones pendientes; el día 1 se cierran.

### 6.1 Decisiones pendientes (cerrar el día 1)
- [ ] **Organización espacial:** ¿los 3 enfrentamientos ocurren *dentro* del templo (salas interiores apiladas), *sobre* la isla (plataformas exteriores a distinta altura), o una mezcla (exterior → interior)?
- [ ] **Forma de cada arena:** circular, rectangular o irregular; tamaño acorde al jefe (el Bone Dragon y Ghidorah necesitan más espacio que Malenia).
- [ ] **Identidad de cada piso:** qué distingue visualmente al piso 1, 2 y 3 (materiales, iluminación, decoración).
- [ ] **Escena final:** dónde está Elysia (altar en la cima, interior o exterior).
- [ ] **Uso de la isla flotante:** solo como vista lejana/fondo, o como terreno donde se construye el templo.

### 6.2 Reglas para que todo se vea como un conjunto
Los assets vienen de autores distintos; sin unificarlos, el juego se verá como piezas sueltas. Reglas obligatorias:

1. **Un solo shader PSX** aplicado a todos los modelos (vértices "temblorosos", filtro *nearest*, iluminación por vértice). Es la herramienta principal de cohesión.
2. **Paleta común:** piedra gris fría, bronce oxidado, negro, acentos blancos/cuarzo. Las texturas que no encajen se re-tiñen en Godot (`albedo_color`) o se reemplazan por texturas de `modulardungeontextures`.
3. **Resolución de texturas uniforme:** todas reducidas a 128 px o 256 px.
4. **Escala normalizada:** Kaelen ≈ 1.7 m; puertas ≈ 3 m; módulos de pared según la grilla del kit. Se valida todo en una escena de referencia de escala el día 1.
5. **Iluminación y niebla compartidas:** un mismo `WorldEnvironment` base (niebla, color ambiental, cielo) reutilizado en todas las escenas, con variaciones pequeñas por piso.
6. **Un kit principal de construcción:** se elige un kit (`PSX_Dungeon` o `Modular Dungeon`) como base de las arenas; el otro solo aporta decoración.

### 6.3 Construcción sobre la isla flotante
- Importar `float-islands/FloatingIsland.fbx`, aplicarle el shader PSX y la paleta común.
- Colocar la entrada del templo sobre la isla para que el exterior y el interior se lean como el mismo lugar.
- Cielo con gradiente y niebla para ocultar el vacío bajo la isla.
- Cada arena necesita: `NavigationRegion3D` horneada, colisiones, puntos de aparición de esbirros (`Marker3D`), punto de inicio del jugador, posición del jefe y límites invisibles.

### 6.4 Entregables
| Escena | Contenido mínimo |
|---|---|
| `island_intro` | Isla + entrada del templo, recorrido corto hasta la puerta |
| `arena_1`, `arena_2`, `arena_3` | Arena cerrada, navmesh, spawns, iluminación del piso |
| `ending` | Espacio de Elysia, cámara fija |
| `scale_reference` | Kaelen + módulos de cada kit + jefes, para validar escala y estilo |

## 7. Inteligencia Artificial dentro del juego

Tres capas, cada una con una técnica reconocida de IA para videojuegos.

### 7.1 Esbirros — Máquina de estados finitos + navegación
- **Percepción:** detección por radio (12 m) + cono de visión (110°) + raycast de línea de visión.
- **Estados:** `Idle/Patrulla → Persecución → Rodear → Ataque → Recuperación → Muerte`; `Aturdido` al recibir golpe.
- **Navegación:** `NavigationRegion3D` + `NavigationAgent3D` (búsqueda de rutas A* sobre la malla de navegación) con evitación entre agentes.
- **Coordinación por fichas de ataque:** un gestor central reparte como máximo 2 fichas. Solo un esbirro con ficha puede pasar a `Ataque`; los demás pasan a `Rodear` (orbitan a Kaelen a 3-4 m). Esto evita que todos ataquen a la vez y produce el ritmo de un soulslike.

### 7.2 Jefes — Selección de ataques por utilidad
Cada ataque es un recurso (`BossAttack`) con: rango mínimo/máximo, tiempo de aviso (telegraph), recuperación y peso base. Cada vez que el jefe decide qué hacer, calcula un puntaje para cada ataque:

```
puntaje = peso_base
        × ajuste_distancia(distancia a Kaelen)
        × penalización_repetición (0.3 si fue el último ataque)
        × bonus_anticipación (si el jugador esquiva repetidamente hacia un lado)
        × multiplicador_fase
```

Elige por sorteo ponderado entre los 2 mejores (para que no sea completamente predecible). El jefe guarda un historial corto de cómo esquiva el jugador para el bonus de anticipación.

### 7.3 Orquestador
Un nodo autoload `Orchestrator` que ajusta la presión del combate según cómo juega el jugador.

**Intensidad (0-100):**
- Sube: recibir daño (+daño × 1.5), vida baja (< 30%: +5/s), enemigos a < 5 m (+2/s cada uno).
- Baja: −8/s de forma natural; −15/s si no hay enemigos cerca.

**Fases (máquina de estados):**
| Fase | Comportamiento | Transición |
|---|---|---|
| Crecimiento | Genera oleadas con presupuesto creciente | intensidad ≥ 80 → Pico |
| Pico | No genera nada; deja que los enemigos actuales presionen | 5 s → Respiro |
| Respiro | No genera nada durante 10-20 s | tiempo cumplido e intensidad < 30 → Crecimiento |

**Presupuesto de oleada:**
```
presupuesto = base_nivel
            × factor_desempeño   (0.6 a 1.4, según vida actual y tiempo sin recibir daño)
            × multiplicador_fase_jefe (1.0; 1.5 en fase 2)
```
Esbirro normal cuesta 1, esbirro élite (más vida/daño, mismo modelo con otro tinte) cuesta 3. Límite de esbirros vivos: 6.

**Puntos de aparición:** `Marker3D` en cada arena; el Orquestador elige los que están fuera del cono de la cámara y a más de 8 m de Kaelen.

**Reglas de seguridad:** si la vida de Kaelen es < 25%, se fuerza Respiro. Si el jefe está en un ataque especial, no se genera nada.

**Comunicación:** señales globales (`player_damaged`, `enemy_died`, `boss_phase_changed`, `arena_entered`, `arena_cleared`).

**Vista de depuración (F3):** muestra en pantalla intensidad, fase, presupuesto, esbirros vivos y fichas de ataque asignadas. Sirve para la presentación y para ajustar valores.

## 8. HUD
- Barras de vida y estamina (esquina superior izquierda).
- Barra del jefe con su nombre (parte inferior), visible solo durante el enfrentamiento.
- Mensajes grandes centrados: "HAS MUERTO" / nombre del jefe derrotado.
- Indicador de lock-on sobre el objetivo.

## 9. Menús

### 9.1 Menú principal (obligatorio)
- Fondo: la isla flotante con cámara girando lentamente (reutiliza `island_intro`).
- Título del juego.
- Botones: **Iniciar**, **Opciones** (oculto si no se implementa), **Créditos**, **Salir**.
- Navegable con ratón y teclado/mando (foco inicial en "Iniciar").

### 9.2 Menú de pausa (obligatorio)
Complejidad baja (≈ medio día). Se abre con `Esc` / `Start`:
- Pausa el juego con `get_tree().paused = true`; el menú usa `process_mode = PROCESS_MODE_ALWAYS` para seguir respondiendo.
- Botones: **Continuar**, **Opciones** (si existe), **Volver al menú principal**, **Salir del juego**.
- Libera el cursor del ratón al abrir y lo vuelve a capturar al cerrar.

### 9.3 Menú de opciones (opcional)
- Volumen: General, Música, Efectos (sliders conectados a los buses de audio).
- Sensibilidad de cámara.
- Pantalla completa / ventana.
- Persistencia simple en `user://settings.cfg` (`ConfigFile`).

### 9.4 Pantalla de muerte y créditos
- Muerte: "HAS MUERTO" + fundido + reaparición automática (sin menú).
- Créditos: equipo + lista de assets, autores y licencias (requisito de CC-BY), botón para volver al menú.

## 10. Sonido (SFX y música)

### 10.1 Buses de audio
`Master` → `Music`, `SFX`, `UI`. Permite el control de volumen del menú de opciones y bajar la música en la pausa.

### 10.2 Lista de efectos de sonido

| Categoría | Sonidos |
|---|---|
| Kaelen | pasos (piedra), swing del mandoble ×2-3 variantes, impacto en carne, impacto en metal/hueso, rodar, recibir golpe, muerte, respiración agotada (sin estamina) |
| Esbirros | pasos, ataque, recibir golpe, muerte (por tipo: esqueleto/hueso, arcanista, caballero/metal) |
| Jefes | rugido de entrada, aviso de ataque, golpe al suelo/impacto pesado, cambio a fase 2, muerte |
| UI | mover selección, confirmar, volver, abrir/cerrar pausa |
| Ambiente | viento en la isla, eco/goteo en el templo, cadenas o fuego por arena |

### 10.3 Música
- Menú principal, ambiente del templo (bajo, tenso), tema de jefe (uno compartido o uno por jefe), final (tranquilo).
- Transición: fundido de la música de ambiente a la de jefe al iniciar el enfrentamiento.

### 10.4 Fuentes de audio gratuitas
Freesound (filtrar por CC0 / CC-BY), Kenney (CC0), OpenGameArt, Sonniss GDC Game Audio Bundle. Registrar autor y licencia de cada archivo para los créditos.

### 10.5 Implementación
- `AudioStreamPlayer3D` en personajes para sonidos espaciales; `AudioStreamPlayer` para música y UI.
- Variación de tono aleatoria (±10%) en sonidos repetidos (pasos, swings) para que no suenen iguales.
- Sonidos de impacto disparados desde el sistema de hitbox, no desde cada script.
- Formato: `.ogg` para música, `.wav` para efectos cortos.

## 11. Arquitectura en Godot

```
res://
  assets/        # modelos, texturas, audio (Git LFS), cada uno con su licencia
  scenes/
    player/      kaelen.tscn
    enemies/     minion_base.tscn + variantes por nivel
    bosses/      boss_base.tscn + boss_dragon / boss_malenia / boss_ghidorah
    levels/      island_intro, arena_1, arena_2, arena_3, ending, scale_reference
    ui/          main_menu, pause_menu, options_menu, hud, credits, debug_overlay
  scripts/
    player/      player_controller.gd, player_combat.gd, lock_on.gd, camera_rig.gd
    combat/      health.gd, hitbox.gd, hurtbox.gd, stamina.gd
    ai/          minion_fsm.gd, attack_token_manager.gd, boss_brain.gd, boss_attack.gd (Resource), orchestrator.gd
    game/        game_state.gd (autoload: nivel actual, vida máxima), events.gd (autoload: señales)
    audio/       audio_manager.gd (autoload: música y sonidos globales)
  shaders/       psx.gdshader, post_effect.gdshader
```

Principios: componentes pequeños (`Health`, `Hitbox`, `Hurtbox`, `Stamina`) que se reutilizan en Kaelen, esbirros y jefes. Los jefes comparten `boss_base` y solo cambian modelo y recursos `BossAttack`. Las arenas son escenas independientes cargadas por `game_state`.

## 12. Repositorio y assets
- **No** se copia la carpeta completa de assets: solo lo listado en la sección 3, ordenado en `assets/<categoría>/<nombre>/` con su `license.txt`.
- **Git LFS** para modelos, texturas y audio.
- Fuentes pesadas (`.rar`, `floating_island` de 61 MB, Ghidorah sin reducir) quedan fuera del repo.
- Conversión FBX → GLB en Blender cuando el import directo de Godot falle.
- **Regla de trabajo:** una sola persona edita cada escena `.tscn` a la vez (dueño por escena) para evitar conflictos de merge.

## 13. Roles

| Persona | Responsabilidad principal |
|---|---|
| A — Jugador e interfaz | Controlador, cámara, lock-on, combate de Kaelen, HUD, menús |
| B — IA y enemigos | FSM de esbirros, fichas de ataque, `boss_base` + utilidad, Orquestador, overlay de depuración |
| C — Arte, escenarios y sonido | Mixamo, Blender, importación, construcción de arenas e isla, cohesión visual, shader PSX, SFX y música, créditos |

## 14. Cronograma

| Día | Meta | Criterio de "hecho" |
|---|---|---|
| 1 | Proyecto + repo + LFS; importar assets; **cerrar decisiones de escenarios (6.1)**; Kaelen con placeholder | Cada modelo visible en Godot con sus animaciones listadas; `scale_reference` armada; cápsula que se mueve con cámara |
| 2 | Combate de Kaelen; esbirro con FSM y navegación; arena 1 en bruto | Se puede matar a un esbirro y morir ante él |
| 3 | `boss_base` + jefe 1; menú principal y pausa | **Hito crítico: jefe 1 se puede ganar y perder**, entrando desde el menú |
| 4 | Orquestador; jefes 2 y 3; arenas 2 y 3; isla | Las 3 arenas jugables por separado; Orquestador generando oleadas |
| 5 | Flujo completo: transiciones, reaparición, vida decreciente, final, créditos; SFX principales | Partida completa de principio a fin |
| 6 | Pulido: cohesión visual, música, resto de SFX, balance, overlay F3; opciones si da tiempo | 2 personas externas lo terminan (o casi) |
| 7 | Congelación de funciones; bugs; exportar Windows (+ Web si funciona) | Ejecutable final probado en otra PC |

**Si el día 3 falla el hito:** se recorta a 2 animaciones por jefe, se elimina el recorrido por la isla (queda solo como fondo del menú) y el Orquestador se reduce a dos estados (generar / no generar).

## 15. Pruebas
- **Escena de pruebas** (`test_arena.tscn`) con Kaelen, un esbirro y un jefe intercambiable.
- **Atajos de depuración:** F3 overlay de IA, F5 saltar al siguiente jefe, F6 invulnerabilidad.
- **Checklist de partida completa** al final de los días 5, 6 y 7: menú → isla → 3 jefes → final → créditos → menú, muriendo al menos una vez por jefe y usando la pausa.
- Ajuste de dificultad mirando el overlay del Orquestador (la intensidad debe oscilar, no quedarse en 0 ni en 100).

## 16. Riesgos

| Riesgo | Mitigación |
|---|---|
| Modelos con rigs incompatibles o FBX que no importan | Validar todo el día 1; reservas listadas; límite de 2 h por asset |
| Jefes sin animaciones | Movimiento por tweens y código (embestidas, saltos, rotaciones) |
| Assets que no combinan visualmente | Reglas de cohesión (6.2) aplicadas desde el día 1 |
| Diseño de escenarios sin decidir retrasa todo | Decisiones de 6.1 se cierran el día 1; arenas en bruto primero, decoración el día 6 |
| Conflictos de merge en `.tscn` | Dueño por escena; commits pequeños y frecuentes |
| Ghidorah demasiado pesado | Reducir polígonos en Blender antes de importar |
| Exportación Web falla | Windows es el entregable obligatorio; Web es opcional |
