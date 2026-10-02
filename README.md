# Plasma widgets

Widgets custom para la barra de KDE Plasma 6.

| Widget | Qué muestra |
|---|---|
| `org.mauricio.procmonitor` | Anillo con uso de CPU, memoria o GPU (se elige en la configuración). Al hacer clic, lista de programas ordenados por consumo. |
| `org.mauricio.diskmonitor` | Barras con el espacio usado y libre de cada disco, con color de alerta (ámbar bajo 20 % libre, rojo bajo 10 %). Al hacer clic, detalle por disco. |
| `temperaturas/` | Monitor de temperaturas (CPU, VRM, GPU y discos NVMe). No es código propio: es el widget estándar "Monitor del sistema" de KDE configurado. La carpeta guarda esa configuración y un script que lo recrea en la barra. |

## Instalación

Clonar este repo en `~/.local/share/plasma/plasmoids/` y agregar los widgets a la barra desde "Agregar widgets".

```bash
git clone https://github.com/mzwenger/plasma-widgets.git ~/.local/share/plasma/plasmoids
```

Para el monitor de temperaturas:

```bash
~/.local/share/plasma/plasmoids/temperaturas/instalar.sh
```

## Notas

- `procmonitor` en modo GPU requiere `nvidia-smi`.
- `diskmonitor` define los discos en su configuración como `letra|nombre|origen;...`. El origen es un punto de montaje, o una partición NTFS sin montar (`/dev/...`), que se lee con `ntfsinfo` y requiere `sudo` sin clave para ese comando.
- El monitor de temperaturas usa sensores identificados por hardware (`lmsensors/...`). En otro equipo hay que ajustar esos ids en `temperaturas/agregar.js`.
