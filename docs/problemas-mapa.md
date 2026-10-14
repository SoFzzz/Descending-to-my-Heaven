# Problemas conocidos del mapa

Encontrados al caminar con Kaelen (`scenes/levels/*_gameplay.tscn`). **No se corrigen editando las escenas generadas**: se arreglan en las tablas de `scripts/tools/level_builder.gd` y se vuelve a generar.

Coordenadas en metros, en el espacio de cada nivel (sur = +Z, norte = −Z).

| # | Nivel | Qué pasa | Dónde | Propuesta |
|---|---|---|---|---|
| 1 | `exterior` | La pared invisible del fondo del sendero está en la capa `world`, así que el `SpringArm3D` de la cámara choca con ella: al inicio la cámara queda a **1.7 m** de Kaelen en vez de 4 m. | Pared entre (−2.5, 36) y (2.5, 36); `PlayerStart` en (0, 5.71, 34). | Correr el inicio del sendero hacia el norte (`path_start_z` = 36 → poner `PlayerStart` a 6 m de la pared) o alargar la pared trasera hacia el sur. Mismo efecto, en menor medida, con las paredes laterales del sendero (5 m de ancho): con la cámara de costado se acerca. |
| 2 | `exterior` | El arco del kit sobre la puerta del templo queda más alto que el hueco de la puerta (se ve una franja de muro entre ambos). Solo estético. | Puerta en (0, −0.2, −31), hueco de 3 × 4 m. | Bajar el arco o agrandar `door` a 4 × 4 m para que coincida con el arco (4 m de ancho). |
| 3 | `arena_1`–`3` | Ninguno de colisión. Verificado: Kaelen se detiene contra la reja norte (z = −20.0), el muro este (x = 19.65), el pilar (9, −9) (z = −7.65); sube la escalera norte hasta el rellano (y = 4.0, z = −34.05) y baja la escalera sur del vestíbulo (y = −1.76). | — | — |

Nota: los escalones de 0.25 m no los sube un `CharacterBody3D` por sí solo; `player_controller.gd` tiene la subida de escalones (`MAX_STEP` = 0.35 m). Los esbirros con `NavigationAgent3D` necesitarán lo mismo si deben usar escaleras (en las arenas no hace falta: están detrás de las rejas).
