import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors

PlasmoidItem {
    id: root

    readonly property string mode: Plasmoid.configuration.mode
    readonly property bool isCpu: mode === "cpu"
    readonly property bool isGpu: mode === "gpu"
    readonly property color accent: Plasmoid.configuration.color
    readonly property real percent: sensor.value || 0
    // Último minuto de uso, una muestra cada 2 s.
    property var history: []
    property var vramHistory: []

    // Lista agrupada por programa: [{name, count, value}]
    property var processes: []
    // GPU: memoria de video usada / total (MB)
    property real vramUsed: 0
    property real vramTotal: 0

    readonly property string label: isCpu ? "CPU" : (isGpu ? "GPU" : "Memoria")
    Plasmoid.title: "Procesos por " + label
    toolTipMainText: label
    property real vramSensorUsed: 0
    property real vramSensorTotal: 0
    readonly property real vramPercent: vramSensorTotal > 0 ? 100 * vramSensorUsed / vramSensorTotal : 0
    readonly property string vramHeader: {
        const totalBytes = vramSensorTotal > 0 ? vramSensorTotal : vramTotal * 1048576
        const usedBytes = vramSensorTotal > 0 ? vramSensorUsed : vramUsed * 1048576
        return Math.round(percent) + "% en uso · VRAM " + Math.round(vramPercent) + "% · " + formatMem(usedBytes / 1024) + " de " + formatMem(totalBytes / 1024)
    }
    toolTipSubText: isGpu
        ? Math.round(percent) + "% en uso · VRAM " + Math.round(vramPercent) + "%"
        : Math.round(percent) + "% en uso"

    Sensors.Sensor {
        id: sensor
        sensorId: root.isCpu ? "cpu/all/usage" : (root.isGpu ? "gpu/all/usage" : "memory/physical/usedPercent")
        updateRateLimit: 2000
    }
    Sensors.Sensor {
        id: vramUsedSensor
        sensorId: "gpu/all/usedVram"
        updateRateLimit: 2000
        enabled: root.isGpu
        onValueChanged: root.vramSensorUsed = value || 0
    }
    Sensors.Sensor {
        id: vramTotalSensor
        sensorId: "gpu/all/totalVram"
        updateRateLimit: 2000
        enabled: root.isGpu
        onValueChanged: root.vramSensorTotal = value || 0
    }

    Sensors.Sensor {
        id: memUsed
        sensorId: "memory/physical/used"
        updateRateLimit: 2000
        enabled: root.mode === "memory"
    }
    Sensors.Sensor {
        id: memTotal
        sensorId: "memory/physical/total"
        enabled: root.mode === "memory"
    }

    // GPU: nvidia-smi pmon (uso de la GPU y memoria de video por proceso).
    // CPU: segunda muestra de top (uso actual, no promedio histórico).
    // Memoria: RSS de ps (memoria real que ocupa cada proceso).
    readonly property string command: isGpu
        ? "echo TOTAL $(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits | tr -d ' ' | tr ',' ' '); nvidia-smi pmon -c 1 -s um | awk '!/^#/{print $2, $4, $10}' | while read pid sm fb; do printf '%s\\t%s\\t%s\\n' \"$sm\" \"$fb\" \"$(ps -o comm= -p $pid)\"; done"
        : isCpu
        ? "LC_ALL=C top -b -n 2 -d 1 -w 512 | awk '/^top -/{n++} n==2 && $1 ~ /^[0-9]+$/ {c=$12; for(i=13;i<=NF;i++) c=c\" \"$i; print $9\"\\t\"c}'"
        : "LC_ALL=C ps -eo rss=,comm= "

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)
            root.parseOutput(data["stdout"] || "")
        }
    }

    function refresh() {
        if (executable.connectedSources.length === 0) {
            executable.connectSource(command)
        }
    }

    function parseOutput(out) {
        const groups = {}
        for (const line of out.split("\n")) {
            let value, name, vram = 0
            if (isGpu) {
                const t = line.trim().split(/\s+/)
                if (t[0] === "TOTAL") { vramUsed = parseFloat(t[1]); vramTotal = parseFloat(t[2]); continue }
                const f = line.split("\t")
                if (f.length < 3) continue
                value = parseFloat(f[0]) || 0   // "-" = sin uso
                vram = parseFloat(f[1]) || 0     // MB
                name = f[2].trim()
            } else if (isCpu) {
                const tab = line.indexOf("\t")
                if (tab < 0) continue
                value = parseFloat(line.slice(0, tab))
                name = line.slice(tab + 1).trim()
            } else {
                const m = line.trim().match(/^(\d+)\s+(.+)$/)
                if (!m) continue
                value = parseInt(m[1]) // KiB
                name = m[2].trim()
            }
            if (!name || isNaN(value)) continue
            if (!groups[name]) groups[name] = { name: name, count: 0, value: 0, vram: 0 }
            groups[name].count++
            groups[name].value += value
            groups[name].vram += vram
        }
        let list = Object.values(groups)
        if (isCpu) {
            // top da % por núcleo; lo paso a % del total del equipo
            const cores = Math.max(1, cpuCount.value || 1)
            list.forEach(p => p.value = p.value / cores)
            list = list.filter(p => p.value >= 0.05)
        }
        if (isGpu) {
            // ordenar por uso de GPU y, a igual uso, por memoria de video
            list.sort((a, b) => (b.value - a.value) || (b.vram - a.vram))
        } else {
            list.sort((a, b) => b.value - a.value)
        }
        processes = list.slice(0, 60)
    }

    Sensors.Sensor {
        id: cpuCount
        sensorId: "cpu/all/cpuCount"
    }

    function formatMem(kib) {
        if (kib >= 1048576) return (kib / 1048576).toFixed(1) + " GB"
        return Math.round(kib / 1024) + " MB"
    }

    Timer {
        interval: root.isCpu ? 2500 : 2000
        repeat: true
        triggeredOnStart: true
        running: root.expanded
        onTriggered: root.refresh()
    }

    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: true
        onTriggered: {
            const next = root.history.slice()
            next.push(Math.max(0, root.percent))
            if (next.length > 30)
                next.shift()
            root.history = next
            if (!root.isGpu)
                return
            const vram = root.vramHistory.slice()
            vram.push(Math.max(0, Math.min(100, root.vramPercent)))
            if (vram.length > 30)
                vram.shift()
            root.vramHistory = vram
        }
    }

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
            property real value: root.percent
            property color fg: root.accent
            property color bg: Kirigami.Theme.textColor
            onValueChanged: requestPaint()
            onFgChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const w = Math.min(width, height)
                const lw = Math.max(2, w * 0.08)
                const r = w / 2 - lw / 2
                const cx = width / 2, cy = height / 2
                ctx.lineWidth = lw
                ctx.strokeStyle = Qt.rgba(bg.r, bg.g, bg.b, 0.15)
                ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.stroke()
                ctx.strokeStyle = fg
                ctx.lineCap = "round"
                const start = -Math.PI / 2
                const v = Math.max(0, Math.min(100, value))
                if (v > 0) {
                    ctx.beginPath(); ctx.arc(cx, cy, r, start, start + 2 * Math.PI * v / 100); ctx.stroke()
                }
            }
        }

        PlasmaComponents.Label {
            anchors.centerIn: parent
            text: Math.round(root.percent) + "%"
            font.pixelSize: Math.max(8, compact.height * 0.30)
            font.bold: true
        }

        // Chip con el nombre del recurso, apoyado en el borde inferior derecho (igual que la letra de los discos)
        Rectangle {
            height: Math.max(10, Math.round(compact.height * 0.32))
            width: chipLabel.implicitWidth + height * 0.5
            radius: height / 2
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.5)
            border.width: 1
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.4)
            PlasmaComponents.Label {
                id: chipLabel
                anchors.centerIn: parent
                text: root.isCpu ? "CPU" : (root.isGpu ? "GPU" : "MEM")
                font.pixelSize: Math.max(6, Math.round(parent.height * 0.6))
                font.bold: true
            }
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        Layout.preferredHeight: Kirigami.Units.gridUnit * 32
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 20

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                Kirigami.Heading {
                    level: 3
                    text: root.label
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    opacity: 0.8
                    text: root.isCpu
                        ? Math.round(root.percent) + "% en uso"
                        : root.isGpu
                        ? root.vramHeader
                        : root.formatMem((memUsed.value || 0) / 1024) + " de " + root.formatMem((memTotal.value || 0) / 1024)
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing

            HistoryChart {
                Layout.fillWidth: true
                valuesA: root.history
                nameA: "Uso"
                textA: Math.round(root.percent) + "%"
                colorA: root.accent
                yMax: 100
                unit: "%"
            }
            HistoryChart {
                visible: root.isGpu
                Layout.fillWidth: true
                valuesA: root.vramHistory
                nameA: "VRAM"
                textA: Math.round(root.vramPercent) + "%"
                colorA: "#5dade2"
                yMax: 100
                unit: "%"
            }

        PlasmaComponents.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: list
                model: root.processes
                clip: true
                reuseItems: true

                readonly property real maxValue: root.processes.length ? root.processes[0].value : 1
                // GPU: la barra muestra la parte de la memoria de video que ocupa cada programa
                function barFraction(p) {
                    if (root.isGpu) return root.vramTotal > 0 ? p.vram / root.vramTotal : 0
                    return maxValue > 0 ? p.value / maxValue : 0
                }

                delegate: Item {
                    required property var modelData
                    width: ListView.view.width
                    height: Kirigami.Units.gridUnit * 1.8

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height - 4
                        radius: 3
                        color: root.accent
                        opacity: 0.22
                        width: parent.width * list.barFraction(modelData)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.smallSpacing
                        anchors.rightMargin: Kirigami.Units.smallSpacing
                        Item {
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            Kirigami.Icon {
                                id: appIcon
                                anchors.fill: parent
                                source: modelData.name.split(/[ \/]/)[0].toLowerCase()
                                visible: valid
                            }
                            Kirigami.Icon {
                                anchors.fill: parent
                                source: "application-x-executable"
                                visible: !appIcon.valid
                            }
                        }
                        PlasmaComponents.Label {
                            text: modelData.name + (modelData.count > 1 ? "  (" + modelData.count + ")" : "")
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        PlasmaComponents.Label {
                            font.bold: true
                            text: root.isGpu
                                ? (modelData.value > 0 ? Math.round(modelData.value) + "% · " : "") + root.formatMem(modelData.vram * 1024)
                                : root.isCpu
                                ? (modelData.value < 10 ? modelData.value.toFixed(1) : Math.round(modelData.value)) + "%"
                                : root.formatMem(modelData.value)
                        }
                    }
                }

                PlasmaExtras.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 2
                    visible: list.count === 0
                    text: "Cargando…"
                }
            }
        }
        }
    }
}
