# Configuración de herramientas (Godot, Blender y MCP)

Guía para que cada integrante deje su PC lista. Las rutas de ejemplo son las de la PC principal; si las tuyas son distintas, ver "Rutas distintas" al final.

## 1. Programas

| Programa | Versión | Ruta usada en el proyecto |
|---|---|---|
| Godot | 4.7.2 estable | `D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` |
| Blender | 5.2 | `D:\Unity\blender.exe` |
| Git + Git LFS | cualquiera reciente | — |
| Node.js | 22 o superior | (para el MCP de Godot) |
| Python | 3.12 o superior | (para el MCP de Blender) |

## 2. Proyecto de Godot

1. Clonar el repo (ver guía de Git LFS).
2. Abrir Godot → **Importar** → seleccionar `project.godot` en la raíz del repo.
3. La carpeta `_source/` no aparece en Godot a propósito (tiene `.gdignore`).

Ajustes ya configurados en `project.godot`:
- Renderizador **Compatibility** (permite exportar a Web).
- Resolución interna 640×360, ventana 1280×720 (look PSX).
- Filtro de texturas *nearest* e iluminación por vértice forzada.
- Nombres de capas de colisión y navegación (ver sección 7.7 del documento de diseño).
- Buses de audio `Master`, `Music`, `SFX`, `UI` (`default_bus_layout.tres`).

## 3. Servidores MCP (para trabajar con Claude Code)

Los servidores se instalan **fuera del repo**, en `D:\mcp-servers\`. El archivo `.mcp.json` del repo ya los registra para Claude Code.

### 3.1 MCP de Godot
```powershell
New-Item -ItemType Directory -Force D:\mcp-servers\godot
npm install --prefix D:\mcp-servers\godot @coding-solo/godot-mcp@0.1.1
```
Herramientas: abrir el editor, ejecutar el proyecto, leer la salida de depuración, crear escenas, agregar nodos, exportar `MeshLibrary`, etc.

### 3.2 MCP de Blender
```powershell
python -m venv D:\mcp-servers\blender
D:\mcp-servers\blender\Scripts\python.exe -m pip install mcp-for-blender
```
Instalar el addon en Blender:
```powershell
New-Item -ItemType Directory -Force D:\mcp-servers\blender\blender_scripts\addons
$env:BLENDERMCP_ADDONS_DIR = "D:\mcp-servers\blender\blender_scripts\addons"
D:\mcp-servers\blender\Scripts\mcp-for-blender.exe install-addon
```
Activarlo en Blender (una sola vez):
1. **Edit → Preferences → Add-ons** → menú ▾ (arriba a la derecha) → **Install from Disk…**
2. Elegir `D:\mcp-servers\blender\blender_scripts\addons\blender_mcp.py`.
3. Marcar la casilla de **MCP for Blender** y guardar preferencias.

Para usarlo: abrir Blender → en el visor 3D presionar `N` → pestaña **MCP for Blender** → **Start MCP Server** si no está corriendo. Claude solo puede usar Blender mientras Blender esté abierto con el servidor encendido.

La telemetría está desactivada en `.mcp.json` (`DISABLE_TELEMETRY=true`).

### 3.3 Activar en Claude Code
Cerrar y volver a abrir la sesión de Claude Code en la carpeta del repo. La primera vez pedirá aprobar los servidores `godot` y `blender` del archivo `.mcp.json`.

## 4. Rutas distintas
Si Godot o los servidores están en otro lugar, definir estas variables de entorno de usuario (no hace falta editar `.mcp.json`):

| Variable | Valor por defecto |
|---|---|
| `GODOT_PATH` | `D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe` |
| `GODOT_MCP_DIR` | `D:/mcp-servers/godot` |
| `BLENDER_MCP_EXE` | `D:/mcp-servers/blender/Scripts/mcp-for-blender.exe` |

## 5. Problemas conocidos
- **`uvx` falla instalando `pywin32` ("el proceso no tiene acceso al archivo")**: el antivirus bloquea la instalación. Usar el método con `pip` + `venv` de la sección 3.2.
- **Archivos de 1 KB en lugar de modelos o audio**: faltó Git LFS al clonar; ejecutar `git lfs pull`.
