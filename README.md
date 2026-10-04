# Game Vault

Selector de juegos flotante para Plasma 6: Steam, emulación, atajos no-Steam y manuales en un drawer central con categorías, buscador y último jugado primero.

- **Categorías con Tab**: Todos, Recientes, Steam, Emulación, No-Steam, Favoritos y Ocultos (oculta, se abre con Ctrl+H).
- **Teclado primero**: flechas para navegar, Enter lanza, F5 reescanea, Ctrl+F favorito, Ctrl+O ocultar.
- **Buscador** que se abre al escribir, con debounce y navegación sin perder el foco.
- **Último jugado primero**: registra tus lanzamientos y ordena por recencia real.
- **Tema autónomo**: sigue el acento de KDE en vivo, sin scripts; colores manuales con ruedita en ajustes.
- **Arte inteligente**: usa tu portada amplia de Steam y se autocura si Steam reescribe el atajo.
- Mouse opcional (apagado por defecto) y panel de ajustes con scroll.

## Capturas

![Game Vault flotando](screenshots/gamevault-drawer.png)

![Categorías con Tab](screenshots/gamevault-tabs.png)

![Juego al frente](screenshots/gamevault-focus.png)

## Ajustes

![Ajustes con secciones](screenshots/gamevault-settings.png)

## Instalar

```bash
git clone https://github.com/ezku100/gamevault.git
cd gamevault
./install.sh
```

Manual: descarga el `.plasmoid` desde [Releases](https://github.com/ezku100/gamevault/releases/latest), luego clic derecho en el panel → Añadir o gestionar elementos gráficos → Obtener nuevos → Instalar desde archivo.

## Agregar al panel

1. Clic derecho en el panel (o el escritorio) → **Añadir o gestionar elementos gráficos**.
2. Busca **Game Vault** y agrégalo (puedes arrastrarlo al panel).
3. Opcional: clic derecho al icono → **Configurar** → **Atajos** → asigna un atajo global (sugerido `Meta+Ctrl+G`).
4. Si no aparece tras instalar, reinicia Plasma: `nohup plasmashell --replace >/tmp/plasmashell.log 2>&1 &`

## Atajos de teclado

| Tecla | Acción |
|---|---|
| `←` `→` `↑` `↓` | Mover selección |
| `Enter` / `Espacio` | Lanzar juego |
| `Esc` | Limpiar búsqueda → cerrar buscador → cerrar drawer |
| `Tab` / `Shift+Tab` | Siguiente / anterior categoría |
| `Ctrl+F` | Marcar / desmarcar favorito |
| `Ctrl+O` | Ocultar / mostrar juego |
| `Ctrl+H` | Abrir categoría Ocultos |
| `F5` | Reescanear biblioteca |
| Escribir | Abre el buscador y filtra |

Atajo global sugerido: `Meta+Ctrl+G` (clic derecho al widget → Configurar → Atajos).

## Créditos

- Basado en [GameDrawer](https://github.com/atopion/gamedrawer) de atopion
- Fork, categorías y estilos: ezku
- Licencia: GPLv3
