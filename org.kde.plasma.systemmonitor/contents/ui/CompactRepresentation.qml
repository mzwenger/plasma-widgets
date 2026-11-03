// Barras de temperatura en el panel: CPU, GPU, VRM, LIN, WIN, con etiqueta vertical.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors

Item {
    id: compactRoot

    readonly property var bars: [
        { label: "CPU", color: "#e74c3c", sensor: "cpu/all/maximumTemperature", tip: "CPU" },
        { label: "GPU", color: "#2ecc71", sensor: "gpu/gpu0/temperature", tip: "GPU" },
        { label: "VRM", color: "#f39c12", sensor: "lmsensors/nct6795-isa-0a20/temp3", tip: "VRM" },
        { label: "LIN", color: "#bdc3c7", sensor: "lmsensors/nvme-pci-0100/temp1", tip: "Linux (Samsung)" },
        { label: "WIN", color: "#7f8c8d", sensor: "lmsensors/nvme-pci-2500/temp1", tip: "Windows (XPG)" }
    ]
    readonly property int barCount: bars.length
    readonly property real rangeTo: 100

    Layout.fillHeight: true
    Layout.minimumWidth: barCount * 12
    Layout.preferredWidth: barCount * Math.max(14, Math.round(height * 0.32))
    Layout.maximumWidth: barCount * 22

    MouseArea {
        anchors.fill: parent
        onClicked: root.expanded = !root.expanded
    }

    Row {
        id: row
        anchors.fill: parent
        anchors.topMargin: 1
        anchors.bottomMargin: 1
        spacing: 2

        Repeater {
            model: compactRoot.bars

            delegate: Item {
                id: col
                required property int index
                required property var modelData

                width: (row.width - row.spacing * (compactRoot.barCount - 1)) / compactRoot.barCount
                height: row.height

                property real temp: 0
                readonly property string labelText: modelData.label
                readonly property color barColor: modelData.color
                readonly property string tipText: modelData.tip + " " + Math.round(temp) + " °C"

                Sensors.Sensor {
                    sensorId: col.modelData.sensor
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
                        color: col.barColor
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
