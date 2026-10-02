# Plasma widgets

Widgets custom para la barra de KDE Plasma 6.

| Widget | Qué muestra |
|---|---|
| `org.mauricio.procmonitor` | Anillo con uso de CPU, memoria o GPU (se elige en la configuración). Al hacer clic, lista de programas ordenados por consumo. |
| `org.mauricio.diskmonitor` | Barras con el espacio usado y libre de cada disco, con color de alerta (ámbar bajo 20 % libre, rojo bajo 10 %). Al hacer clic, detalle por disco. |

## Instalación

Clonar este repo en `~/.local/share/plasma/plasmoids/` y agregar los widgets a la barra desde "Agregar widgets".

```bash
git clone https://github.com/mzwenger/plasma-widgets.git ~/.local/share/plasma/plasmoids
```

## Notas

- `procmonitor` en modo GPU requiere `nvidia-smi`.
- `diskmonitor` define los discos en su configuración como `letra|nombre|origen;...`. El origen es un punto de montaje, o una partición NTFS sin montar (`/dev/...`), que se lee con `ntfsinfo` y requiere `sudo` sin clave para ese comando.
