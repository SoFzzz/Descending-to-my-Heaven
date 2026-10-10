# Descending to my Heaven — Documento de Diseño (Versión Jam: 1 semana)

- **Fecha:** 2026-10-10
- **Equipo:** 3 personas, dedicación completa durante 7 días
- **Motor:** Godot 4.3+ (GDScript)
- **Referencia narrativa:** Documento de Diseño Maestro v4.0 (Unity, 3 meses). Este documento lo **reemplaza** en alcance; el lore se conserva.
- **Objetivo de éxito:** un juego 3D lowpoly estilo PSX, jugable de principio a fin, donde se puede **derrotar a los 3 jefes** y ver el final. La IA dentro del juego debe ser demostrable y explicable.

---

## 1. Visión

Acción en tercera persona con combate tipo soulslike. Kaelen, con armadura robada y un mandoble, asciende un templo-mazmorra de 3 pisos en una isla flotante. Cada piso es una sala cerrada con un jefe y esbirros. Al vencer al tercer jefe encuentra a Elysia.

Estética: fantasía oscura PSX (baja resolución interna, texturas con filtro *nearest*, niebla de distancia, paleta apagada).

## 2. Alcance

### Dentro (obligatorio)
- Kaelen: moverse, cámara orbital, fijar objetivo (lock-on), ataque ligero (combo de 2-3 golpes), rodar con invulnerabilidad, estamina, recibir daño, morir.
- 3 salas con jefe + esbirros.
- Sistema de jefe único reutilizable (vida, 3-4 ataques con aviso, fase 2 al 50%).
- IA de esbirros, IA de selección de ataques del jefe y Director de IA (sección 6).
- Vida máxima decreciente por nivel: 100% → 70% → 40%.
- Muerte → reaparece en la entrada de la sala actual; el jefe se reinicia.
- Intro en la isla flotante (corta, caminable) → templo → piso 1 → 2 → 3 → escena final con Elysia → créditos.
- Calamidad visual simple por nivel superado (post-proceso).
- HUD: vida, estamina, barra del jefe. Menú principal y pausa mínimos.
- Pantalla de créditos con todas las licencias.

### Fuera (descartado explícitamente)
- Escalada estilo Shadow of the Colossus, grilletes, puntos débiles, "La Rotura".
- Parry (solo se agrega el día 6 si sobra tiempo).
- Inventario, objetos, niveles de personaje, guardado entre sesiones.
- Diálogos ramificados; voces.
- Exploración larga o laberintos entre salas.

## 3. Reparto de personajes y assets

| Rol | Modelo (D:\ASSETS-PRUEBA) | Rig / animación |
|---|---|---|
| Kaelen | `low-poly-woman-knight` (ajustado en Blender) | Rig + animaciones Mixamo |
| Elysia | `modelo-base-elisya/female_lowp.blend` (túnica/velo en Blender) | Rig Mixamo; idle, levantarse, abrazo |
| Arma de Kaelen | `demonic weapons pack/greatsword` (ya tiene .glb) | Adjunta al hueso de la mano (`BoneAttachment3D`) |
| Jefe 1 | `bonedragon` | Rig propio; animaciones faltantes por código/tweens |
| Esbirros 1 | `Skeleton` | Sin rig → Mixamo |
| Jefe 2 | `MaleniaPsx` | Rig propio + ~3 animaciones; resto Mixamo si es compatible |
| Esbirros 2 | `Plague Arcanist` | Rig propio + ~11 animaciones |
| Jefe 3 | `mecha-king-ghidorah` (reducir polígonos) | Rig propio; animaciones por código/tweens |
| Esbirros 3 | `knight__ps1_psx` | Rig propio (solo Idle) → Mixamo |
| Escenarios | `PSX_Dungeon`, `Modular Dungeon Free Edition`, `modulardungeontextures`, `float-islands` | Estáticos |
| Reserva | `TheWrapper V2` (7 animaciones), `psx_insectoid_demon`, `aura_battler` | Sustitutos si algo falla al importar |

**Regla de sustitución:** si el día 1 un modelo no importa bien o no se puede animar, se reemplaza por uno de reserva ese mismo día. No se gastan más de 2 horas peleando con un asset.

**Animaciones mínimas:**
- Kaelen: idle, caminar, correr, rodar, ataque 1-2-3, recibir golpe, morir.
- Esbirro: idle, caminar, atacar, recibir golpe, morir.
- Jefe: idle, moverse, 3 ataques, morir. Lo que falte se simula con tweens (inclinar, embestir, sacudir).

**Nota de licencias:** Malenia (Elden Ring) y Mecha King Ghidorah (Toho) son fan-art de propiedades con copyright. Válido para entrega académica; si se publica en itch.io, dejarlo explícito o publicarlo como no listado.

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
| Fase 2 del jefe | al 50% de vida: +25% velocidad de ataque, más presupuesto al Director |

Impactos: hitbox `Area3D` activada en ventanas de la animación; hurtbox en cada personaje. Feedback: pausa de impacto (~60 ms), parpadeo de material, partículas simples, sonido.

## 5. Flujo del juego

```
Menú → Isla flotante (intro, 1-2 min, texto narrativo) → Puerta del templo
  → Sala 1 (Bone Dragon)  → calamidad: mundo en gris
  → Sala 2 (Malenia)      → calamidad: niebla densa y oscura
  → Sala 3 (Ghidorah)     → calamidad: tonos invertidos/blancos
  → Altar: Elysia (escena con cámara fija y texto) → Créditos
```

Entre salas hay una escalera o pasillo corto para transicionar (y ocultar la carga de escena).

## 6. Inteligencia Artificial dentro del juego

Tres capas, cada una con una técnica reconocida de IA para videojuegos.

### 6.1 Esbirros — Máquina de estados finitos + navegación
- **Percepción:** detección por radio (12 m) + cono de visión (110°) + raycast de línea de visión.
- **Estados:** `Idle/Patrulla → Persecución → Rodear → Ataque → Recuperación → Muerte`; `Aturdido` al recibir golpe.
- **Navegación:** `NavigationRegion3D` + `NavigationAgent3D` (búsqueda de rutas A* sobre la malla de navegación) con evitación entre agentes.
- **Coordinación por fichas de ataque:** un gestor central reparte como máximo 2 fichas. Solo un esbirro con ficha puede pasar a `Ataque`; los demás pasan a `Rodear` (orbitan a Kaelen a 3-4 m). Esto evita que todos ataquen a la vez y produce el ritmo de un soulslike.

### 6.2 Jefes — Selección de ataques por utilidad
Cada ataque es un recurso (`BossAttack`) con: rango mínimo/máximo, tiempo de aviso (telegraph), recuperación y peso base. Cada vez que el jefe decide qué hacer, calcula un puntaje para cada ataque:

```
puntaje = peso_base
        × ajuste_distancia(distancia a Kaelen)
        × penalización_repetición (0.3 si fue el último ataque)
        × bonus_anticipación (si el jugador esquiva repetidamente hacia un lado)
        × multiplicador_fase
```

Elige por sorteo ponderado entre los 2 mejores (para que no sea completamente predecible). El jefe guarda un historial corto de cómo esquiva el jugador para el bonus de anticipación.

### 6.3 Director de IA (orquestador estilo Left 4 Dead)
Un nodo autoload `AIDirector` que ajusta la presión del combate según cómo juega el jugador.

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

**Puntos de aparición:** `Marker3D` en cada sala; el Director elige los que están fuera del cono de la cámara y a más de 8 m de Kaelen.

**Reglas de seguridad:** si la vida de Kaelen es < 25%, el Director fuerza Respiro. Si el jefe está en ataque especial, no genera.

**Comunicación:** señales globales (`player_damaged`, `enemy_died`, `boss_phase_changed`, `room_entered`, `room_cleared`).

**Vista de depuración (F3):** muestra en pantalla intensidad, fase, presupuesto, esbirros vivos y fichas de ataque asignadas. Sirve para la presentación y para ajustar valores.

## 7. Arquitectura en Godot

```
res://
  assets/        # modelos, texturas, audio importados (Git LFS), cada uno con su LICENSE
  scenes/
    player/      kaelen.tscn
    enemies/     minion_base.tscn + variantes por nivel
    bosses/      boss_base.tscn + boss_dragon / boss_malenia / boss_ghidorah
    levels/      island_intro, room_1, room_2, room_3, ending
    ui/          hud, main_menu, pause, credits, debug_overlay
  scripts/
    player/      player_controller.gd, player_combat.gd, lock_on.gd, camera_rig.gd
    combat/      health.gd, hitbox.gd, hurtbox.gd, stamina.gd
    ai/          minion_fsm.gd, attack_token_manager.gd, boss_brain.gd, boss_attack.gd (Resource), ai_director.gd
    game/        game_state.gd (autoload: nivel actual, vida máxima, calamidades), events.gd (autoload: señales)
  shaders/       psx.gdshader (vertex snapping, filtro nearest), post_calamity.gdshader
```

Principios: componentes pequeños (`Health`, `Hitbox`, `Hurtbox`, `Stamina`) que se reutilizan en Kaelen, esbirros y jefes. Los jefes comparten `boss_base` y solo cambian modelo y recursos `BossAttack`. Las salas son escenas independientes cargadas por `game_state`.

## 8. Pipeline de assets y repositorio
- **No** se copia la carpeta completa de assets. Solo lo listado en la sección 3, ordenado en `assets/<categoría>/<nombre>/` con su `license.txt`.
- **Git LFS** para `*.fbx, *.glb, *.gltf, *.bin, *.blend, *.png, *.jpg, *.wav, *.ogg`.
- `.gitignore` de Godot (`.godot/`, `*.import` se versiona; `export/` no).
- Fuentes pesadas (`.rar`, `floating_island` de 61 MB, Ghidorah sin reducir) quedan fuera del repo.
- Conversión FBX → GLB en Blender cuando el import directo de Godot falle; escalas normalizadas (Kaelen ≈ 1.7 m).
- **Regla de commits:** una sola persona edita cada escena `.tscn` a la vez (se reparten por dueño) para evitar conflictos de merge.

## 9. Roles

| Persona | Responsabilidad principal |
|---|---|
| A — Jugador | Controlador, cámara, lock-on, combate de Kaelen, HUD |
| B — IA y enemigos | FSM de esbirros, fichas de ataque, `boss_base` + utilidad, AI Director, overlay de depuración |
| C — Arte y niveles | Mixamo, Blender, importación, salas con kits modulares, navmesh, shaders PSX, audio, menús, créditos |
| Claude | Apoyo en código, scripts de Blender, revisión |

## 10. Cronograma

| Día | Meta | Criterio de "hecho" |
|---|---|---|
| 1 | Proyecto + repo + LFS; importar todos los assets elegidos; Kaelen con placeholder | Cada modelo elegido visible en Godot con sus animaciones listadas; cápsula que se mueve con cámara |
| 2 | Combate de Kaelen; esbirro con FSM y navegación | Se puede matar a un esbirro y morir ante él |
| 3 | `boss_base` + jefe 1 + sala 1 | **Hito crítico: jefe 1 se puede ganar y perder** |
| 4 | AI Director; jefes 2 y 3; salas 2 y 3 | Las 3 salas jugables por separado; Director generando oleadas |
| 5 | Flujo completo: intro, transiciones, reaparición, vida decreciente, final, créditos | Partida completa de principio a fin sin trucos |
| 6 | Pulido: shader PSX, calamidades, audio, balance, overlay F3 | 2 personas externas lo terminan (o casi) |
| 7 | Congelación de funciones; bugs; exportar Windows (+ Web si funciona) | Ejecutable final probado en otra PC |

**Si el día 3 falla el hito:** se recorta a 2 animaciones por jefe, se elimina la intro de la isla y el Director se reduce a dos estados (generar / no generar).

## 11. Pruebas
- **Escena de pruebas** (`test_arena.tscn`) con Kaelen, un esbirro y un jefe intercambiable, para probar sin recorrer el juego.
- **Atajos de depuración:** F3 overlay de IA, F5 saltar a la siguiente sala, F6 invulnerabilidad.
- **Checklist de partida completa** al final de los días 5, 6 y 7: menú → intro → 3 jefes → final → créditos, muriendo al menos una vez en cada sala.
- Ajuste de dificultad mirando el overlay del Director (la intensidad debe oscilar, no quedarse en 0 ni en 100).

## 12. Riesgos

| Riesgo | Mitigación |
|---|---|
| Modelos con rigs incompatibles o FBX que no importan | Validar todo el día 1; reservas listadas; límite de 2 h por asset |
| Jefes sin animaciones | Movimiento por tweens y código (embestidas, saltos, rotaciones) |
| Conflictos de merge en `.tscn` | Dueño por escena; commits pequeños y frecuentes |
| Ghidorah demasiado pesado | Reducir polígonos en Blender antes de importar |
| El combate no se siente bien | Prioridad a ajustar feedback de impacto el día 6 antes que contenido nuevo |
| Exportación Web falla | Windows es el entregable obligatorio; Web es opcional |
