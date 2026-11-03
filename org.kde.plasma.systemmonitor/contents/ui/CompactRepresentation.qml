// Barras de temperatura en el panel, con etiqueta vertical de 3 letras.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors

Item {
    id: compactRoot

    readonly property var sensorIds: (Plasmoid.faceController && Plasmoid.faceController.highPrioritySensorIds)
        ? Plasmoid.faceController.highPrioritySensorIds
        : []
    readonly property int barCount: Math.max(sensorIds.length, 1)
    readonly property int gap: 2
    readonly property real rangeTo: 100

    Layout.fillHeight: true
    Layout.minimumWidth: barCount * 12 + gap * Math.max(0, barCount - 1)
    Layout.preferredWidth: barCount * Math.max(14, Math.round(height * 0.32)) + gap * Math.max(0, barCount - 1)
    Layout.maximumWidth: barCount * 22 + gap * Math.max(0, barCount - 1)

    function colorOf(value) {
        const text = String(value ?? "")
        if (text.startsWith("#") || text.startsWith("rgb"))
            return text
        const parts = text.split(",")
        if (parts.length >= 3)
            return Qt.rgba(parseInt(parts[0], 10) / 255, parseInt(parts[1], 10) / 255, parseInt(parts[2], 10) / 255, 1)
        return Kirigami.Theme.highlightColor
    }

    function shortLabel(id) {
        const labels = (Plasmoid.faceController && Plasmoid.faceController.sensorLabels) ? Plasmoid.faceController.sensorLabels : {}
        const raw = String(labels[id] || "")
        const word = raw.split(/\s+/)[0] || ""
        const letters = word.replace(/[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ]/g, "")
        const cut = letters.substring(0, 3)
        return cut ? cut.toUpperCase() : "•"
    }

    function longLabel(id) {
        const labels = (Plasmoid.faceController && Plasmoid.faceController.sensorLabels) ? Plasmoid.faceController.sensorLabels : {}
        return String(labels[id] || "")
    }

    function barColor(id) {
        const colors = (Plasmoid.faceController && Plasmoid.faceController.sensorColors) ? Plasmoid.faceController.sensorColors : {}
        return colorOf(colors[id])
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.expanded = !root.expanded
    }

    Row {
        id: row
        anchors.fill: parent
        anchors.topMargin: 1
        anchors.bottomMargin: 1
        spacing: compactRoot.gap

        Repeater {
            model: compactRoot.sensorIds

            delegate: Item {
                id: col
                required property int index
                required property var modelData

                width: compactRoot.barCount > 0
                    ? (row.width - row.spacing * Math.max(0, compactRoot.barCount - 1)) / compactRoot.barCount
                    : 0
                height: row.height

                property real temp: 0
                readonly property string labelText: compactRoot.shortLabel(modelData)
                readonly property string tipName: {
                    const longName = compactRoot.longLabel(modelData)
                    return longName || labelText
                }
                readonly property color fillColor: compactRoot.barColor(modelData)
                readonly property string tipText: tipName + " " + Math.round(temp) + " °C"

                Sensors.Sensor {
                    sensorId: String(col.modelData || "")
                    updateRateLimit: 2000
                    onValueChanged: col.temp = Number(value) || 0
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 2
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                    clip: true

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: parent.height * Math.max(0, Math.min(1, col.temp / compactRoot.rangeTo))
                        color: col.fillColor
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: -2

                    Repeater {
                        model: col.labelText.split("")
                        delegate: QQC2.Label {
                            required property string modelData
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData
                            font.pixelSize: Math.max(7, Math.round(col.height * 0.20))
                            font.bold: true
                            font.capitalization: Font.AllUppercase
                            color: Kirigami.Theme.textColor
                            style: Text.Outline
                            styleColor: Qt.rgba(0, 0, 0, 0.55)
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.expanded = !root.expanded
                    QQC2.ToolTip.visible: containsMouse
                    QQC2.ToolTip.text: col.tipText
                    QQC2.ToolTip.delay: 400
                }
            }
        }
    }
}
