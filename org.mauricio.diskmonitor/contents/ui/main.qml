import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // [{letter, name, source, size, avail}] — size/avail en bytes (0 = sin dato)
    property var disks: []
    readonly property real totalAvail: disks.reduce((s, d) => s + d.avail, 0)

    readonly property color okColor: "#2ecc71"
    readonly property color warnColor: "#f39c12"
    readonly property color critColor: "#e74c3c"

    Plasmoid.title: "Espacio en discos"
    toolTipMainText: "Discos"
    toolTipSubText: disks.map(d => d.name + ": " + formatBytes(d.avail) + " libres de " + formatBytes(d.size)).join("\n")

    // Definición de discos desde la configuración: "letra|nombre|origen;..."
    readonly property var diskDefs: Plasmoid.configuration.disks.split(";")
        .map(s => s.split("|"))
        .filter(p => p.length === 3)
        .map(p => ({ letter: p[0].trim(), name: p[1].trim(), source: p[2].trim() }))

    // Un comando por disco; cada uno imprime "letra<TAB>bytes_totales bytes_libres".
    // Montados: df. Particiones NTFS sin montar (Windows): ntfsinfo lee la tabla de clusters sin montar.
    readonly property string command: diskDefs.map(d => {
        const q = "'" + d.source.replace(/'/g, "'\\''") + "'"
        const read = d.source.startsWith("/dev/")
            ? "sudo -n ntfsinfo -m " + q + " 2>/dev/null | awk '/Cluster Size/{c=$3} /Volume Size in Clusters/{t=$5} /Free Clusters/{f=$3} END{if(c) printf \"%.0f %.0f\", c*t, c*f}'"
            : "df -B1 --output=size,avail " + q + " 2>/dev/null | tail -n 1"
        return "printf '%s\\t%s\\n' '" + d.letter + "' \"$(" + read + ")\""
    }).join("; ")

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
        const values = {}
        for (const line of out.split("\n")) {
            const tab = line.indexOf("\t")
            if (tab < 0) continue
            const nums = line.slice(tab + 1).trim().split(/\s+/)
            values[line.slice(0, tab)] = { size: parseFloat(nums[0]) || 0, avail: parseFloat(nums[1]) || 0 }
        }
        disks = diskDefs.map(d => Object.assign({}, d, values[d.letter] || { size: 0, avail: 0 }))
    }

    function freePercent(d) { return d.size > 0 ? 100 * d.avail / d.size : 0 }
    function usedFraction(d) { return d.size > 0 ? 1 - d.avail / d.size : 0 }
    function barColor(d) {
        if (d.size <= 0) return Kirigami.Theme.disabledTextColor
        const free = freePercent(d)
        if (free < Plasmoid.configuration.critPercent) return critColor
        if (free < Plasmoid.configuration.warnPercent) return warnColor
        return okColor
    }

    // Mismo criterio que "df -h": unidades de 1024
    function formatBytes(b) {
        if (b <= 0) return "—"
        const g = b / 1073741824
        if (g >= 1000) return (g / 1024).toFixed(1) + " TB"
        return Math.round(g) + " GB"
    }
    function formatShort(b) {
        if (b <= 0) return "—"
        const g = b / 1073741824
        if (g >= 1000) return (g / 1024).toFixed(1) + "T"
        return Math.round(g) + "G"
    }

    Timer {
        interval: 60000
        repeat: true
        triggeredOnStart: true
        running: true
        onTriggered: root.refresh()
    }
    onExpandedChanged: if (expanded) refresh()

    compactRepresentation: MouseArea {
        id: compact
        Layout.minimumWidth: grid.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        readonly property int fontPx: Math.max(8, Math.floor(compact.height * 0.24))

        GridLayout {
            id: grid
            anchors.centerIn: parent
            columns: 3
            rowSpacing: Math.max(1, Math.round(compact.height * 0.06))
            columnSpacing: Kirigami.Units.smallSpacing

            Repeater {
                model: root.disks
                delegate: PlasmaComponents.Label {
                    required property var modelData
                    text: modelData.letter
                    font.pixelSize: compact.fontPx
                    font.bold: true
                    Layout.row: index
                    Layout.column: 0
                    required property int index
                }
            }
            Repeater {
                model: root.disks
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    Layout.row: index
                    Layout.column: 1
                    Layout.preferredWidth: compact.height * 1.5
                    Layout.preferredHeight: Math.max(3, Math.round(compact.height * 0.14))
                    radius: height / 2
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * root.usedFraction(modelData)
                        radius: parent.radius
                        color: root.barColor(modelData)
                    }
                }
            }
            Repeater {
                model: root.disks
                delegate: PlasmaComponents.Label {
                    required property var modelData
                    required property int index
                    Layout.row: index
                    Layout.column: 2
                    Layout.minimumWidth: compact.fontPx * 2.6
                    horizontalAlignment: Text.AlignRight
                    text: root.formatShort(modelData.avail)
                    font.pixelSize: compact.fontPx
                }
            }
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.preferredHeight: Kirigami.Units.gridUnit * (3 + root.disks.length * 2.2)
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                Kirigami.Heading {
                    level: 3
                    text: "Discos"
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    opacity: 0.8
                    text: root.formatBytes(root.totalAvail) + " libres en total"
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: root.disks
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                    spacing: Kirigami.Units.smallSpacing * 2

                    Kirigami.Icon {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        source: modelData.source.startsWith("/dev/") ? "drive-harddisk" : (modelData.source === "/" ? "computer" : "drive-harddisk")
                    }
                    PlasmaComponents.Label {
                        text: modelData.name
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 0.5
                        radius: height / 2
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * root.usedFraction(modelData)
                            radius: parent.radius
                            color: root.barColor(modelData)
                        }
                    }
                    PlasmaComponents.Label {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                        horizontalAlignment: Text.AlignRight
                        text: modelData.size > 0
                            ? root.formatBytes(modelData.avail) + " libres de " + root.formatBytes(modelData.size)
                            : "sin datos"
                        opacity: 0.8
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
