# Guía: esqueletos y animaciones con Mixamo

Objetivo: que cada personaje humanoide termine como **un solo `.glb` en `assets/`** con su esqueleto y todas sus animaciones ya nombradas como el código las espera.

Herramientas: navegador (mixamo.com con la cuenta del equipo), Blender 5.2 (`D:\Unity\blender.exe`), Godot 4.7.

---

## 0. Qué personajes van a Mixamo

| # | Personaje | Archivo de origen | ¿Qué hacer antes de subir? | Destino final |
|---|---|---|---|---|
| 1 | **Kaelen** | `_source/models/low-poly-woman-knight/source/women knight final.fbx` | Revisar T-pose y textura (§1) | `assets/characters/kaelen/kaelen.glb` |
| 2 | **Skeleton** (esbirro 1) | `_source/models/Skeleton/Skeleton/skeleton.fbx` | Revisar T-pose y textura | `assets/minions/skeleton/skeleton.glb` |
| 3 | **Knight** (élite 1) | `_source/models/knight__ps1_psx/scene.gltf` | **Quitarle su esqueleto** y convertir a FBX (§1.3) | `assets/minions/knight/knight.glb` |
| 4 | **Malenia** (jefe 2) | `_source/models/MaleniaPsx/Malenia/malenia.fbx` | Quitarle el metarig y convertir a FBX (§1.3) | `assets/bosses/malenia/malenia.glb` |

**No van a Mixamo:**
- **Elysia**: queda **sin esqueleto** (Mixamo rompe su vestido de una pieza y el pelo). Se exporta estática a `assets/characters/elysia/elysia.glb` y se anima con un `Tween` en Godot.
- **Plague Arcanist**: ya es Mixamo; solo hay que renombrar sus 10 clips (§6).
- **TheWrapper**: ya tiene rig y 6 animaciones propias.
- **Bone Dragon, Ghidorah y Aura Battler**: no son humanoides; Mixamo no los puede riggear.

> **Malenia:** el plan original decía conservar su metarig y hacer el retarget en Godot. Es más rápido y seguro tirar ese esqueleto y riggearla en Mixamo como a los demás, porque así todas sus animaciones salen directamente compatibles. Su `Idle` actual se pierde, pero se reemplaza por uno de Mixamo.

**Orden recomendado:** Kaelen primero (bloquea a la persona A), después Skeleton (esbirro del día 2), Knight y Malenia.

---

## 1. Preparar el modelo en Blender (antes de subir)

Mixamo exige: **una sola malla (o varias sin esqueleto), sin rig previo, en T-pose o A-pose, mirando hacia el frente (-Y en Blender), de pie sobre el suelo, en un .fbx o .obj (o .zip con texturas)**.

### 1.1 Abrir y revisar
1. Blender → *File → New → General*, borrar el cubo, la cámara y la luz (`A`, `X`).
2. *File → Import → FBX* (o *glTF* para el Knight) y elegir el archivo de origen.
3. Revisar en la vista frontal (`1` del teclado numérico):
   - Está **de pie y de frente**. Si mira hacia otro lado: seleccionar, `R Z 180`, `Ctrl+A → All Transforms`.
   - **Brazos abiertos** (T o A). Si tiene los brazos pegados al cuerpo, Mixamo falla: avisar al equipo y usar el sustituto.
   - Los pies en Z = 0.
4. Pulsar `N` → pestaña *Item*: la altura (Dimensions Z) debería ser razonable (1-3 m). Si sale 0.01 o 170, aplicar escala: escalar hasta ~1.7 m y `Ctrl+A → All Transforms`. (La escala exacta se ajusta luego en Godot.)
5. Cambiar a vista *Material Preview* (`Z → 4`): la textura debe verse. Si sale rosa, en *Shader Editor* conectar la imagen de `textures/` al *Base Color*.

### 1.2 Kaelen y Skeleton (ya son FBX sin rig)
Si el modelo se ve bien en el paso 1.1 y no tocaste nada, **puedes subir el `.fbx` original directamente**. Si lo corregiste, exporta como en §1.4.

### 1.3 Knight y Malenia (quitar rig / convertir)
1. En el *Outliner* (arriba a la derecha), si hay un objeto **Armature**:
   - Seleccionar la malla → pestaña de modificadores (llave azul) → borrar el modificador **Armature**.
   - Seleccionar la Armature → `X` → *Delete*.
   - Si la malla queda en pose rara (no T-pose), **no sirve sin el rig**: en ese caso, antes de borrar el modificador pulsa en él *Apply* con el personaje en su pose de reposo (Armature → *Pose Mode* → `Alt+G`, `Alt+R`, `Alt+S`).
2. Borrar también los grupos de vértices viejos: malla seleccionada → *Object Data* (triángulo verde) → *Vertex Groups* → flecha `v` → *Delete All Groups*.
3. Malenia: borrar la espada si está como objeto aparte (se pondrá en Godot con `BoneAttachment3D`).
4. Exportar (§1.4).

### 1.4 Exportar para Mixamo
*File → Export → FBX*:
- *Path Mode*: **Copy**, y activar el botón de la cajita al lado (**Embed Textures**). Así la textura viaja dentro del FBX.
- *Limit to*: *Selected Objects* (seleccionar solo las mallas).
- *Object Types*: solo **Mesh**.
- *Apply Scalings*: **FBX All**; *Forward*: **-Z Forward**; *Up*: **Y Up**.
- Guardar en `_source/mixamo/<personaje>/upload.fbx` (crear la carpeta; `_source` no entra a Godot).

---

## 2. Crear el esqueleto en Mixamo (auto-rig)

1. Entrar a <https://www.mixamo.com> con la cuenta del equipo.
2. Botón **Upload Character** → arrastrar `upload.fbx`. Esperar.
3. Si aparece sin textura (gris) no pasa nada grave: la textura se vuelve a poner en Godot. Si aparece **acostado o de espaldas**, volver a §1.1 y corregir la rotación.
4. Pantalla **Auto-Rigger** → *Next*. Colocar los 5 marcadores **en la vista frontal**:
   - **Chin** (barbilla), **Wrists** (muñecas, ambos), **Elbows** (codos), **Knees** (rodillas), **Groin** (entrepierna).
   - Activar *Use Symmetry*.
   - *Skeleton LOD*: **Standard Skeleton (65)**. En modelos PSX sin dedos separados (Skeleton, Knight) usar **No Fingers (25)**: evita manos deformadas.
5. *Next* y esperar (1-2 min). Revisar el preview girando el modelo:
   - Brazos y piernas se mueven sin estirar el torso → *Next*.
   - Si algo se deforma mucho (capa, falda, casco que se estira): *Back*, mover un poco los marcadores (muñecas más adentro, entrepierna más arriba) y repetir. Máximo 3 intentos; si no, se acepta tal cual.
6. Mixamo deja el personaje cargado a la izquierda. **Todas las animaciones que elijas ahora se aplican a este personaje**; no subas otro hasta terminar sus descargas (§3-4).

---

## 3. Descargar el modelo base

1. Sin elegir animación (o con la pose por defecto), pulsar **Download**:
   - *Format*: **FBX Binary (.fbx)**
   - *Pose*: **T-pose**
   - *Skin*: **With Skin** (la base sí necesita la malla).
2. Guardar como `_source/mixamo/<personaje>/base.fbx`.

---

## 4. Elegir y descargar las animaciones

Por cada animación:
1. Pestaña **Animations** → buscar con los términos de la tabla.
2. Hacer clic para ver el preview **sobre tu personaje**. Elegir la que se vea mejor.
3. Ajustes de la derecha:
   - **In Place**: ✔ activado siempre que aparezca (caminar, correr, rodar, ataques que avanzan). El movimiento lo hace el código, no la animación.
   - *Overdrive* (velocidad): 50 normal; súbelo si el ataque se siente lento.
   - *Character Arm-Space*: subirlo si los brazos atraviesan la armadura.
4. **Download** con:
   - *Format*: **FBX Binary (.fbx)**
   - *Skin*: **Without Skin** (recomendado: archivos más livianos). *With Skin* también sirve: el script descarta la malla repetida y solo toma la animación.
   - *Frames per Second*: **30**
   - *Keyframe Reduction*: **none**
5. Guardar en `_source/mixamo/<personaje>/anims/` con **exactamente** el nombre de la columna "Archivo". El nombre del archivo es el nombre del clip que verá el código.

### 4.1 Kaelen (mandoble) — 9 clips

| Archivo | Buscar en Mixamo | Notas |
|---|---|---|
| `idle.fbx` | `great sword idle` | |
| `walk.fbx` | `great sword walk` | In Place |
| `run.fbx` | `great sword run` | In Place |
| `roll.fbx` | `sprinting forward roll` o `stand to roll` | In Place; debe durar ~0.6 s (subir Overdrive si dura más) |
| `attack_1.fbx` | `great sword slash` | primer golpe del combo |
| `attack_2.fbx` | `great sword slash` (otra variante) | que empiece donde termina el 1 |
| `attack_3.fbx` | `great sword high spin attack` o `great sword jump attack` | golpe fuerte (daño 18) |
| `hurt.fbx` | `great sword impact` | |
| `death.fbx` | `great sword death` | |

### 4.2 Skeleton y Knight (esbirros) — 5 clips cada uno

| Archivo | Skeleton: buscar | Knight: buscar |
|---|---|---|
| `idle.fbx` | `zombie idle` | `sword and shield idle` |
| `walk.fbx` | `zombie walk` (In Place) | `sword and shield walk` (In Place) |
| `attack.fbx` | `zombie attack` | `sword and shield slash` |
| `hurt.fbx` | `zombie reaction hit` | `sword and shield impact` |
| `death.fbx` | `zombie dying` | `sword and shield death` |

### 4.3 Malenia (jefe 2) — 7 clips

| Archivo | Buscar |
|---|---|
| `idle.fbx` | `sword idle` o `katana idle` |
| `walk.fbx` | `sword walk` (In Place) |
| `slash.fbx` | `stable sword inward slash` o `sword slash` |
| `thrust.fbx` | `sword thrust` o `stab` |
| `spin.fbx` | `spin attack` o `sword spin` |
| `hurt.fbx` | `sword impact` o `hit reaction` |
| `death.fbx` | `sword death` o `dying` |

Al terminar, la carpeta debe verse así:

```
_source/mixamo/kaelen/
├── upload.fbx        (lo que subiste, si lo exportaste tú)
├── base.fbx          (With Skin, T-pose)
└── anims/
    ├── idle.fbx
    ├── walk.fbx
    └── ...
```

---

## 5. Juntar todo en un `.glb` (automático)

El script `_source/tools/combine_mixamo.py` importa `base.fbx`, le pega cada animación de `anims/` con el nombre del archivo, marca `idle`, `walk` y `run` como bucle (sufijo `-loop`, que Godot reconoce) y exporta un solo `.glb`.

Desde la raíz del repo, en una terminal (un comando por personaje):

```bash
"/d/Unity/blender.exe" -b --factory-startup -P _source/tools/combine_mixamo.py -- _source/mixamo/kaelen assets/characters/kaelen/kaelen.glb
```

```bash
"/d/Unity/blender.exe" -b --factory-startup -P _source/tools/combine_mixamo.py -- _source/mixamo/skeleton assets/minions/skeleton/skeleton.glb
```

```bash
"/d/Unity/blender.exe" -b --factory-startup -P _source/tools/combine_mixamo.py -- _source/mixamo/knight assets/minions/knight/knight.glb
```

```bash
"/d/Unity/blender.exe" -b --factory-startup -P _source/tools/combine_mixamo.py -- _source/mixamo/malenia assets/bosses/malenia/malenia.glb
```

Salida esperada: una línea `+ <clip>` por animación y al final `OK -> ... con N animaciones`. Si dice `Sin esqueleto en ...`, ese FBX no trae rig (por ejemplo, se subió el `upload.fbx` en vez del descargado de Mixamo): volver a descargarlo.

Copiar también la textura del personaje junto al `.glb` (ej. `assets/characters/kaelen/blenderpaintedit.png`) y su `license.txt`.

---

## 6. Plague Arcanist (solo renombrar)

1. Blender → importar `_source/models/Plague Arcanist/Plague Arcanist/Plague Arcanist.fbx`.
2. Abrir el editor **Dope Sheet → Action Editor**. En el desplegable de acciones aparecen las 10 (`Armature|mixamo.com|Layer0`, `Armature.001|...`, etc.).
3. Elegir cada una, darle *Play* (`Espacio`) y renombrarla según lo que hace: `idle-loop`, `walk-loop`, `attack`, `hurt`, `death`. Las que sobren se pueden dejar con su nombre.
4. Botón **Push Down** en cada acción renombrada (las manda al NLA).
5. *File → Export → glTF 2.0*: formato **glTF Binary (.glb)**, en *Animation* elegir modo **NLA Tracks**. Guardar en `assets/minions/plague_arcanist/plague_arcanist.glb`.

---

## 7. Verificar en Godot

1. Abrir el proyecto en Godot; esperar a que importe los `.glb`.
2. Doble clic en el `.glb` → ventana **Advanced Import Settings**:
   - Panel izquierdo → *AnimationPlayer* → deben aparecer todos los clips con los nombres de §4 (sin el `-loop`; ese sufijo solo activa el bucle).
   - Darle *Play* a cada uno: se debe mover sin deformarse.
   - Revisar que `idle`, `walk`, `run` tengan *Loop Mode: Linear*.
3. Arrastrarlo a `scenes/levels/scale_reference.tscn` y medir la altura (Kaelen 1.70 m, Skeleton 1.75, Knight 2.10, Malenia 2.60). Si no coincide: en *Advanced Import Settings* → raíz → *Root Scale*, ajustar y *Reimport*.
4. Si la textura no aparece, en el material del `MeshInstance3D` asignar la imagen copiada en §5 (más adelante se cambia por `psx_base.tres`).
5. Anotar en `docs/asset-status.md`: factor de escala, altura medida, lista de clips y estado **listo**.

---

## 8. Guardar en el repositorio

Los `.fbx`, `.glb` y `.png` ya están configurados para **Git LFS** (`.gitattributes`). Comprobar una vez que LFS está instalado:

```bash
git lfs install
```

Luego, por cada personaje terminado (ejemplo Kaelen):

```bash
git add _source/mixamo/kaelen assets/characters/kaelen docs/asset-status.md
```

```bash
git commit -m "feat: add rigged Kaelen with Mixamo animations"
```

```bash
git push
```

Se suben **ambas cosas**: los FBX crudos de `_source/mixamo/` (para no tener que volver a Mixamo si algo se rompe) y el `.glb` final de `assets/`. **No** subir la carpeta `.godot/` (ya está en `.gitignore`); los archivos `.import` que crea Godot junto al `.glb` **sí** se suben.

Avisar en el chat del equipo: "`kaelen.glb` listo: idle, walk, run, roll, attack_1, attack_2, attack_3, hurt, death".

---

## Problemas comunes

| Síntoma | Causa | Solución |
|---|---|---|
| Mixamo: "unable to map your existing skeleton" | El FBX trae un rig | §1.3: borrar Armature y grupos de vértices |
| Mixamo lo muestra acostado | Ejes al exportar | Exportar con -Z Forward / Y Up y transformaciones aplicadas |
| Personaje gigante o diminuto en Godot | Escala FBX de Mixamo (0.01) | *Root Scale* en el importador de Godot |
| La animación se desplaza y vuelve de golpe | Se olvidó *In Place* | Volver a descargar ese clip con *In Place* |
| Capa o falda atraviesa las piernas | Auto-rig pesa la tela con las piernas | Aceptable en PSX; si molesta, *Character Arm-Space* o mover el marcador de entrepierna |
| `combine_mixamo.py`: "No hay animaciones" | Archivos fuera de `anims/` | Moverlos a `<personaje>/anims/` |
