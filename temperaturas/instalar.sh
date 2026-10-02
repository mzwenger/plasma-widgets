#!/bin/sh
# Recrea el monitor de temperaturas en la barra de Plasma.
exec qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat "$(dirname "$0")/agregar.js")"
