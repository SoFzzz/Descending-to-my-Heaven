# Playtest — Descending to my Heaven

Plantilla para registrar el playtest de la **Tarea 18** del [plan de trabajo](2026-10-11-plan-de-trabajo.md): dos personas externas juegan una partida completa (menú → exterior → 3 jefes → final → créditos). Se copia la sección "Sesión" una vez por persona. Los problemas pasan a la tabla de acciones y se priorizan en la **Tarea 19** (congelación).

## Cómo observar

- No explicar controles ni mecánicas. Ayudar solo si la persona lleva más de 3 minutos bloqueada, y anotarlo.
- Pedir que piense en voz alta mientras juega.
- Anotar cada muerte en el momento: zona, causa (esbirro, tipo de ataque del jefe, rayo, caída u otra) y tiempo desde el inicio de la zona.
- No usar el modo dios (F6) ni saltar de nivel (F5). El overlay F3 solo para comprobar la intensidad de oleadas, y dejar constancia si se usa.

## Sesión

### Datos de la sesión

| Campo | Valor |
|---|---|
| Fecha | |
| Persona (código, no nombre) | P1 / P2 |
| Experiencia con juegos de acción 3D | baja / media / alta |
| Controles usados | teclado y ratón / mando de Xbox |
| Idioma del juego | español / inglés |
| Versión / commit (`git rev-parse --short HEAD`) | |
| Duración total de la partida | |
| Partida completada (sí / no) | |
| Observador | |

### Resultados por zona

| Zona | Muertes | Dónde murió | Tiempo | Problemas | Gravedad |
|---|---|---|---|---|---|
| Exterior | | | | | alta / media / baja |
| Arena 1 — Bone Dragon | | | | | alta / media / baja |
| Arena 2 — Blackhorn | | | | | alta / media / baja |
| Arena 3 — Ghidorah | | | | | alta / media / baja |
| Final (Elysia y créditos) | | | | | alta / media / baja |

En "Dónde murió" indicar la causa: tipo de esbirro, id del ataque del jefe (`bite`, `tail_sweep`, `beam`, `slam`, `pounce`, `charge`), caída o daño ambiental.

Gravedad:

- **Alta:** bloquea la partida o hace la zona injugable.
- **Media:** frustra o confunde, pero se supera.
- **Baja:** detalle visual o de sonido sin efecto en la jugabilidad.

### Lista de verificación de cambios recientes

Marcar cada punto como comprobado (`[x]`) o con problema (`[!]`) y anotar el detalle en la columna de problemas de la tabla de arriba.

- [ ] **Expulsión de jefes:** Kaelen no atraviesa ni queda empujada dentro del cuerpo de un jefe.
- [ ] **Alcance de la espada:** los golpes conectan a la distancia que muestra la animación; no hay golpes que no conectan ni golpes a distancia excesiva.
- [ ] **Esbirros:** no aparecen más de 3 a la vez, con 1 élite como máximo en ese grupo.
- [ ] **Escaleras:** se suben y bajan sin quedarse atascado.
- [ ] **Pantalla de muerte:** aparece al morir y el botón de reintentar carga la arena.
- [ ] **Música al morir:** la música de jefe se apaga o cambia al morir, como se espera.
- [ ] **Vida llena al entrar a cada arena:** 100 / 70 / 40 PV según el nivel.
- [ ] **Sonidos de UI:** los botones de menús y pausa suenan.
- [ ] **Mando de Xbox:** menú, combate, cámara, rodada, bloqueo y pausa funcionan sin teclado.
- [ ] **Opciones e idioma:** volumen por bus, sensibilidad, controles reasignables y cambio entre español e inglés se aplican al momento.
- [ ] **Lag de Ghidorah:** sin tirones al aparecer el rayo o en la fase final de la pelea.
- [ ] **Final con la sala rota:** la sala de Elysia se ve completa, sin huecos ni geometría rota, durante el abrazo y los cortes.

### Comentarios libres

<!-- Impresiones de la persona, frases textuales, momentos de frustración o de disfrute. -->

---

## Conclusiones y acciones

Completar al cerrar las dos sesiones.

| # | Problema | Zona | Gravedad | Acción | Responsable | Estado |
|---|---|---|---|---|---|---|
| 1 | | | alta / media / baja | | | abierto / hecho |
| 2 | | | alta / media / baja | | | abierto / hecho |
| 3 | | | alta / media / baja | | | abierto / hecho |

**Resumen:**

- Problemas de gravedad alta abiertos al cerrar la T18: ___
- Problemas que pasan a la congelación de la T19: ___
- Cambios hechos durante la T18 a raíz del playtest: ___
