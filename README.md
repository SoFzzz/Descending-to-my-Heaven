# Descending to my Heaven

Boss rush 3D en tercera persona, con combate de estilo soulslike y estética PSX. Kaelen sube un templo de tres pisos sobre una isla flotante y derrota a tres guardianes para reencontrarse con Elysia.

Proyecto desarrollado con Godot 4.7.2 (GDScript con tipado estático).

---

## Descarga y cómo jugar

**Versión actual:** `v1.0.0-rc1` (release candidata, Windows x86_64).

1. Descarga `DescendingToMyHeaven.exe` desde la release: https://github.com/SoFzzz/Descending-to-my-Heaven/releases/tag/v1.0.0-rc1
2. Ejecútalo. No requiere instalación. Pesa unos 166 MB porque lleva todo el juego dentro.
3. Si Windows SmartScreen avisa de que la aplicación no está reconocida, pulsa **"Más información"** y después **"Ejecutar de todas formas"**. El ejecutable no tiene firma de código.

Los ajustes se guardan en `%APPDATA%\Godot\app_userdata\Descending to my Heaven\`.

SHA-256 del ejecutable: `F4D7FED830464D7F90B0FA4F1F0BB19692A56013BC247454F55E270FA854ABC4`

---

## Características

- **Tres jefes:** Bone Dragon, Blackhorn y Mecha King Ghidorah. Cada uno tiene fase 2 al 50 % de vida y una repulsión que castiga el juego de ráfagas.
- **IA táctica:** los jefes cortan la huida, se preparan para atacar desde la espalda o esperan, y los esbirros cierran pinzas y tienden emboscadas. Un orquestador regula la intensidad de cada oleada.
- **Combate soulslike:** combos de mandoble, rodada con invulnerabilidad, estamina y un frasco de curación con cargas limitadas por nivel.
- **Final:** una secuencia de diálogo con voces, cámaras propias y la caída de la isla.
- **Opciones completas:** controles reasignables, volumen por bus (general, música, efectos e interfaz), pantalla y resolución, y español o inglés.
- **Mando de Xbox** compatible.

---

## Controles

| Acción | Teclado y ratón | Mando Xbox |
|---|---|---|
| Mover | W A S D | Stick izquierdo |
| Cámara | Ratón | Stick derecho |
| Atacar | Clic izquierdo | X o RB |
| Rodar | Espacio | B |
| Curarse | R | Y |
| Fijar objetivo | Clic central o Q | R3 |
| Pausa | Esc | Start |
| Avanzar diálogos | Enter, Espacio o clic izquierdo | A, RB o X |

Las acciones de teclado y mando se pueden cambiar en **Opciones > Controles**. Los sticks de movimiento y cámara son fijos.

---

## Requisitos y desarrollo

- **Godot 4.7.2 estable**, con el renderizador Compatibility (`gl_compatibility`).
- **Git LFS** para los modelos, texturas, audio y `.blend`. Antes de clonar, ejecuta `git lfs install`. Si un `.glb`, `.png` u `.ogg` ocupa 1 KB, falta LFS: ejecuta `git lfs pull`.

Para abrir el proyecto:

1. En Godot 4.7.2, pulsa **Importar** y elige `project.godot`.
2. Ejecuta con F5. La escena principal es `scenes/ui/main_menu.tscn`.

Pruebas unitarias desde la raíz del repositorio (`godot` es el ejecutable de Godot 4.7.2):

```
godot --headless --path . -s res://tests/run_tests.gd
```

Debe terminar con `N/N passed` y código de salida 0. Las pruebas de flujo de escenas están en `tests/flow/`.

Para generar un ejecutable de Windows, consulta la sección 2.6 de `AGENTS.md`.

La guía completa (estado del proyecto, arquitectura, IA, niveles, audio, convenciones y riesgos pendientes) está en **[AGENTS.md](AGENTS.md)**.

---

## Estructura del repositorio

| Carpeta | Contenido |
|---|---|
| `scenes/` | Escenas: jugador, enemigos, jefes, niveles, interfaz y final |
| `scripts/` | Código GDScript: `ai/`, `combat/`, `player/`, `game/`, `ui/`, `audio/`, `vfx/`, `tools/` |
| `assets/` | Modelos, texturas, audio y fuentes que usa el juego (con Git LFS) |
| `shaders/` | Shaders PSX y postproceso |
| `resources/` | Recursos de Godot: ataques de jefes y variantes de audio |
| `localization/` | `translations.csv` con los textos en español e inglés |
| `addons/` | Efectos de terceros (viento, chispas, círculos mágicos) |
| `tests/` | Pruebas unitarias (`test_*.gd`) y flujos de escena (`flow/`) |
| `_source/` | Material original (modelos, packs de audio y scripts de Blender). Godot no lo importa |

---

## Créditos

Equipo:

- Paula Sofia Gonzalez Zambrano
- David Alejandro Aza Jojoa
- Stehven Alexander Obando Cordoba

Los créditos completos de los assets de terceros y sus licencias están en `AGENTS.md` (sección 12) y en `assets/credits.txt`, que es el texto que muestra la pantalla de créditos del juego.

Varios assets no permiten redistribución, por eso el repositorio es privado y solo se publica el juego exportado.

---

## Licencia

El código del proyecto pertenece a su equipo de desarrollo. Es un proyecto académico.

Los assets de terceros conservan las licencias de sus autores. Consulta la tabla de la sección 12 de `AGENTS.md` antes de reutilizar cualquier archivo.
