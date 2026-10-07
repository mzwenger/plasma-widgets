import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Configuración: "letra|nombre|origen"
    readonly property var def: {
        const p = Plasmoid.configuration.disk.split("|").map(s => s.trim())
        return { letter: p[0] || "?", name: p[1] || p[0] || "Disco", source: p[2] || "/" }
    }
    readonly property bool isRawDevice: def.source.startsWith("/dev/")
    readonly property string quoted: "'" + def.source.replace(/'/g, "'\\''") + "'"

    // Espacio (bytes; 0 = sin dato)
    property real size: 0
    property real avail: 0
    // Actividad: % del tiempo en que el disco estuvo ocupado, y velocidades en bytes/s
    property real busy: 0
    property real readRate: 0
    property real writeRate: 0
    property var prev: null

    readonly property real usedFraction: size > 0 ? 1 - avail / size : 0
    readonly property real freePercent: size > 0 ? 100 * avail / size : 0

    readonly property color okColor: "#2ecc71"
    readonly property color warnColor: "#f39c12"
    readonly property color busyWarnColor: "#f1c40f"
    readonly property color critColor: "#e74c3c"

    readonly property color spaceColor: size <= 0 ? Kirigami.Theme.disabledTextColor
        : freePercent < Plasmoid.configuration.critPercent ? critColor
        : freePercent < Plasmoid.configuration.warnPercent ? warnColor
        : okColor
    readonly property color busyColor: busy > Plasmoid.configuration.busyCrit ? critColor
        : busy >= Plasmoid.configuration.busyWarn ? busyWarnColor
        : okColor

    Plasmoid.title: def.name
    toolTipMainText: def.name
    toolTipSubText: "Actividad " + Math.round(busy) + "%\n"
        + (size > 0 ? formatBytes(avail) + " libres de " + formatBytes(size) : "Espacio sin datos")

    // Espacio. Montados: df. Particiones NTFS sin montar (Windows): ntfsinfo lee la tabla de clusters sin montar.
    // -f: Windows deja el volumen marcado "pendiente de chequeo" (inicio rápido / apagado incompleto) y sin -f ntfsinfo se niega a abrirlo; es solo lectura.
    readonly property string spaceCommand: isRawDevice
        ? "sudo -n ntfsinfo -f -m " + quoted + " 2>/dev/null | awk '/Cluster Size/{c=$3} /Volume Size in Clusters/{t=$5} /Free Clusters/{f=$3} END{if(c) printf \"%.0f %.0f\", c*t, c*f}'"
        : "df -B1 --output=size,avail " + quoted + " 2>/dev/null | tail -n 1"

    // Actividad: contadores del kernel para la partición (sectores leídos, escritos y ms ocupado) + reloj del sistema
    readonly property string activityCommand:
        "d=$(basename \"$(readlink -f " + (isRawDevice ? quoted : "\"$(findmnt -nvo SOURCE --target " + quoted + ")\"") + ")\"); "
        + "awk -v d=\"$d\" '$3==d{print $6, $10, $13}' /proc/diskstats; cut -d' ' -f1 /proc/uptime"

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)
            const out = data["stdout"] || ""
            if (source === root.spaceCommand) root.parseSpace(out)
            else if (source === root.activityCommand) root.parseActivity(out)
        }
    }

    function run(cmd) {
        if (executable.connectedSources.indexOf(cmd) < 0) executable.connectSource(cmd)
    }

    function parseSpace(out) {
        const n = out.trim().split(/\s+/)
        size = parseFloat(n[0]) || 0
        avail = parseFloat(n[1]) || 0
    }

    function parseActivity(out) {
        const lines = out.trim().split("\n")
        if (lines.length < 2) return
        const c = lines[0].trim().split(/\s+/).map(Number)
        const now = { sr: c[0], sw: c[1], ticks: c[2], t: parseFloat(lines[1]) }
        if (prev && now.t > prev.t) {
            const dt = now.t - prev.t
            busy = Math.max(0, Math.min(100, (now.ticks - prev.ticks) / (dt * 10)))
            readRate = Math.max(0, (now.sr - prev.sr) * 512 / dt)
            writeRate = Math.max(0, (now.sw - prev.sw) * 512 / dt)
        }
        prev = now
    }

    // Mismo criterio que "df -h": unidades de 1024
    function formatBytes(b) {
        if (b <= 0) return "—"
        const g = b / 1073741824
        if (g >= 1000) return (g / 1024).toFixed(1) + " TB"
        return Math.round(g) + " GB"
    }
    function formatRate(b) {
        const m = b / 1048576
        if (m >= 100) return Math.round(m) + " MB/s"
        if (m >= 0.1) return m.toFixed(1) + " MB/s"
        return "0 MB/s"
    }

    Timer {
        interval: 60000
        repeat: true
        triggeredOnStart: true
        running: true
        onTriggered: root.run(root.spaceCommand)
    }
    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: true
        onTriggered: root.run(root.activityCommand)
    }
    onExpandedChanged: if (expanded) run(spaceCommand)

    compactRepresentation: MouseArea {
        id: compact
        Layout.minimumWidth: height
        Layout.preferredWidth: height
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        Canvas {
            id: ring
            anchors.fill: parent
            anchors.margins: Math.round(parent.height * 0.08)
            property real busy: root.busy
            property real used: root.usedFraction
            property color busyColor: root.busyColor
            property color spaceColor: root.spaceColor
            property color bg: Kirigami.Theme.textColor
            onBusyChanged: requestPaint()
            onUsedChanged: requestPaint()
            onBusyColorChanged: requestPaint()
            onSpaceColorChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const w = Math.min(width, height)
                const lw = Math.max(2, w * 0.09)
                const r = w / 2 - lw / 2
                const cx = width / 2, cy = height / 2

                // Anillo exterior: actividad
                ctx.lineWidth = lw
                ctx.strokeStyle = Qt.rgba(bg.r, bg.g, bg.b, 0.15)
                ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.stroke()
                if (busy > 0) {
                    ctx.strokeStyle = busyColor
                    ctx.lineCap = "round"
                    const start = -Math.PI / 2
                    ctx.beginPath(); ctx.arc(cx, cy, r, start, start + 2 * Math.PI * busy / 100); ctx.stroke()
                }

                // Interior: se llena de abajo hacia arriba según el espacio ocupado
                const ri = r - lw / 2 - Math.max(1, w * 0.05)
                ctx.fillStyle = Qt.rgba(bg.r, bg.g, bg.b, 0.06)
                ctx.beginPath(); ctx.arc(cx, cy, ri, 0, 2 * Math.PI); ctx.fill()
                if (used > 0) {
                    const h = 2 * ri * used
                    ctx.save()
                    ctx.beginPath(); ctx.arc(cx, cy, ri, 0, 2 * Math.PI); ctx.clip()
                    ctx.fillStyle = Qt.rgba(spaceColor.r, spaceColor.g, spaceColor.b, 0.55)
                    ctx.fillRect(0, cy + ri - h, width, h)
                    ctx.restore()
                }
            }
        }

        PlasmaComponents.Label {
            anchors.centerIn: parent
            text: Math.round(root.busy) + "%"
            font.pixelSize: Math.max(8, compact.height * 0.30)
            font.bold: true
            color: root.busy >= 1 ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
        }

        // Etiqueta con la letra del disco, apoyada en el borde inferior derecho
        Rectangle {
            readonly property int d: Math.max(10, Math.round(compact.height * 0.36))
            width: d
            height: d
            radius: d / 2
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.5)
            border.width: 1
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.4)
            PlasmaComponents.Label {
                anchors.centerIn: parent
                text: root.def.letter
                font.pixelSize: Math.max(7, Math.round(parent.d * 0.62))
                font.bold: true
            }
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: Kirigami.Units.gridUnit * 10
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                Kirigami.Icon {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    source: root.def.source === "/" ? "computer" : "drive-harddisk"
                }
                Kirigami.Heading {
                    level: 3
                    text: root.def.name
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    opacity: 0.8
                    text: Math.round(root.busy) + "% de actividad"
                }
            }
        }

        GridLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing * 2
            columns: 3
            columnSpacing: Kirigami.Units.smallSpacing * 2
            rowSpacing: Kirigami.Units.smallSpacing * 2

            PlasmaComponents.Label { text: "Espacio" }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 0.5
                radius: height / 2
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width * root.usedFraction
                    radius: parent.radius
                    color: root.spaceColor
                }
            }
            PlasmaComponents.Label {
                opacity: 0.8
                text: root.size > 0 ? root.formatBytes(root.avail) + " libres de " + root.formatBytes(root.size) : "sin datos"
            }

            PlasmaComponents.Label { text: "Actividad" }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 0.5
                radius: height / 2
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width * root.busy / 100
                    radius: parent.radius
                    color: root.busyColor
                }
            }
            PlasmaComponents.Label {
                opacity: 0.8
                text: Math.round(root.busy) + "%"
            }

            PlasmaComponents.Label { text: "Lectura" }
            PlasmaComponents.Label {
                Layout.columnSpan: 2
                opacity: 0.8
                text: root.formatRate(root.readRate)
            }

            PlasmaComponents.Label { text: "Escritura" }
            PlasmaComponents.Label {
                Layout.columnSpan: 2
                opacity: 0.8
                text: root.formatRate(root.writeRate)
            }

            Item { Layout.fillHeight: true; Layout.columnSpan: 3 }
        }
    }
}
